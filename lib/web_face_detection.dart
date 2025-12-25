import 'dart:async';
import 'package:flutter/material.dart';

// Web-specific imports - safe because this file is deferred and only loaded on web
import 'dart:js_util' as js_util;
import 'dart:ui_web' as ui_web;
import 'dart:html' as html;

/// Web-specific face detection widget using HTML video element and MediaPipe
class WebFaceDetectionView extends StatefulWidget {
  const WebFaceDetectionView({super.key});

  @override
  State<WebFaceDetectionView> createState() => _WebFaceDetectionViewState();
}

class _WebFaceDetectionViewState extends State<WebFaceDetectionView> {
  static const String _videoViewType = 'face-detection-video';
  static const double _canvasWidth = 640.0;  // Fixed canvas width
  static const double _canvasHeight = 480.0; // Fixed canvas height (4:3 aspect ratio)

  List<FaceBox> _detectedFaces = [];
  String _debugMessage = "Initializing...";
  int _frameCount = 0;
  DateTime _lastFpsTime = DateTime.now();
  double _fps = 0;
  Size _videoSize = Size.zero;
  bool _pixelationEnabled = false;
  int _pixelationLevel = 10;
  bool _faceDetectionInitialized = false;
  bool _cameraPermissionDenied = false;

  @override
  void initState() {
    super.initState();
    // ignore: avoid_print
    print('🌐 Web: WebFaceDetectionView.initState() called');

    // Defer camera initialization so the page loads first
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ignore: avoid_print
      print('🌐 Web: First frame complete, calling _initializeWebCamera()');
      _initializeWebCamera();
    });

    // Safety timeout: if not initialized after 15 seconds, force show app
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted && !_faceDetectionInitialized) {
        // ignore: avoid_print
        print('🌐 Web: Initialization timeout - forcing UI to show');
        setState(() {
          _faceDetectionInitialized = true;
          _debugMessage = "Initialized (timeout)";
        });
      }
    });
  }

  Future<void> _initializeWebCamera() async {
    // Register the video element factory FIRST (no camera access needed yet)
    ui_web.platformViewRegistry.registerViewFactory(
      _videoViewType,
      (int viewId) {
        final video = html.VideoElement()
          ..id = 'webcam'  // Must match the ID that face_detection.js expects
          ..autoplay = true
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.objectFit = 'cover';

        return video;
      },
    );

    // Then request camera access after a delay to ensure UI is rendered
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;

      // ignore: avoid_print
      print('🌐 Web: Requesting camera access...');

      // Request camera access
      html.window.navigator.mediaDevices
          ?.getUserMedia({'video': true, 'audio': false}).then((stream) {
        if (!mounted) return;

        final videoElement = html.document.getElementById('webcam') as html.VideoElement?;
        if (videoElement != null) {
          videoElement.srcObject = stream;

          // Wait for video to be ready
          videoElement.onLoadedMetadata.listen((_) {
            if (!mounted) return;

            setState(() {
              _videoSize = Size(
                videoElement.videoWidth.toDouble(),
                videoElement.videoHeight.toDouble(),
              );
              _debugMessage = "Ready (Web/MediaPipe)";
              _cameraPermissionDenied = false;
            });

            // Start face detection
            _startFaceDetection();
          });
        }
      }).catchError((error) {
        if (!mounted) return;

        // Check if this is a permission error
        final isPermissionError = error.toString().toLowerCase().contains('permission') ||
                                  error.toString().toLowerCase().contains('notallowed') ||
                                  error.toString().toLowerCase().contains('denied');

        // ignore: avoid_print
        print('🌐 Web: Camera error: $error');

        setState(() {
          _debugMessage = "Camera error: $error";
          if (isPermissionError) {
            _cameraPermissionDenied = true;
          }
        });
      });
    });
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
      // ignore: avoid_print
      print('🌐 Web: Set pixelation: enabled=$_pixelationEnabled, level=$_pixelationLevel');
    } catch (e) {
      // ignore: avoid_print
      print('🌐 Web: Error setting pixelation: $e');
    }
  }

  void _startFaceDetection() {
    // ignore: avoid_print
    print('🌐 Web: Setting up face detection...');

    // FIRST: Set up detector ready listener
    html.window.addEventListener('detectorReady', (html.Event event) {
      final customEvent = event as html.CustomEvent;
      final detail = customEvent.detail;
      final success = detail?['success'] as bool? ?? false;

      if (success) {
        // ignore: avoid_print
        print('🌐 Web: MediaPipe detector ready!');
        if (mounted) {
          setState(() {
            _faceDetectionInitialized = true;
            _debugMessage = "Ready (Web/MediaPipe)";
          });
        }
      } else {
        final error = detail?['error'] as String? ?? 'Unknown error';
        // ignore: avoid_print
        print('🌐 Web: MediaPipe detector initialization failed: $error');
        if (mounted) {
          setState(() {
            _faceDetectionInitialized = true;
            _debugMessage = "Init failed: $error";
          });
        }
      }
    });

    // SECOND: Set up event listener for faces detected
    html.window.addEventListener('facesDetected', (html.Event event) {
      final customEvent = event as html.CustomEvent;
      final detail = customEvent.detail;
      if (detail != null && detail['faces'] != null) {
        final faces = detail['faces'] as List;
        _onFacesDetected(faces);
      } else {
        // ignore: avoid_print
        print('🌐 Web: Received facesDetected event with null detail');
      }
    });

    // ignore: avoid_print
    print('🌐 Web: Event listeners registered');

    // THIRD: Call startApp() in JavaScript to initialize MediaPipe and camera
    try {
      // Call the startApp() function we defined in face_detection.js
      js_util.callMethod(html.window, 'startApp', []);
      // ignore: avoid_print
      print('🌐 Web: Called JavaScript startApp()');
    } catch (e) {
      // ignore: avoid_print
      print('🌐 Web: Error calling startApp(): $e');
      if (mounted) {
        setState(() {
          _faceDetectionInitialized = true;
          _debugMessage = "Init failed: $e";
        });
      }
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
      ));
    }

    setState(() {
      _detectedFaces = faceBoxes;
      _debugMessage =
          'Faces: ${faceBoxes.length} | Video: ${_videoSize.width.toInt()}x${_videoSize.height.toInt()} | FPS: ${_fps.toStringAsFixed(1)} | Web';
    });
  }


  /// Calculate canvas offset to center fixed-size canvas in available space
  Offset _calculateCanvasOffset(Size screenSize) {
    final offsetX = (screenSize.width - _canvasWidth) / 2;
    final offsetY = (screenSize.height - _canvasHeight) / 2;
    return Offset(offsetX, offsetY);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final canvasOffset = _calculateCanvasOffset(screenSize);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Pixelation'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: !_faceDetectionInitialized
            ? null
            : [
                // Pixelation toggle
                IconButton(
                  icon: Icon(
                    _pixelationEnabled ? Icons.privacy_tip : Icons.privacy_tip_outlined,
                    color: _pixelationEnabled ? Colors.white : Colors.grey,
                  ),
                  onPressed: () {
                    setState(() {
                      _pixelationEnabled = !_pixelationEnabled;
                    });
                    _applyPixelation();
                  },
                  tooltip: 'Toggle Blur',
                ),
              ],
      ),
      body: Builder(
        builder: (context) {
          final screenSize = MediaQuery.of(context).size;
          final canvasOffset = _calculateCanvasOffset(screenSize);

          // Account for AppBar height when passing to JavaScript
          final appBarHeight = AppBar().preferredSize.height;
          final statusBarHeight = MediaQuery.of(context).padding.top;
          final adjustedCanvasOffsetY = canvasOffset.dy + appBarHeight + statusBarHeight;

          // Sync canvas dimensions and offset with JavaScript (fixed dimensions)
          if (_faceDetectionInitialized) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              try {
                js_util.callMethod(
                  html.window,
                  'updateCanvasDimensions',
                  [_canvasWidth, _canvasHeight, canvasOffset.dx, adjustedCanvasOffsetY],
                );
              } catch (e) {
                // ignore: avoid_print
                print('🌐 Web: Error updating canvas dimensions: $e');
              }
            });
          }

          return Container(
            width: screenSize.width,
            height: screenSize.height,
            color: const Color(0xFF1A1A1A),
            child: Stack(
              children: [
                // Background color
                Positioned.fill(
                  child: Container(
                    color: const Color(0xFF1A1A1A),
                  ),
                ),

                // Loading message at top center (visible immediately)
                if (!_faceDetectionInitialized && !_cameraPermissionDenied)
                  Positioned(
                    top: 50,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Text(
                        'Initializing...',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),

                // Video element - always render so camera initialization can proceed
                Positioned(
                  left: canvasOffset.dx,
                  top: canvasOffset.dy,
                  width: _canvasWidth,
                  height: _canvasHeight,
                  child: HtmlElementView(viewType: _videoViewType),
                ),


                // Show permission denied overlay if camera access was denied
                if (_cameraPermissionDenied)
                  Container(
                    color: Colors.black.withValues(alpha: 0.7),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.lock_outline,
                            size: 64,
                            color: Colors.red,
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
                              'This app requires camera access to detect and pixelate faces. Please allow camera access when prompted by your browser.',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 32),
                          ElevatedButton.icon(
                            onPressed: () {
                              // Retry camera initialization
                              // ignore: avoid_print
                              print('🌐 Web: User clicked Try Again');
                              setState(() {
                                _cameraPermissionDenied = false;
                              });
                              _initializeWebCamera();
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Try Again'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                // Show loading overlay on top while initializing
                else if (!_faceDetectionInitialized)
                  Container(
                    color: Colors.black.withValues(alpha: 0.7),
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

                // Face count display above video stream (only when initialized)
                if (_faceDetectionInitialized)
                  Positioned(
                    top: canvasOffset.dy - 40,
                    left: canvasOffset.dx,
                    right: screenSize.width - canvasOffset.dx - _canvasWidth,
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

                // Face detection boxes - only show when initialized and blur is disabled
                if (_faceDetectionInitialized &&
                    !_pixelationEnabled &&
                    _videoSize != Size.zero)
                  ..._detectedFaces.map((face) {
                    // Scale boxes to fixed canvas size
                    final scaleX = _canvasWidth / _videoSize.width;
                    final scaleY = _canvasHeight / _videoSize.height;

                    return Positioned(
                      left: canvasOffset.dx + (face.left * scaleX),
                      top: canvasOffset.dy + (face.top * scaleY),
                      width: face.width * scaleX,
                      height: face.height * scaleY,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white70, width: 1),
                        ),
                      ),
                    );
                  }),


                // Pixelation level slider control (only when initialized and enabled)
                if (_faceDetectionInitialized && _pixelationEnabled)
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
                              _applyPixelation();
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
