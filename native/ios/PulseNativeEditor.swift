import AVFoundation
import CoreImage
import Photos

// App-owned bridge; public Flutter configuration never contains signing secrets.
final class PulseIOSNativeEditor: NSObject, FlutterPlugin {
  private var exporter: AVAssetExportSession?
  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = PulseIOSNativeEditor()
    let channel = FlutterMethodChannel(name: "pulse/native_editor", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)
  }
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    if call.method == "progress" { result(Double(exporter?.progress ?? 0)); return }
    if call.method == "cancel" { exporter?.cancelExport(); result(nil); return }
    if call.method == "saveDownload" { save(args, result); return }
    guard ["export", "avatar", "style", "watermark"].contains(call.method) else { result(FlutterMethodNotImplemented); return }
    guard exporter == nil else { result(FlutterError(code: "busy", message: "An export is already running", details: nil)); return }
    do { try export(call.method, args, result) }
    catch { result(FlutterError(code: "export_failed", message: error.localizedDescription, details: nil)) }
  }
  private func invalid(_ message: String) -> NSError {
    NSError(domain: "PulseVideo", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
  private func export(_ method: String, _ args: [String: Any], _ result: @escaping FlutterResult) throws {
    guard let input = args["input"] as? String, let output = args["output"] as? String,
          input != output, FileManager.default.fileExists(atPath: input) else { throw invalid("Choose a valid source and a different output file.") }
    let asset = AVURLAsset(url: URL(fileURLWithPath: input))
    let duration = CMTimeGetSeconds(asset.duration)
    guard duration.isFinite, duration > 0, let source = asset.tracks(withMediaType: .video).first else { throw invalid("This video cannot be opened.") }
    let trimmed = method == "export" || method == "avatar"
    let start = trimmed ? (args["startMs"] as? NSNumber)?.doubleValue ?? -1 : 0
    let end = trimmed ? (args["endMs"] as? NSNumber)?.doubleValue ?? -1 : duration * 1000
    guard start >= 0, end > start, start < duration * 1000,
          method != "avatar" || end - start <= 5000 else { throw invalid("Choose a valid trim range. Profile clips must be at most five seconds.") }
    let range = CMTimeRange(start: CMTime(seconds: start / 1000, preferredTimescale: 600),
                            duration: CMTime(seconds: min(end / 1000, duration) - start / 1000, preferredTimescale: 600))
    let composition = AVMutableComposition()
    guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw invalid("Unable to create video track.") }
    try video.insertTimeRange(range, of: source, at: .zero)
    video.preferredTransform = source.preferredTransform
    let mute = method == "avatar" || (args["mute"] as? Bool ?? false)
    if !mute {
      for audio in asset.tracks(withMediaType: .audio) {
        if let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
          let overlap = CMTimeRangeGetIntersection(range, audio.timeRange)
          if CMTimeCompare(overlap.duration, .zero) > 0 {
            try track.insertTimeRange(overlap, of: audio, at: CMTimeSubtract(overlap.start, range.start))
          }
        }
      }
    }
    let style = args["settings"] as? [String: Any] ?? [:]
    let rotation = method == "style" ? (style["rotation"] as? NSNumber)?.doubleValue ?? 0 : 0
    let angle = -rotation * .pi / 2
    let natural = CGRect(origin: .zero, size: source.naturalSize).applying(source.preferredTransform)
    let rotated = CGRect(origin: .zero, size: CGSize(width: abs(natural.width), height: abs(natural.height))).applying(CGAffineTransform(rotationAngle: angle))
    var width = max(2, abs(rotated.width)), height = max(2, abs(rotated.height))
    let ratio = method == "avatar" ? 1.0 : (style["ratio"] as? NSNumber)?.doubleValue
    if let ratio = ratio, ratio.isFinite, ratio > 0 {
      if width / height > ratio { width = height * ratio } else { height = width / ratio }
    }
    let scale = min(1, (method == "avatar" ? 512 : 1920) / max(width, height))
    let canvas = CGSize(width: max(2, floor(width * scale / 2) * 2), height: max(2, floor(height * scale / 2) * 2))
    let bounds = CGRect(origin: .zero, size: canvas)
    var overlay: CIImage?
    if method == "watermark" {
      guard let path = args["logo"] as? String, let image = CIImage(contentsOf: URL(fileURLWithPath: path)) else { throw invalid("Pulse watermark image is unavailable.") }
      let factor = canvas.width * 0.16 / image.extent.width
      overlay = image.transformed(by: CGAffineTransform(scaleX: factor, y: factor)).transformed(by: CGAffineTransform(translationX: canvas.width * 0.80, y: canvas.height * 0.04))
    } else if method == "style", let text = style["text"] as? String, !text.isEmpty {
      let format = UIGraphicsImageRendererFormat(); format.scale = 1
      let image = UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: max(14, canvas.width / 24)), .foregroundColor: UIColor.white, .strokeColor: UIColor.black, .strokeWidth: -3, .paragraphStyle: paragraph]
        (String(text.prefix(80)) as NSString).draw(in: CGRect(x: canvas.width * 0.07, y: canvas.height * 0.76, width: canvas.width * 0.86, height: canvas.height * 0.20), withAttributes: attributes)
      }
      if let cg = image.cgImage { overlay = CIImage(cgImage: cg) }
    }
    let fixedOverlay = overlay
    let videoComposition = AVMutableVideoComposition(asset: composition, applyingCIFiltersWithHandler: { request in
      var image = request.sourceImage
      if angle != 0 { image = image.transformed(by: CGAffineTransform(rotationAngle: angle)) }
      let extent = image.extent
      let crop = CGRect(x: extent.midX - width / 2, y: extent.midY - height / 2, width: width, height: height)
      image = image.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY)).transformed(by: CGAffineTransform(scaleX: canvas.width / width, y: canvas.height / height))
      if method == "style" {
        image = image.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: (style["brightness"] as? NSNumber)?.doubleValue ?? 0, kCIInputContrastKey: 1 + ((style["contrast"] as? NSNumber)?.doubleValue ?? 0), kCIInputSaturationKey: (style["mono"] as? Bool ?? false) ? 0 : 1])
      }
      if let overlay = fixedOverlay { image = overlay.composited(over: image) }
      request.finish(with: image.cropped(to: bounds), context: nil)
    })
    videoComposition.renderSize = canvas
    videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
    guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { throw invalid("This device cannot export this codec.") }
    try? FileManager.default.removeItem(atPath: output)
    session.outputURL = URL(fileURLWithPath: output); session.outputFileType = .mp4
    session.shouldOptimizeForNetworkUse = true; session.videoComposition = videoComposition
    exporter = session
    session.exportAsynchronously { [weak self] in
      DispatchQueue.main.async {
        self?.exporter = nil
        if session.status == .completed { result(nil) }
        else {
          try? FileManager.default.removeItem(atPath: output)
          result(FlutterError(code: session.status == .cancelled ? "cancelled" : "export_failed", message: session.status == .cancelled ? "Export cancelled" : session.error?.localizedDescription ?? "Video export failed.", details: nil))
        }
      }
    }
  }
  private func save(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let input = args["input"] as? String, FileManager.default.fileExists(atPath: input) else { result(FlutterError(code: "save_failed", message: "The downloaded file is unavailable.", details: nil)); return }
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      guard status == .authorized || status == .limited else { DispatchQueue.main.async { result(FlutterError(code: "permission_denied", message: "Allow Pulse to add media in iPhone Settings.", details: nil)) }; return }
      PHPhotoLibrary.shared().performChanges({
        let url = URL(fileURLWithPath: input)
        if (args["mime"] as? String ?? "").hasPrefix("video/") { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) }
        else { PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url) }
      }) { success, error in
        DispatchQueue.main.async { result(success ? nil : FlutterError(code: "save_failed", message: error?.localizedDescription ?? "Could not save media.", details: nil)) }
      }
    }
  }
}
