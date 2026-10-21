# Chapterloom

Chapterloom is a native macOS app for finding narrated audiobook chapters and embedding them in an M4B file. It reads existing title, author, and cover art from source audio, proposes chapter markers using a local Whisper model, and lets you review timing and names before export. Export copies AAC audio and artwork without re-encoding when possible.

## Requirements

- macOS 14 or newer
- Homebrew tools: `brew install ffmpeg whisper.cpp mp4v2`
- Internet connection on first scan to download the English Whisper base model (about 141 MB). After download, transcription runs locally. Set `CHAPTERLOOM_MODEL_PATH` to an existing `ggml-base.en.bin` to use a local model immediately.

## Build and run

```sh
zsh Scripts/build-app.sh
open dist/Chapterloom.app
```

The build script creates and ad hoc signs `dist/Chapterloom.app`. Xcode is required for Swift compilation. The app bundle is local; it is not notarized for distribution.

## Workflow

1. Choose or drop an M4A, M4B, or MP3 audiobook.
2. Select **Entire book** or **First 30 min**, then **Find chapters**. The app transcribes 15 minute chunks locally and detects spoken chapter numbers and epilogue headings.
3. Preview each marker, edit names, and move timing in half second steps. Add or remove markers as needed.
4. Export M4B. The app writes an MP4 chapter track, sets its language to English for Apple media framework compatibility, and verifies chapter count.

First 30 min limits chapter detection only; export still uses the full source book. For a short output, first make a short source clip with FFmpeg.

## Privacy and repository

Audio stays on the Mac. The initial model download goes to `~/Library/Application Support/Chapterloom/Models`. `Samples/`, audio, model weights, and screen recordings are ignored by Git. Do not commit copyrighted audiobook files.

## Development

```sh
swift test
```

Tests cover spoken-number parsing and chapter metadata boundary generation. On Macs with restrictive Swift build sandboxing, use `--disable-sandbox` and a scratch path under `/private/tmp`.
