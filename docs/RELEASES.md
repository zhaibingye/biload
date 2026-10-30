# 发布构建

作者：烨染霜华。版本号来自 `pubspec.yaml`，依赖锁定在 `pubspec.lock`。

Windows / Android 可使用 `tool/build_windows.ps1` 与 `tool/build_android.ps1` 本地构建。Linux 和 macOS 使用各自原生环境；Windows 不能直接生成可用的 macOS 应用。

推送 `v*` 标签或手动运行 `.github/workflows/release.yml`，可构建全部平台，也可选择单个平台迭代。桌面程序打包前必须通过 `tool/verify_desktop_release.py`：直接运行 Release 可执行文件，验证安装位置数据目录、本地账号加密、原生数据库、界面渲染、三种视频编码与三种音频格式、多音轨、独立音频、暂停续传、字节进度、缓存清理与 WebView POST/HttpOnly Cookie。验证使用本机回环服务与原创两秒素材，测试数据和真实账号、任务隔离。打包须排除运行时生成的 `user-data` 和 `downloads` 文件夹。

Linux 在 Ubuntu 22.04 构建，使用相同包在 Ubuntu 24.04 再运行；macOS 同一通用包分别在 Apple Silicon 和 Intel 运行。macOS 最低 13，采用关闭 App Sandbox 的桌面便携模式以支持 `.app` 旁写入用户数据，重签名时保留当前 entitlements；网页登录采用内存数据存储。Windows 商业签名与 Apple 公证按维护者确认范围后补。

Android CI 只生成未签名检查包，不进入正式 Releases。公开 APK 必须使用 `tool/build_signed_android.ps1` 的固定私有密钥签名；此密钥从原有 biload 兼容证书迁移，保留数据升级，无每次构建更换签名的问题。证书 SHA-256：`10918b393dca1b5b284b21f8b9a3ee24005cd779dbe0256a7f2de58bd099c27e`。私钥在仓库外，密码受 Windows DPAPI 保护，Gradle 通过进程环境读取。请单独安全备份私钥与密码，禁止提交到 Git。其他开发者应使用自己的发布密钥。

正式交付前使用 `tool/verify_android_package.py` 核对签名、包名、API 26/36、arm64、ZIP 与所有 ELF LOAD 段的 16 KB 对齐、许可资源，并检查原生插件注册。按维护者要求，本轮 Android 不安排实机测试；编译和静态检查不声称覆盖所有 Android 设备。

Windows 完整分发目录必须保留 DLL、data 与 licenses。FFmpegKit Windows 包附带各个 DLL 对应的许可证、来源和源代码包地址，见 `licenses/ffmpeg_kit_flutter_new/NOTICE.txt`。原生 FFmpegKit 8.1.2-full-gpl 的构建脚本与平台下载地址见 [上游发布](https://github.com/sk3llo/ffmpeg_kit_flutter/releases/tag/8.1.2-full-gpl)，Windows 构建源码见 [windows-8.1.2](https://github.com/sk3llo/ffmpeg-kit/tree/windows-8.1.2)。各平台发布时应保留相应许可信息与对应源码获取说明。

最终 Releases 提供四端安装包、SHA256SUMS.txt 与验证报告压缩包。只有完整构建、运行检查及签名核对通过后才发布非预发布版本；任何检查失败都需修复后重新验证。真实短信安全验证、全部会员/地区内容与所有设备的播放行为不由这些自动化素材证明。报告不含真实 Cookie、验证码、密码或私钥。
