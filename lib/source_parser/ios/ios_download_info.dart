import 'package:flutter/material.dart';

Future<void> showIosDownloadInfo(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    scrollable: true,
    title: const Text('iPhone 下载'),
    content: const Text(
      '所有解析和下载均在本机完成。\n\n'
      '支持媒体直链、X 可用的 MP4，以及 YouTube 可用的 MP4 音视频流；分离音视频会在本机合并。'
      '可通过右上角账号入口登录 X，使用本机登录状态读取有权访问的帖子。\n\n'
      '下载时请保持 App 在前台。HLS / DASH 清单和 WebM 转换暂不支持。\n\n'
      '文件保存在“文件 → 我的 iPhone → Videodownloader → VideoDownloader”。'
      '在下载队列或历史中点击“分享或存储文件”，可导出到其他 App 或“文件”。',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('知道了'),
      ),
    ],
  ),
);
