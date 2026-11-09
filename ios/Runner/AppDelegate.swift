import AVKit
import Flutter
import UIKit
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // 130 Video player: AVPlayer carries an MP4/MOV on in the system pop-up.
  private var pipPlayer: AVPlayer?
  private var pipLayer: AVPlayerLayer?
  private var pipController: AVPictureInPictureController?
  private var pipObservation: NSKeyValueObservation?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FamilyVideoPlayer") {
      let channel = FlutterMethodChannel(name: "app.family/video_player", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "getBrightness":
          result(Double(UIScreen.main.brightness))
        case "setBrightness":
          if let args = call.arguments as? [String: Any], let level = args["level"] as? Double {
            UIScreen.main.brightness = CGFloat(max(0.0, min(1.0, level)))
          }
          result(nil)
        case "pipSupported":
          result(AVPictureInPictureController.isPictureInPictureSupported())
        case "enterPip":
          guard let self = self,
                let args = call.arguments as? [String: Any],
                let path = args["path"] as? String,
                AVPictureInPictureController.isPictureInPictureSupported() else {
            result(false)
            return
          }
          let ms = (args["positionMs"] as? Int) ?? 0
          self.startPip(path: path, positionMs: ms, result: result)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    // 112 Widgets: the app's snapshot goes to the App Group the widget reads.
    // Taps arrive as familyapp://widget/<action> deep links (Dart side).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FamilyHomeWidget") {
      let channel = FlutterMethodChannel(name: "app.family/home_widget", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "publish":
          guard let data = call.arguments as? [String: String],
                let defaults = UserDefaults(suiteName: "group.app.family.familyUtilityApp") else {
            result(false)
            return
          }
          for (key, value) in data {
            defaults.set(value, forKey: key)
          }
          WidgetCenter.shared.reloadAllTimelines()
          result(true)
        case "initialAction":
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
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

  private func startPip(path: String, positionMs: Int, result: @escaping FlutterResult) {
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    try? AVAudioSession.sharedInstance().setActive(true)
    let player = AVPlayer(url: URL(fileURLWithPath: path))
    let layer = AVPlayerLayer(player: player)
    layer.frame = CGRect(x: 0, y: 0, width: 2, height: 2)
    layer.opacity = 0.01
    let root = UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.windows.first { $0.isKeyWindow } }
      .first?.rootViewController
    guard let view = root?.view, let controller = AVPictureInPictureController(playerLayer: layer) else {
      result(false)
      return
    }
    view.layer.addSublayer(layer)
    pipPlayer = player
    pipLayer = layer
    pipController = controller
    player.seek(to: CMTime(value: CMTimeValue(positionMs), timescale: 1000))
    player.play()
    pipObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { c, _ in
      if c.isPictureInPicturePossible && !c.isPictureInPictureActive {
        c.startPictureInPicture()
      }
    }
    result(true)
  }
}
