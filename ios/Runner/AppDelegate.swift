import Flutter
import UIKit
import MLKitFaceDetection
import MLKitVision
import AVFoundation
import CoreMedia

// Professional logging utility
func AppLog(_ message: String, tag: String = "AppDelegate") {
  #if DEBUG
  print("[\(tag)] \(message)")
  #endif
}

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var faceDetector: FaceDetector?
  private let detectionQueue = DispatchQueue(label: "com.facepixel.facedetection", qos: .userInitiated)

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    AppLog("Application initialized", tag: "app")

    guard let controller = window?.rootViewController as? FlutterViewController else {
      AppLog("Failed to get FlutterViewController", tag: "app")
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    let faceDetectionChannel = FlutterMethodChannel(
      name: "com.facepixel.app/faceDetection",
      binaryMessenger: controller.binaryMessenger
    )

    faceDetectionChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "initializeFaceDetection":
        AppLog("Initializing face detection", tag: "detection")
        self.initializeFaceDetection(result: result)
      case "processFrame":
        self.processFrame(call: call, result: result)
      case "cleanupCamera":
        AppLog("Cleaning up camera resources", tag: "camera")
        self.cleanupCamera(result: result)
      default:
        AppLog("Unknown method: \(call.method)", tag: "app")
        result(FlutterMethodNotImplemented)
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func initializeFaceDetection(result: @escaping FlutterResult) {
    AppLog("Creating face detector", tag: "detection")
    let options = FaceDetectorOptions()
    options.performanceMode = .fast
    options.landmarkMode = .none
    options.classificationMode = .none
    options.minFaceSize = CGFloat(0.01)

    faceDetector = FaceDetector.faceDetector(options: options)
    AppLog("Face detector created", tag: "detection")
    result(true)
  }

  private func processFrame(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let frameBytes = args["frameBytes"] as? FlutterStandardTypedData,
          let width = args["width"] as? Int,
          let height = args["height"] as? Int,
          let rotation = args["rotation"] as? Int else {
      AppLog("Failed to parse frame arguments", tag: "processing")
      result(["success": false, "faces": []])
      return
    }

    guard let detector = faceDetector else {
      AppLog("Face detector not available", tag: "processing")
      result(["success": false, "faces": []])
      return
    }

    let imageData = frameBytes.data

    // Use serial queue to process frames sequentially
    detectionQueue.async { [weak self] in
      do {
        // FOLLOW ANDROID PATTERN: Keep frame data alive, create image, detect faces
        // Keep frame data in memory - critical for CVPixelBuffer to access it safely
        let frameDataHolder = NSData(bytes: (imageData as NSData).bytes, length: imageData.count)

        // Auto-detect pixel format - same logic as Android
        let expectedBGRASize = width * height * 4
        let expectedYUVSize = width * height * 3 / 2

        let pixelFormat: OSType
        let bytesPerRow: Int

        if imageData.count == expectedBGRASize {
          pixelFormat = kCVPixelFormatType_32BGRA
          bytesPerRow = width * 4
        } else if imageData.count >= expectedYUVSize && imageData.count <= expectedYUVSize + 100 {
          pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
          bytesPerRow = width
        } else {
          AppLog("Unknown image format, data size: \(imageData.count)", tag: "processing")
          DispatchQueue.main.async {
            result(["success": false, "faces": []])
          }
          return
        }

        // Create CVPixelBuffer from frame data pointer (frameDataHolder keeps data alive)
        var pixelBuffer: CVPixelBuffer?
        let options: [String: Any] = [
          kCVPixelBufferCGImageCompatibilityKey as String: true,
          kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]

        let status = CVPixelBufferCreateWithBytes(
          kCFAllocatorDefault,
          width,
          height,
          pixelFormat,
          UnsafeMutableRawPointer(mutating: frameDataHolder.bytes),
          bytesPerRow,
          nil,
          nil,
          options as CFDictionary,
          &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
          AppLog("Failed to create pixel buffer", tag: "processing")
          DispatchQueue.main.async {
            result(["success": false, "faces": []])
          }
          return
        }

        // Create CMSampleBuffer from CVPixelBuffer for VisionImage
        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &formatDescription)

        guard let formatDesc = formatDescription else {
          AppLog("Failed to create video format description", tag: "processing")
          DispatchQueue.main.async {
            result(["success": false, "faces": []])
          }
          return
        }

        var sampleBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo(duration: CMTimeMake(value: 1, timescale: 30), presentationTimeStamp: CMTimeMake(value: 0, timescale: 1), decodeTimeStamp: CMTimeMake(value: 0, timescale: 1))
        CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: formatDesc, sampleTiming: &timingInfo, sampleBufferOut: &sampleBuffer)

        guard let smplBuffer = sampleBuffer else {
          AppLog("Failed to create sample buffer", tag: "processing")
          DispatchQueue.main.async {
            result(["success": false, "faces": []])
          }
          return
        }

        let visionImage = VisionImage(buffer: smplBuffer)

        let faces = try detector.results(in: visionImage)
        AppLog("Face detection completed: found \(faces.count) faces", tag: "processing")

        var faceArray: [[String: NSNumber]] = []

        for face in faces {
          let boundingBox = face.frame

          // Only include meaningfully visible faces
          if boundingBox.width >= 20 && boundingBox.height >= 20 {
            // Estimate confidence based on face size
            let confidence = self?.estimateFaceConfidence(width: boundingBox.width, height: boundingBox.height) ?? 0.5

            faceArray.append([
              "x": NSNumber(value: Float(boundingBox.origin.x)),
              "y": NSNumber(value: Float(boundingBox.origin.y)),
              "width": NSNumber(value: Float(boundingBox.width)),
              "height": NSNumber(value: Float(boundingBox.height)),
              "confidence": NSNumber(value: Float(confidence))
            ])
          }
        }

        DispatchQueue.main.async {
          result(["success": true, "faces": faceArray])
        }

      } catch {
        AppLog("Face detection error: \(error.localizedDescription)", tag: "processing")
        DispatchQueue.main.async {
          result(["success": false, "faces": []])
        }
      }
    }
  }

  private func cleanupCamera(result: @escaping FlutterResult) {
    AppLog("Releasing face detector", tag: "camera")
    self.faceDetector = nil
    result(true)
  }

  /// Estimate face confidence based on size
  /// ML Kit doesn't expose confidence scores, so we estimate based on face dimensions
  /// Larger faces are typically more reliable (better quality detection)
  private func estimateFaceConfidence(width: CGFloat, height: CGFloat) -> Double {
    let minSize: CGFloat = 50  // pixels
    let maxSize: CGFloat = 400 // pixels

    let avgSize = (width + height) / 2.0

    // Scale confidence from 0.5 to 1.0 based on face size
    // Small faces (20-50px): lower confidence
    // Large faces (200px+): higher confidence
    let sizeConfidence: Double
    if avgSize < minSize {
      sizeConfidence = 0.5 + (Double(avgSize) / Double(minSize)) * 0.3
    } else if avgSize > maxSize {
      sizeConfidence = 0.95
    } else {
      sizeConfidence = 0.5 + (Double(avgSize) / Double(maxSize)) * 0.45
    }

    // Clamp to 0.5-1.0 range
    return min(max(sizeConfidence, 0.5), 1.0)
  }
}
