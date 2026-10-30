import Cocoa
import FlutterMacOS
import WebKit

class MainFlutterWindow: NSWindow {
  private var storageChannel: FlutterMethodChannel?
  private var loginWindow: OfficialLoginWindow?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = frame
    contentViewController = flutterViewController
    setFrame(windowFrame, display: true)
    isRestorable = false
    RegisterGeneratedPlugins(registry: flutterViewController)
    storageChannel = FlutterMethodChannel(
      name: "app.biload/platform", binaryMessenger: flutterViewController.engine.binaryMessenger)
    storageChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "storageChooseDirectory":
        let panel = NSOpenPanel()
        panel.title = "选择 biload 下载目录"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: self) { response in
          guard response == .OK, let url = panel.url else { result(nil); return }
          result(["directory": url.path, "label": url.path])
        }
      case "officialLogin", "verifyLoginBrowser":
        guard self.loginWindow == nil,
              let args = call.arguments as? [String: String],
              let value = args["url"], let url = URL(string: value) else {
          result(FlutterError(code: "login_window", message: "请先关闭当前登录窗口。", details: nil))
          return
        }
        let verification = call.method == "verifyLoginBrowser" &&
          ProcessInfo.processInfo.environment["BILOAD_VERIFY_RELEASE"] == "1"
        guard OfficialLoginWindow.allowed(url, verification: verification) else {
          result(FlutterError(code: "login_url", message: "登录地址无效。", details: nil))
          return
        }
        self.loginWindow = OfficialLoginWindow(url: url, title: args["title"] ?? "biload 登录",
            verification: verification) { value in
          self.loginWindow = nil
          result(value)
        }
        self.loginWindow?.showWindow(self)
        self.loginWindow?.window?.makeKeyAndOrderFront(self)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    super.awakeFromNib()
    if ProcessInfo.processInfo.environment["BILOAD_VERIFY_RELEASE"] == "1" {
      DispatchQueue.main.async {
        NSApp.activate(ignoringOtherApps: true)
        self.makeKeyAndOrderFront(nil)
      }
    }
  }
}

/// Login cookies and webpage storage live in memory; only the adopted account
/// is persisted by Dart in the installation's user-data folder.
private class OfficialLoginWindow: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
  private let webView: WKWebView
  private let verification: Bool
  private var completion: ((Any?) -> Void)?
  private var timer: Timer?
  private var inspecting = false
  private var firstCookieAt: Date?

  init(url: URL, title: String, verification: Bool, completion: @escaping (Any?) -> Void) {
    self.verification = verification
    self.completion = completion
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    webView = WKWebView(frame: .zero, configuration: configuration)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760),
        styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    super.init(window: window)
    window.title = title
    window.isReleasedWhenClosed = false
    window.isRestorable = false
    window.delegate = self
    window.contentView = webView
    window.center()
    webView.navigationDelegate = self
    webView.uiDelegate = self
    webView.load(URLRequest(url: url))
    timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.inspect() }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  static func allowed(_ url: URL, verification: Bool) -> Bool {
    guard let host = url.host, url.user == nil else { return false }
    if verification { return url.scheme == "http" && host == "127.0.0.1" }
    return url.scheme == "https" && ["bilibili.com", "biligame.com", "geetest.com", "gtimg.com", "qq.com"]
      .contains { host == $0 || host.hasSuffix("." + $0) }
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
    decisionHandler(navigationAction.targetFrame?.isMainFrame == false ||
        Self.allowed(url, verification: verification) ? .allow : .cancel)
  }

  func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
      for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
    if navigationAction.targetFrame == nil, let url = navigationAction.request.url,
        Self.allowed(url, verification: verification) { webView.load(navigationAction.request) }
    return nil
  }

  private func inspect() {
    guard !inspecting, completion != nil else { return }
    inspecting = true
    webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
      guard let self = self else { return }
      let valid = cookies.filter {
        let host = $0.domain.hasPrefix(".") ? String($0.domain.dropFirst()) : $0.domain
        return (self.verification ? host == "127.0.0.1" : host == "bilibili.com" || host.hasSuffix(".bilibili.com")) &&
          ($0.expiresDate == nil || $0.expiresDate! > Date())
      }
      let name = self.verification ? "biload_fixture" : "SESSDATA"
      guard let cookie = valid.first(where: { $0.name == name && !$0.value.isEmpty }) else {
        self.inspecting = false
        return
      }
      self.firstCookieAt = self.firstCookieAt ?? Date()
      let key = self.verification ? "biload_fixture" : "ac_time_value"
      self.webView.evaluateJavaScript("window.localStorage.getItem('\(key)') || ''") { value, _ in
        self.inspecting = false
        let token = value as? String ?? ""
        if self.verification {
          if token == "ready" { self.finish(["value": cookie.value, "httpOnly": cookie.isHTTPOnly]) }
        } else if !token.isEmpty || Date().timeIntervalSince(self.firstCookieAt!) >= 10 {
          var values: [String: String] = [:]
          for item in valid { values[item.name] = item.value }
          self.finish(["cookies": values, "refreshToken": token])
        }
      }
    }
  }

  private func finish(_ value: Any?) {
    guard let callback = completion else { return }
    completion = nil
    timer?.invalidate()
    timer = nil
    close()
    callback(value)
  }

  func windowWillClose(_ notification: Notification) { finish(nil) }
}
