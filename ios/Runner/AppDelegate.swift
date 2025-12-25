import Flutter
import UIKit
import MLKitFaceDetection
import MLKitVision
import AVFoundation

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
        // Auto-detect pixel format based on data size
        let expectedBGRASize = width * height * 4
        let expectedYUVSize = width * height * 3 / 2

        let pixelFormat: OSType
        let bytesPerRow: Int

        if imageData.count == expectedBGRASize {
          NSLog("📷 processFrame: Detected BGRA8888 format")
          pixelFormat = kCVPixelFormatType_32BGRA
          bytesPerRow = width * 4
        } else if imageData.count >= expectedYUVSize && imageData.count <= expectedYUVSize + 100 {
          NSLog("📷 processFrame: Detected YUV420 format")
          pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
          bytesPerRow = width
        } else {
          NSLog("❌ processFrame: Unknown format, data size: \(imageData.count)")
          DispatchQueue.main.async {
            result(["success": false, "faces": []])
          }
          return
        }

        // Create CVPixelBuffer - MUST allocate memory we own (not pointer to external data)
        // The frame data from Flutter can be deallocated at any time, so we must copy it
        var pixelBuffer: CVPixelBuffer?

        let status = CVPixelBufferCreate(
          kCFAllocatorDefault,
          width,
          height,
          pixelFormat,
          nil,
          &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
          NSLog("❌ processFrame: Failed to create CVPixelBuffer, status: \(status)")
          DispatchQueue.main.async {
            result(["success": false, "faces": []])
          }
          return
        }

        // Lock buffer and copy frame data into it
        CVPixelBufferLockBaseAddress(buffer, .readAndWrite)

        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
          let bytesPerRowActual = CVPixelBufferGetBytesPerRow(buffer)

          // Copy data plane by plane for proper handling
          memcpy(baseAddress, (imageData as NSData).bytes, imageData.count)
        }

        CVPixelBufferUnlockBaseAddress(buffer, .readAndWrite)

        // Create CMVideoFormatDescription
        var formatDesc: CMVideoFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
          allocator: kCFAllocatorDefault,
          imageBuffer: buffer,
          formatDescriptionOut: &formatDesc
        )

        guard formatStatus == noErr, let formatDescription = formatDesc else {
          NSLog("❌ processFrame: Failed to create CMVideoFormatDescription")
          DispatchQueue.main.async {
            result(["success": false, "faces": []])
          }
          return
        }

        // Create CMSampleBuffer
        var sampleBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo(
          duration: CMTime(value: 1, timescale: 30),
          presentationTimeStamp: CMTime.zero,
          decodeTimeStamp: CMTime.invalid
        )

        let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
          allocator: kCFAllocatorDefault,
          imageBuffer: buffer,
          formatDescription: formatDescription,
          sampleTiming: &timingInfo,
          sampleBufferOut: &sampleBuffer
        )

        guard sampleStatus == noErr, let smplBuffer = sampleBuffer else {
          NSLog("❌ processFrame: Failed to create CMSampleBuffer")
          DispatchQueue.main.async {
            result(["success": false, "faces": []])
          }
          return
        }

        // Create VisionImage
        let visionImage = VisionImage(buffer: smplBuffer)
        visionImage.orientation = self?.getImageOrientation(from: rotation) ?? .up

        NSLog("📍 processFrame: Running face detection on background thread")
        let faces = try detector.results(in: visionImage)
        NSLog("✅ processFrame: Face detection completed, found \(faces.count) faces")

        var faceArray: [[String: NSNumber]] = []

        for (index, face) in faces.enumerated() {
          let boundingBox = face.frame
          NSLog("📍 Face \(index): x=\(boundingBox.origin.x) y=\(boundingBox.origin.y) w=\(boundingBox.width) h=\(boundingBox.height)")

          if boundingBox.width >= 20 && boundingBox.height >= 20 {
            faceArray.append([
              "x": NSNumber(value: Float(boundingBox.origin.x)),
              "y": NSNumber(value: Float(boundingBox.origin.y)),
              "width": NSNumber(value: Float(boundingBox.width)),
              "height": NSNumber(value: Float(boundingBox.height))
            ])
          } else {
            NSLog("📍 Face \(index): Filtered out - too small")
          }
        }

        DispatchQueue.main.async {
          NSLog("📲 processFrame: Returning results")
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

  private func cleanupCamera(result: @escaping FlutterResult) {
    NSLog("🧹 cleanupCamera: Releasing face detector")
    self.faceDetector = nil
    result(true)
  }
}
