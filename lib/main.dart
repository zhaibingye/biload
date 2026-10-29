import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_controller.dart';
import 'ui/app.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'biload',
      'FFmpeg / FFmpegKit',
    ], await rootBundle.loadString('LICENSE'));
    yield LicenseEntryWithLineBreaks([
      'biload third-party notices',
    ], await rootBundle.loadString('THIRD_PARTY_NOTICES.md'));
  });
  runApp(const BiloadBootstrap());
}

class BiloadBootstrap extends StatefulWidget {
  const BiloadBootstrap({super.key});
  @override
  State<BiloadBootstrap> createState() => _BiloadBootstrapState();
}

class _BiloadBootstrapState extends State<BiloadBootstrap> {
  late Future<BiloadController> startup;
  @override
  void initState() {
    super.initState();
    startup = BiloadController.create();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<BiloadController>(
    future: startup,
    builder: (context, snapshot) {
      if (snapshot.hasData) return BiloadApp(controller: snapshot.data!);
      return MaterialApp(
        title: 'biload',
        debugShowCheckedModeBanner: false,
        theme: biloadTheme(),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Brand(),
                  const SizedBox(height: 28),
                  if (snapshot.hasError) ...[
                    const Text(
                      '无法初始化本地服务，请检查运行环境后重试。',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    SelectableText(
                      '${snapshot.error}',
                      style: const TextStyle(fontSize: 11, color: muted),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () =>
                          setState(() => startup = BiloadController.create()),
                      child: const Text('重试'),
                    ),
                  ] else ...[
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      '正在打开你的工作台',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
