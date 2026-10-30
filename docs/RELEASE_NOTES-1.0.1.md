作者：**烨染霜华**。本次更新统一桌面图标，优化界面与代码，并调整用户数据存放方式。

## 用户数据与下载位置

- Windows/Linux 的账号、设置、任务记录、续传记录和缓存保存在程序旁的 `user-data`；macOS 放在 `.app` 旁。
- 完成的视频仍默认保存在各系统“下载”目录下的 `biload`，也可自行更改下载目录。
- 设置页可打开用户数据文件夹并清理已结束任务的缓存。关闭软件后删除 `user-data` 即可重置个人数据。
- **新版本不读取、兼容或迁移旧版数据，也不会清理旧目录。首次使用需重新登录并设置偏好。**
- 请将桌面程序放在可写目录。安装位置不可写时会提示更换位置，不会另存到隐藏目录。
- Android 的 APK 安装区由系统管理，应用数据继续保存在系统应用目录，完成的视频仍在公共下载目录。

## 修复与精简

- Windows/macOS 替换遗留的 Flutter 模板图标；Linux 补齐窗口图标、桌面入口与图标资源。
- 修复 Windows 并发数选择完成后持续显示灰色焦点底色的问题。
- 页面切换加入短暂淡入淡出，遵循系统减少动画设置。
- 移除视频链接框下意义不明的三个标签。
- 清理重复状态判断、缓存校验、构建准备以及旧版文件迁移逻辑，移除不再使用的依赖。
- 桌面账号加密文件保存在本地数据目录；Windows 使用当前用户的 DPAPI，Linux/macOS 使用 AES-GCM 和当前用户独占权限的本地密钥。macOS 网页登录使用内存 WebView 数据存储。

## 安装

- Windows 10/11 x64：解压后运行 `biload.exe`，保留 DLL、`data` 和 `licenses`。需要 Microsoft Visual C++ v14 x64 运行库，网页登录需要 WebView2。
- Ubuntu 22.04/24.04 x64：安装 `ffmpeg libgtk-3-0 libwebkit2gtk-4.1-0 libsecret-1-0 libjson-glib-1.0-0 network-manager fonts-noto-cjk`，解压后运行 `biload`。
- macOS 13+：通用包包含 Apple Silicon 与 Intel，使用桌面便携模式；将 `.app` 放在可写位置。当前采用 ad-hoc 签名，尚未 Apple 公证；Windows 也尚无商业代码签名。
- Android 8+ arm64：安装 APK。固定签名证书 SHA-256：`10918b393dca1b5b284b21f8b9a3ee24005cd779dbe0256a7f2de58bd099c27e`。

本次只提供四个平台安装包。Android 本轮仅做静态、插件注册、签名、架构与 16 KB 对齐检查，未做手机实测。验证报告与校验信息内部留存，构建和运行结果可查看 GitHub Actions 记录。

仅保存当前账号有权访问的完整未加密流；不绕过 DRM、地区或付费权限。GPL-3.0-or-later，平台包保留第三方许可资料。
