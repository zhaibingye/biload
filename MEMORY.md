# 项目工程记忆

仅记录已验证的约束与规律；功能或依赖改变后同步修正。以下经验经 1.0.1 发布验证（2026-10-30）。

## 数据目录

- 桌面账号、设置、任务、续传记录和缓存统一由 `AppPaths` 定位：Windows/Linux 在可执行文件旁的 `user-data`，macOS 在 `.app` 旁。安装目录不可写时明确提示，不回退到隐藏目录。
- 完成的视频默认仍放在系统 Downloads 下的 `biload`；保存位置由 `OutputStorage` 管理。用户数据位置与成品下载位置必须独立。
- 不读取、兼容、迁移或清理旧版数据。Android 安装区只读，数据由系统应用目录管理，视频默认使用公共下载目录。
- 下载器须显式使用 `TransferStore` 和本地缓存目录，避免插件默认存储另建数据库。Windows 网页配置显式指定目录；Linux 在 GTK 初始化前固定 GLib 目录缓存并恢复进程环境，避免外部播放器继承这些目录；macOS 登录使用内存 WKWebView。
- 桌面账号使用 `FileSessionVault`：Windows DPAPI 绑定当前系统用户；Linux/macOS 使用 AES-GCM 和当前用户独占权限的密钥文件。不要把 Cookie、密钥或账号文件加入仓库和发布包。

## Windows 本机构建

- Unicode 工程路径通过 `tool/flutter_project.ps1` 使用 ASCII junction 构建；不要复制一份源码来规避路径问题。
- Flutter 更新依赖时可能清除桌面插件链接，即使 `pub get` 返回成功。共享构建准备须在依赖解析后执行一次 `link_plugins.ps1`；若首次因 symlink 支持失败，准备 junction 后重跑 `pub get`，保证原生插件注册完成。
- 并发数菜单完成选择后释放自己的 FocusNode，避免桌面端焦点底色一直保留。页面切换遵循系统减少动画设置。

## 图标与发布

- 桌面图标以 `assets/brand/biload.svg` 为源，用 `tool/generate_desktop_icons.py` 生成 Windows 多尺寸 ICO 和 macOS AppIcon；Linux 同时维护嵌入资源、窗口图标名与桌面入口。修改源图后要检查生成资产。
- 发布版本来自 `pubspec.yaml`，界面版本常量有测试约束。Flutter 3.47.8 的 arm64 split APK 会在构建号上增加 2000；`verify_android_package.py` 针对这种正式分包校验，不能直接拿 pubspec 构建号比较 APK versionCode。
- 正式 APK 使用仓库外的固定私钥；密码由 Windows DPAPI 保护，经进程环境传给 Gradle。CI 未签名 APK 只用于静态检查，不能作为正式安装包上传。
- 所有发布文件必须对应同一已验证提交。桌面运行检查用 `tool/verify_desktop_release.py` 执行真实打包二进制与本机回环素材；Windows 还应复测待发布压缩包。Linux 包在 Ubuntu 22.04/24.04、macOS 通用包在 Apple Silicon/Intel 复测。Android 没有手机环境时明确标记静态验证。
- 排除运行时生成的 `user-data` 与 `downloads`，保留原生库及第三方许可证；核对版本、签名、架构、Android 16 KB 对齐及 SHA-256。四个平台包、验证附件、校验文件齐全并验证后再发布稳定版。GitHub 存储偶发流量限制可延迟重试，不能跳过摘要验证。
