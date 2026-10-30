# README 界面图

这些 PNG 由 biload 的实际 Flutter 组件渲染生成，使用虚构的视频、账号和任务数据，不包含用户凭据。手机图片是手机尺寸的响应式布局预览，不是 Android 实机截图。

在项目根目录设置环境变量 `BILOAD_CAPTURE=1`，运行：

```sh
flutter test test/ui_test.dart
```

输出位于 `artifacts/ui/`。README 中选用以下图片：

| 渲染输出 | 展示文件 |
|---|---|
| home-1440.png | desktop-home.png |
| versions-desktop.png | desktop-versions.png |
| queue-1440.png | desktop-downloads.png |
| settings-1440.png | desktop-settings.png |
| home-390.png | mobile-home.png |
| queue-390.png | mobile-downloads.png |
| account-mobile.png | mobile-account.png |

任务展示数据定义在 `test/ui_showcase.dart`，仅在显式开启截图时使用，不触发下载。
