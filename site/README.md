# Chapterloom landing page

Static HTML and CSS with four rendered app screens. No install or build step.

## Preview

Run `python3 -m http.server 4173 --directory site` from repository root, then open `http://localhost:4173`.

## Screenshots

The images in `site/screenshots/` are generated from the real Chapterloom SwiftUI view with staged source, scan, review, and export states. The source and markers match the verified 10-minute test. They are app renders rather than captures of a live scan.

To regenerate from repository root, run:

```sh
swiftc -parse-as-library Sources/Chapterloom/AppState.swift Sources/Chapterloom/ChapterEngine.swift Sources/Chapterloom/ChapterloomView.swift Scripts/render-screenshots.swift -o /tmp/chapterloom-render-screenshots
/tmp/chapterloom-render-screenshots Samples/sunrise-first-10m.m4a site/screenshots
```

## Manual Vercel deployment

1. Import repository into Vercel.
2. Set **Root Directory** to `site`.
3. Set **Framework Preset** to **Other**. Leave **Build Command** empty.
4. Deploy.

Vercel serves `site/index.html` at site root. Screenshot PNGs deploy with page. Avoid committing source audiobook or excerpts.
