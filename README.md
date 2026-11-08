# VideoDownloader

VideoDownloader is a Flutter desktop app for parsing web page resources. The
target workflow is: paste a URL, detect the source platform, extract video,
image, and other downloadable files, then show them by category for download.

## iOS

The iOS app uses an independent, on-device download path without `yt-dlp`
or command-line `ffmpeg`. See [iOS development and device validation](docs/ios_development.md)
for supported formats, signing, App Groups, and testing. The desktop behavior
described below differs from the iOS feature set.

## Current Status

- macOS app can be built and launched.
- The main workspace has Download and Files tabs. Queue, history, and conversion
  tasks live on a separate task page; settings have a dedicated page.
- Opening the app or returning from the background shows the Download tab,
  keeping task lists out of the way when adding new links.
- Settings include an opt-in share auto-download switch (off by default): shared
  links are parsed and downloadable resources are queued automatically. Direct
  URL opens and manual parsing continue to parse only.
- URL source classification is available for Douyin, X, YouTube, Bilibili, and
  Other.
- Common web page fetching and HTML resource extraction are connected.
- Download queue is connected. Resources can be queued and saved into the app's
  `VideoDownloader` documents folder.
- Download tasks, destinations, and progress are saved locally. Reopening the
  app automatically resumes interrupted and waiting tasks; failed and canceled
  tasks remain available for manual retry.
- Direct downloads keep `.part` files and use HTTP Range / If-Range to resume.
  Servers returning the whole file cause a clean restart. YouTube built-in
  downloads reuse bytes for the same stream format, and YouTube / X `yt-dlp`
  downloads reuse their task workspaces. Expired direct links may need parsing
  again. Recovery starts when the app reopens; it does not keep a killed app
  running. Downloads interrupted before this version cannot be recovered.
- Users can choose a custom download directory and reset to the default app
  documents directory.
- Completed download tasks can open their containing folder from the queue.
- Download history entries can trigger `m3u8 -> mp4` conversion, with a
  dedicated conversion task queue on the task page.
- Parsed resources support thumbnail preview, search, host filtering, and file
  extension filtering.
- Recently parsed URLs are stored locally and can be reused or cleared.
- Completed downloads are stored locally in download history and can be cleared.
- Converted MP4 outputs are written back into download history after success.
- YouTube public oEmbed metadata is used to extract video title, author, and
  thumbnail cover when available.
- YouTube parser also creates a downloadable "YouTube video" task when a valid
  video id is detected.
- X status links on macOS first resolve public photo and video attachments.
  Photos use original image URLs and videos use the highest bitrate MP4;
  when the public interface is unavailable, the desktop parser keeps its
  `yt-dlp` video task fallback.
- On macOS, Settings → X likes reads the app's signed-in account, supports
  cursor pagination, search, refresh, and opening original posts. Media posts
  can return to the Download tab for parsing with the existing X downloader.
  This uses X's web interface and requires an X login inside the app; browser
  login sessions are separate. X interface changes or rate limits may interrupt loading.
- Failed and canceled tasks can be retried directly from the queue page.
- Queue tasks and individual history entries can be removed without deleting
  completed files. Removing an active task cancels its download.
- The file library reads actual download directories independently of history,
  with search, date sorting, refresh, and confirmed file deletion. On iOS,
  files support native video playback, image preview, and sharing.
- YouTube download now uses a two-stage strategy:
  `youtube_explode_dart` first, then `yt-dlp` fallback when needed.
- Platform-specific Douyin and Bilibili parsers are not connected yet.
- YouTube platform parsing is in progress beyond metadata extraction.

## Development Roadmap

### 1. Parser Foundation

- Define a stable parser service contract for URL input and parsed resource
  output.
- Keep platform detection separate from resource extraction.
- Add structured error states for invalid URL, network failure, unsupported
  page, empty result, and platform restriction.
- Keep the current demo parser as a fallback for UI development.

Acceptance:

- UI code does not need to know whether data came from a demo parser, common
  page parser, or platform-specific parser.
- Parsing failures can be shown to users with readable messages.

### 2. Common Web Page Parser

- Fetch normal HTTP and HTTPS pages.
- Extract common image resources from `img`, `picture`, Open Graph metadata,
  and JSON-LD when available.
- Extract common video resources from `video`, `source`, Open Graph metadata,
  and HLS/DASH manifest links when they are directly exposed.
- Normalize relative URLs against the original page URL.
- Deduplicate resources by final URL and type.

Acceptance:

- A normal article or product page can return visible images.
- A simple HTML5 video page can return at least one video resource.
- Resources are grouped into Video, Image, and Other in the existing UI.

### 3. Download Queue

- Replace the current snackbar-only download action with a download task model.
  Done.
- Save downloads into the app documents directory. Done.
- Let users choose a save directory. Done.
- Show download states: pending, downloading, completed, failed, canceled. Done.
- Preserve meaningful file names where possible.

Acceptance:

- Clicking a resource creates a task instead of only showing a toast. Done.
- Failed downloads keep an error message that is useful for retrying. Done.
- Queued tasks run sequentially and can be canceled before completion. Done.
- The selected directory is used for future queued downloads. Done.
- Completed tasks can open their containing folder. Done.

### 4. Platform Parsers

- Douyin: inspect share-page redirects, embedded page state, and exposed media
  URLs.
- X: create a dedicated status-download task and keep improving metadata /
  public media extraction when available. Started.
- YouTube: inspect public metadata, thumbnails, and exposed player/manifest data
  where allowed. Started.
- Bilibili: inspect public page state, player metadata, thumbnails, and exposed
  DASH/FLV resources where allowed.
- Keep unsupported or protected resources visible as restricted items instead
  of pretending they can be downloaded.

Acceptance:

- YouTube parser can return public oEmbed thumbnail metadata. Done.
- X parser can create a dedicated status download task for `x.com` /
  `twitter.com` post URLs. Done.
- Each platform parser can return at least thumbnails or metadata before full
  video extraction is attempted. Started.
- Protected, signed, login-only, or DRM-like resources are labeled clearly.

### 5. Resource Preview and Filtering

- Add preview thumbnails for images and video cover resources. Started.
- Add filters by source platform, resource type, file extension, and host.
  Started.
- Add search within parsed results. Done.

Acceptance:

- Users can quickly narrow results when a page exposes many files. Started.
- Preview loading failures do not break the result list. Done.

### 6. Persistence and History

- Store recently parsed URLs locally. Done.
- Store completed download history. Done.
- Allow clearing history from the app. Done.
- Allow history items to launch media conversion tasks. Done for `m3u8 -> mp4`.

Acceptance:

- Relaunching the app keeps recent parse history. Done.
- Relaunching the app keeps completed download history. Done.
- Users can remove stored history intentionally. Done.
- Successful `m3u8 -> mp4` conversion results appear in the same history list.

### 7. Media Conversion

- Keep conversion as an explicit task model instead of doing heavy work inline
  in a history cell. Done for Phase 1.
- Support `m3u8 -> mp4` from download history. Done.
- Reuse runtime `ffmpeg` capability checks and external-command error feedback.
  Done.
- Show conversion states: pending, converting, completed, failed, canceled.
  Done.
- Add retry and open-folder actions for completed/failed conversion tasks.
  Done.

Acceptance:

- History only exposes `转 MP4` when the local file is an `m3u8` playlist. Done.
- Starting a conversion does not block the history list. Done.
- Conversion work is visible from the same floating activity entry as downloads.
  Done.
- Completed MP4 files can be found again from download history. Done.

## Suggested Next Step

With download and conversion task basics connected, the next highest-value work
is to improve **resource understanding and post-download ergonomics** rather
than opening more platform integrations immediately.

## iOS Share-In Plan

The longer-term mobile direction is to let users share X links from the X iOS
app into VideoDownloader, then complete parsing and downloading inside our app.

Recommended implementation order:

1. **Phase 1: App link intake in the existing Flutter app**
   - Add an iOS URL scheme / deep-link entry for the Runner app.
   - Let the Flutter layer receive an incoming X link and prefill / auto-parse
     it on launch.
   - Keep this path available for manual testing before a Share Extension
     exists.
2. **Phase 2: iOS Share Extension**
   - Add a native iOS Share Extension target.
   - Accept shared URLs from the X app share sheet.
   - Pass the shared link into the main app through an App Group or direct
     handoff.
3. **Phase 3: Share-driven UX polish**
   - Auto-route users into the parser/downloader flow after share-in.
   - Show clearer “received from share” state and recovery on relaunch.
   - Optionally keep a lightweight intake history for shared links.

Why this order:

- Phase 1 is the minimum viable foundation and can be implemented directly in
  the current Flutter app.
- Phase 2 depends on native iOS extension wiring and is easier once the main
  app already knows how to consume an external link.
- Phase 3 improves ergonomics only after the transport path is stable.

Current Phase 1 intake contract:

- iOS URL scheme: `videodownloader://parse?url=<percent-encoded target url>`
- Example:
  `videodownloader://parse?url=https%3A%2F%2Fx.com%2FOpenAI%2Fstatus%2F123`
- Expected behavior:
  the app opens, prefills the target URL, and starts parsing automatically.

Current Phase 2 share-in contract:

- Share target: `VideoDownloader`
- Expected source: X App share sheet, or any App that shares a web link / text
- Current handoff path:
  Share Extension atomically saves the X link to a file in the App Group container and attempts to open
  `videodownloader://parse?url=<shared url>` back into the main app.
  If the system does not open the host, the extension confirms the link is saved;
  opening the main app manually consumes it.
  Storage errors distinguish an unavailable shared container from a file write
  failure and display the specific error. A successful handoff consumes the file
  once; a later share replaces any pending link.
  For direct handoff, the extension locates `UIApplication` through the responder
  chain (with a runtime lookup fallback) and calls `open(_:options:completionHandler:)`.
  If that fails, it tries `NSExtensionContext.open`. This compatibility path is
  intended for private distribution and requires device verification after iOS updates.
- Current preference:
  only accept `x.com` / `twitter.com` post links; if shared text contains
  multiple links, prefer the first valid `.../status/...` entry

Quick iPhone verification:

1. Build and install the iOS App on device.
2. In the X App, open a post and tap `Share`.
3. Choose `VideoDownloader` in the iOS share sheet.
4. If the main App opens, expect parsing to start. Otherwise, close the share
   window and open the App manually to consume the saved link.
5. If share-in fails, the extension should keep a visible error page instead
   of disappearing immediately.
6. After the main App opens, expect a visible `来自 iOS 分享` 提示条 and a
   `查看日志` button so the intake log can be copied back for debugging.

Recommended order:

1. **Upgrade HLS resource metadata before download**
   - Detect likely master/media playlists more accurately.
   - Distinguish direct MP4 from playlist-based streams in UI.
   - Add lightweight hints such as "HLS playlist", "needs ffmpeg", or
     "recommended output: MP4".
2. **Add conversion/task detail polish**
   - Copy conversion logs for failure diagnosis.
   - Show more specific ffmpeg stderr summaries.
   - Optionally support "open output file" in addition to "open folder".
3. **Broaden parser coverage**
   - Expand JSON-LD / manifest / source extraction.
   - Improve platform parsers only after generic web and HLS cases feel solid.

Why this order:

- Users will feel the benefit immediately on real `m3u8` pages.
- It reduces confusion around which resources need conversion.
- It strengthens the full parse -> download -> convert loop before adding more
  site-specific complexity.

The original parser slice remains relevant and is still in progress:

1. Add a real parser path in `SourceParserService`. Done.
2. Fetch the input URL. Done.
3. Extract `img`, `video`, `source`, and basic Open Graph resources. Done.
4. Fall back to a readable empty/error state when no resource is found. Done.
5. Add broader parser coverage for JSON-LD, `picture`, manifests, and
   downloadable links. Started.

## Local Parser Fixture

Use the local fixture when a real-world test URL is not available. It serves a
small HTML page with image tags, video tags, Open Graph metadata, JSON-LD, and a
downloadable JSON link.

Start the fixture server from the project root:

```sh
cd tooling/parser_fixture_site
python3 -m http.server 8765
```

Then parse this URL in the app:

```text
http://127.0.0.1:8765/
```

Or verify the parser from the terminal:

```sh
dart run tooling/check_parser_url.dart http://127.0.0.1:8765/
```

Expected result:

- Platform: Other
- Images: normal image, `srcset` images, video poster, Open Graph image, and
  JSON-LD thumbnail
- Videos: `video` sources, Open Graph video, and JSON-LD content URL
- Other: downloadable JSON file

The fixture media files are lightweight placeholders. The parser only needs the
HTML resource URLs for this test; real download validation belongs to the
download queue phase.

## Git Repository Recommendation

This workspace is now initialized as a Git repository. Commits are still not
created automatically. The next phases will touch dependencies, network code,
platform behavior, and possibly lock files, so Git will make it easier to
review changes, roll back experiments, and split future commits by purpose.

Do not create commits automatically. Commit planning should happen only after a
human asks for it.

## YouTube Download Strategy (Phase 1)

For YouTube resources, download is no longer a single-path network request.
Current strategy:

1. Default to an isolated `yt-dlp` workflow for X downloads and YouTube's
   `yt-dlp` path.
2. Each task downloads into its own temporary workspace and only moves the
   final media file into the user-selected directory after success.
3. When the app is configured for built-in priority, `youtube_explode_dart`
   remains available as the alternate strategy.
4. If the chosen strategy fails, return a readable queue error message and
   allow manual retry.

This improves reliability for real-world URLs such as Shorts or videos with
unstable client behavior, while keeping each task's output deterministic.

### Workflow details

- `yt-dlp` runs with a defensive profile:
  `--no-playlist -N 8 --retries 10 --fragment-retries 50 -f "bv*+ba/best" --merge-output-format mp4`.
- The app stages YouTube downloads inside per-task workspaces before moving the
  final media file into the target directory.
- X status downloads also stage `yt-dlp` output inside per-task workspaces
  before moving the final file into the target directory.
- `youtube_explode_dart` manifest mode still tries multiple client
  combinations when that strategy is enabled.

### Operational note

`yt-dlp` must be available in system `PATH` for X downloads and YouTube's
`yt-dlp` workflow. If it is not installed, X downloads will fail, and YouTube
should be switched to built-in priority before retrying.

## Troubleshooting (X / YouTube)

- Error contains "请求过于频繁": wait and retry, or switch proxy route.
- Error contains "拒绝访问/403": likely geo/account/policy limits on that stream.
- Error contains "不可播放": age/region/copyright restrictions are likely.
- Error contains "需要登录/Private/not found": the X post may be private,
  deleted, or only visible when logged in.
- Error shows `yt-dlp` not found: install `yt-dlp` and retry failed tasks.

## Step-by-step implementation plan

This project now follows a staged YouTube delivery plan:

1. **Phase 1 (done/in progress)**
   - Retry support in queue UI and controller.
  - YouTube dedicated engine with isolated `yt-dlp` workflow by default.
   - Friendly error mapping for common YouTube failures.
   - README strategy + troubleshooting docs.
2. **Phase 2**
   - Runtime capability checks (`yt-dlp`/`ffmpeg`) with UI visibility.
   - Advanced settings for fallback behavior and optional cookie-based mode.
3. **Phase 3**
   - Engine module split for maintainability (done).
   - Keep `DownloadQueueController` focused on queue orchestration, delegating
     platform-specific download details to `download_engines/`.
   - More scenario tests for strategy chains and edge failures (done).

## Architecture notes (Phase 3)

- `DownloadQueueController` orchestrates tasks, progress reporting, cancel and retry.
- `download_engines/YouTubeDownloadEngine` handles YouTube specifics:
  - isolated `yt-dlp` staging and final file handoff
  - optional `youtube_explode_dart` strategy
  - progress parsing, cancellation, and queue-friendly errors

This separation keeps the queue stable while allowing YouTube download logic to
iterate without touching unrelated queue code.
