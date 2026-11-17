import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:videodownloader/source_parser/download_file_naming.dart';
import 'package:videodownloader/source_parser/download_queue_controller.dart';
import 'package:videodownloader/source_parser/download_task_codec.dart';
import 'package:videodownloader/source_parser/source_resource.dart';

void main() {
  const photo = SourceResource(
    title: 'Photo',
    url: 'https://pbs.twimg.com/media/random.png?name=orig',
    type: SourceResourceType.image,
    platform: SourcePlatform.x,
    host: 'pbs.twimg.com',
    sizeHint: '',
  );

  test('post path and query never become the filename', () {
    final resource = photo.withAttachmentSource(
      'https://x.com/demo/status/123/photo/2?s=20',
      1,
      1,
    );
    expect(downloadFileName(resource), '123.png');
    expect(downloadFileName(photo), 'random.png');
  });

  test('mixed attachments preserve original indexes through task recovery', () {
    final resource = photo.withAttachmentSource(
      'https://x.com/demo/status/123/video/1',
      2,
      3,
    );
    final task = DownloadTask(
      id: 'recover',
      fileName: downloadFileName(resource),
      resource: resource,
    )..status = DownloadStatus.downloading;
    final recovered = DownloadTaskCodec.decode(DownloadTaskCodec.encode(task))!;
    expect(downloadFileName(recovered.resource), '123-2.png');
    expect(recovered.resource.attachmentCount, 3);
    expect(recovered.status, DownloadStatus.pending);
  });

  test('old persisted tasks remain readable', () {
    final task = DownloadTask(
      id: 'old',
      fileName: 'random.png',
      resource: photo,
    );
    final json = DownloadTaskCodec.encode(task);
    final resource = json['resource']! as Map<String, Object?>;
    resource.remove('sourcePageUrl');
    resource.remove('attachmentIndex');
    resource.remove('attachmentCount');
    expect(DownloadTaskCodec.decode(json)!.fileName, 'random.png');
  });

  test(
    'collision suffixes cannot be confused with attachment indexes',
    () async {
      final directory = await Directory.systemTemp.createTemp('post_names_');
      addTearDown(() => directory.delete(recursive: true));
      await File('${directory.path}/123-2.png').writeAsString('original');
      await File(
        '${directory.path}/123-2 (2).png.part',
      ).writeAsString('partial');
      final output = await uniqueDownloadFile(directory, '123-2.png');
      expect(output.uri.pathSegments.last, '123-2 (3).png');
      expect(
        await File('${directory.path}/123-2.png').readAsString(),
        'original',
      );
    },
  );
}
