import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'path_log_label.dart';

/// 通过 macOS 原生 [NSWorkspace] 在 Finder 中显示路径（文件会选中，目录则打开该文件夹）。
///
/// 比 `Process.run('open', …)` 更适配沙盒与 GUI 进程的权限模型；失败时由调用方回退到 `/usr/bin/open`。
Future<bool> tryRevealPathWithNsWorkspace(String absolutePath) async {
  if (!Platform.isMacOS) {
    return false;
  }
  const channel = MethodChannel('videodownloader/reveal_in_finder');
  final label = pathLogLabel(absolutePath);
  try {
    debugPrint(
      'lib/source_parser/reveal_in_finder_macos.dart#tryRevealPathWithNsWorkspace: '
      'invoke path=$label',
    );
    // macOS 侧返回 ObjC BOOL 时可能是 `int`（如 1），不能只用 `== true`。
    final result = await channel.invokeMethod<dynamic>('reveal', absolutePath);
    final ok = result == true || result == 1;
    debugPrint(
      'lib/source_parser/reveal_in_finder_macos.dart#tryRevealPathWithNsWorkspace: '
      'result=$result ok=$ok path=$label',
    );
    return ok;
  } on MissingPluginException catch (error) {
    debugPrint(
      'lib/source_parser/reveal_in_finder_macos.dart#tryRevealPathWithNsWorkspace: '
      'missing_plugin error=$error path=$label',
    );
    return false;
  } on PlatformException catch (error) {
    debugPrint(
      'lib/source_parser/reveal_in_finder_macos.dart#tryRevealPathWithNsWorkspace: '
      'platform_exception code=${error.code} message=${error.message} details=${pathLogLabel(error.details.toString())} path=$label',
    );
    return false;
  } on Object catch (error) {
    debugPrint(
      'lib/source_parser/reveal_in_finder_macos.dart#tryRevealPathWithNsWorkspace: '
      'error=$error path=$label',
    );
    return false;
  }
}
