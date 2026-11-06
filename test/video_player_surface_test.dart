import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videodownloader/source_parser/player/playback_controls.dart';
import 'package:videodownloader/source_parser/player/video_player_surface.dart';

import 'helpers/test_video_controller.dart';

Future<void> mountPlayer(
  WidgetTester tester,
  TestVideoController controller, {
  bool fullscreen = false,
  double width = 380,
  EdgeInsets safePadding = EdgeInsets.zero,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: 240,
            child: MediaQuery(
              data: MediaQueryData(padding: safePadding),
              child: VideoPlayerSurface(
                controller: controller,
                title: '测试视频',
                fullscreen: fullscreen,
                onToggleFullscreen: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> removePlayer(
  WidgetTester tester,
  TestVideoController controller,
) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 400));
  await controller.dispose();
}

void main() {
  test('time formatting supports hours and negative input', () {
    expect(formatPlaybackTime(const Duration(seconds: -2)), '00:00');
    expect(formatPlaybackTime(const Duration(seconds: 65)), '01:05');
    expect(formatPlaybackTime(const Duration(seconds: 3661)), '1:01:01');
  });

  testWidgets('controls hide during playback and stay visible when paused', (
    tester,
  ) async {
    final controller = TestVideoController();
    await mountPlayer(tester, controller);
    expect(find.byType(PlaybackControls), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.byType(PlaybackControls), findsNothing);
    await controller.pause();
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(find.byType(PlaybackControls), findsOneWidget);
    await removePlayer(tester, controller);
  });

  testWidgets('drag previews then seeks once and resumes playback', (
    tester,
  ) async {
    final controller = TestVideoController();
    await mountPlayer(tester, controller);
    final origin = tester.getTopLeft(find.byType(VideoPlayerSurface));
    final gesture = await tester.startGesture(origin + const Offset(80, 40));
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(70, 0));
    await tester.pump();
    expect(controller.seeks, isEmpty);
    expect(controller.value.isPlaying, isFalse);
    expect(find.textContaining('松开跳转'), findsOneWidget);
    await gesture.up();
    await tester.pump();
    expect(controller.seeks, hasLength(1));
    expect(controller.seeks.single, greaterThan(const Duration(seconds: 60)));
    expect(controller.value.isPlaying, isTrue);
    await removePlayer(tester, controller);
  });

  testWidgets('slider remains mounted while scrubbing a paused video', (
    tester,
  ) async {
    final controller = TestVideoController(playing: false);
    await mountPlayer(tester, controller);
    final start = tester.getCenter(find.byType(Slider));
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(find.byType(Slider), findsOneWidget);
    await gesture.moveBy(const Offset(20, 0));
    await gesture.up();
    await tester.pump();
    expect(controller.seeks, hasLength(1));
    expect(controller.value.isPlaying, isFalse);
    await removePlayer(tester, controller);
  });

  testWidgets('long press restores the original speed on release', (
    tester,
  ) async {
    final controller = TestVideoController(speed: 1.5);
    await mountPlayer(tester, controller);
    final origin = tester.getTopLeft(find.byType(VideoPlayerSurface));
    final gesture = await tester.startGesture(origin + const Offset(100, 40));
    await tester.pump(const Duration(milliseconds: 600));
    expect(controller.value.playbackSpeed, 2);
    expect(find.text('2.0x 快进中'), findsOneWidget);
    await gesture.up();
    await tester.pump();
    expect(controller.value.playbackSpeed, 1.5);
    expect(find.text('2.0x 快进中'), findsNothing);
    await removePlayer(tester, controller);
  });

  for (final fullscreen in [false, true]) {
    testWidgets(
      'fast-forward hint sits at bottom right, fullscreen=$fullscreen',
      (tester) async {
        final controller = TestVideoController();
        await mountPlayer(tester, controller, fullscreen: fullscreen);
        final surface = tester.getRect(find.byType(VideoPlayerSurface));
        final gesture = await tester.startGesture(
          surface.topLeft + const Offset(100, 40),
        );
        await tester.pump(const Duration(milliseconds: 600));
        final hint = tester.getRect(
          find.ancestor(
            of: find.text('2.0x 快进中'),
            matching: find.byType(DecoratedBox),
          ),
        );
        expect(hint.right, closeTo(surface.right - 12, 0.01));
        expect(hint.bottom, closeTo(surface.bottom - 12, 0.01));
        await gesture.up();
        await tester.pump();
        expect(find.text('2.0x 快进中'), findsNothing);
        await removePlayer(tester, controller);
      },
    );
  }

  testWidgets('fast-forward hint respects safe area and clears on cancel', (
    tester,
  ) async {
    final controller = TestVideoController(speed: 1.5);
    await mountPlayer(
      tester,
      controller,
      fullscreen: true,
      safePadding: const EdgeInsets.only(right: 28, bottom: 36),
    );
    final surface = tester.getRect(find.byType(VideoPlayerSurface));
    final gesture = await tester.startGesture(
      surface.topLeft + const Offset(100, 40),
    );
    await tester.pump(const Duration(milliseconds: 600));
    final hint = tester.getRect(
      find.ancestor(
        of: find.text('2.0x 快进中'),
        matching: find.byType(DecoratedBox),
      ),
    );
    expect(hint.right, closeTo(surface.right - 28, 0.01));
    expect(hint.bottom, closeTo(surface.bottom - 36, 0.01));
    await gesture.cancel();
    await tester.pump();
    expect(find.text('2.0x 快进中'), findsNothing);
    expect(controller.value.playbackSpeed, 1.5);
    await removePlayer(tester, controller);
  });

  testWidgets('narrow controls do not overflow', (tester) async {
    final controller = TestVideoController();
    await mountPlayer(tester, controller, width: 280);
    expect(tester.takeException(), isNull);
    await removePlayer(tester, controller);
  });

  testWidgets('completed video can replay from the beginning', (tester) async {
    final controller = TestVideoController(playing: false);
    controller.value = controller.value.copyWith(
      position: controller.value.duration,
      isCompleted: true,
    );
    await mountPlayer(tester, controller);
    await tester.tap(find.byTooltip('播放'));
    await tester.pump();
    expect(controller.seeks, [Duration.zero]);
    expect(controller.value.isPlaying, isTrue);
    await removePlayer(tester, controller);
  });

  testWidgets('background during scrubbing prevents resuming on release', (
    tester,
  ) async {
    final controller = TestVideoController();
    await mountPlayer(tester, controller);
    final origin = tester.getTopLeft(find.byType(VideoPlayerSurface));
    final gesture = await tester.startGesture(origin + const Offset(80, 40));
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(controller.value.isPlaying, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(controller.value.isPlaying, isFalse);
    await removePlayer(tester, controller);
  });
}
