import 'dart:io' show Platform;
import 'dart:async' show TimeoutException;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'logger.dart';
// Conditional import: use web implementation on web, stub on native platforms (Android/iOS)
import 'web_face_detection.dart'
    if (dart.library.io) 'web_face_detection_stub.dart'
    deferred as web_module;

void main() async {
  AppLogger.info('Application started', 'main');
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.info('WidgetsFlutterBinding initialized', 'main');

  // Only enumerate cameras on native platforms (iOS/Android)
  // Web implementation uses MediaPipe directly via JavaScript, doesn't need camera plugin
  late List<CameraDescription> cameras;
  if (kIsWeb) {
    cameras = [];
    AppLogger.info('Web platform detected, skipping camera enumeration', 'main');
  } else {
    cameras = await availableCameras();
    AppLogger.info('Found ${cameras.length} cameras', 'main');
    for (int i = 0; i < cameras.length; i++) {
      final camera = cameras[i];
      final lensDir = camera.lensDirection == CameraLensDirection.front
          ? 'FRONT'
          : 'BACK';
      AppLogger.debug('Camera $i: $lensDir', 'main');
    }
  }

  AppLogger.info('Initializing app', 'main');
  runApp(MyApp(cameras: cameras));
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
  bool _faceDetectionInitialized = false;
  bool _cameraPermissionDenied = false;
  bool _controllerInitialized = false;
  bool _cameraRequested = false;

  // Image dimensions (from camera frames)
  Size _imageSize = Size.zero;

  // Detection canvas dimensions (where face boxes should render)
  Size _detectionCanvasSize = Size.zero;
  Offset _detectionCanvasOffset = Offset.zero;

  // Debug visualization
  int? _overrideRotation; // Override rotation for testing

  // Pixelation settings
  bool _pixelationEnabled = false;
  int _pixelationLevel = 10; // 1-100, lower = more pixels (more privacy)

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
  /// Uses camera output dimensions from controller's preview size
  /// Fits video within available screen space with letterboxing/pillarboxing
  Size _calculateVideoDimensions(Size screenSpace) {
    // Get camera preview size - this is the actual camera output dimensions
    var previewSize = _controller.value.previewSize;
    if (previewSize == null || previewSize.width <= 0 || previewSize.height <= 0) {
      return screenSpace;
    }

    // For portrait mode display: if preview is landscape (width > height), swap dimensions
    if (previewSize.width > previewSize.height) {
      previewSize = Size(previewSize.height, previewSize.width);
    }

    final videoAspectRatio = previewSize.width / previewSize.height;
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
    AppLogger.info('State initialized', 'init');
    // Start with front camera if available
    _currentCameraIndex = 0;
    final frontCameraIndex = widget.cameras.indexWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
    );
    if (frontCameraIndex != -1) {
      _currentCameraIndex = frontCameraIndex;
      AppLogger.debug('Using front camera at index $frontCameraIndex', 'init');
    } else {
      AppLogger.debug('No front camera found, using camera at index 0', 'init');
    }

    // Mark as ready without requesting camera permission yet
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppLogger.debug('UI ready, waiting for user to enable camera', 'init');
      if (mounted) {
        setState(() {
          _faceDetectionInitialized = true;
          _debugMessage = "Ready - Tap 'Enable Camera' to start";
        });
      }
    });

    // Safety timeout: if not initialized after 15 seconds, force show app
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted && !_faceDetectionInitialized) {
        AppLogger.warning('Face detection initialization timeout', 'init');
        setState(() {
          _faceDetectionInitialized = true;
          _debugMessage = "Initialized (timeout)";
        });
      }
    });
  }

  Future<void> _initializeNativeFaceDetection() async {
    AppLogger.info('Initializing native face detection', 'faceDetection');

    // Web platform is handled by WebFaceDetectionView (deferred module)
    if (kIsWeb) {
      AppLogger.info('Web platform detected, using WebFaceDetectionView', 'faceDetection');
      if (mounted) {
        setState(() {
          _faceDetectionInitialized = true;
        });
      }
      return;
    }

    // Native platforms (iOS/Android) use ML Kit
    try {
      AppLogger.debug('Invoking platform method: initializeFaceDetection', 'faceDetection');
      final result = await platform.invokeMethod('initializeFaceDetection');
      AppLogger.debug('Platform method returned: $result', 'faceDetection');
      if (result) {
        AppLogger.info('Face detection initialized', 'faceDetection');
        if (mounted) {
          setState(() {
            _faceDetectionInitialized = true;
            _debugMessage = "Ready (ML Kit)";
          });
        }
      } else {
        AppLogger.error('Face detection initialization failed', 'faceDetection');
        if (mounted) {
          setState(() {
            _faceDetectionInitialized = true;
            _debugMessage = "Init failed: returned false";
          });
        }
      }
    } catch (e) {
      AppLogger.error('Exception during face detection initialization: $e', 'faceDetection', e);
      if (mounted) {
        setState(() {
          _faceDetectionInitialized = true;
          _debugMessage = "Init failed: $e";
        });
      }
    }
  }

  Future<void> _requestCameraAccess() async {
    AppLogger.info('Camera access requested', 'camera');
    if (mounted) {
      setState(() {
        _cameraRequested = true;
      });
    }
    await _initializeCamera();
    await _initializeNativeFaceDetection();
  }

  Future<void> _initializeCamera() async {
    AppLogger.info('Initializing camera', 'camera');
    try {
      AppLogger.debug('Creating CameraController', 'camera');

      // Simple platform-specific config like fluttercamtest
      if (kIsWeb) {
        _controller = CameraController(
          widget.cameras[_currentCameraIndex],
          ResolutionPreset.high,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.bgra8888,
        );
      } else if (Platform.isAndroid) {
        _controller = CameraController(
          widget.cameras[_currentCameraIndex],
          ResolutionPreset.high,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.nv21,
        );
      } else {
        // iOS: Simple initialization without forcing any format
        _controller = CameraController(
          widget.cameras[_currentCameraIndex],
          ResolutionPreset.high,
          enableAudio: false,
        );
      }

      AppLogger.debug('Initializing controller', 'camera');
      await _controller.initialize();
      AppLogger.info('Camera initialized', 'camera');

      if (!mounted) {
        return;
      }

      // Update preview size
      final previewSize = _controller.value.previewSize;
      if (previewSize != null) {
        _lastImageWidth = previewSize.width.toInt();
        _lastImageHeight = previewSize.height.toInt();
        AppLogger.debug('Preview size: ${_lastImageWidth}x${_lastImageHeight}', 'camera');
      }

      setState(() {
        _isSwitchingCamera = false;
        _cameraPermissionDenied = false;
        _controllerInitialized = true;
      });

      // Start image stream AFTER camera is stable
      await _startImageStream();
    } catch (e) {
      AppLogger.error('Camera initialization failed: $e', 'camera', e);

      // Check if this is a permission error
      final isPermissionError = e.toString().toLowerCase().contains('permission') ||
                                e.toString().toLowerCase().contains('denied');

      setState(() {
        _debugMessage = "Camera error: $e";
        _isSwitchingCamera = false;
        _controllerInitialized = false;
        if (isPermissionError) {
          _cameraPermissionDenied = true;
        }
      });
    }
  }

  Future<void> _startImageStream() async {
    if (_isSwitchingCamera) {
      AppLogger.warning('Skipping image stream start, camera switching', 'camera');
      return;
    }

    try {
      AppLogger.debug('Starting image stream', 'camera');
      await _controller.startImageStream((image) {
        Future.microtask(() => _processFrame(image));
      });
      AppLogger.info('Image stream started', 'camera');
    } catch (e) {
      AppLogger.error('Error starting image stream: $e', 'camera', e);
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
        AppLogger.debug(
          'Frame: ${image.width}x${image.height}, Rotation: $mlKitRotation°, Camera: $cameraInfo',
          'processing',
        );
      }

      List<Map<String, dynamic>> facesList = [];

      // Use ML Kit via platform channel (MyHomePage is only used on native platforms)
      final result = await platform.invokeMethod<Map>('processFrame', {
        'frameBytes': image.planes[0].bytes,
        'width': image.width,
        'height': image.height,
        'rotation': mlKitRotation,
        'isFrontCamera': isFrontCamera,
      });

      if (result != null) {
        final success = result['success'] as bool;

        if (success) {
          facesList = (result['faces'] as List)
              .map((f) => Map<String, dynamic>.from(f as Map))
              .toList();
          AppLogger.debug('Detected ${facesList.length} faces', 'processing');
        } else {
          AppLogger.warning('Face detection returned success=false', 'processing');
        }
      } else {
        AppLogger.error('Face detection returned null result', 'processing');
      }

      // Convert face data to Face objects
      List<Face> faces = [];

      if (facesList.isNotEmpty) {
        faces = facesList
            .map(
              (f) => Face(
                x: (f['x'] as num).toDouble(),
                y: (f['y'] as num).toDouble(),
                width: (f['width'] as num).toDouble(),
                height: (f['height'] as num).toDouble(),
              ),
            )
            .toList();
      }

      // Always update state, even if no faces are detected (to clear old faces)
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
          AppLogger.error('Error updating UI with face results: $e', 'processing', e);
        }
      }
    } catch (e) {
      AppLogger.error('Exception in frame processing: $e', 'processing', e);
      // CRITICAL: Only clear faces if detection truly failed
      // Don't clear on transient errors
      if (mounted && !_isSwitchingCamera) {
        try {
          setState(() {
            _debugMessage = 'Error: $e';
          });
        } catch (_) {
          // Ignore setState errors during cleanup
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _switchCamera() async {
    if (_isSwitchingCamera || widget.cameras.length < 2) return;

    setState(() {
      _isSwitchingCamera = true;
      _detectedFaces = [];
    });

    try {
      _currentCameraIndex = (_currentCameraIndex + 1) % widget.cameras.length;
      AppLogger.info('Switching to camera $_currentCameraIndex', 'camera');

      await _controller.dispose();
      AppLogger.debug('Controller disposed', 'camera');

      await _initializeCamera();
      AppLogger.info('Camera switch completed', 'camera');
    } catch (e) {
      AppLogger.error('Camera switch failed: $e', 'camera', e);
      setState(() {
        _debugMessage = "Switch failed: $e";
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

    // Account for frame orientation and rotation
    // Android delivers landscape frames (1280x720), iOS delivers portrait frames (720x1280)
    // Only swap dimensions if frame is landscape AND rotation indicates swap needed

    late double effectiveImageWidth;
    late double effectiveImageHeight;

    final isFrameLandscape = _imageSize.width > _imageSize.height;

    if ((rotation == 90 || rotation == 270) && isFrameLandscape) {
      // Frame is landscape and rotation says to swap for ML Kit
      effectiveImageWidth = _imageSize.height;
      effectiveImageHeight = _imageSize.width;
    } else {
      // Frame is already in correct orientation or doesn't need swapping
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

    // Front camera is horizontally mirrored in ML Kit coordinates
    // Only flip if frame is landscape (Android) - iOS portrait frames don't need flipping
    if (isFrontCamera && isFrameLandscape) {
      left = _detectionCanvasSize.width - left - width;
    }

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
        AppLogger.debug('Testing rotation: $rotation°', 'test');
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
    if (_controllerInitialized) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show permission denied screen if camera access was denied (check this first before accessing _controller)
    if (_cameraPermissionDenied) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Face Pixelation'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Container(
          color: const Color(0xFF1A1A1A),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 64,
                  color: Colors.white,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Camera Access Denied',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'This app requires camera access to detect and pixelate faces. Please enable camera permissions in your device settings.',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () {
                    // Retry camera initialization
                    setState(() {
                      _cameraPermissionDenied = false;
                      _cameraRequested = false;
                    });
                    _requestCameraAccess();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 12,
                    ),
                  ),
                  child: const Text('Try Again'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // If camera requested but not yet initialized, show loading
    if (_cameraRequested && (!_controllerInitialized || (_controllerInitialized && !_controller.value.isInitialized) || _isSwitchingCamera)) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Face Pixelation'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Show loading overlay while face detection initializes (after camera is requested)
    if (_cameraRequested && !_faceDetectionInitialized) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Face Pixelation'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Stack(
          children: [
            // Show camera preview in background
            Container(
              color: const Color(0xFF1A1A1A),
              child: Center(
                child: CameraPreview(_controller),
              ),
            ),
            // Loading overlay
            Container(
              color: Colors.black.withValues(alpha: 0.6),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                    SizedBox(height: 24),
                    Text(
                      'Initializing face detection...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // If camera not requested yet, show welcome screen
    if (!_cameraRequested) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Face Pixelation'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ElevatedButton(
                onPressed: _requestCameraAccess,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
                child: const Text('Enable Camera'),
              ),
            ),
          ],
        ),
        body: Container(
          color: const Color(0xFF1A1A1A),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.videocam,
                  size: 64,
                  color: Colors.white,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Face Pixelation',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Real-time face detection and pixelation for privacy',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: _requestCameraAccess,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                  child: const Text('Enable Camera'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Pixelation'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Pixelation toggle (only show after camera is working)
          if (_cameraRequested && !_cameraPermissionDenied)
            IconButton(
              icon: Icon(
                _pixelationEnabled ? Icons.privacy_tip : Icons.privacy_tip_outlined,
                color: _pixelationEnabled ? Colors.white : Colors.grey,
              ),
              onPressed: () {
                setState(() {
                  _pixelationEnabled = !_pixelationEnabled;
                });
              },
              tooltip: 'Toggle Blur',
            ),
          // Camera switch button
          if (_cameraRequested && !_cameraPermissionDenied && widget.cameras.length > 1)
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


          // Calculate video dimensions that preserve aspect ratio
          final videoDimensions = _calculateVideoDimensions(bodySize);
          final videoOffset = _calculateVideoOffset(videoDimensions, bodySize);

          return Container(
            width: bodySize.width,
            height: bodySize.height,
            color: const Color(0xFF1A1A1A),
            child: Stack(
              children: [
                // CENTERED VIDEO PREVIEW - Preserves aspect ratio
                Positioned(
                  left: videoOffset.dx,
                  top: videoOffset.dy,
                  width: videoDimensions.width,
                  height: videoDimensions.height,
                  child: CameraPreview(_controller),
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

                // Face detection boxes - only show when blur is disabled (for reference)
                if (!_pixelationEnabled &&
                    _detectedFaces.isNotEmpty &&
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
                          border: Border.all(color: Colors.black, width: 3),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                        ),
                      ),
                    );
                  }),

                // Backdrop blur overlay for detected faces
                if (_pixelationEnabled &&
                    _detectedFaces.isNotEmpty &&
                    _detectionCanvasSize != Size.zero)
                  ..._detectedFaces.map((face) {
                    final box = _transformFaceCoordinates(face);
                    // Calculate blur sigma from blur level (1-100)
                    // Level 1 = minimal blur, Level 100 = heavy blur
                    final blurSigma = (_pixelationLevel / 2).toDouble();

                    return Positioned(
                      left: _detectionCanvasOffset.dx + box.left,
                      top: _detectionCanvasOffset.dy + box.top,
                      width: box.width,
                      height: box.height,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(box.width * 0.15),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(
                            sigmaX: blurSigma,
                            sigmaY: blurSigma,
                          ),
                          child: Container(
                            // Transparent container to apply the blur
                            color: Colors.transparent,
                          ),
                        ),
                      ),
                    );
                  }),


                // Blur level slider control
                if (_pixelationEnabled)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.privacy_tip, color: Colors.white),
                              const SizedBox(width: 8),
                              const Text(
                                'Blur Strength',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _pixelationLevel.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Slider(
                            value: _pixelationLevel.toDouble(),
                            min: 1,
                            max: 100,
                            divisions: 99,
                            label: _pixelationLevel.toString(),
                            activeColor: Colors.white,
                            inactiveColor: Colors.grey[800],
                            onChanged: (value) {
                              setState(() {
                                _pixelationLevel = value.toInt();
                              });
                            },
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: const [
                                Text(
                                  'Subtle (1)',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 10,
                                  ),
                                ),
                                Text(
                                  'Strong (100)',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
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

