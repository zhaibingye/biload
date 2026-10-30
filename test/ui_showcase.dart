import 'package:biload/core/models.dart';

/// In-memory display data, used only when explicitly capturing README images.
/// These tasks never enter the downloader or represent saved user files.
List<DownloadJob> showcaseJobs() => [
  for (final (index, title, part, status, fraction) in [
    (1, '山与海之间，一段值得收藏的旅程', '穿过森林，去看海', JobStatus.downloading, 0.382),
    (2, '城市漫游 · 从清晨到日落', '沿着街巷，慢慢走', JobStatus.paused, 0.631),
    (3, '把日常拍成电影', '在平凡的日子里发现光', JobStatus.queued, 0.0),
  ])
    DownloadJob(
      id: 'showcase-$index',
      page: MediaPage(
        ref: const ContentRef(ContentKind.video, 'BV17x411w7KC'),
        cid: index,
        aid: 170001,
        bvid: 'BV17x411w7KC',
        title: title,
        part: part,
        index: 1,
        duration: 120,
      ),
      videoKey: 'showcase-avc',
      audioKeys: ['showcase-aac'],
      container: 'mp4',
      directory: 'C:/Downloads/biload',
      createdAt: DateTime(2026, 10, 30),
      status: status,
      progress: fraction,
      totalBytes: 160 * 1024 * 1024,
      downloadedBytes: (160 * 1024 * 1024 * fraction).round(),
      bytesPerSecond: status == JobStatus.downloading ? 3.6 * 1024 * 1024 : 0,
      message: status == JobStatus.paused ? '已暂停，可随时继续' : '等待下载',
    ),
];
