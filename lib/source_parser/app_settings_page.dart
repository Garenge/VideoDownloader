import 'dart:io';
import 'package:flutter/material.dart';
import 'download_queue_controller.dart';
import 'download_settings.dart';

class AppSettingsPage extends StatefulWidget {
  const AppSettingsPage({
    super.key,
    required this.queue,
    required this.settings,
    required this.onSave,
    required this.onDownloadSettings,
    required this.onSelectDirectory,
    required this.onResetDirectory,
    required this.accountLabel,
    required this.authenticated,
    required this.onAccountAction,
    this.onProxySettings,
    this.onLikedPosts,
  });
  final DownloadQueueController queue;
  final DownloadSettings Function() settings;
  final Future<void> Function(DownloadSettings) onSave;
  final Future<void> Function() onDownloadSettings;
  final Future<void> Function() onSelectDirectory;
  final VoidCallback onResetDirectory;
  final String Function() accountLabel;
  final bool Function() authenticated;
  final Future<void> Function() onAccountAction;
  final Future<void> Function()? onProxySettings;
  final Future<void> Function()? onLikedPosts;

  @override
  State<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends State<AppSettingsPage> {
  bool _saving = false;
  Future<void> _saveAutoDownload(bool value) async {
    setState(() => _saving = true);
    try {
      await widget.onSave(widget.settings().copyWith(shareAutoDownload: value));
    } on Object catch (error) {
      debugPrint(
        'app_settings_page.dart#_saveAutoDownload: 保存分享设置失败 error=$error',
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存设置失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _accountAction() async {
    await widget.onAccountAction();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('设置')),
    body: AnimatedBuilder(
      animation: widget.queue,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            key: const ValueKey('share-auto-download-switch'),
            title: const Text('分享自动下载'),
            subtitle: const Text(
              '开启后，分享链接到此 App 时，自动解析并将可下载资源加入下载任务；关闭后仅自动解析。',
            ),
            value: widget.settings().shareAutoDownload,
            onChanged: _saving ? null : _saveAutoDownload,
          ),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('下载设置'),
            onTap: widget.onDownloadSettings,
          ),
          if (widget.onProxySettings != null)
            ListTile(
              key: const ValueKey('proxy-settings-button'),
              leading: const Icon(Icons.settings_ethernet),
              title: const Text('代理设置'),
              onTap: widget.onProxySettings,
            ),
          if (widget.onLikedPosts != null)
            ListTile(
              key: const ValueKey('x-liked-posts-button'),
              leading: const Icon(Icons.favorite),
              title: const Text('X 点赞列表'),
              subtitle: const Text('读取当前 X 登录账号的点赞内容'),
              onTap: widget.onLikedPosts,
            ),
          if (!Platform.isIOS) ...[
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('保存目录'),
              subtitle: Text(widget.queue.selectedDirectoryPath ?? '使用默认下载目录'),
              onTap: widget.onSelectDirectory,
              trailing: IconButton(
                tooltip: '重置保存目录',
                onPressed: widget.queue.selectedDirectoryPath == null
                    ? null
                    : widget.onResetDirectory,
                icon: const Icon(Icons.restart_alt),
              ),
            ),
          ],
          if (Platform.isMacOS || Platform.isIOS)
            ListTile(
              leading: const Icon(Icons.account_circle),
              title: Text(widget.accountLabel()),
              subtitle: Text(widget.authenticated() ? '点击退出 X 登录' : '点击登录 X'),
              onTap: _accountAction,
            ),
        ],
      ),
    ),
  );
}
