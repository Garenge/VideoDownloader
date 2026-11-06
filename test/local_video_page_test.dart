import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:videodownloader/source_parser/downloaded_file_store.dart';
import 'package:videodownloader/source_parser/player/local_video_page.dart';
import 'package:videodownloader/source_parser/player/video_player_surface.dart';

import 'helpers/local_video_platform.dart';

void main() {
  late LocalVideoPlatform platform;
  late Directory directory;
  late DownloadedFile file;

  setUp(() async {
    platform = LocalVideoPlatform();
    final previous = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = platform;
    addTearDown(() => VideoPlayerPlatform.instance = previous);
    directory = await Directory.systemTemp.createTemp('local_player_test');
    final video = await File('${directory.path}/sample.mp4').writeAsBytes([0]);
    file = DownloadedFile(video.path, 1, DateTime(2026));
  });

  tearDown(() async => directory.delete(recursive: true));

  Future<void> pumpPlayer(WidgetTester tester) async {
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    await tester.pump();
  }

  Future<void> openPlayer(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => LocalVideoPage(file: file)),
            ),
            child: const Text('打开视频'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开视频'));
    await pumpPlayer(tester);
  }

  Future<void> removePlayer(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await pumpPlayer(tester);
  }

  testWidgets('fullscreen preserves controller and position; exit disposes', (
    tester,
  ) async {
    await openPlayer(tester);
    final controller = tester
        .widget<VideoPlayerSurface>(find.byType(VideoPlayerSurface))
        .controller!;
    expect(platform.sources.single.sourceType, DataSourceType.file);
    await controller.seekTo(const Duration(seconds: 42));
    await tester.tap(find.byTooltip('全屏'));
    await pumpPlayer(tester);
    expect(
      tester
          .widget<VideoPlayerSurface>(find.byType(VideoPlayerSurface))
          .fullscreen,
      isTrue,
    );
    await tester.binding.handlePopRoute();
    await pumpPlayer(tester);
    expect(find.byType(LocalVideoPage), findsOneWidget);
    final surface = tester.widget<VideoPlayerSurface>(
      find.byType(VideoPlayerSurface),
    );
    expect(surface.fullscreen, isFalse);
    expect(surface.controller, same(controller));
    expect(controller.value.position, const Duration(seconds: 42));
    expect(platform.sources, hasLength(1));
    await tester.tap(find.byType(BackButton));
    await pumpPlayer(tester);
    expect(find.byType(LocalVideoPage), findsNothing);
    expect(platform.disposed, hasLength(1));
    expect(platform.playing, isEmpty);
    await removePlayer(tester);
  });

  testWidgets('background pauses without auto-resuming', (tester) async {
    await openPlayer(tester);
    expect(platform.playing, isNotEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(platform.playing, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(platform.playing, isEmpty);
    await removePlayer(tester);
  });

  testWidgets('missing file shows retry and system open entry', (tester) async {
    File(file.path).deleteSync();
    await openPlayer(tester);
    expect(find.textContaining('无法播放此视频'), findsOneWidget);
    expect(find.byTooltip('用系统应用打开'), findsOneWidget);
    expect(platform.sources, isEmpty);
    File(file.path).writeAsBytesSync([0]);
    await tester.tap(find.text('重试'));
    await pumpPlayer(tester);
    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(platform.playing, isNotEmpty);
    await removePlayer(tester);
  });

  testWidgets('decoder failure releases controller and supports retry', (
    tester,
  ) async {
    platform.failInitialization = true;
    await openPlayer(tester);
    expect(find.textContaining('无法播放此视频'), findsOneWidget);
    expect(platform.disposed, hasLength(1));
    platform.failInitialization = false;
    await tester.tap(find.text('重试'));
    await pumpPlayer(tester);
    expect(platform.playing, isNotEmpty);
    await removePlayer(tester);
    expect(platform.disposed, hasLength(2));
  });

  testWidgets('native creation failure still shows error and allows retry', (
    tester,
  ) async {
    platform.failCreation = true;
    await openPlayer(tester);
    expect(find.textContaining('无法播放此视频'), findsOneWidget);
    platform.failCreation = false;
    await tester.tap(find.text('重试'));
    await pumpPlayer(tester);
    expect(platform.playing, isNotEmpty);
    await removePlayer(tester);
  });
}
