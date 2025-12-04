import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Register platform channel
    let registrar = flutterViewController.registrar(forPlugin: "PlatformChannel")
    PlatformChannel.shared.register(with: registrar)

    super.awakeFromNib()
  }
}
