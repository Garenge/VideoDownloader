import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:videodownloader/source_parser/download_settings.dart';
import 'package:videodownloader/source_parser/download_settings_store.dart';

void main() {
  test(
    'share auto download defaults off and survives save and parameter edits',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'share_settings_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = DownloadSettingsStore(
        fileResolver: () async => File('${directory.path}/settings.json'),
      );
      expect((await store.load()).shareAutoDownload, isFalse);
      expect(
        DownloadSettings.fromJson({'ytDlpRetries': 5}).shareAutoDownload,
        isFalse,
      );
      await store.save((await store.load()).copyWith(shareAutoDownload: true));
      final reloaded = await store.load();
      expect(reloaded.shareAutoDownload, isTrue);
      expect(reloaded.copyWith(ytDlpRetries: 3).shareAutoDownload, isTrue);
    },
  );
}
