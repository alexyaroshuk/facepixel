import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
// Conditional import: use web implementation on web, stub on native platforms (Android/iOS)
import 'web_face_detection.dart'
    if (dart.library.io) 'web_face_detection_stub.dart'
    deferred as web_module;

void main() async {
  print('🟢 Flutter: main() START');
  WidgetsFlutterBinding.ensureInitialized();
  print('🟢 Flutter: WidgetsFlutterBinding ensured');

  final cameras = await availableCameras();
  print('🟢 Flutter: Found ${cameras.length} cameras');
  for (int i = 0; i < cameras.length; i++) {
    final camera = cameras[i];
    final lensDir = camera.lensDirection == CameraLensDirection.front
        ? 'FRONT'
        : 'BACK';
    print('  - Camera $i: $lensDir');
  }

  print('🟢 Flutter: Calling runApp()');
  runApp(MyApp(cameras: cameras));
  print('🟢 Flutter: runApp() returned');
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Face Pixelation',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: kIsWeb ? const _WebPlaceholder() : MyHomePage(cameras: cameras),
    );
  }
}

/// Placeholder that loads WebFaceDetectionView on web
class _WebPlaceholder extends StatefulWidget {
  const _WebPlaceholder();

  @override
  State<_WebPlaceholder> createState() => _WebPlaceholderState();
}

class _WebPlaceholderState extends State<_WebPlaceholder> {
  late Future<void> _loadWeb;

  @override
  void initState() {
    super.initState();
    _loadWeb = web_module.loadLibrary();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loadWeb,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          // Web module loaded, use reflection to create WebFaceDetectionView
          return web_module.WebFaceDetectionView();
        } else {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const MyHomePage({super.key, required this.cameras});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late CameraController _controller;
  List<Face> _detectedFaces = [];
  bool _isProcessing = false;
  String _debugMessage = "Initializing...";
  int _frameCount = 0;
  DateTime _lastFpsTime = DateTime.now();
  double _fps = 0;
  DateTime _lastProcessTime = DateTime.now();
  int _currentCameraIndex = 0;
  bool _isSwitchingCamera = false;
  int _lastImageWidth = 0;
  int _lastImageHeight = 0;

  // Image dimensions (from camera frames)
  Size _imageSize = Size.zero;

  // Detection canvas dimensions (where face boxes should render)
  Size _detectionCanvasSize = Size.zero;
  Offset _detectionCanvasOffset = Offset.zero;

  // Debug visualization
  bool _showRedBorder = true;
  bool _showTealBorder = true;
  bool _showTestPanel = false;
  bool _showDebugUI = true;
  int? _overrideRotation; // Override rotation for testing

  static const platform = MethodChannel('com.facepixel.app/faceDetection');

  /// Calculate correct rotation for ML Kit based on camera frame dimensions
  /// When rotation is correct, ML Kit can detect faces
  int _calculateMLKitRotation() {
    // If override is set (for testing), use it
    if (_overrideRotation != null) {
      return _overrideRotation!;
    }

    // The key insight: ML Kit needs to know which direction is "up" in the frame
    // based on how the camera sensor is oriented relative to the device

    final isFrontCamera =
        widget.cameras[_currentCameraIndex].lensDirection ==
        CameraLensDirection.front;

    // CRITICAL: iOS and Android have different sensor orientations!
    if (Platform.isIOS) {
      // iOS sensor orientations:
      // - Front camera: 90° (needs to be rotated left to be upright)
      // - Back camera: 90° (needs to be rotated left to be upright)
      return 90;
    } else {
      // Android sensor orientations:
      // - Front camera: 270° (landscape, mirrored)
      // - Back camera: 90° (landscape)
      if (isFrontCamera) {
        return 270;
      } else {
        return 90;
      }
    }
  }

  /// Calculate video dimensions while preserving aspect ratio
  /// Frame dimensions from camera are already in correct display orientation
  /// Fits video within available screen space with letterboxing/pillarboxing
  Size _calculateVideoDimensions(Size screenSpace) {
    if (_imageSize.width <= 0 || _imageSize.height <= 0) {
      return screenSpace;
    }

    // IMPORTANT: Frame dimensions from camera.startImageStream() are already
    // in the correct orientation for display - do NOT swap them based on rotation.
    // Rotation is only needed for ML Kit face detection coordinates, not display.
    final videoAspectRatio = _imageSize.width / _imageSize.height;
    final screenAspectRatio = screenSpace.width / screenSpace.height;

    late double videoWidth;
    late double videoHeight;

    if (videoAspectRatio > screenAspectRatio) {
      // Video is wider: fit to width
      videoWidth = screenSpace.width;
      videoHeight = screenSpace.width / videoAspectRatio;
    } else {
      // Video is taller: fit to height
      videoHeight = screenSpace.height;
      videoWidth = screenSpace.height * videoAspectRatio;
    }

    return Size(videoWidth, videoHeight);
  }

  /// Calculate video position offset (centered in screen space)
  Offset _calculateVideoOffset(Size videoDimensions, Size screenSpace) {
    final offsetX = (screenSpace.width - videoDimensions.width) / 2;
    final offsetY = (screenSpace.height - videoDimensions.height) / 2;
    return Offset(offsetX, offsetY);
  }

  @override
  void initState() {
    super.initState();
    print('🔧 Flutter: _MyHomePageState.initState() START');
    // Start with front camera if available
    _currentCameraIndex = 0;
    final frontCameraIndex = widget.cameras.indexWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
    );
    if (frontCameraIndex != -1) {
      _currentCameraIndex = frontCameraIndex;
      print('🔧 Flutter: Using front camera at index $frontCameraIndex');
    } else {
      print('🔧 Flutter: No front camera found, using camera at index 0');
    }
    print('🔧 Flutter: Calling _initializeCamera()');
    _initializeCamera();
    print('🔧 Flutter: Calling _initializeNativeFaceDetection()');
    _initializeNativeFaceDetection();
  }

  Future<void> _initializeNativeFaceDetection() async {
    print('🚀 Flutter: _initializeNativeFaceDetection() START');

    // Web platform is handled by WebFaceDetectionView (deferred module)
    if (kIsWeb) {
      print(
        '🌐 Flutter: Running on web - face detection handled by WebFaceDetectionView',
      );
      return;
    }

    // Native platforms (iOS/Android) use ML Kit
    try {
      print(
        '🚀 Flutter: Calling platform.invokeMethod(initializeFaceDetection)',
      );
      final result = await platform.invokeMethod('initializeFaceDetection');
      print('🚀 Flutter: Got result from initializeFaceDetection: $result');
      if (result) {
        print('✅ Flutter: Face detection initialized successfully');
        setState(() {
          _debugMessage = "Ready (ML Kit)";
        });
      } else {
        print('❌ Flutter: Face detection initialization returned false');
        setState(() {
          _debugMessage = "Init failed: returned false";
        });
      }
    } catch (e) {
      print('❌ Flutter: Exception in _initializeNativeFaceDetection: $e');
      setState(() {
        _debugMessage = "Init failed: $e";
      });
    }
  }

  Future<void> _initializeCamera() async {
    print('📷 Flutter: _initializeCamera() START');
    try {
      print('📷 Flutter: Creating CameraController with ResolutionPreset.max');

      // Platform-specific camera configuration
      if (kIsWeb) {
        _controller = CameraController(
          widget.cameras[_currentCameraIndex],
          ResolutionPreset.max,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.bgra8888,
        );
      } else if (Platform.isAndroid) {
        _controller = CameraController(
          widget.cameras[_currentCameraIndex],
          ResolutionPreset.max,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.nv21,
        );
      } else {
        // iOS: DON'T specify imageFormatGroup - let camera plugin choose default
        // This avoids "Unsupported pixel format type" errors on camera switch
        _controller = CameraController(
          widget.cameras[_currentCameraIndex],
          ResolutionPreset.max,
          enableAudio: false,
        );
      }

      print('📷 Flutter: Calling _controller.initialize()');
      await _controller.initialize();
      print('✅ Flutter: Camera controller initialized');

      if (!mounted) {
        print('⚠️ Flutter: Widget not mounted after camera init');
        return;
      }

      // Initialize image dimensions from camera preview size
      final previewSize = _controller.value.previewSize;

      if (previewSize != null) {
        _lastImageWidth = previewSize.width.toInt();
        _lastImageHeight = previewSize.height.toInt();
        print(
          '📷 Flutter: Preview size: ${_lastImageWidth}x${_lastImageHeight}',
        );
      }

      print('📷 Flutter: Starting image stream');
      _controller.startImageStream((image) {
        Future.microtask(() => _processFrame(image));
      });
      print('✅ Flutter: Image stream started');

      setState(() {
        _isSwitchingCamera = false;
      });
    } catch (e) {
      print('❌ Flutter: Camera error: $e');
      setState(() {
        _debugMessage = "Camera error: $e";
        _isSwitchingCamera = false;
      });
    }
  }

  Future<void> _processFrame(CameraImage image) async {
    // Skip if switching cameras to prevent crashes
    if (_isSwitchingCamera) {
      return;
    }

    // Skip if controller is not initialized or disposed
    try {
      if (!_controller.value.isInitialized) {
        return;
      }
    } catch (e) {
      // Controller might be disposed, skip processing
      return;
    }

    final now = DateTime.now();

    // Only process every 100ms to reduce overhead
    if (now.difference(_lastProcessTime).inMilliseconds < 100) {
      return;
    }
    _lastProcessTime = now;

    if (_isProcessing) return;

    _isProcessing = true;
    _frameCount++;

    try {
      // Calculate FPS
      if (now.difference(_lastFpsTime).inMilliseconds > 1000) {
        if (mounted) {
          setState(() {
            _fps =
                _frameCount /
                now.difference(_lastFpsTime).inMilliseconds *
                1000;
            _frameCount = 0;
            _lastFpsTime = now;
          });
        }
      }

      // Update image dimensions
      _lastImageWidth = image.width;
      _lastImageHeight = image.height;
      _imageSize = Size(image.width.toDouble(), image.height.toDouble());

      final mlKitRotation = _calculateMLKitRotation();
      final isFrontCamera =
          widget.cameras[_currentCameraIndex].lensDirection ==
          CameraLensDirection.front;

      // Log rotation info (once per second to avoid spam)
      if (_frameCount % 10 == 0) {
        final cameraInfo = isFrontCamera ? 'FRONT' : 'BACK';
        // ignore: avoid_print
        print(
          '🎥 Flutter: Sending frame: ${image.width}x${image.height}, Rotation: $mlKitRotation°, Camera: $cameraInfo, BytesLength: ${image.planes[0].bytes.length}',
        );
      }

      List<Map<String, dynamic>> facesList = [];

      // Use ML Kit via platform channel (MyHomePage is only used on native platforms)
      print(
        '📤 Flutter: Calling platform.invokeMethod(processFrame) with width=${image.width}, height=${image.height}',
      );
      final result = await platform.invokeMethod<Map>('processFrame', {
        'frameBytes': image.planes[0].bytes,
        'width': image.width,
        'height': image.height,
        'rotation': mlKitRotation,
        'isFrontCamera': isFrontCamera,
      });

      print('📥 Flutter: Got result from processFrame: $result');

      if (result != null) {
        final success = result['success'] as bool;
        print('📥 Flutter: result[success] = $success');

        if (success) {
          facesList = (result['faces'] as List)
              .map((f) => Map<String, dynamic>.from(f as Map))
              .toList();
          print('📥 Flutter: Found ${facesList.length} faces');
        } else {
          print('❌ Flutter: processFrame returned success=false');
        }
      } else {
        print('❌ Flutter: processFrame returned null result');
      }

      // Convert face data to Face objects
      if (facesList.isNotEmpty) {
        final faces = facesList
            .map(
              (f) => Face(
                x: (f['x'] as num).toDouble(),
                y: (f['y'] as num).toDouble(),
                width: (f['width'] as num).toDouble(),
                height: (f['height'] as num).toDouble(),
              ),
            )
            .toList();

        if (mounted && !_isSwitchingCamera) {
          try {
            final previewSize = _controller.value.previewSize;
            setState(() {
              _detectedFaces = faces;
              final w = previewSize?.width.toInt() ?? 0;
              final h = previewSize?.height.toInt() ?? 0;
              final platform = kIsWeb ? 'Web' : 'Native';
              _debugMessage =
                  'Faces: ${faces.length} | Image: ${_lastImageWidth}x$_lastImageHeight | Preview: ${w}x$h | FPS: ${_fps.toStringAsFixed(1)} | $platform';
            });
          } catch (e) {
            print('⚠️ Flutter: Error updating UI with face results: $e');
          }
        }
      }
    } catch (e) {
      print('❌ Flutter: Exception in _processFrame: $e');
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _switchCamera() async {
    if (_isSwitchingCamera || widget.cameras.length < 2) return;

    print('🔄 Flutter: Camera switch requested');

    // Set this flag IMMEDIATELY to block new frame processing
    setState(() {
      _isSwitchingCamera = true;
      _detectedFaces = [];
    });

    try {
      print('🔄 Flutter: Blocking new frame processing');

      // CRITICAL: Stop image stream FIRST
      // This prevents new frames from being queued
      if (_controller.value.isStreamingImages) {
        print('🔄 Flutter: Stopping image stream');
        try {
          await _controller.stopImageStream();
          print('✅ Flutter: Image stream stopped');
        } catch (e) {
          print('⚠️ Flutter: Error stopping stream: $e');
        }
      }

      // Wait for any in-flight frame processing to complete
      print('🔄 Flutter: Waiting for pending frame processing to complete...');
      for (int i = 0; i < 150; i++) {
        if (!_isProcessing) break;
        await Future.delayed(const Duration(milliseconds: 50));
      }

      if (_isProcessing) {
        print('⚠️ Flutter: Frame processing still active after 7.5s, forcing stop');
        _isProcessing = false;
      }

      // CRITICAL: Dispose the old controller
      // This must complete fully before creating a new one
      print('🔄 Flutter: Disposing old camera controller');
      try {
        await _controller.dispose();
        print('✅ Flutter: Camera controller disposed');
      } catch (e) {
        print('⚠️ Flutter: Error disposing controller: $e');
      }

      // CRITICAL: Long wait for iOS camera framework to fully release resources
      // The AVCaptureSession and AVCaptureDevice need to be completely cleaned up
      // Otherwise the new camera initialization fails with pixel format error
      print('🔄 Flutter: Waiting for AVCapture resources to be released...');
      await Future.delayed(const Duration(milliseconds: 2000));

      // Switch to next camera
      _currentCameraIndex = (_currentCameraIndex + 1) % widget.cameras.length;
      print('🔄 Flutter: Switched camera index to $_currentCameraIndex');

      // Reinitialize with new camera
      print('🔄 Flutter: Initializing new camera');
      await _initializeCamera();

      print('✅ Flutter: Camera switch complete');
    } catch (e) {
      print('❌ Flutter: CRASH during camera switch: $e');
      print('❌ Flutter: Stack trace: ${StackTrace.current}');
      setState(() {
        _debugMessage = "Switch failed: $e";
        _isSwitchingCamera = false;
      });
    }
  }

  /// Calculate detection canvas dimensions
  /// Canvas matches the actual video area (preserving aspect ratio)
  void _updateDetectionCanvasDimensions(Size bodySize) {
    final videoDimensions = _calculateVideoDimensions(bodySize);
    final videoOffset = _calculateVideoOffset(videoDimensions, bodySize);

    _detectionCanvasSize = videoDimensions;
    _detectionCanvasOffset = videoOffset;

    // Debug logging
    // ignore: avoid_print
    print(
      '📐 CANVAS: size=${videoDimensions.width.toInt()}x${videoDimensions.height.toInt()} @ (${videoOffset.dx.toInt()},${videoOffset.dy.toInt()})',
    );
  }

  /// Transform face coordinates from image space to screen space
  /// CRITICAL: Account for rotation changing effective image dimensions and front camera mirroring
  FaceBox _transformFaceCoordinates(Face face) {
    if (_imageSize.width <= 0 ||
        _imageSize.height <= 0 ||
        _detectionCanvasSize.width <= 0) {
      return FaceBox(left: 0, top: 0, width: 0, height: 0);
    }

    final rotation = _calculateMLKitRotation();
    final isFrontCamera =
        widget.cameras[_currentCameraIndex].lensDirection ==
        CameraLensDirection.front;

    // When rotation is 90° or 270°, the effective image dimensions are SWAPPED
    // Original: 1600x1200
    // After 90° rotation: effectively 1200x1600 (width and height swap!)

    late double effectiveImageWidth;
    late double effectiveImageHeight;

    if (rotation == 90 || rotation == 270) {
      // Dimensions are swapped due to rotation
      effectiveImageWidth = _imageSize.height;
      effectiveImageHeight = _imageSize.width;
    } else {
      // No swap for 0° or 180°
      effectiveImageWidth = _imageSize.width;
      effectiveImageHeight = _imageSize.height;
    }

    // Calculate scale factors using EFFECTIVE dimensions
    final scaleX = _detectionCanvasSize.width / effectiveImageWidth;
    final scaleY = _detectionCanvasSize.height / effectiveImageHeight;

    // Transform the bounding box
    var left = face.x * scaleX;
    final top = face.y * scaleY;
    final width = face.width * scaleX;
    final height = face.height * scaleY;

    // Front camera at 270° is horizontally mirrored in ML Kit coordinates
    // Flip X coordinate to match visual position
    if (isFrontCamera && (rotation == 270 || rotation == 90)) {
      left = _detectionCanvasSize.width - left - width;
    }

    // ignore: avoid_print
    print(
      '✅ Transform: face(${face.x.toInt()}, ${face.y.toInt()}) → screen(${left.toInt()}, ${top.toInt()}) | rotation=$rotation° | camera=${isFrontCamera ? 'FRONT' : 'BACK'} | effective dims: ${effectiveImageWidth.toInt()}x${effectiveImageHeight.toInt()}',
    );

    return FaceBox(left: left, top: top, width: width, height: height);
  }

  /// Build a rotation test button
  Widget _buildRotationButton(int rotation) {
    final isActive = _overrideRotation == rotation;
    return ElevatedButton(
      onPressed: () {
        setState(() {
          _overrideRotation = rotation;
        });
        // ignore: avoid_print
        print('🧪 Testing rotation: $rotation°');
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isActive ? Colors.orange : Colors.blue[900],
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: Text(
        '$rotation°',
        style: TextStyle(
          fontSize: 11,
          color: Colors.white,
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized || _isSwitchingCamera) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Pixelation'),
        backgroundColor: Colors.grey[700],
        foregroundColor: Colors.white,
        actions: [
          // Debug UI toggle
          IconButton(
            icon: Icon(_showDebugUI ? Icons.info : Icons.info_outline),
            onPressed: () {
              setState(() {
                _showDebugUI = !_showDebugUI;
              });
            },
            tooltip: 'Toggle Debug UI',
          ),
          // Camera switch
          if (widget.cameras.length > 1)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Center(
                child: _isSwitchingCamera
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: const Icon(Icons.flip_camera_ios),
                        onPressed: _switchCamera,
                        tooltip: 'Switch Camera',
                      ),
              ),
            ),
        ],
      ),
      body: Builder(
        builder: (context) {
          // Get actual screen size from MediaQuery
          final screenSize = MediaQuery.of(context).size;
          final appBarHeight = AppBar().preferredSize.height;
          // Body size = full screen minus AppBar (which is in Scaffold above this body)
          final bodySize = Size(
            screenSize.width,
            screenSize.height - appBarHeight,
          );

          // Calculate detection canvas dimensions on layout
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _updateDetectionCanvasDimensions(bodySize);
          });

          // ⚠️ DEBUG: Log what we're rendering
          if (_showRedBorder || _showTealBorder) {
            // ignore: avoid_print
            print(
              '🎨 BUILD: screenSize=${screenSize.width.toInt()}x${screenSize.height.toInt()} | bodySize=${bodySize.width.toInt()}x${bodySize.height.toInt()} | appBarHeight=${appBarHeight.toInt()}',
            );
          }

          // Calculate video dimensions that preserve aspect ratio
          final videoDimensions = _calculateVideoDimensions(bodySize);
          final videoOffset = _calculateVideoOffset(videoDimensions, bodySize);

          return Container(
            width: bodySize.width,
            height: bodySize.height,
            color: Colors.black,
            child: Stack(
              children: [
                // CENTERED VIDEO PREVIEW - Preserves aspect ratio
                Positioned(
                  left: videoOffset.dx,
                  top: videoOffset.dy,
                  width: videoDimensions.width,
                  height: videoDimensions.height,
                  child: Container(
                    decoration: _showRedBorder
                        ? BoxDecoration(
                            border: Border.all(color: Colors.red, width: 5),
                          )
                        : null,
                    child: CameraPreview(_controller),
                  ),
                ),

                // TEAL BORDER - overlays on top of video
                if (_showTealBorder)
                  Positioned(
                    left: videoOffset.dx,
                    top: videoOffset.dy,
                    width: videoDimensions.width,
                    height: videoDimensions.height,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.cyan, width: 3),
                      ),
                    ),
                  ),

                // Face count above video stream
                Positioned(
                  top: videoOffset.dy - 40,
                  left: videoOffset.dx,
                  right:
                      videoOffset.dx +
                      (bodySize.width - videoOffset.dx - videoDimensions.width),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Faces: ${_detectedFaces.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),

                // Face detection boxes - flat list, no nested Stacks
                if (_detectedFaces.isNotEmpty &&
                    _detectionCanvasSize != Size.zero)
                  ..._detectedFaces.map((face) {
                    final box = _transformFaceCoordinates(face);
                    return Positioned(
                      left: _detectionCanvasOffset.dx + box.left,
                      top: _detectionCanvasOffset.dy + box.top,
                      width: box.width,
                      height: box.height,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.green, width: 2),
                        ),
                      ),
                    );
                  }),

                // Status overlay with detailed debug info
                if (_showDebugUI)
                  Positioned(
                    top: 8,
                    left: 8,
                    right: 8,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _debugMessage,
                              style: const TextStyle(
                                color: Colors.green,
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Screen: ${bodySize.width.toInt()}x${bodySize.height.toInt()}',
                              style: const TextStyle(
                                color: Colors.lightBlue,
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              'Camera frame: ${_imageSize.width.toInt()}x${_imageSize.height.toInt()}',
                              style: const TextStyle(
                                color: Colors.yellow,
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              'Video area: ${_detectionCanvasSize.width.toInt()}x${_detectionCanvasSize.height.toInt()}',
                              style: const TextStyle(
                                color: Colors.cyan,
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              'Video offset: (${_detectionCanvasOffset.dx.toInt()}, ${_detectionCanvasOffset.dy.toInt()})',
                              style: const TextStyle(
                                color: Colors.cyan,
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Rotation: ${_calculateMLKitRotation()}°${_overrideRotation != null ? ' (OVERRIDE)' : ''}',
                              style: TextStyle(
                                color: _overrideRotation != null
                                    ? Colors.orange
                                    : Colors.lightGreen,
                                fontFamily: 'monospace',
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _isProcessing ? 'Processing...' : 'Ready',
                              style: TextStyle(
                                color: _isProcessing
                                    ? Colors.orange
                                    : Colors.green,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Aspect ratios
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.grey,
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Camera aspect: ${(_imageSize.width / _imageSize.height).toStringAsFixed(3)}',
                                    style: const TextStyle(
                                      color: Colors.yellow,
                                      fontFamily: 'monospace',
                                      fontSize: 10,
                                    ),
                                  ),
                                  Text(
                                    'Video aspect: ${(_detectionCanvasSize.width / _detectionCanvasSize.height).toStringAsFixed(3)}',
                                    style: const TextStyle(
                                      color: Colors.cyan,
                                      fontFamily: 'monospace',
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _showRedBorder = !_showRedBorder;
                                    });
                                  },
                                  child: Text(
                                    '🔴 Red: ${_showRedBorder ? 'ON' : 'OFF'}',
                                    style: TextStyle(
                                      color: _showRedBorder
                                          ? Colors.red
                                          : Colors.grey,
                                      fontFamily: 'monospace',
                                      fontSize: 10,
                                      fontWeight: _showRedBorder
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _showTealBorder = !_showTealBorder;
                                    });
                                  },
                                  child: Text(
                                    '🔷 Teal: ${_showTealBorder ? 'ON' : 'OFF'}',
                                    style: TextStyle(
                                      color: _showTealBorder
                                          ? Colors.cyan
                                          : Colors.grey,
                                      fontFamily: 'monospace',
                                      fontSize: 10,
                                      fontWeight: _showTealBorder
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _showTestPanel = !_showTestPanel;
                                    });
                                  },
                                  child: Text(
                                    'Test: ${_showTestPanel ? 'ON' : 'OFF'}',
                                    style: TextStyle(
                                      color: _showTestPanel
                                          ? Colors.orange
                                          : Colors.lightBlue,
                                      fontFamily: 'monospace',
                                      fontSize: 10,
                                      fontWeight: _showTestPanel
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Test panel - rotation testing buttons
                if (_showTestPanel)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange, width: 2),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '🔄 ROTATION TEST PANEL',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontFamily: 'monospace',
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Current: ${_overrideRotation ?? 'AUTO'} | Detected faces: ${_detectedFaces.length}',
                            style: TextStyle(
                              color: _detectedFaces.isNotEmpty
                                  ? Colors.lightGreen
                                  : Colors.red,
                              fontFamily: 'monospace',
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildRotationButton(0),
                              _buildRotationButton(90),
                              _buildRotationButton(180),
                              _buildRotationButton(270),
                              ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    _overrideRotation = null;
                                  });
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.grey[700],
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                                child: const Text(
                                  'AUTO',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.grey[900],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _overrideRotation != null
                                  ? '⚠️ Testing rotation: $_overrideRotation°\nLook for faces in logcat'
                                  : '✓ Using auto-calculated rotation\nNo override active',
                              style: TextStyle(
                                color: _overrideRotation != null
                                    ? Colors.orange
                                    : Colors.lightGreen,
                                fontFamily: 'monospace',
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class Face {
  final double x;
  final double y;
  final double width;
  final double height;

  Face({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}

/// Represents a face bounding box in screen space coordinates
class FaceBox {
  final double left;
  final double top;
  final double width;
  final double height;

  FaceBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}
