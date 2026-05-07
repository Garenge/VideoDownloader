# VideoDownloader

VideoDownloader is a Flutter desktop app for parsing web page resources. The
target workflow is: paste a URL, detect the source platform, extract video,
image, and other downloadable files, then show them by category for download.

## Current Status

- macOS app can be built and launched.
- Home page has been changed from the default counter demo to a resource parser
  workspace.
- URL source classification is available for Douyin, X, YouTube, Bilibili, and
  Other.
- Common web page fetching and HTML resource extraction are connected.
- Download queue is connected. Resources can be queued and saved into the app's
  `VideoDownloader` documents folder.
- Users can choose a custom download directory and reset to the default app
  documents directory.
- Completed download tasks can open their containing folder from the queue.
- Download history entries can trigger `m3u8 -> mp4` conversion, with a
  dedicated conversion task queue in the activity panel.
- Parsed resources support thumbnail preview, search, host filtering, and file
  extension filtering.
- Recently parsed URLs are stored locally and can be reused or cleared.
- Completed downloads are stored locally in download history and can be cleared.
- Converted MP4 outputs are written back into download history after success.
- YouTube public oEmbed metadata is used to extract video title, author, and
  thumbnail cover when available.
- YouTube parser also creates a downloadable "YouTube video" task when a valid
  video id is detected.
- Failed tasks can be retried directly from the queue panel.
- YouTube download now uses a two-stage strategy:
  `youtube_explode_dart` first, then `yt-dlp` fallback when needed.
- Platform-specific Douyin, X, and Bilibili parsers are not connected yet.
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
- X: inspect page metadata and public media URLs that are present without
  authentication.
- YouTube: inspect public metadata, thumbnails, and exposed player/manifest data
  where allowed. Started.
- Bilibili: inspect public page state, player metadata, thumbnails, and exposed
  DASH/FLV resources where allowed.
- Keep unsupported or protected resources visible as restricted items instead
  of pretending they can be downloaded.

Acceptance:

- YouTube parser can return public oEmbed thumbnail metadata. Done.
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

1. Try `youtube_explode_dart` to fetch metadata + stream manifest and download
   a selected stream.
2. If that fails (403/429/playability/client-specific issues), automatically
   fall back to local `yt-dlp`.
3. If both fail, return a readable queue error message and allow manual retry.

This improves reliability for real-world URLs such as Shorts or videos with
unstable client behavior.

### Fallback details

- `youtube_explode_dart` manifest tries multiple client combinations.
- `yt-dlp` fallback runs with a defensive profile:
  `--no-playlist -N 8 --retries 10 --fragment-retries 50 -f "bv*+ba/best" --merge-output-format mp4`.
- Queue task metadata is updated from the actual downloaded file after fallback.

### Operational note

`yt-dlp` must be available in system `PATH` for fallback to work. If it is not
installed, YouTube tasks can still succeed through `youtube_explode_dart`, but
fallback will fail with an explicit error.

## Troubleshooting (YouTube)

- Error contains "请求过于频繁": wait and retry, or switch proxy route.
- Error contains "拒绝访问/403": likely geo/account/policy limits on that stream.
- Error contains "不可播放": age/region/copyright restrictions are likely.
- Error shows `yt-dlp` not found: install `yt-dlp` and retry failed tasks.

## Step-by-step implementation plan

This project now follows a staged YouTube delivery plan:

1. **Phase 1 (done/in progress)**
   - Retry support in queue UI and controller.
   - YouTube dual-engine strategy (`youtube_explode_dart` + `yt-dlp` fallback).
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
  - `youtube_explode_dart` stream download
  - manifest client fallback
  - optional `yt-dlp` fallback with configurable arguments

This separation keeps the queue stable while allowing YouTube download logic to
iterate without touching unrelated queue code.
