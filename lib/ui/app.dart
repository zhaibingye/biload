import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_controller.dart';
import '../core/models.dart';
import '../services/output_storage.dart';
import 'login_dialog.dart';
import 'theme.dart';

class BiloadApp extends StatelessWidget {
  const BiloadApp({super.key, required this.controller});
  final BiloadController controller;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'biload',
    debugShowCheckedModeBanner: false,
    theme: biloadTheme(),
    home: Workspace(controller: controller),
  );
}

class Workspace extends StatefulWidget {
  const Workspace({super.key, required this.controller});
  final BiloadController controller;
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  final input = TextEditingController();
  final bodyScroll = ScrollController();
  int destination = 0;
  int queueFilter = 0;
  static const destinations = [
    (Icons.add_link_rounded, '新建下载'),
    (Icons.downloading_rounded, '下载任务'),
    (Icons.tune_rounded, '账号与设置'),
  ];
  BiloadController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    c.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  void navigateTo(int value) {
    if (bodyScroll.hasClients) bodyScroll.jumpTo(0);
    setState(() => destination = value);
  }

  @override
  void dispose() {
    c.removeListener(changed);
    input.dispose();
    bodyScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 940;
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              if (wide) sidebar(),
              Expanded(
                child: Column(
                  children: [
                    header(wide),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: bodyScroll,
                        padding: EdgeInsets.fromLTRB(
                          wide ? 36 : 18,
                          16,
                          wide ? 36 : 18,
                          36,
                        ),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1100),
                            child: switch (destination) {
                              1 => queue(),
                              2 => settings(),
                              _ => createPage(wide),
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: destination,
                onDestinationSelected: navigateTo,
                destinations: [
                  for (final item in destinations)
                    NavigationDestination(icon: Icon(item.$1), label: item.$2),
                ],
              ),
      );
    },
  );

  Widget sidebar() => Container(
    width: 218,
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(right: BorderSide(color: line)),
    ),
    padding: const EdgeInsets.fromLTRB(20, 32, 20, 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(padding: EdgeInsets.only(left: 10), child: Brand()),
        const SizedBox(height: 52),
        const Padding(
          padding: EdgeInsets.only(left: 14, bottom: 14),
          child: Text('你的工作台', style: TextStyle(fontSize: 11, color: muted)),
        ),
        for (var i = 0; i < destinations.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: destination == i
                  ? const Color(0xFFEAF2EC)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(13),
              child: InkWell(
                borderRadius: BorderRadius.circular(13),
                onTap: () => navigateTo(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 15,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        destinations[i].$1,
                        size: 20,
                        color: destination == i ? accent : muted,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        destinations[i].$2,
                        style: TextStyle(
                          fontSize: 13,
                          color: destination == i ? accent : muted,
                          fontWeight: destination == i
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const Spacer(),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: canvas,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.folder_copy_outlined, color: accent, size: 25),
              SizedBox(height: 12),
              Text(
                '留在自己的设备里',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 6),
              Text('本地下载 · 原始画质', style: TextStyle(fontSize: 11, color: muted)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Padding(
          padding: EdgeInsets.only(left: 12),
          child: Text(
            'BILOAD  /  0.1.5',
            style: TextStyle(fontSize: 10, color: muted, letterSpacing: 1.2),
          ),
        ),
      ],
    ),
  );

  Widget header(bool wide) => Padding(
    padding: EdgeInsets.fromLTRB(wide ? 36 : 18, 20, wide ? 36 : 18, 16),
    child: Row(
      children: [
        if (!wide)
          const Brand(compact: true)
        else
          Text(
            '工作台   /   ${destinations[destination].$2}',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
        const Spacer(),
        InkWell(
          key: const ValueKey('account-entry'),
          borderRadius: BorderRadius.circular(30),
          onTap: () {
            if (c.auth.loggedIn) {
              navigateTo(2);
            } else {
              showLogin(context, c.auth);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: line),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  c.auth.loggedIn
                      ? Icons.verified_user_outlined
                      : Icons.account_circle_outlined,
                  size: 17,
                  color: c.auth.loggedIn ? accent : muted,
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 130),
                  child: Text(
                    c.auth.account?.name ?? '登录账号',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                if (c.auth.account?.vip ?? false) ...[
                  const SizedBox(width: 8),
                  const Tag('大会员', color: Color(0xFFA36A3E)),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget createPage(bool wide) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '为喜欢的内容，留一份。',
                    style: TextStyle(
                      color: accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 13),
                  Text(
                    '把喜欢的，\n好好收藏。',
                    style: TextStyle(
                      fontSize: wide ? 44 : 33,
                      height: 1.35,
                      fontWeight: FontWeight.w800,
                      color: ink,
                      letterSpacing: -1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '粘贴链接，挑选画质与音轨，保存到你的设备。',
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (wide)
              const SizedBox(width: 230, height: 210, child: _HeroArtwork()),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.link_rounded, color: accent, size: 21),
                const SizedBox(width: 9),
                const Text(
                  '视频链接',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: c.parsing || c.adding
                      ? null
                      : () => action(context, () async {
                          final data = await Clipboard.getData(
                            Clipboard.kTextPlain,
                          );
                          if (mounted && data?.text != null) {
                            input.text = data!.text!;
                          }
                        }),
                  icon: const Icon(Icons.content_paste_rounded, size: 15),
                  label: const Text('粘贴'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: input,
              key: const Key('video-link'),
              minLines: 1,
              maxLines: 3,
              onSubmitted: (_) => c.parse(input.text),
              decoration: const InputDecoration(
                hintText: '粘贴 bilibili.com、b23.tv 链接，或输入 BV / AV / ep / ss 编号',
                hintStyle: TextStyle(fontSize: 12, color: muted),
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 18,
              runSpacing: 14,
              children: [
                const Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [Tag('普通视频'), Tag('分 P'), Tag('番剧 / 影视')],
                ),
                FilledButton.icon(
                  key: const Key('parse-link'),
                  onPressed: c.parsing || c.adding
                      ? null
                      : () => c.parse(input.text),
                  icon: c.parsing
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_forward_rounded, size: 19),
                  label: Text(c.parsing ? '正在解析' : '解析视频'),
                ),
              ],
            ),
          ],
        ),
      ),
      if (c.parsing || c.adding) ...[
        const SizedBox(height: 18),
        Row(
          children: [
            const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                c.status,
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ),
          ],
        ),
      ],
      if (c.error != null) ...[
        const SizedBox(height: 18),
        Notice(c.error!, error: true),
      ],
      if (c.content != null) ...[
        const SizedBox(height: 24),
        contentCard(),
        if (c.catalog != null) ...[
          const SizedBox(height: 18),
          variants(wide),
          const SizedBox(height: 18),
          outputOptions(),
        ],
      ],
      if (c.content == null && !c.parsing) ...[
        const SizedBox(height: 28),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.high_quality_outlined, size: 19, color: muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                c.auth.loggedIn ? '画质与音轨将按当前账号的实际权限显示。' : '登录账号后，可以获取更多画质与音轨。',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    ],
  );

  Widget contentCard() {
    final media = c.content!;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: cover(media.cover, 118, 77),
              ),
              const SizedBox(width: 17),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      media.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${media.author}  ·  ${media.pages.length} 个分集',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (media.pages.length > 1) ...[
            const SizedBox(height: 20),
            DropdownButtonFormField<int>(
              key: ValueKey('${media.pages.first.key}:${c.pageIndex}'),
              initialValue: c.pageIndex,
              isExpanded: true,
              items: [
                for (var i = 0; i < media.pages.length; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(
                      '${i + 1}. ${media.pages[i].part}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
              ],
              onChanged: c.parsing || c.adding
                  ? null
                  : (i) {
                      if (i != null) c.selectPage(i);
                    },
              decoration: const InputDecoration(labelText: '查看分集版本'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: c.allPages,
              onChanged: c.parsing || c.adding
                  ? null
                  : (value) => c.setAllPages(value ?? false),
              title: const Text('下载全部分集', style: TextStyle(fontSize: 13)),
              subtitle: const Text(
                '应用相同规格；缺少所选规格时会提示，不自动降级。',
                style: TextStyle(fontSize: 11, color: muted),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ],
      ),
    );
  }

  Widget variants(bool wide) {
    final catalog = c.catalog!;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                '选择下载版本',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '${catalog.videos.length} 视频 · ${catalog.audios.length} 音轨',
                style: const TextStyle(fontSize: 11, color: muted),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Text(
            '视频',
            style: TextStyle(
              fontSize: 12,
              color: muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          for (final video in catalog.videos)
            _variantRow(
              selected: c.selectedVideos.contains(video.key),
              onTap: () => c.toggleVideo(video.key),
              title: video.qualityLabel,
              tag: video.codecLabel,
              detail: [
                if (video.width > 0) '${video.width} × ${video.height}',
                if (video.frameRate.isNotEmpty) '${_fps(video.frameRate)} fps',
                if (video.progressive) '含音频',
              ].join('  ·  '),
              trailing: video.estimateBytes(c.page!.duration) > 0
                  ? '约 ${formatBytes(video.estimateBytes(c.page!.duration))}'
                  : '',
            ),
          if (catalog.videos.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('未返回独立视频流', style: TextStyle(color: muted)),
            ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),
          const Text(
            '音频',
            style: TextStyle(
              fontSize: 12,
              color: muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          for (final audio in catalog.audios)
            _variantRow(
              selected: c.selectedAudios.contains(audio.key),
              onTap: () => c.toggleAudio(audio.key),
              title: audio.qualityLabel,
              tag: audio.languageTitle.isEmpty ? '原音' : audio.languageTitle,
              detail:
                  '${(audio.bandwidth / 1000).round()} kbps  ·  ${audio.codecs}',
              trailing: audio.bandwidth > 0
                  ? '约 ${formatBytes(audio.bandwidth * c.page!.duration / 8)}'
                  : '',
            ),
          if (catalog.audios.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                '无独立音轨；合流视频将保留自带音频。',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ),
          if (catalog.unavailable.isNotEmpty) ...[
            const SizedBox(height: 16),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                '其他声明规格（${catalog.unavailable.length}）',
                style: const TextStyle(fontSize: 12, color: muted),
              ),
              children: [
                for (final format in catalog.unavailable)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.lock_outline_rounded,
                      size: 17,
                      color: muted,
                    ),
                    title: Text(
                      format.label,
                      style: const TextStyle(fontSize: 12),
                    ),
                    subtitle: Text(
                      format.reason,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
              ],
            ),
          ],
          for (final warning in catalog.warnings) ...[
            const SizedBox(height: 12),
            Notice(warning, error: true),
          ],
        ],
      ),
    );
  }

  String _fps(String value) {
    final parts = value.split('/');
    if (parts.length != 2) return value;
    final a = double.tryParse(parts[0]), b = double.tryParse(parts[1]);
    return a == null || b == null || b == 0
        ? value
        : (a / b).toStringAsFixed(a % b == 0 ? 0 : 2);
  }

  Widget _variantRow({
    required bool selected,
    required VoidCallback onTap,
    required String title,
    required String tag,
    required String detail,
    required String trailing,
  }) => Padding(
    padding: const EdgeInsets.only(top: 7),
    child: Material(
      color: selected ? const Color(0xFFF0F6F0) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? const Color(0xFFBDCEBF) : line),
      ),
      child: InkWell(
        onTap: c.adding ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: c.adding ? null : (_) => onTap(),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Tag(tag),
                      ],
                    ),
                    if (detail.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        detail,
                        style: const TextStyle(color: muted, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
              if (MediaQuery.sizeOf(context).width > 500)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    trailing,
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget outputOptions() => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '保存方式',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const Text('文件容器', style: TextStyle(fontSize: 12, color: muted)),
            const Spacer(),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'mp4', label: Text('MP4')),
                ButtonSegment(value: 'mkv', label: Text('MKV')),
              ],
              selected: {c.container},
              showSelectedIcon: false,
              onSelectionChanged: c.adding
                  ? null
                  : (v) => c.setContainer(v.first),
            ),
          ],
        ),
        const SizedBox(height: 18),
        InkWell(
          onTap: chooseDirectory,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: canvas,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.folder_outlined, size: 21, color: accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    c.outputDirectoryLabel,
                    style: const TextStyle(color: muted, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
                const Icon(Icons.edit_outlined, size: 16, color: muted),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          c.outputSelectionDescription,
          style: const TextStyle(fontSize: 11, color: muted),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: c.adding || c.parsing
              ? null
              : () => action(context, () async {
                  final count = await c.enqueue();
                  if (mounted) {
                    navigateTo(1);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          count == 0 ? '相同任务已在队列中' : '已加入 $count 个下载任务',
                        ),
                      ),
                    );
                  }
                }),
          icon: const Icon(Icons.south_rounded, size: 20),
          label: Text(c.adding ? '正在检查分集' : '加入下载队列'),
        ),
      ],
    ),
  );

  Future<void> chooseDirectory() => action(context, () async {
    if (Platform.isAndroid) {
      final selected = await c.downloads.outputStorage.chooseDirectory();
      if (selected != null) {
        c.setDirectory(selected.directory, label: selected.label);
      }
      return;
    }
    final directory = await FilePicker.getDirectoryPath(
      dialogTitle: '选择 biload 下载目录',
    );
    if (directory != null) c.setDirectory(directory);
  });

  Widget queue() {
    final jobs = c.downloads.jobs;
    final active = jobs.where((j) => !j.isFinished).length;
    final complete = jobs.where((j) => j.status == JobStatus.complete).length;
    final failed = jobs.where((j) => j.status == JobStatus.failed).length;
    final filtered = jobs
        .where(
          (j) => switch (queueFilter) {
            1 => !j.isFinished,
            2 => j.status == JobStatus.complete,
            _ => true,
          },
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        const Text(
          '下载任务',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          '进度、暂停和继续，都在这里。',
          style: TextStyle(color: muted, fontSize: 13),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: metric('进行中', '$active', Icons.downloading_rounded),
            ),
            const SizedBox(width: 10),
            Expanded(child: metric('已完成', '$complete', Icons.task_alt_rounded)),
            const SizedBox(width: 10),
            Expanded(
              child: metric('需要处理', '$failed', Icons.info_outline_rounded),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          children: [
            for (var i = 0; i < 3; i++)
              ChoiceChip(
                label: Text(['全部', '进行中', '已完成'][i]),
                selected: queueFilter == i,
                onSelected: (_) => setState(() => queueFilter = i),
              ),
          ],
        ),
        const SizedBox(height: 18),
        if (filtered.isEmpty)
          Panel(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  const Icon(
                    Icons.inbox_outlined,
                    size: 52,
                    color: Color(0xFFB9C8BA),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '这里还没有下载任务',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '从一个喜欢的视频链接开始。',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton(
                    onPressed: () => navigateTo(0),
                    child: const Text('新建下载'),
                  ),
                ],
              ),
            ),
          )
        else
          for (final job in filtered)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: jobCard(job),
            ),
      ],
    );
  }

  Widget metric(String label, String value, IconData icon) => Panel(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: accent, size: 22),
        const SizedBox(height: 12),
        Text(
          value,
          style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w700),
        ),
        Text(label, style: const TextStyle(color: muted, fontSize: 11)),
      ],
    ),
  );

  Widget jobCard(DownloadJob job) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: cover(job.page.cover, 90, 61),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.page.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'P${job.page.index} · ${job.page.part}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: muted),
                  ),
                  const SizedBox(height: 8),
                  Tag(
                    _statusLabel(job.status),
                    color: job.status == JobStatus.failed
                        ? const Color(0xFFA36A3E)
                        : accent,
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: '任务操作',
              onSelected: (value) => action(context, () async {
                if (value == 'cancel') await c.downloads.cancel(job);
                if (value == 'remove') await c.downloads.remove(job);
              }),
              itemBuilder: (_) => [
                if (!job.isFinished)
                  const PopupMenuItem(value: 'cancel', child: Text('取消下载')),
                if (job.isFinished)
                  const PopupMenuItem(
                    value: 'remove',
                    child: Text('移除记录（保留文件）'),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (!job.isFinished)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value:
                  job.status == JobStatus.resolving ||
                      job.status == JobStatus.merging ||
                      (job.status == JobStatus.downloading &&
                          job.totalBytes == 0)
                  ? null
                  : job.progress,
              minHeight: 5,
              backgroundColor: canvas,
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Text(
              job.status == JobStatus.downloading
                  ? '${job.totalBytes > 0 ? '${(job.progress * 100).toStringAsFixed(1)}% · ${formatBytes(job.downloadedBytes)} / ${formatBytes(job.totalBytes)} · 剩余 ${formatBytes(job.remainingBytes)}' : '已下载 ${formatBytes(job.downloadedBytes)} · 正在获取总大小'} · ${formatBytes(job.bytesPerSecond)}/s'
                  : job.message,
              style: TextStyle(
                fontSize: 11,
                color: job.status == JobStatus.failed
                    ? const Color(0xFFA36A3E)
                    : muted,
              ),
            ),
            Wrap(
              spacing: 6,
              children: [
                if ({
                  JobStatus.queued,
                  JobStatus.resolving,
                  JobStatus.downloading,
                }.contains(job.status))
                  TextButton.icon(
                    onPressed: () =>
                        action(context, () => c.downloads.pause(job)),
                    icon: const Icon(Icons.pause_rounded, size: 17),
                    label: const Text('暂停'),
                  ),
                if ({JobStatus.paused, JobStatus.failed}.contains(job.status))
                  TextButton.icon(
                    onPressed: () =>
                        action(context, () => c.downloads.resume(job)),
                    icon: const Icon(Icons.play_arrow_rounded, size: 17),
                    label: Text(job.status == JobStatus.failed ? '重试' : '继续'),
                  ),
                if (job.status == JobStatus.complete) ...[
                  TextButton.icon(
                    onPressed: () => action(context, () => openOutput(job)),
                    icon: const Icon(
                      Icons.play_circle_outline_rounded,
                      size: 17,
                    ),
                    label: const Text('打开'),
                  ),
                  if (c.downloads.outputStorage.isLegacyOutput(job.output) ||
                      job.retainedSource.isNotEmpty)
                    TextButton.icon(
                      onPressed: c.downloads.movingFiles
                          ? null
                          : () => action(context, () async {
                              await c.downloads.migrateLegacyOutputs(
                                c.outputDirectory,
                                only: job,
                              );
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      job.retainedSource.isEmpty
                                          ? '已移至下载目录，旧文件已清理'
                                          : '已保存到下载目录，请在设置中重试清理旧副本',
                                    ),
                                  ),
                                );
                              }
                            }),
                      icon: const Icon(Icons.ios_share_rounded, size: 17),
                      label: const Text('移至下载目录'),
                    ),
                ],
              ],
            ),
          ],
        ),
      ],
    ),
  );

  String _statusLabel(JobStatus value) => switch (value) {
    JobStatus.queued => '排队中',
    JobStatus.resolving => '解析中',
    JobStatus.downloading => '下载中',
    JobStatus.paused => '已暂停',
    JobStatus.merging => '合并与检查',
    JobStatus.complete => '已完成',
    JobStatus.failed => '需要处理',
    JobStatus.canceled => '已取消',
  };

  Future<void> openOutput(DownloadJob job) async {
    if (!await c.downloads.outputStorage.exists(job.output)) {
      throw const BiliException('文件已被移动或删除。');
    }
    if (Platform.isAndroid || Platform.isWindows) {
      await c.downloads.outputStorage.open(job.output);
    } else if (!await launchUrl(
      Uri.file(job.output),
      mode: LaunchMode.externalApplication,
    )) {
      throw const BiliException('无法打开文件，请在下载目录中查看。');
    }
  }

  Widget settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 18),
      const Text(
        '账号与设置',
        style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      const Text('让下载按照你的习惯工作。', style: TextStyle(color: muted, fontSize: 13)),
      const SizedBox(height: 28),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '哔哩哔哩账号',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: canvas,
                  child: c.auth.account?.avatar.isNotEmpty ?? false
                      ? ClipOval(child: cover(c.auth.account!.avatar, 52, 52))
                      : const Icon(Icons.person_outline_rounded, color: muted),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.auth.account?.name ?? '尚未登录',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        c.auth.account == null
                            ? '登录后获取账号可用的完整版本'
                            : 'UID ${c.auth.account!.uid} · ${c.auth.account!.vip ? '大会员' : '普通用户'}',
                        style: const TextStyle(fontSize: 11, color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton(
                  onPressed: () => showLogin(context, c.auth),
                  child: Text(c.auth.loggedIn ? '切换 / 重新登录' : '登录账号'),
                ),
                if (c.auth.api.session.hasLogin) ...[
                  OutlinedButton(
                    onPressed: c.auth.busy
                        ? null
                        : () => action(context, c.auth.refresh),
                    child: const Text('检查登录状态'),
                  ),
                  TextButton(
                    onPressed: () => action(context, c.auth.logout),
                    child: const Text('退出登录'),
                  ),
                ],
              ],
            ),
            if (c.auth.warning != null) ...[
              const SizedBox(height: 16),
              Notice(c.auth.warning!, error: true),
            ],
          ],
        ),
      ),
      const SizedBox(height: 18),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '下载偏好',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(
                  child: Text('同时下载任务数', style: TextStyle(fontSize: 13)),
                ),
                DropdownButton<int>(
                  value: c.downloads.concurrency,
                  items: [
                    for (var i = 1; i <= 4; i++)
                      DropdownMenuItem(value: i, child: Text('$i')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      c.downloads.configure(concurrent: value);
                    }
                  },
                ),
              ],
            ),
            const Divider(height: 32),
            Text(
              c.outputDirectoryLabel,
              style: const TextStyle(fontSize: 12, color: muted),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: chooseDirectory,
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: const Text('更改下载目录'),
              ),
            ),
            if (Platform.isAndroid) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () =>
                      c.setDirectory(OutputStorage.androidDownloads),
                  child: const Text('恢复默认下载目录'),
                ),
              ),
              const Text(
                '完成的视频保存在公共文件夹，可在系统文件管理器中删除。下载和合并的临时文件会自动清理。',
                style: TextStyle(fontSize: 12, color: muted),
              ),
              if (c.downloads.legacyOutputCount > 0) ...[
                const SizedBox(height: 16),
                Text(
                  '旧版有 ${c.downloads.legacyOutputCount} 个文件仍在应用目录。迁移成功后会删除应用内原件。',
                  style: const TextStyle(fontSize: 12, color: muted),
                ),
                const SizedBox(height: 10),
                FilledButton.tonal(
                  onPressed: c.downloads.movingFiles
                      ? null
                      : () => action(context, () async {
                          final count = await c.downloads.migrateLegacyOutputs(
                            c.outputDirectory,
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('已迁移 $count 个文件')),
                            );
                          }
                        }),
                  child: Text(c.downloads.movingFiles ? '正在迁移文件…' : '迁移旧版文件'),
                ),
              ],
              TextButton(
                onPressed: () => action(context, () async {
                  await c.downloads.cleanupFinishedCache(
                    includeFailed: true,
                    strict: true,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已清理已结束任务的临时文件，失败任务重试时会重新下载'),
                      ),
                    );
                  }
                }),
                child: const Text('清理已结束任务的临时文件'),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 18),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Brand(),
            SizedBox(height: 16),
            Text('0.1.5 · 免费开源', style: TextStyle(color: muted, fontSize: 12)),
            SizedBox(height: 8),
            Text(
              '保存账号有权访问的内容。版本与可下载状态以实时解析结果为准。',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'biload',
                applicationVersion: '0.1.5',
                applicationLegalese: '作者：烨染霜华 · GPL-3.0-or-later',
              ),
              icon: const Icon(Icons.article_outlined, size: 18),
              label: const Text('开源许可'),
            ),
          ],
        ),
      ),
    ],
  );
}

Widget cover(String url, double width, double height) => Image.network(
  url.startsWith('//') ? 'https:$url' : url,
  width: width,
  height: height,
  fit: BoxFit.cover,
  errorBuilder: (_, _, _) => Container(
    width: width,
    height: height,
    color: const Color(0xFFE8EEE7),
    child: const Icon(
      Icons.smart_display_outlined,
      color: Color(0xFFA8B9A9),
      size: 28,
    ),
  ),
);

class Brand extends StatelessWidget {
  const Brand({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: compact ? 28 : 34,
        height: compact ? 28 : 34,
        decoration: BoxDecoration(
          color: ink,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(
          Icons.south_rounded,
          color: const Color(0xFFDEF2C7),
          size: compact ? 20 : 25,
        ),
      ),
      const SizedBox(width: 10),
      Text(
        'biload',
        style: TextStyle(
          color: ink,
          fontSize: compact ? 22 : 27,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.3,
        ),
      ),
    ],
  );
}

class _HeroArtwork extends StatelessWidget {
  const _HeroArtwork();
  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      Container(
        width: 190,
        height: 190,
        decoration: const BoxDecoration(
          color: Color(0xFFE7EDDF),
          shape: BoxShape.circle,
        ),
      ),
      Transform.rotate(
        angle: -0.13,
        child: Container(
          width: 132,
          height: 160,
          decoration: BoxDecoration(
            color: const Color(0xFFC3D8B8),
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      Transform.translate(
        offset: const Offset(14, -3),
        child: Transform.rotate(
          angle: 0.07,
          child: Container(
            width: 133,
            height: 160,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFD9E1D1)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0E183A32),
                  blurRadius: 22,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 76,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDAE8D1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.play_arrow_rounded,
                      size: 40,
                      color: accent,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(height: 5, width: 70, color: const Color(0xFFB7CBB0)),
                const SizedBox(height: 8),
                Container(height: 5, width: 45, color: const Color(0xFFE1E9DB)),
              ],
            ),
          ),
        ),
      ),
      Positioned(
        right: 12,
        bottom: 16,
        child: Container(
          width: 53,
          height: 53,
          decoration: BoxDecoration(
            color: ink,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: canvas, width: 4),
          ),
          child: const Icon(
            Icons.south_rounded,
            color: Color(0xFFE0EDB9),
            size: 27,
          ),
        ),
      ),
    ],
  );
}
