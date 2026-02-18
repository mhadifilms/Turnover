# Turnover

A macOS menu bar utility for VFX artists to upload renders to S3 with automatic color space tagging and audio muxing.

## Features

- Drag-and-drop or file picker for `.mov` / `.mp4` renders
- Auto-detects project and episode from filename conventions
- Color space tagging via ffmpeg (P3-D65/PQ, Rec.2020/PQ, Rec.709)
- Audio track muxing from matching S3 source files
- S3 upload with progress tracking
- AWS SSO authentication
- JSON-based project config — no hardcoded paths
- Menu bar extra with quick access to recent uploads

## Requirements

- macOS 14.0+
- ffmpeg & ffprobe (auto-downloaded on first run)
- AWS CLI v2 with SSO configured

## Setup

1. Build and run:
   ```
   swift run VFXUploadApp
   ```
2. Follow the first-run setup to install dependencies and configure AWS SSO.
3. Import a project config JSON when prompted.

### Project Config

Projects are defined in a JSON file that gets imported into the app. Example:

```json
[
  {
    "id": "show_101",
    "displayName": "Show 101",
    "s3Bucket": "my-bucket",
    "s3BasePath": "CLIENTS/Show/101/WORKING",
    "episodeNumber": 101,
    "colorSpace": "P3-D65-PQ",
    "platesFolder": "Plates",
    "vfxFolder": "VFX"
  }
]
```

Import via **Settings > Projects > Import Config** or during first-run setup.

## Bundling

To create a `.app` bundle:

```
./Scripts/bundle-app.sh
cp -r VFXUpload.app /Applications/
```

## Development

```
swift build          # debug build
swift test           # run tests
swift run VFXUploadApp -- --clean-install   # simulate first-run setup
```
