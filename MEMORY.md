# 项目工程记忆

核对基线：1.0.1（2026-10-30）。以下区分用户约定与有适用条件的经验；实现、依赖或要求变化时重新核实。

## 用户约定与数据边界

- 优先修复根因、合并重复逻辑，避免为小功能反复增加状态守卫。精简前确认已有互斥条件和接口契约，保留有实际回归依据的处理。
- 用户数据与成品视频分开：`AppPaths` 将桌面数据放在程序旁的 `user-data`（macOS 在 `.app` 旁），不可写时明确报错，不另找隐藏目录；`OutputStorage` 将视频默认放在系统 Downloads/biload，允许另选位置。Android 安装区只读，数据由系统应用目录管理，视频使用公共下载目录。
- 新版本不读取、兼容、迁移或清理旧版数据；不要重新引入旧目录扫描或迁移逻辑。
- Releases 只提供 Windows、Linux、macOS、Android 四端安装包；验证报告和校验信息在本地或 CI 内部留存，不作为公开附件。
- 插件默认存储也要检查：下载状态由 `TransferStore` 接管，临时传输显式使用本地缓存；Windows 登录指定 WebView profile，Linux 在 GTK 初始化前固定 GLib 目录缓存后恢复环境，macOS 登录使用内存 WKWebView。仅调整业务数据库路径不足以覆盖这些存储。
- `FileSessionVault` 的 Windows DPAPI 密文绑定系统用户，移动数据目录不保证跨用户或跨电脑保留登录；Linux/macOS 使用 AES-GCM 与当前用户独占权限的本地密钥。账号数据和私钥不进入仓库或分发包。

## 已验证的易错点

- **Windows 构建与插件注册**：Unicode 工程路径使用 `tool/flutter_project.ps1` 的 ASCII junction。当前 Flutter 工具链在依赖变更后可能清空桌面插件链接，`pub get` 成功不代表链接保留；若因 symlink 支持中断，还可能留下空注册文件。保留依赖解析后的链接准备，失败时补跑 `pub get`，构建后用 `tool/verify_android_plugins.dart` 核对注册结果；不能仅凭 APK 编译成功判断插件可用。
- **暂停确认时序**：桌面下载器的 `pause()` 返回只确认命令送达，续传数据可能尚未写入。继续操作需等 paused/最终事件确认并复用传输句柄，否则快速暂停后继续可能卡住。依据：`lib/services/download_manager.dart` 与延迟暂停确认回归测试。
- **Windows Cookie 桥接**：`desktop_webview_window 0.4.0` 的 Windows 字符串转换会保留尾部 NUL，使域名和 Cookie 名匹配失败。接收层仅去除尾部 NUL，拒绝嵌入控制字符，不任意改写凭据。依据：`lib/services/browser_cookies.dart`、`test/browser_cookies_test.dart`；升级插件后重新核实。
- **Android 分包版本码**：当前 Flutter 3.47.8 默认 arm64 split APK 的 versionCode 为 pubspec 构建号加 2000。`tool/verify_android_package.py` 按此校验；换 ABI、取消分包或更改版本码策略时须同步调整，不能推广为所有 APK 的规则。

## 维护与验证入口

- 桌面图标源为 `assets/brand/biload.svg`；生成脚本、Linux GResource/桌面入口及 `test/desktop_icons_test.dart` 共同约束各平台资产。并发菜单焦点释放与账号页淡入回归见 `test/ui_test.dart`。
- 目录边界、账号密文和续传记录重开见 `test/portable_storage_test.dart`；实际打包程序检查见 `tool/verify_desktop_release.py`。编译、静态检查、运行检查和设备验收的结论分开记录，无设备时不推定已实测。
- 发布流程与固定签名要求见 `docs/RELEASES.md`，验证线索见 CI 记录与本地 `artifacts/`。`docs/DEVELOPMENT.md` 含多个版本的历史实现；旧版迁移和 macOS 沙箱安全书签已由 1.0.1 的便携存储方案取代，不能将旧段落当作当前设计。
