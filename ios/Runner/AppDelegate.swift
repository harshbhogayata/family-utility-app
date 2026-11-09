import Flutter
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
    // 056 Private vault: keep the vault folder out of iCloud / iTunes backups
    // unless the person turns backups on.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FamilyBackupExclusion") {
      let channel = FlutterMethodChannel(name: "family_utility/backup", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "setExcludedFromBackup",
              let args = call.arguments as? [String: Any],
              let path = args["path"] as? String,
              let excluded = args["excluded"] as? Bool else {
          result(FlutterMethodNotImplemented)
          return
        }
        var url = URL(fileURLWithPath: path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = excluded
        do {
          try url.setResourceValues(values)
          result(true)
        } catch {
          result(FlutterError(code: "backup", message: error.localizedDescription, details: nil))
        }
      }
    }
  }
}
