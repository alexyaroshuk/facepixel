import Flutter
import UIKit
import MLKitFaceDetection
import MLKitVision
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var faceDetector: FaceDetector?

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
    NSLog("🔧 initializeFaceDetection: Starting")
    do {
      let options = FaceDetectorOptions()
      options.performanceMode = .fast
      options.landmarkMode = .none
      options.classificationMode = .none
      options.minFaceSize = CGFloat(0.01)

      faceDetector = FaceDetector.faceDetector(options: options)
      NSLog("✅ initializeFaceDetection: FaceDetector created successfully")
      result(true)
    } catch {
      NSLog("❌ initializeFaceDetection: Error - \(error.localizedDescription)")
      result(false)
    }
  }

  private func processFrame(call: FlutterMethodCall, result: @escaping FlutterResult) {
    NSLog("📷 processFrame: Starting")
    guard let args = call.arguments as? [String: Any],
          let frameBytes = args["frameBytes"] as? FlutterStandardTypedData,
          let width = args["width"] as? Int,
          let height = args["height"] as? Int,
          let rotation = args["rotation"] as? Int else {
      NSLog("❌ processFrame: Failed to parse arguments")
      result(["success": false])
      return
    }

    guard let detector = faceDetector else {
      NSLog("❌ processFrame: Face detector not initialized")
      result(["success": false])
      return
    }

    let imageData = frameBytes.data
    NSLog("📷 processFrame: Received frame \(width)x\(height), rotation: \(rotation)°, data size: \(imageData.count)")

    // ML Kit requires background thread - dispatch async
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      NSLog("📷 processFrame: Running on background thread")
      // Create a copy of the data for CVPixelBuffer
      let mutableData = NSMutableData(data: imageData)
      var pixelBuffer: CVPixelBuffer?

      let status = CVPixelBufferCreateWithBytes(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        mutableData.mutableBytes,
        imageData.count,
        nil,
        nil,
        nil,
        &pixelBuffer
      )

      guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
        NSLog("❌ processFrame: Failed to create CVPixelBuffer, status: \(status)")
        result(["success": false])
        return
      }

      NSLog("✅ processFrame: CVPixelBuffer created")

      // Create CMSampleBuffer from CVPixelBuffer
      var formatDesc: CMVideoFormatDescription?
      CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: buffer,
        formatDescriptionOut: &formatDesc
      )

      guard let formatDescription = formatDesc else {
        NSLog("❌ processFrame: Failed to create CMVideoFormatDescription")
        result(["success": false])
        return
      }

      NSLog("✅ processFrame: CMVideoFormatDescription created")

      var sampleBuffer: CMSampleBuffer?
      var timingInfo = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: 30),
        presentationTimeStamp: CMTime.zero,
        decodeTimeStamp: CMTime.invalid
      )

      CMSampleBufferCreateReadyWithImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: buffer,
        formatDescription: formatDescription,
        sampleTiming: &timingInfo,
        sampleBufferOut: &sampleBuffer
      )

      guard let smplBuffer = sampleBuffer else {
        NSLog("❌ processFrame: Failed to create CMSampleBuffer")
        result(["success": false])
        return
      }

      NSLog("✅ processFrame: CMSampleBuffer created")

      // Create VisionImage from CMSampleBuffer
      let visionImage = VisionImage(buffer: smplBuffer)
      visionImage.orientation = self?.getImageOrientation(from: rotation) ?? .up

      NSLog("✅ processFrame: VisionImage created")

      // Detect faces (on background thread as required by ML Kit)
      do {
        NSLog("📍 processFrame: Starting face detection")
        let faces = try detector.results(in: visionImage)
        NSLog("✅ processFrame: Face detection completed, found \(faces.count) faces")
        var faceArray: [[String: NSNumber]] = []

        for (index, face) in faces.enumerated() {
          let boundingBox = face.frame
          NSLog("📍 Face \(index): (\(boundingBox.origin.x), \(boundingBox.origin.y)) \(boundingBox.width)x\(boundingBox.height)")
          faceArray.append([
            "x": NSNumber(value: Float(boundingBox.origin.x)),
            "y": NSNumber(value: Float(boundingBox.origin.y)),
            "width": NSNumber(value: Float(boundingBox.width)),
            "height": NSNumber(value: Float(boundingBox.height))
          ])
        }

        result(["success": true, "faces": faceArray])
      } catch {
        NSLog("❌ processFrame: Face detection error - \(error.localizedDescription)")
        result(["success": false])
      }
    }
  }

  private func getImageOrientation(from rotation: Int) -> UIImage.Orientation {
    switch rotation {
    case 0:
      return .up
    case 90:
      return .right
    case 180:
      return .down
    case 270:
      return .left
    default:
      return .up
    }
  }
}
