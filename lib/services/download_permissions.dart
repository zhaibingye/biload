import 'package:background_downloader/background_downloader.dart';

const downloadNotificationPermissionMessage =
    '请允许 biload 的下载通知后继续，可在系统应用设置中开启通知。';

Future<bool> prepareDownloadNotifications(
  Future<PermissionStatus> Function() getStatus,
  Future<PermissionStatus> Function() requestPermission, {
  bool requestIfNeeded = false,
}) async {
  var status = await getStatus();
  // Android reports a fresh permission as denied, not undetermined.
  if (status != PermissionStatus.granted && requestIfNeeded) {
    status = await requestPermission();
  }
  return status == PermissionStatus.granted;
}
