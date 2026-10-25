import Vision
import UIKit

// Face boxes remain on this device and are discarded after the crown effect.
final class PulseIOSGiftFaces: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "pulse/gift_faces", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(PulseIOSGiftFaces(), channel: channel)
  }
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "detect" else { result(FlutterMethodNotImplemented); return }
    let args = call.arguments as? [String: Any] ?? [:]
    guard let bytes = args["bytes"] as? FlutterStandardTypedData,
          bytes.data.count <= 2000000,
          let image = UIImage(data: bytes.data)?.cgImage,
          image.width <= 1600, image.height <= 1600 else { result(nil); return }
    DispatchQueue.global(qos: .userInitiated).async {
      var anchor: [Double]?
      do {
        let request = VNDetectFaceRectanglesRequest()
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        if let face = request.results?.filter({ $0.confidence >= 0.5 })
          .max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) {
          let box = face.boundingBox
          anchor = [Double(box.minX), Double(1 - box.maxY), Double(box.width),
                    Double(box.height), -(face.roll?.doubleValue ?? 0)]
        }
      } catch { anchor = nil }
      let answer = anchor
      DispatchQueue.main.async { result(answer) }
    }
  }
}
