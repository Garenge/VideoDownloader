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
- Platform-specific Douyin, X, YouTube, and Bilibili parsers are not connected
  yet.

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
  where allowed.
- Bilibili: inspect public page state, player metadata, thumbnails, and exposed
  DASH/FLV resources where allowed.
- Keep unsupported or protected resources visible as restricted items instead
  of pretending they can be downloaded.

Acceptance:

- Each platform parser can return at least thumbnails or metadata before full
  video extraction is attempted.
- Protected, signed, login-only, or DRM-like resources are labeled clearly.

### 5. Resource Preview and Filtering

- Add preview thumbnails for images and video cover resources.
- Add filters by source platform, resource type, file extension, and host.
- Add search within parsed results.

Acceptance:

- Users can quickly narrow results when a page exposes many files.
- Preview loading failures do not break the result list.

### 6. Persistence and History

- Store recently parsed URLs locally.
- Store completed download history.
- Allow clearing history from the app.

Acceptance:

- Relaunching the app keeps recent parse and download history.
- Users can remove stored history intentionally.

## Suggested Next Step

Start with **Common Web Page Parser** before platform-specific parsers. It has
the best risk-to-value ratio because it proves the full pipeline: fetch page,
extract resources, normalize URLs, deduplicate results, and render them through
the existing UI.

The first implementation slice is now in progress:

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
