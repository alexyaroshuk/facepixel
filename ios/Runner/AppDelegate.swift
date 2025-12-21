import Flutter
import UIKit
import MLKitFaceDetection
import MLKitVision

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var faceDetector: FaceDetector?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as! FlutterViewController
    let faceDetectionChannel = FlutterMethodChannel(
      name: "com.facepixel.app/faceDetection",
      binaryMessenger: controller.binaryMessenger
    )

    faceDetectionChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "initializeFaceDetection":
        self.initializeFaceDetection(result: result)
      case "processFrame":
        self.processFrame(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func initializeFaceDetection(result: @escaping FlutterResult) {
    let options = FaceDetectorOptions()
    options.performanceMode = .fast
    options.landmarkMode = .none
    options.classificationMode = .none
    options.minFaceSize = CGFloat(0.01)

    faceDetector = FaceDetector.faceDetector(options: options)
    result(true)
  }

  private func processFrame(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let frameBytes = args["frameBytes"] as? FlutterStandardTypedData,
          let width = args["width"] as? Int,
          let height = args["height"] as? Int,
          let rotation = args["rotation"] as? Int,
          let detector = faceDetector else {
      result(["success": false])
      return
    }

    let imageData = frameBytes.data

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
      result(["success": false])
      return
    }

    // Create VisionImage from pixel buffer
    let visionImage = VisionImage(buffer: buffer)
    visionImage.orientation = getImageOrientation(from: rotation)

    // Detect faces
    do {
      let faces = try detector.results(in: visionImage)
      var faceArray: [[String: NSNumber]] = []

      for face in faces {
        let boundingBox = face.frame
        faceArray.append([
          "x": NSNumber(value: Float(boundingBox.origin.x)),
          "y": NSNumber(value: Float(boundingBox.origin.y)),
          "width": NSNumber(value: Float(boundingBox.width)),
          "height": NSNumber(value: Float(boundingBox.height))
        ])
      }

      result(["success": true, "faces": faceArray])
    } catch {
      result(["success": false])
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
