import 'dart:io';

import 'package:flutter/services.dart';

/// 通过 macOS 原生 [NSWorkspace] 在 Finder 中显示路径（文件会选中，目录则打开该文件夹）。
///
/// 比 `Process.run('open', …)` 更适配沙盒与 GUI 进程的权限模型；失败时由调用方回退到 `/usr/bin/open`。
Future<bool> tryRevealPathWithNsWorkspace(String absolutePath) async {
  if (!Platform.isMacOS) {
    return false;
  }
  const channel = MethodChannel('videodownloader/reveal_in_finder');
  try {
    // macOS 侧返回 ObjC BOOL 时可能是 `int`（如 1），不能只用 `== true`。
    final result = await channel.invokeMethod<dynamic>('reveal', absolutePath);
    return result == true || result == 1;
  } on MissingPluginException {
    return false;
  } on Object {
    return false;
  }
}
