import 'dart:async';
import 'package:flutter/material.dart';

// Web-specific imports - safe because this file is deferred and only loaded on web
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:js_util' as js_util;
import 'dart:ui_web' as ui_web;
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
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
  // ignore: unused_field
  String _debugMessage = "Initializing...";
  int _frameCount = 0;
  DateTime _lastFpsTime = DateTime.now();
  double _fps = 0;
  Size _videoSize = Size.zero;
  bool _pixelationEnabled = false;
  int _pixelationLevel = 10;
  bool _faceDetectionInitialized = false;
  bool _cameraPermissionDenied = false;
  bool _cameraRequested = false;

  @override
  void initState() {
    super.initState();
    // ignore: avoid_print
    print('🌐 Web: WebFaceDetectionView.initState() called');

    // Register the video element factory (doesn't create element yet)
    _registerVideoElementFactory();

    // Request camera automatically
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _requestCameraAccess();
      }
    });
  }

  void _registerVideoElementFactory() {
    // Register the video element factory
    ui_web.platformViewRegistry.registerViewFactory(
      _videoViewType,
      (int viewId) {
        final video = html.VideoElement()
          ..id = 'webcam'
          ..autoplay = true
          ..muted = true
          ..attributes['playsinline'] = 'true'
          ..attributes['crossorigin'] = 'anonymous'
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.objectFit = 'cover'
          ..style.transform = 'scaleX(-1)';

        // Request camera access when element is created
        // ignore: avoid_print
        print('🌐 Web: Platform view factory called, requesting camera...');
        html.window.navigator.mediaDevices
            ?.getUserMedia({'video': true, 'audio': false}).then((stream) {
          if (!mounted) return;

          // ignore: avoid_print
          print('🌐 Web: Got camera stream, setting srcObject...');
          video.srcObject = stream;

          // Wait for video to actually have dimensions (not just metadata)
          var checkDimensionsCount = 0;
          void checkVideoDimensions() {
            checkDimensionsCount++;
            if (video.videoWidth > 0 && video.videoHeight > 0) {
              // Video has actual dimensions now
              if (!mounted) return;

              // ignore: avoid_print
              print('🌐 Web: Video dimensions available: ${video.videoWidth}x${video.videoHeight}');
              setState(() {
                _videoSize = Size(
                  video.videoWidth.toDouble(),
                  video.videoHeight.toDouble(),
                );
                _debugMessage = "Ready (Web/MediaPipe)";
              });

              // Start face detection
              _startFaceDetection();
            } else if (checkDimensionsCount < 50) {
              // Keep checking for dimensions (up to 50 times = 2.5 seconds)
              Future.delayed(const Duration(milliseconds: 50), checkVideoDimensions);
            } else {
              // Timeout - just start anyway
              if (!mounted) return;
              // ignore: avoid_print
              print('🌐 Web: Video dimensions timeout, starting detection anyway...');
              setState(() {
                _videoSize = Size(
                  video.videoWidth.toDouble(),
                  video.videoHeight.toDouble(),
                );
              });
              _startFaceDetection();
            }
          }

          // Start checking dimensions immediately
          checkVideoDimensions();
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
              _cameraRequested = false;
            }
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

    // Set up event listener for detected faces FIRST (before calling JavaScript)
    html.window.addEventListener('facesDetected', (html.Event event) {
      // ignore: avoid_print
      print('🌐 Web: RECEIVED facesDetected event from JavaScript!');
      final customEvent = event as html.CustomEvent;
      final detail = customEvent.detail;
      if (detail != null && detail['faces'] != null) {
        final faces = detail['faces'] as List;
        // ignore: avoid_print
        print('🌐 Web: Processing ${faces.length} detected faces');
        _onFacesDetected(faces);
      } else {
        // ignore: avoid_print
        print('🌐 Web: facesDetected event has no faces data');
      }
    });

    // ignore: avoid_print
    print('🌐 Web: Event listener registered, now calling startApp()...');

    // Call JavaScript to initialize MediaPipe and start detection
    try {
      js_util.callMethod(html.window, 'startApp', []);
      // ignore: avoid_print
      print('🌐 Web: Called JavaScript startApp()');
    } catch (e) {
      // ignore: avoid_print
      print('🌐 Web: Error calling startApp(): $e');
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

  Future<void> _requestCameraAccess() async {
    if (!mounted) return;

    setState(() {
      _cameraRequested = true;
    });

    // ignore: avoid_print
    print('🌐 Web: User requesting camera access...');
  }

  @override
  Widget build(BuildContext context) {
    // Show permission denied screen if access was denied
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
                    'This app requires camera access. Please enable camera permissions in your browser settings.',
                    style: TextStyle(
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
                      fontStyle: FontStyle.italic,
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Pixelation'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Pixelation toggle (only show after camera is working)
          if (_cameraRequested)
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

                // If camera not requested yet, show welcome screen
                if (!_cameraRequested)
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.videocam,
                          size: 64,
                          color: Colors.deepPurple,
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
                        const Text(
                          'Please allow camera access when prompted by your browser',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                // Video element - only render after camera is requested
                if (_cameraRequested)
                  Positioned(
                    left: canvasOffset.dx,
                    top: canvasOffset.dy,
                    width: _canvasWidth,
                    height: _canvasHeight,
                    child: HtmlElementView(viewType: _videoViewType),
                  ),
                // Show loading overlay on top while initializing (after camera requested)
                if (_cameraRequested && _videoSize == Size.zero)
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
                if (_cameraRequested && _videoSize != Size.zero)
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

                // Face detection boxes - only show when blur is disabled
                if (_cameraRequested &&
                    _videoSize != Size.zero &&
                    !_pixelationEnabled &&
                    _detectedFaces.isNotEmpty)
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

                // Pixelation level slider control (only when enabled)
                if (_cameraRequested && _videoSize != Size.zero && _pixelationEnabled)
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
