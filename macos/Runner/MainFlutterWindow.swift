import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    let api = DarwinHostApiImpl(binaryMessenger: flutterViewController.engine.binaryMessenger)
    DarwinHostApiSetup.setUp(
      binaryMessenger: flutterViewController.engine.binaryMessenger,
      api: api
    )

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
