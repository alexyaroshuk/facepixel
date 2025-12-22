import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// Web-specific imports - safe because this file is deferred and only loaded on web
import 'dart:js_interop' as js;
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
  List<FaceBox> _detectedFaces = [];
  bool _isReady = false;
  String _debugMessage = "Initializing...";
  int _frameCount = 0;
  DateTime _lastFpsTime = DateTime.now();
  double _fps = 0;
  Size _videoSize = Size.zero;

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
              _isReady = true;
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
    print('🌐 Web: Setting up face detection...');

    // FIRST: Set up event listener BEFORE starting JS
    html.window.addEventListener('facesDetected', (html.Event event) {
      final customEvent = event as html.CustomEvent;
      final detail = customEvent.detail;
      if (detail != null && detail['faces'] != null) {
        final faces = detail['faces'] as List;
        _onFacesDetected(faces);
      } else {
        print('🌐 Web: Received facesDetected event with null detail');
      }
    });

    print('🌐 Web: Event listener registered');

    // SECOND: Call startApp() in JavaScript to initialize MediaPipe and camera
    try {
      // Call the startApp() function we defined in face_detection.js
      js_util.callMethod(html.window, 'startApp', []);
      print('🌐 Web: Called JavaScript startApp()');
    } catch (e) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Pixelation (Web)'),
        backgroundColor: Colors.grey[700],
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // Video element
          HtmlElementView(viewType: _videoViewType),

          // Face detection boxes
          if (_videoSize != Size.zero)
            ..._detectedFaces.map((face) {
              return Positioned(
                left: face.left,
                top: face.top,
                width: face.width,
                height: face.height,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.green, width: 2),
                  ),
                ),
              );
            }),

          // Debug overlay
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
              child: Text(
                _debugMessage,
                style: const TextStyle(
                  color: Colors.green,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
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
