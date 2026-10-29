#include "flutter_window.h"

#include <optional>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <filesystem>
#include <string>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  platform_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "app.biload/platform",
      &flutter::StandardMethodCodec::GetInstance());
  platform_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() != "storageOpen") {
      result->NotImplemented();
      return;
    }
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    const std::string* path = nullptr;
    if (args) {
      const auto found = args->find(flutter::EncodableValue("output"));
      if (found != args->end()) path = std::get_if<std::string>(&found->second);
    }
    if (!path || path->empty() || path->find('\0') != std::string::npos) {
      result->Error("invalid_path", "文件路径无效。");
      return;
    }
    const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
        path->data(), static_cast<int>(path->size()), nullptr, 0);
    if (!length) {
      result->Error("invalid_path", "文件路径编码无效。");
      return;
    }
    std::wstring wide_path(static_cast<size_t>(length), L'\0');
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path->data(),
        static_cast<int>(path->size()), wide_path.data(), length);
    const std::filesystem::path file(wide_path);
    std::error_code error;
    if (!file.is_absolute() || !std::filesystem::is_regular_file(file, error)) {
      result->Error("missing_file", "文件已被移动或删除。");
      return;
    }
    SHELLEXECUTEINFOW info{};
    info.cbSize = sizeof(info);
    info.fMask = SEE_MASK_FLAG_NO_UI | SEE_MASK_NOASYNC;
    info.hwnd = GetHandle();
    info.lpVerb = L"open";
    // ShellExecute receives the real UTF-16 path, not a file:// URL. Characters
    // such as #, %, spaces and Chinese names must remain literal file names.
    info.lpFile = wide_path.c_str();
    info.nShow = SW_SHOWNORMAL;
    if (!ShellExecuteExW(&info)) {
      const DWORD code = GetLastError();
      result->Error("open_failed", code == ERROR_NO_ASSOCIATION
          ? "未找到可打开此格式的默认播放器，请安装播放器或设置文件关联。"
          : "系统无法打开文件，请检查默认播放器与文件访问权限。",
          flutter::EncodableValue(static_cast<int64_t>(code)));
      return;
    }
    result->Success();
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  platform_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
