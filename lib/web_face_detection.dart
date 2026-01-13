import 'dart:async';
import 'package:flutter/material.dart';

// Web-specific imports - safe because this file is deferred and only loaded on web
import 'dart:js_util' as js_util;
import 'dart:ui_web' as ui_web;
import 'dart:html' as html;
import 'logger.dart';

/// Web-specific face detection widget using HTML video element and MediaPipe
class WebFaceDetectionView extends StatefulWidget {
  const WebFaceDetectionView({super.key});

  @override
  State<WebFaceDetectionView> createState() => _WebFaceDetectionViewState();
}

class _WebFaceDetectionViewState extends State<WebFaceDetectionView> {
  static const String _videoViewType = 'face-detection-video';
  // Maximum canvas dimensions (will shrink to fit smaller screens)
  static const double _maxCanvasWidth = 640.0;
  static const double _maxCanvasHeight = 480.0;
  static const double _aspectRatio = 4.0 / 3.0;

  List<FaceBox> _detectedFaces = [];
  String _debugMessage = "Initializing...";
  int _frameCount = 0;
  DateTime _lastFpsTime = DateTime.now();
  double _fps = 0;
  Size _videoSize = Size.zero;
  bool _showDebugUI = false;
  bool _showRedBorder = false;  // Disabled for production
  bool _showTealBorder = false;  // Disabled for production
  bool _pixelationEnabled = false;
  int _pixelationLevel = 10;
  bool _permissionDenied = false;
  String _permissionErrorMessage = "Camera permission denied";
  bool _cameraRequested = false;  // Track if user has requested camera access
  bool _showConfidence = false;  // Toggle for displaying confidence scores

  @override
  void initState() {
    super.initState();
    // Don't initialize camera here - wait for user to click button
    AppLogger.info('Web view initialized', 'web');
  }

  Future<void> _requestCameraAccess() async {
    AppLogger.info('Camera access requested', 'web');
    if (mounted) {
      setState(() {
        _cameraRequested = true;
      });
    }
    await _initializeWebCamera();
  }

  Future<void> _initializeWebCamera() async {
    // Register the video element factory
    ui_web.platformViewRegistry.registerViewFactory(
      _videoViewType,
      (int viewId) {
        final video = html.VideoElement()
          ..id = 'webcam'  // Must match the ID that face_detection.js expects
          ..autoplay = true
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.objectFit = 'cover';

        // Request camera access
        html.window.navigator.mediaDevices
            ?.getUserMedia({'video': true, 'audio': false}).then((stream) {
          video.srcObject = stream;

          // Wait for video to be ready
          video.onLoadedMetadata.listen((_) {
            setState(() {
              _videoSize = Size(
                video.videoWidth.toDouble(),
                video.videoHeight.toDouble(),
              );
              _debugMessage = "Ready (Web/MediaPipe)";
            });

            // Start face detection
            _startFaceDetection();
          });
        }).catchError((error) {
          final errorMsg = error.toString().toLowerCase();
          final isPermissionError = errorMsg.contains('permission') ||
                                   errorMsg.contains('notallowed') ||
                                   errorMsg.contains('denied');

          setState(() {
            if (isPermissionError) {
              _permissionDenied = true;
              _permissionErrorMessage = "Camera access was denied. Please enable camera permissions in your browser settings.";
            }
            _debugMessage = "Camera error: $error";
          });
        });

        return video;
      },
    );
  }

  /// Apply pixelation using JavaScript overlay
  void _applyPixelation() {
    try {
      // Call JavaScript function to set pixelation settings
      js_util.callMethod(
        html.window,
        'setPixelationSettings',
        [_pixelationEnabled, _pixelationLevel],
      );
      AppLogger.debug('Pixelation settings changed: enabled=$_pixelationEnabled, level=$_pixelationLevel', 'web');
    } catch (e) {
      AppLogger.error('Error setting pixelation: $e', 'web', e);
    }
  }

  void _startFaceDetection() {
    AppLogger.info('Setting up face detection', 'web');

    // FIRST: Set up event listener BEFORE starting JS
    html.window.addEventListener('facesDetected', (html.Event event) {
      final customEvent = event as html.CustomEvent;
      final detail = customEvent.detail;
      if (detail != null && detail['faces'] != null) {
        final faces = detail['faces'] as List;
        _onFacesDetected(faces);
      } else {
        AppLogger.warning('Received facesDetected event with null detail', 'web');
      }
    });

    AppLogger.debug('Event listener registered', 'web');

    // SECOND: Call startApp() in JavaScript to initialize MediaPipe and camera
    try {
      // Call the startApp() function we defined in face_detection.js
      js_util.callMethod(html.window, 'startApp', []);
      AppLogger.info('Face detection engine initialized', 'web');
    } catch (e) {
      AppLogger.error('Error initializing face detection: $e', 'web', e);
    }
  }

  void _onFacesDetected(List faces) {
    _frameCount++;
    final now = DateTime.now();

    // Calculate FPS
    if (now.difference(_lastFpsTime).inMilliseconds > 1000) {
      setState(() {
        _fps = _frameCount / now.difference(_lastFpsTime).inMilliseconds * 1000;
        _frameCount = 0;
        _lastFpsTime = now;
      });
    }

    // Convert faces to FaceBox objects
    final List<FaceBox> faceBoxes = [];
    for (var face in faces) {
      faceBoxes.add(FaceBox(
        left: (face['x'] as num).toDouble(),
        top: (face['y'] as num).toDouble(),
        width: (face['width'] as num).toDouble(),
        height: (face['height'] as num).toDouble(),
        confidence: (face['confidence'] as num?)?.toDouble() ?? 0.5,
      ));
    }

    setState(() {
      _detectedFaces = faceBoxes;
      _debugMessage =
          'Faces: ${faceBoxes.length} | Video: ${_videoSize.width.toInt()}x${_videoSize.height.toInt()} | FPS: ${_fps.toStringAsFixed(1)} | Web';
    });
  }


  /// Calculate canvas size that fits within screen while maintaining aspect ratio
  /// Uses max 640x480 but shrinks proportionally for smaller screens
  Size _calculateCanvasSize(Size screenSize) {
    // Reserve space for control bar (50px) above and slider (130px) below when enabled
    const double controlBarHeight = 50.0;
    final double sliderHeight = _pixelationEnabled ? 130.0 : 20.0;
    const double padding = 16.0;
    
    final double availableWidth = screenSize.width - (padding * 2);
    final double availableHeight = screenSize.height - controlBarHeight - sliderHeight;
    
    // Start with max dimensions
    double canvasWidth = _maxCanvasWidth;
    double canvasHeight = _maxCanvasHeight;
    
    // Shrink to fit available width if needed
    if (canvasWidth > availableWidth) {
      canvasWidth = availableWidth;
      canvasHeight = canvasWidth / _aspectRatio;
    }
    
    // Shrink to fit available height if needed
    if (canvasHeight > availableHeight) {
      canvasHeight = availableHeight;
      canvasWidth = canvasHeight * _aspectRatio;
    }
    
    // Ensure positive dimensions
    canvasWidth = canvasWidth.clamp(100.0, _maxCanvasWidth);
    canvasHeight = canvasHeight.clamp(75.0, _maxCanvasHeight);
    
    return Size(canvasWidth, canvasHeight);
  }

  /// Calculate canvas offset to center canvas in available space
  Offset _calculateCanvasOffset(Size screenSize, Size canvasSize) {
    // Control bar is above, so offset from top accounts for it
    const double controlBarHeight = 50.0;
    final double offsetX = (screenSize.width - canvasSize.width) / 2;
    final double offsetY = controlBarHeight + ((screenSize.height - controlBarHeight - canvasSize.height) / 2) - 40;
    return Offset(offsetX.clamp(0.0, screenSize.width), offsetY.clamp(controlBarHeight, screenSize.height));
  }

  @override
  Widget build(BuildContext context) {
    // Show permission denied screen
    if (_permissionDenied) {
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
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    _permissionErrorMessage,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Then refresh the page to try again.',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Note: If _cameraRequested is true, we skip the welcome screen
    // and build the main video scaffold below (which includes HtmlElementView)
    // This allows the permission prompt to appear. The loading overlay is shown
    // in the main scaffold's Stack when _videoSize == Size.zero

    // Show welcome screen if camera hasn't been requested yet
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
      ),
      body: Builder(
        builder: (context) {
          final screenSize = MediaQuery.of(context).size;
          final canvasSize = _calculateCanvasSize(screenSize);
          final canvasOffset = _calculateCanvasOffset(screenSize, canvasSize);
          final canvasWidth = canvasSize.width;
          final canvasHeight = canvasSize.height;

          // Account for AppBar height when passing to JavaScript
          final appBarHeight = AppBar().preferredSize.height;
          final statusBarHeight = MediaQuery.of(context).padding.top;
          final adjustedCanvasOffsetY = canvasOffset.dy + appBarHeight + statusBarHeight;

          // Sync canvas dimensions and offset with JavaScript
          WidgetsBinding.instance.addPostFrameCallback((_) {
            try {
              js_util.callMethod(
                html.window,
                'updateCanvasDimensions',
                [canvasWidth, canvasHeight, canvasOffset.dx, adjustedCanvasOffsetY],
              );
            } catch (e) {
              AppLogger.error('Error updating canvas dimensions: $e', 'web', e);
            }
          });

          return Container(
            width: screenSize.width,
            height: screenSize.height,
            color: const Color(0xFF1A1A1A),
            child: Stack(
              children: [
                // Red border - video stream area (for debugging)
                if (_showRedBorder)
                  Positioned(
                    left: canvasOffset.dx,
                    top: canvasOffset.dy,
                    width: canvasWidth,
                    height: canvasHeight,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.red, width: 5),
                      ),
                    ),
                  ),

                // Video element - positioned within the canvas
                Positioned(
                  left: canvasOffset.dx,
                  top: canvasOffset.dy,
                  width: canvasWidth,
                  height: canvasHeight,
                  child: HtmlElementView(viewType: _videoViewType),
                ),

                // Teal detection canvas area (for debugging)
                if (_showTealBorder)
                  Positioned(
                    left: canvasOffset.dx,
                    top: canvasOffset.dy,
                    width: canvasWidth,
                    height: canvasHeight,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.teal.withValues(alpha: 0.1),
                        border: Border.all(color: Colors.cyan, width: 3),
                      ),
                    ),
                  ),

                // Face detection boxes - only show when blur is disabled
                if (!_pixelationEnabled && _videoSize != Size.zero) ...[
                  ..._detectedFaces.map((face) {
                    final scaleX = canvasWidth / _videoSize.width;
                    final scaleY = canvasHeight / _videoSize.height;

                    final boxLeft = canvasOffset.dx + (face.left * scaleX);
                    final boxTop = canvasOffset.dy + (face.top * scaleY);
                    final boxWidth = face.width * scaleX;
                    final boxHeight = face.height * scaleY;

                    return Positioned(
                      left: boxLeft,
                      top: boxTop,
                      width: boxWidth,
                      height: boxHeight,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.black, width: 1),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 1),
                          ),
                        ),
                      ),
                    );
                  }),
                  // Confidence labels
                  if (_showConfidence)
                    ..._detectedFaces.map((face) {
                      final scaleX = canvasWidth / _videoSize.width;
                      final scaleY = canvasHeight / _videoSize.height;

                      final boxLeft = canvasOffset.dx + (face.left * scaleX);
                      final boxTop = canvasOffset.dy + (face.top * scaleY);
                      final boxWidth = face.width * scaleX;
                      final confidenceText = '${(face.confidence * 100).toStringAsFixed(0)}%';

                      return Stack(
                        children: [
                          Positioned(
                            left: boxLeft + boxWidth - 40,
                            top: boxTop - 20,
                            child: Text(
                              confidenceText,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                foreground: Paint()
                                  ..strokeWidth = 3
                                  ..color = Colors.black
                                  ..style = PaintingStyle.stroke,
                              ),
                            ),
                          ),
                          Positioned(
                            left: boxLeft + boxWidth - 40,
                            top: boxTop - 20,
                            child: Text(
                              confidenceText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                ],

                // Control bar above video stream
                Positioned(
                  top: canvasOffset.dy - 50,
                  left: canvasOffset.dx,
                  width: canvasWidth,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Faces count
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Faces: ${_detectedFaces.length}',
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ),
                      // Buttons
                      Row(
                        children: [
                          ElevatedButton(
                            onPressed: () => setState(() => _showConfidence = !_showConfidence),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _showConfidence ? Colors.white : Colors.black87,
                              foregroundColor: _showConfidence ? Colors.black : Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            child: const Text('Info', style: TextStyle(fontSize: 14)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () {
                              setState(() => _pixelationEnabled = !_pixelationEnabled);
                              _applyPixelation();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _pixelationEnabled ? Colors.white : Colors.black87,
                              foregroundColor: _pixelationEnabled ? Colors.black : Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            child: const Text('Blur', style: TextStyle(fontSize: 14)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Debug overlay
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_debugMessage, style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 11)),
                          const SizedBox(height: 4),
                          Text('Screen: ${screenSize.width.toInt()}x${screenSize.height.toInt()}', style: const TextStyle(color: Colors.grey, fontFamily: 'monospace', fontSize: 11)),
                          Text('Video: ${_videoSize.width.toInt()}x${_videoSize.height.toInt()}', style: const TextStyle(color: Colors.grey, fontFamily: 'monospace', fontSize: 11)),
                          Text('Canvas: ${canvasWidth.toInt()}x${canvasHeight.toInt()}', style: const TextStyle(color: Colors.grey, fontFamily: 'monospace', fontSize: 11)),
                        ],
                      ),
                    ),
                  ),

                // Blur slider control
                if (_pixelationEnabled)
                  Positioned(
                    top: canvasOffset.dy + canvasHeight + 12,
                    left: canvasOffset.dx,
                    width: canvasWidth,
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
                              const Text('Blur Strength', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              const Spacer(),
                              Text(_pixelationLevel.toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Slider(
                            value: _pixelationLevel.toDouble(),
                            min: 1,
                            max: 100,
                            divisions: 99,
                            activeColor: Colors.white,
                            inactiveColor: Colors.grey[800],
                            onChanged: (value) {
                              setState(() => _pixelationLevel = value.toInt());
                              _applyPixelation();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                // Loading overlay
                if (_cameraRequested && _videoSize == Size.zero)
                  Container(
                    color: Colors.black.withValues(alpha: 0.6),
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                          SizedBox(height: 24),
                          Text('Requesting camera access...', style: TextStyle(color: Colors.white, fontSize: 16)),
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

class FaceBox {
  final double left;
  final double top;
  final double width;
  final double height;
  final double confidence;

  FaceBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.confidence = 0.5,
  });
}
