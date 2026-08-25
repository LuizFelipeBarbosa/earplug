import Flutter
import UIKit
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "FlyerTextExtractor"
    ) else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "earplug/flyer_ocr",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "extractText" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let typedData = arguments["bytes"] as? FlutterStandardTypedData,
        let image = UIImage(data: typedData.data),
        let cgImage = image.cgImage
      else {
        result(FlutterError(code: "invalid_image", message: "The flyer image could not be read.", details: nil))
        return
      }

      let request = VNRecognizeTextRequest { request, error in
        if let error {
          DispatchQueue.main.async {
            result(FlutterError(code: "text_recognition_failed", message: error.localizedDescription, details: nil))
          }
          return
        }
        let observations = (request.results as? [VNRecognizedTextObservation] ?? []).sorted {
          let verticalDifference = abs($0.boundingBox.midY - $1.boundingBox.midY)
          return verticalDifference > 0.02
            ? $0.boundingBox.midY > $1.boundingBox.midY
            : $0.boundingBox.minX < $1.boundingBox.minX
        }
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        DispatchQueue.main.async { result(lines) }
      }
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      request.recognitionLanguages = ["en-US"]

      DispatchQueue.global(qos: .userInitiated).async {
        do {
          try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "text_recognition_failed", message: error.localizedDescription, details: nil))
          }
        }
      }
    }
  }
}
