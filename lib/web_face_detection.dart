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
  bool _showDebugUI = true;
  bool _showRedBorder = true;
  bool _showTealBorder = true;

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
        title: const Text('Face Pixelation (Web)'),
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
        ],
      ),
      body: Builder(
        builder: (context) {
          final screenSize = MediaQuery.of(context).size;
          final canvasOffset = _calculateCanvasOffset(screenSize);

          // Sync canvas dimensions with JavaScript once (fixed dimensions)
          WidgetsBinding.instance.addPostFrameCallback((_) {
            try {
              js_util.callMethod(
                html.window,
                'updateCanvasDimensions',
                [_canvasWidth, _canvasHeight],
              );
            } catch (e) {
              // ignore: avoid_print
              print('🌐 Web: Error updating canvas dimensions: $e');
            }
          });

          return Container(
            width: screenSize.width,
            height: screenSize.height,
            color: Colors.black,
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

                // Face detection boxes - positioned relative to canvas
                if (_videoSize != Size.zero)
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
                          border: Border.all(color: Colors.green, width: 2),
                        ),
                      ),
                    );
                  }),

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
                                color: Colors.green,
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Screen: ${screenSize.width.toInt()}x${screenSize.height.toInt()}',
                              style: const TextStyle(
                                color: Colors.lightBlue,
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              'Video size: ${_videoSize.width.toInt()}x${_videoSize.height.toInt()}',
                              style: const TextStyle(
                                color: Colors.yellow,
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              'Canvas (fixed): ${_canvasWidth.toInt()}x${_canvasHeight.toInt()}',
                              style: const TextStyle(
                                color: Colors.cyan,
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              'Canvas offset: (${canvasOffset.dx.toInt()}, ${canvasOffset.dy.toInt()})',
                              style: const TextStyle(
                                color: Colors.cyan,
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
