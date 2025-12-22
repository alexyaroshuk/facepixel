import 'package:flutter/material.dart';

/// Stub implementation for non-web platforms
class WebFaceDetectionView extends StatelessWidget {
  const WebFaceDetectionView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Face Pixelation')),
      body: const Center(child: Text('Web only')),
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
