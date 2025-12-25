import Flutter
import UIKit
import MLKitFaceDetection
import MLKitVision
import AVFoundation
import CoreMedia

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var faceDetector: FaceDetector?
  private let detectionQueue = DispatchQueue(label: "com.facepixel.facedetection", qos: .userInitiated)

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    NSLog("🍎 AppDelegate: application:didFinishLaunchingWithOptions called")

    guard let controller = window?.rootViewController as? FlutterViewController else {
      NSLog("❌ AppDelegate: Failed to get FlutterViewController")
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    NSLog("✅ AppDelegate: Got FlutterViewController")

    let faceDetectionChannel = FlutterMethodChannel(
      name: "com.facepixel.app/faceDetection",
      binaryMessenger: controller.binaryMessenger
    )

    faceDetectionChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      NSLog("📱 AppDelegate: Method channel called: \(call.method)")
      switch call.method {
      case "initializeFaceDetection":
        NSLog("🔧 AppDelegate: Initializing face detection")
        self.initializeFaceDetection(result: result)
      case "processFrame":
        NSLog("📷 AppDelegate: Processing frame")
        self.processFrame(call: call, result: result)
      case "cleanupCamera":
        NSLog("🧹 AppDelegate: Cleaning up camera resources")
        self.cleanupCamera(result: result)
      default:
        NSLog("⚠️ AppDelegate: Unknown method: \(call.method)")
        result(FlutterMethodNotImplemented)
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    NSLog("✅ AppDelegate: Plugins registered successfully")
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func initializeFaceDetection(result: @escaping FlutterResult) {
    NSLog("🔧 initializeFaceDetection: Starting on main thread")
    let options = FaceDetectorOptions()
    options.performanceMode = .fast
    options.landmarkMode = .none
    options.classificationMode = .none
    options.minFaceSize = CGFloat(0.01)

    faceDetector = FaceDetector.faceDetector(options: options)
    NSLog("✅ initializeFaceDetection: FaceDetector created successfully")
    result(true)
  }

  private func processFrame(call: FlutterMethodCall, result: @escaping FlutterResult) {
    NSLog("📷 processFrame: Starting")
    guard let args = call.arguments as? [String: Any],
          let frameBytes = args["frameBytes"] as? FlutterStandardTypedData,
          let width = args["width"] as? Int,
          let height = args["height"] as? Int,
          let rotation = args["rotation"] as? Int else {
      NSLog("❌ processFrame: Failed to parse arguments")
      result(["success": false, "faces": []])
      return
    }

    guard let detector = faceDetector else {
      NSLog("⚠️ processFrame: Face detector not available (may be during camera switch)")
      result(["success": false, "faces": []])
      return
    }

    let imageData = frameBytes.data
    NSLog("📷 processFrame: Received frame \(width)x\(height), rotation: \(rotation)°, data size: \(imageData.count)")

    // Use serial queue to process frames sequentially
    detectionQueue.async { [weak self] in
      NSLog("📷 processFrame: Running on background thread")

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
          NSLog("📷 processFrame: BGRA8888 format, width=\(width) height=\(height)")
          pixelFormat = kCVPixelFormatType_32BGRA
          bytesPerRow = width * 4
        } else if imageData.count >= expectedYUVSize && imageData.count <= expectedYUVSize + 100 {
          NSLog("📷 processFrame: YUV420 format, width=\(width) height=\(height)")
          pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
          bytesPerRow = width
        } else {
          NSLog("❌ processFrame: Unknown format, data size: \(imageData.count), expected BGRA: \(expectedBGRASize), YUV: \(expectedYUVSize)")
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
          NSLog("❌ processFrame: Failed to create CVPixelBuffer, status: \(status)")
          DispatchQueue.main.async {
            result(["success": false, "faces": []])
          }
          return
        }

        NSLog("✅ processFrame: CVPixelBuffer created successfully")

        // Create CMSampleBuffer from CVPixelBuffer for VisionImage
        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &formatDescription)

        guard let formatDesc = formatDescription else {
          NSLog("❌ processFrame: Failed to create video format description")
          DispatchQueue.main.async {
            result(["success": false, "faces": []])
          }
          return
        }

        var sampleBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo(duration: CMTimeMake(value: 1, timescale: 30), presentationTimeStamp: CMTimeMake(value: 0, timescale: 1), decodeTimeStamp: CMTimeMake(value: 0, timescale: 1))
        CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: formatDesc, sampleTiming: &timingInfo, sampleBufferOut: &sampleBuffer)

        guard let smplBuffer = sampleBuffer else {
          NSLog("❌ processFrame: Failed to create sample buffer")
          DispatchQueue.main.async {
            result(["success": false, "faces": []])
          }
          return
        }

        let visionImage = VisionImage(buffer: smplBuffer)

        NSLog("📍 processFrame: Running SYNCHRONOUS face detection on background thread")
        let faces = try detector.results(in: visionImage)
        NSLog("✅ processFrame: Face detection completed, found \(faces.count) faces")

        var faceArray: [[String: NSNumber]] = []

        for (index, face) in faces.enumerated() {
          let boundingBox = face.frame
          NSLog("📍 Face \(index): x=\(boundingBox.origin.x) y=\(boundingBox.origin.y) w=\(boundingBox.width) h=\(boundingBox.height)")

          // Only include meaningfully visible faces
          if boundingBox.width >= 20 && boundingBox.height >= 20 {
            faceArray.append([
              "x": NSNumber(value: Float(boundingBox.origin.x)),
              "y": NSNumber(value: Float(boundingBox.origin.y)),
              "width": NSNumber(value: Float(boundingBox.width)),
              "height": NSNumber(value: Float(boundingBox.height))
            ])
          }
        }

        DispatchQueue.main.async {
          NSLog("📲 processFrame: Returning \(faceArray.count) faces to Flutter")
          result(["success": true, "faces": faceArray])
        }

      } catch {
        NSLog("❌ processFrame: Face detection error - \(error.localizedDescription)")
        DispatchQueue.main.async {
          result(["success": false, "faces": []])
        }
      }
    }
  }

  private func cleanupCamera(result: @escaping FlutterResult) {
    NSLog("🧹 cleanupCamera: Releasing face detector")
    self.faceDetector = nil
    result(true)
  }
}
