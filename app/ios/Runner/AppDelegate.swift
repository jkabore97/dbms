import Flutter
import Photos
import UIKit

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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MaraStatus") {
      StatusChannel.register(messenger: registrar.messenger())
    }
  }
}

/// The status picture's ways out on an iPhone (140, status_out_io.dart):
/// a Facebook story through the pasteboard, and the photos, add-only.
/// WhatsApp has no direct status on iOS: the app opens the system sheet.
/// Each answers false when it cannot, and the app falls back to the sheet.
enum StatusChannel {
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "bf.kaj.app/status", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any]
      guard let data = (args?["bytes"] as? FlutterStandardTypedData)?.data else {
        result(false)
        return
      }
      switch call.method {
      case "facebook":
        StatusChannel.facebookStory(data, appId: args?["appId"] as? String ?? "", result: result)
      case "save":
        StatusChannel.save(data, result: result)
      case "whatsapp":
        result(false)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Facebook's « Sharing to Stories » for iOS: the picture on the
  /// pasteboard for five minutes, then facebook-stories://share. Answers
  /// what the open did: false (Facebook missing, or refusing) and the app
  /// opens the system sheet.
  static func facebookStory(_ data: Data, appId: String, result: @escaping FlutterResult) {
    guard !appId.isEmpty,
      let url = URL(string: "facebook-stories://share?source_application=\(appId)"),
      UIApplication.shared.canOpenURL(url)
    else {
      result(false)
      return
    }
    let items: [[String: Any]] = [[
      "com.facebook.sharedSticker.backgroundImage": data,
      "com.facebook.sharedSticker.appID": appId,
    ]]
    UIPasteboard.general.setItems(
      items, options: [.expirationDate: Date().addingTimeInterval(300)])
    UIApplication.shared.open(url, options: [:]) { opened in
      result(opened)
    }
  }

  /// Into Photos, asking only to add (NSPhotoLibraryAddUsageDescription).
  static func save(_ data: Data, result: @escaping FlutterResult) {
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      guard status == .authorized || status == .limited else {
        DispatchQueue.main.async { result(false) }
        return
      }
      PHPhotoLibrary.shared().performChanges({
        PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
      }) { ok, _ in
        DispatchQueue.main.async { result(ok) }
      }
    }
  }
}
