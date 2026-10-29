# 发布构建

作者：烨染霜华。版本号来自 `pubspec.yaml`，依赖锁定在 `pubspec.lock`。

Windows / Android 可使用 `tool/build_windows.ps1` 与 `tool/build_android.ps1` 本地构建。Linux 和 macOS 使用各自原生环境；Windows 不能直接生成可用的 macOS 应用。

推送 `v*` 标签或手动运行 `.github/workflows/release.yml`，会构建 Windows x64 ZIP、Ubuntu 22.04 x64 tar.gz、macOS 通用 ZIP 和 Android arm64 APK。工作流检查 macOS 主程序同时包含 arm64、x86_64，检查 Linux 运行库解析，再上传 Actions artifacts。维护者核对产物与 SHA-256 后创建 GitHub Release；工作流不会在构建不完整时自动发布。

Android CI 使用临时开发签名。0.1.5 Release 的 Android 包由原开发主机构建，沿用此前本地测试包的签名，方便已有测试用户保留数据升级。请勿将密钥提交到仓库。CI 产物不与本地签名包混用；后续稳定发布需要配置独立签名与备份。macOS 使用临时本地签名，尚未经过 Apple 公证。

Windows 完整分发目录必须保留 DLL、data 与 licenses。FFmpegKit Windows 包附带各个 DLL 对应的许可证、来源和源代码包地址，见 `licenses/ffmpeg_kit_flutter_new/NOTICE.txt`。原生 FFmpegKit 8.1.2-full-gpl 的构建脚本与平台下载地址见 [上游发布](https://github.com/sk3llo/ffmpeg_kit_flutter/releases/tag/8.1.2-full-gpl)，Windows 构建源码见 [windows-8.1.2](https://github.com/sk3llo/ffmpeg-kit/tree/windows-8.1.2)。各平台发布时应保留相应许可信息与对应源码获取说明。

编译和自动化检查不能替代所有设备的实机验收。0.1.5 的真实短信安全验证需要用户后续回归；原生回归使用虚构 HttpOnly Cookie 与本地 HTTP 页面，不接触真实验证码或凭据。
