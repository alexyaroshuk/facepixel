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
  bool _showDebugUI = false;
  bool _showRedBorder = true;
  bool _showTealBorder = true;
  bool _pixelationEnabled = false;
  int _pixelationLevel = 10;

  @override
  void initState() {
    super.initState();
    _initializeWebCamera();
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
          setState(() {
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

    // FIRST: Set up event listener BEFORE starting JS
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
    print('🌐 Web: Event listener registered');

    // SECOND: Call startApp() in JavaScript to initialize MediaPipe and camera
    try {
      // Call the startApp() function we defined in face_detection.js
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Pixelation'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
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
        ],
      ),
      body: Builder(
        builder: (context) {
          final screenSize = MediaQuery.of(context).size;
          final canvasOffset = _calculateCanvasOffset(screenSize);

          // Account for AppBar height when passing to JavaScript
          // MediaQuery.of(context).size returns body size (below AppBar)
          // But JavaScript uses position: fixed which is viewport-relative (includes AppBar)
          final appBarHeight = AppBar().preferredSize.height;
          final statusBarHeight = MediaQuery.of(context).padding.top;
          final adjustedCanvasOffsetY = canvasOffset.dy + appBarHeight + statusBarHeight;

          // Sync canvas dimensions and offset with JavaScript (fixed dimensions)
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
                    width: _canvasWidth,
                    height: _canvasHeight,
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
                  width: _canvasWidth,
                  height: _canvasHeight,
                  child: HtmlElementView(viewType: _videoViewType),
                ),

                // Teal detection canvas area (for debugging)
                if (_showTealBorder)
                  Positioned(
                    left: canvasOffset.dx,
                    top: canvasOffset.dy,
                    width: _canvasWidth,
                    height: _canvasHeight,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.teal.withValues(alpha: 0.1),
                        border: Border.all(color: Colors.cyan, width: 3),
                      ),
                    ),
                  ),

                // Face detection boxes - only show when blur is disabled (for reference)
                if (!_pixelationEnabled && _videoSize != Size.zero)
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

                // Backdrop blur overlay is handled by JavaScript (CSS backdrop-filter)
                // See web/face_detection.js updateBlurOverlay() function

                // Face count display above video stream
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
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _debugMessage,
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Screen: ${screenSize.width.toInt()}x${screenSize.height.toInt()}',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              'Video size: ${_videoSize.width.toInt()}x${_videoSize.height.toInt()}',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              'Canvas (fixed): ${_canvasWidth.toInt()}x${_canvasHeight.toInt()}',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              'Canvas offset: (${canvasOffset.dx.toInt()}, ${canvasOffset.dy.toInt()})',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontFamily: 'monospace',
                                fontSize: 11,
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
                                      color: _showRedBorder ? Colors.red : Colors.grey,
                                      fontFamily: 'monospace',
                                      fontSize: 10,
                                      fontWeight: _showRedBorder ? FontWeight.bold : FontWeight.normal,
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
                                      color: _showTealBorder ? Colors.cyan : Colors.grey,
                                      fontFamily: 'monospace',
                                      fontSize: 10,
                                      fontWeight: _showTealBorder ? FontWeight.bold : FontWeight.normal,
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

                // Pixelation level slider control
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
