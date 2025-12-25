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
      result(["success": false, "faces": []])
      return
    }

    // Guard against detector being nil during camera switch cleanup
    guard let detector = faceDetector else {
      NSLog("⚠️ processFrame: Face detector not available (may be during camera switch)")
      result(["success": false, "faces": []])
      return
    }

    let imageData = frameBytes.data
    NSLog("📷 processFrame: Received frame \(width)x\(height), rotation: \(rotation)°, data size: \(imageData.count)")

    // CRITICAL: Use serial queue to process frames sequentially (matching Android behavior)
    // This prevents multiple detections running in parallel and results arriving out of order
    detectionQueue.async { [weak self] in
      NSLog("📷 processFrame: Running on background thread")

      // Auto-detect pixel format based on data size
      // BGRA8888: 4 bytes per pixel
      // YUV420: ~1.5 bytes per pixel (Y plane + UV planes)
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
        NSLog("❌ processFrame: Unknown format, data size: \(imageData.count), expected BGRA: \(expectedBGRASize), YUV: \(expectedYUVSize)")
        DispatchQueue.main.async {
          result(["success": false, "faces": []])
        }
        return
      }

      NSLog("📷 processFrame: Using format \(pixelFormat), bytesPerRow=\(bytesPerRow)")

      // Create CVPixelBuffer with copied data to avoid memory ownership issues
      // CRITICAL: Must copy the frame data because Flutter's frame lifecycle is independent
      // and the async detection queue may process frames out of order or with delays
      // Without proper memory management, the underlying data can be deallocated
      // while the VisionImage/CVPixelBuffer is still in use, causing intermittent detection failures
      var pixelBuffer: CVPixelBuffer?

      // Create a pool to hold the data alive during processing
      // This ensures the frame data persists for the entire detection cycle
      let frameDataHolder = NSMutableData(data: imageData)

      let options: [String: Any] = [
        kCVPixelBufferCGImageCompatibilityKey as String: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
      ]

      let status = CVPixelBufferCreateWithBytes(
        kCFAllocatorDefault,
        width,
        height,
        pixelFormat,
        frameDataHolder.mutableBytes,
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

      NSLog("✅ processFrame: CVPixelBuffer created")

      // Create CMVideoFormatDescription from CVPixelBuffer
      var formatDesc: CMVideoFormatDescription?
      let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: buffer,
        formatDescriptionOut: &formatDesc
      )

      guard formatStatus == noErr, let formatDescription = formatDesc else {
        NSLog("❌ processFrame: Failed to create CMVideoFormatDescription, status: \(formatStatus)")
        DispatchQueue.main.async {
          result(["success": false, "faces": []])
        }
        return
      }

      NSLog("✅ processFrame: CMVideoFormatDescription created")

      // Create CMSampleBuffer from CVPixelBuffer
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
        NSLog("❌ processFrame: Failed to create CMSampleBuffer, status: \(sampleStatus)")
        DispatchQueue.main.async {
          result(["success": false, "faces": []])
        }
        return
      }

      NSLog("✅ processFrame: CMSampleBuffer created")

      // Create VisionImage from CMSampleBuffer
      let visionImage = VisionImage(buffer: smplBuffer)
      visionImage.orientation = self?.getImageOrientation(from: rotation) ?? .up

      NSLog("✅ processFrame: VisionImage created with orientation \(rotation)°")

      // Detect faces (on background thread as required by ML Kit)
      do {
        NSLog("📍 processFrame: Starting face detection")
        let faces = try detector.results(in: visionImage)
        NSLog("✅ processFrame: Face detection completed, found \(faces.count) faces")
        var faceArray: [[String: NSNumber]] = []

        for (index, face) in faces.enumerated() {
          let boundingBox = face.frame
          NSLog("📍 Face \(index): (\(boundingBox.origin.x), \(boundingBox.origin.y)) \(boundingBox.width)x\(boundingBox.height)")

          // Only include faces that are meaningfully visible (not mostly off-screen)
          // Skip if face is too small (less than 20x20) - prevents lingering boxes at edges
          if boundingBox.width >= 20 && boundingBox.height >= 20 {
            faceArray.append([
              "x": NSNumber(value: Float(boundingBox.origin.x)),
              "y": NSNumber(value: Float(boundingBox.origin.y)),
              "width": NSNumber(value: Float(boundingBox.width)),
              "height": NSNumber(value: Float(boundingBox.height))
            ])
          } else {
            NSLog("📍 Face \(index): Filtered out - too small (\(boundingBox.width)x\(boundingBox.height))")
          }
        }

        // CRITICAL: Flutter result callback MUST be called on main thread
        DispatchQueue.main.async {
          NSLog("📲 processFrame: Calling result callback on main thread")
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
