import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // The launch screen's #101214: the window exists before Flutter paints.
    let launch = NSColor(srgbRed: 0x10 / 255.0, green: 0x12 / 255.0,
                         blue: 0x14 / 255.0, alpha: 1)
    backgroundColor = launch

    let flutterViewController = FlutterViewController()
    flutterViewController.backgroundColor = launch
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
