# Third-party components

biload is licensed under GPL-3.0-or-later. Dependency versions and integrity hashes are recorded in `pubspec.lock`.

| Component | Purpose | Upstream |
|---|---|---|
| Flutter / Dart | Cross-platform application runtime | https://github.com/flutter/flutter |
| dio | HTTP client | https://pub.dev/packages/dio |
| crypto / pointycastle / basic_utils | WBI hashing and session-refresh encryption | https://pub.dev/packages/crypto ; https://pub.dev/packages/pointycastle ; https://pub.dev/packages/basic_utils |
| flutter_secure_storage | Operating-system credential storage | https://pub.dev/packages/flutter_secure_storage |
| sqlite3 | Local task database | https://pub.dev/packages/sqlite3 |
| background_downloader | Native background transfers | https://pub.dev/packages/background_downloader |
| ffmpeg_kit_flutter_new | FFmpeg / FFprobe integration, full GPL variant | https://pub.dev/packages/ffmpeg_kit_flutter_new |
| FFmpegKit fork | Corresponding native integration sources and release builds | https://github.com/sk3llo/ffmpeg_kit_flutter |
| FFmpeg | Stream copying, muxing and output inspection | https://ffmpeg.org |
| desktop_webview_window / webview_flutter | Official Bilibili login pages | https://pub.dev/packages/desktop_webview_window ; https://pub.dev/packages/webview_flutter |
| qr_flutter | QR-code display | https://pub.dev/packages/qr_flutter |
| file_picker / path_provider / path / url_launcher | Platform file and path integration | https://pub.dev |

Flutter collects dependency license notices for the runtime license registry. Native FFmpeg bundle notices and the corresponding source/build information must also accompany public binary releases; see each upstream release's LICENSES and source artifacts. Native versions must be checked on each target using FFmpeg's version/configuration output before declaring a release validated.

The local DownKyi checkout and bilibili-API-collect documentation were used as references. Their source trees are not included in biload's application or source distribution. Runtime behavior is implemented separately and checked against live endpoints; API notes do not grant stability guarantees.
