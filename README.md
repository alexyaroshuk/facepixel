# Face Pixel

A real-time face detection and privacy protection app built with Flutter. Detects faces in camera feeds and applies pixelation/blur effects to protect identity and privacy.

## Live Demo

Try the app now: [https://facepixel.vercel.app/](https://facepixel.vercel.app/)

## Features

- **Real-Time Face Detection**: Detects faces from live camera feeds using on-device ML
- **Privacy Pixelation**: Dynamically blur detected faces with adjustable intensity (1-100)
- **Multi-Camera Support**: Switch between front and back cameras
- **Cross-Platform**: Works on Android, iOS, and Web
- **Debug Tools**: Performance metrics, rotation testing, and visual debugging controls
- **On-Device Processing**: All face detection and pixelation happens locally—no cloud transmission

## Supported Platforms

- **Android**: ML Kit face detection via method channels
- **iOS**: ML Kit Vision Framework
- **Web**: MediaPipe Tasks Vision API

## Getting Started

### Prerequisites

- Flutter SDK (latest stable or higher)
- Xcode 13+ (for iOS development)
- Android Studio/SDK 21+ (for Android development)

### Installation

1. Clone the repository:
   ```bash
   git clone <repo-url>
   cd facepixel
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run the app:
   ```bash
   # Android
   flutter run -d android

   # iOS
   flutter run -d ios

   # Web
   flutter run -d web
   ```

## Architecture

### Project Structure

```
lib/
  ├── main.dart                    # Main Flutter app UI
  ├── web_face_detection.dart      # Web-specific face detection
  └── web_face_detection_stub.dart # Stub for native platforms

android/
  └── app/src/main/kotlin/com/facepixel/app/
      ├── MainActivity.kt          # Android activity with method channel
      └── facedetection/
          ├── FaceDetector.kt      # ML Kit face detection wrapper
          ├── CameraFrameProcessor.kt  # Frame processing logic
          └── RectData.kt          # Face rectangle data class

ios/
  └── Runner/AppDelegate.swift     # iOS face detection setup

web/
  ├── face_detection.js            # MediaPipe integration
  └── index.html
```

### Key Components

- **Native Camera Processing**: Android (Kotlin) handles frame processing and face detection
- **Platform Channels**: Dart communicates with native code via method channels
- **Web Implementation**: JavaScript/TypeScript integration with MediaPipe for browser-based detection
- **UI Layer**: Flutter provides consistent Material Design UI across platforms

## Usage

1. **Launch the App**: Camera starts automatically on app open with a loading screen
2. **Toggle Pixelation**: Use the privacy icon in the AppBar to enable/disable blur effect
3. **Adjust Blur Strength**: Use the slider to control pixelation intensity
4. **Switch Cameras**: Use the camera flip icon to switch between front and back cameras
5. **Debug Mode**: Toggle the info icon to view performance metrics and rotation testing controls

## Technical Details

### Face Detection Libraries

- **Android/iOS**: Google ML Kit
- **Web**: MediaPipe Tasks Vision

### Camera Handling

Platform-specific rotation handling accounts for different sensor orientations:
- **iOS**: Both cameras at 90° rotation, portrait frame delivery
- **Android**: Front camera 270°, back camera 90°, landscape frame delivery

### Performance

App includes built-in FPS counter and performance monitoring for debugging real-time performance issues.

## Development

### Running Tests

```bash
flutter test
```

### Code Analysis

```bash
flutter analyze
```

### Build Modes

```bash
# Debug (development)
flutter run

# Release (optimized)
flutter run --release

# Profile (performance testing)
flutter run --profile
```

## Privacy

Face detection and pixelation are performed entirely on-device. No data is sent to external servers or cloud services.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

```
MIT License

Copyright (c) 2025

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
```

## Contributing

Contributions are welcome! Feel free to:
- Report bugs via GitHub Issues
- Submit feature requests
- Create pull requests with improvements

## Support

For issues, questions, or suggestions, please open a GitHub issue or check the [Discussions](../../discussions) section.
