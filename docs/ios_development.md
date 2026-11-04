# iOS 独立运行版本

iOS 端在手机内完成解析、下载和 MP4 音视频合并，不依赖 Mac、局域网下载服务或第三方解析服务器。最低系统版本为 iOS 15。

## 功能范围

| 功能 | 实现与范围 |
| --- | --- |
| 媒体直链 | 支持直接解析 MP4、MOV、M4V 和常见图片链接，复用应用内 HTTP 下载队列 |
| 普通网页 | 复用 HTML 资源提取；不保证动态页面或所有站点都能提取视频 |
| X 视频 | 未登录时请求公开嵌入接口；已登录时打开本机 X 网页，观察网页自身的响应，提取目标帖子的可用 MP4 |
| X 登录 | 右上角账号入口打开官方登录网页；使用本机持久化 WebKit 会话，支持状态检查与退出 |
| YouTube | 使用应用内解析库；优先完整 H.264/AAC MP4，否则下载兼容的分离音视频并通过 AVFoundation 合并 |
| 分享接入 | 现有分享扩展接收 X 帖子链接，写入 App Group；若系统未唤起主 App，手动打开 App 后自动接收 |
| 文件导出 | 下载队列和历史中的“分享或存储文件”打开系统分享面板，可存储到“文件”或交给其他 App |
| 本地记录 | 复用解析历史、下载历史与失败任务重试 |

当前下载需要保持 App 在前台，不提供后台完成或进程被终止后的任务恢复保证。
登录不保证所有帖子可下载：账号必须有访问权限，网页必须返回 MP4；HLS-only、DRM 内容仍不支持。
X 网页接口或结构变化可能导致登录会话解析失效，读取有 40 秒上限且可关闭取消。
HLS、DASH 清单、WebM 转换和桌面的 `ffmpeg` 转换入口在 iOS 不可用。
YouTube 是否能返回可下载流取决于平台接口和当前网络，模拟器及单元测试通过不代表所有线上视频可下载。

## X 登录与网络

右上角账号图标 → “登录 X”，在 X 官方网页中手动完成登录；检测到会话后自动返回。
登录 Cookie 留在本机 WebKit 存储，不导出到 Dart、不写入日志、不发送给 Mac。
退出会删除 X / Twitter 的 Cookie 与站点数据，不影响其它站点。

解析时优先检查本机登录状态；有会话则使用网页自身的登录请求读取帖子，
只提取与目标帖子 ID 匹配的媒体，并校验下载地址属于 HTTPS `video.twimg.com` 域。
无会话时继续使用公开接口，访问被拒绝或无可用 MP4 时提示登录。
超时、断网、无效响应及原生异常会显示错误，解析按钮恢复可重试。

应用内代理用于 Dart 解析和下载；iOS 17 及以上也同步用于 X 登录和读取网页。
iOS 15/16 的 WebKit 无此代理配置接口，需要可访问 X 的系统网络或 VPN。
本地模拟器可使用 Mac 已有的 `http://127.0.0.1:7890` 代理；此地址只适用于当前本机测试，
真机不可沿用模拟器配置，也不依赖 Mac 的解析或下载服务器。

## 真机签名

在 Xcode 中打开 `ios/Runner.xcworkspace`，为 Runner 和 ShareExtension 选择同一个开发团队：

1. 为两个 target 设置自己的 Bundle Identifier，扩展标识建议为主 App 标识加 `.ShareExtension`。
2. 两个 target 的 Signing & Capabilities 都需要启用 App Groups，并选择同一个组。
3. 两个 target、三个构建配置中的 `APP_GROUP_IDENTIFIER` 必须与该组一致。
   工程默认值为 `group.com.example.videodownloader.shared`，实际安装时需使用开发团队可用的组。
4. 选择 iPhone 后运行。签名配置需要覆盖主 App 和扩展，不能只给 Runner 配置。

分享扩展不能可靠地保证唤起主 App，因此链接先写入共享存储。
系统拒绝打开主 App 时，扩展显示“链接已保存”，用户关闭分享窗口并打开主 App 即可继续。
未配置正确的 App Group 时，扩展会明确提示签名配置问题。

## 本地验证

```sh
flutter analyze --no-pub
flutter test --no-pub
flutter devices
flutter run -d <设备 ID>
```

Xcode 中可运行 RunnerTests，覆盖 JavaScript 数值转换生成的 X 请求 token、文件路径边界、
真实音视频文件合并、App Group 中链接只消费一次，以及 X 登录状态、退出、
代理校验和网页响应提取。后者以固定响应验证目标帖子筛选和最高码率选择，
不替代真实账号登录与线上帖子验收。

当前工作环境的 Xcode 27.2 RC 与 Flutter 3.41.4 在通用双架构模拟器构建时存在架构检查问题。
选择具体模拟器运行，或在 Apple Silicon Mac 上使用以下命令构建：

```sh
xcodebuild \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'id=<模拟器 ID>' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
```

原生测试可将最后的 `build` 换成 `test`。使用未签名构建不能验证 App Group 的共享容器权限。

## 手工验收

1. 首次启动无桌面命令安装提示，手机窄屏下解析按钮完整显示。
2. 粘贴可访问的 MP4 直链，加入队列，完成后可在历史中找到对应文件。
3. 从队列和历史导出文件，验证“存储到文件”和取消分享均能正常返回。
4. 输入 X 公开帖子链接，验证多个视频分别显示；不可访问内容显示明确错误。
5. 输入 YouTube 链接，验证完整 MP4 下载及分离音视频合并后的画面和声音。
6. 下载期间取消任务、重试失败任务，确认没有把空文件或未完成文件记为下载成功。
7. 从 X 分享链接，在主 App 冷启动和已运行两种状态下验证接收；不能唤起时手动打开主 App 验证。
8. 输入 HLS / DASH 清单，确认不会将播放清单误报为已下载的视频。
9. 打开 X 登录页，手动完成登录，确认账号入口显示“X 已登录”；重启后仍能读取状态。
10. 已登录时解析自己有权访问的 X 视频，确认网页读取后返回资源并能下载。
11. 退出 X 后重启，确认未登录，公开解析仍可用；错误网络下显示超时/网络提示。

下载文件位于 App 的 `Documents/VideoDownloader`。
已启用系统文件共享，可从“文件 → 我的 iPhone → Videodownloader”访问文档目录。
