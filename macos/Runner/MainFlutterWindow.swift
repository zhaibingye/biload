import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var storageChannel: FlutterMethodChannel?
  private var scopedDirectories: [String: URL] = [:]
  private let bookmarkKey = "biload.downloadDirectoryBookmarks"

  override func awakeFromNib() {
    restoreDirectoryBookmarks()
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

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
          do {
            let data = try url.bookmarkData(options: .withSecurityScope,
                includingResourceValuesForKeys: nil, relativeTo: nil)
            var bookmarks = UserDefaults.standard.dictionary(forKey: self.bookmarkKey) ?? [:]
            bookmarks[url.path] = data
            UserDefaults.standard.set(bookmarks, forKey: self.bookmarkKey)
            self.activateDirectory(url)
            result(["directory": url.path, "label": url.path])
          } catch {
            result(FlutterError(code: "directory_permission",
                message: "无法持久保存目录授权，请重新选择。", details: nil))
          }
        }
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

  private func activateDirectory(_ url: URL) {
    guard scopedDirectories[url.path] == nil else { return }
    if url.startAccessingSecurityScopedResource() { scopedDirectories[url.path] = url }
  }

  private func restoreDirectoryBookmarks() {
    var bookmarks = UserDefaults.standard.dictionary(forKey: bookmarkKey) ?? [:]
    for (path, value) in bookmarks {
      guard let data = value as? Data else { continue }
      do {
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope,
            relativeTo: nil, bookmarkDataIsStale: &stale)
        activateDirectory(url)
        if stale {
          bookmarks[path] = try url.bookmarkData(options: .withSecurityScope,
              includingResourceValuesForKeys: nil, relativeTo: nil)
        }
      } catch {
        // An unavailable or removed directory can be selected again in settings.
        continue
      }
    }
    UserDefaults.standard.set(bookmarks, forKey: bookmarkKey)
  }

  deinit {
    for url in scopedDirectories.values { url.stopAccessingSecurityScopedResource() }
  }
}
