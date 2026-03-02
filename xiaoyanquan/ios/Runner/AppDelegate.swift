import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    LivePhotoPlugin.register(with: self.registrar(forPlugin: "LivePhotoPlugin")!)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
