import AppKit
import Foundation
import WebKit

// Minimal menu-bar panel for Mission Control (ER-134 Phase B).
// Loads ~/.mission-control/panel.html (or argv override).

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  var statusItem: NSStatusItem!
  var popover: NSPopover!
  var webView: WKWebView!
  var timer: Timer?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = item.button {
      button.title = "MC"
      button.toolTip = "Mission Control — Needs you"
      button.action = #selector(togglePopover(_:))
      button.target = self
    }
    statusItem = item

    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 380, height: 460))
    web.setValue(false, forKey: "drawsBackground")
    webView = web

    let pop = NSPopover()
    pop.contentSize = NSSize(width: 380, height: 460)
    pop.behavior = .transient
    pop.contentViewController = NSViewController()
    pop.contentViewController!.view = web
    popover = pop

    reload()
    timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
      self?.reload()
    }
  }

  @objc func togglePopover(_ sender: Any?) {
    guard let button = statusItem.button else { return }
    if popover.isShown {
      popover.performClose(sender)
    } else {
      reload()
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  func reload() {
    let args = CommandLine.arguments
    let override = args.count > 1 ? args[1] : nil
    let home = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".mission-control/panel.html")
    let url = override.map { URL(fileURLWithPath: $0) } ?? home
    if FileManager.default.fileExists(atPath: url.path) {
      webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    } else {
      let html = """
      <html><body style='font:13px -apple-system;padding:16px'>
      <h3>Mission Control panel not installed</h3>
      <p>Run: <code>dashboard install</code> then <code>dashboard panel</code>.</p>
      </body></html>
      """
      webView.loadHTMLString(html, baseURL: nil)
    }
  }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
