import 'dart:async';
import 'package:flutter/material.dart';

// Web-specific imports - safe because this file is deferred and only loaded on web
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:js_util' as js_util;
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Web-specific face detection widget using HTML video element and MediaPipe
class WebFaceDetectionView extends StatefulWidget {
  const WebFaceDetectionView({super.key});

  @override
  State<WebFaceDetectionView> createState() => _WebFaceDetectionViewState();
}

class _WebFaceDetectionViewState extends State<WebFaceDetectionView> {
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

    // Mark as ready (HTML video element already exists)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ignore: avoid_print
      print('🌐 Web: HTML video element is ready for camera stream');
      if (mounted) {
        setState(() {
          _faceDetectionInitialized = true;
          _debugMessage = "Ready - Click 'Enable Camera' to start";
        });
      }
    });
  }

  Future<void> _requestCameraAccess() async {
    if (!mounted) return;

    setState(() {
      _cameraRequested = true;
    });

    // ignore: avoid_print
    print('🌐 Web: User requesting camera access...');

    // Wait for the widget to rebuild and video element to be created
    // This ensures the HtmlElementView has rendered before we request getUserMedia
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attachCameraStream();
    });
  }

  Future<void> _attachCameraStream() async {
    if (!mounted) return;

    // ignore: avoid_print
    print('🌐 Web: Requesting getUserMedia after widget rebuild...');

    // Check if video element exists before requesting
    var videoElement = html.document.getElementById('webcam') as html.VideoElement?;
    // ignore: avoid_print
    print('🌐 Web: Video element exists in DOM: ${videoElement != null}');
    if (videoElement != null) {
      // ignore: avoid_print
      print('🌐 Web: Video element found: id=${videoElement.id}, width=${videoElement.style.width}, height=${videoElement.style.height}');
    }

    // Request camera access
    html.window.navigator.mediaDevices
        ?.getUserMedia({'video': true, 'audio': false}).then((stream) {
      if (!mounted) return;

      // ignore: avoid_print
      print('🌐 Web: getUserMedia succeeded, got stream');

      videoElement = html.document.getElementById('webcam') as html.VideoElement?;

      if (videoElement != null) {
        // ignore: avoid_print
        print('🌐 Web: Setting srcObject on video element...');

        // Debug: Check stream details
        final videoTracks = stream.getVideoTracks();
        // ignore: avoid_print
        print('🌐 Web: Stream has ${videoTracks.length} video tracks');
        if (videoTracks.isNotEmpty) {
          // ignore: avoid_print
          print('🌐 Web: First video track enabled=${videoTracks[0].enabled}, readyState=${videoTracks[0].readyState}');
        }

        videoElement!.srcObject = stream;

        // ignore: avoid_print
        print('🌐 Web: srcObject set. Video element width=${videoElement!.width}, height=${videoElement!.height}, videoWidth=${videoElement!.videoWidth}, videoHeight=${videoElement!.videoHeight}');

        // Ensure video element is visible (not hidden)
        videoElement!.style.display = 'block';
        videoElement!.style.visibility = 'visible';
        videoElement!.style.opacity = '1';

        // Add a small delay to ensure the video element is fully ready
        Future.delayed(const Duration(milliseconds: 100), () {
          if (!mounted) return;

          // ignore: avoid_print
          print('🌐 Web: After delay - videoWidth=${videoElement!.videoWidth}, videoHeight=${videoElement!.videoHeight}');

          // Try to play manually
          final playPromise = videoElement!.play();
          playPromise.then((_) {
            // ignore: avoid_print
            print('🌐 Web: Video play() succeeded');
            // Debug: Check if video is actually playing
            Future.delayed(const Duration(milliseconds: 500), () {
              // ignore: avoid_print
              print('🌐 Web: After play - videoWidth=${videoElement!.videoWidth}, videoHeight=${videoElement!.videoHeight}, paused=${videoElement!.paused}');
            });
          }).catchError((e) {
            // ignore: avoid_print
            print('🌐 Web: Video play() failed: $e');
          });
        });

        // Wait for video to be ready (only listen once, then cancel)
        StreamSubscription? metadataListener;
        metadataListener = videoElement!.onLoadedMetadata.listen((_) {
          if (!mounted) return;

          // ignore: avoid_print
          print('🌐 Web: Video metadata loaded! videoWidth=${videoElement!.videoWidth}, videoHeight=${videoElement!.videoHeight}');

          setState(() {
            _videoSize = Size(
              videoElement!.videoWidth.toDouble(),
              videoElement!.videoHeight.toDouble(),
            );
            _debugMessage = "Ready (Web/MediaPipe)";
            _cameraPermissionDenied = false;
          });

          // Start face detection (only once)
          _startFaceDetection();

          // Cancel the listener to prevent repeated calls
          metadataListener?.cancel();
        });
      } else {
        // ignore: avoid_print
        print('🌐 Web: ERROR - Video element not found in DOM after getUserMedia');
        if (mounted) {
          setState(() {
            _debugMessage = "ERROR: Video element not found in DOM";
            _cameraPermissionDenied = true;
            _cameraRequested = false;
          });
        }
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
          _cameraRequested = false; // Reset so user can try again
        }
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Pixelation'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Enable camera button (if not requested yet)
          if (_faceDetectionInitialized && !_cameraRequested)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ElevatedButton.icon(
                onPressed: _requestCameraAccess,
                icon: const Icon(Icons.videocam),
                label: const Text('Enable Camera'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
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
          if (_faceDetectionInitialized && _cameraRequested) {
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
                        ElevatedButton.icon(
                          onPressed: _requestCameraAccess,
                          icon: const Icon(Icons.videocam),
                          label: const Text('Enable Camera'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 16,
                            ),
                            textStyle: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Video element is rendered via HTML (index.html), not Flutter widget
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
                                _cameraRequested = false;
                              });
                              _requestCameraAccess();
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
                // Show loading overlay on top while initializing (after camera requested)
                else if (_cameraRequested && !_faceDetectionInitialized)
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

                // Face count display above video stream (only when initialized and camera requested)
                if (_cameraRequested && _faceDetectionInitialized)
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

                // Face detection boxes - only show when camera requested, initialized, and blur is disabled
                if (_cameraRequested &&
                    _faceDetectionInitialized &&
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

                // Pixelation level slider control (only when camera requested, initialized, and enabled)
                if (_cameraRequested && _faceDetectionInitialized && _pixelationEnabled)
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
