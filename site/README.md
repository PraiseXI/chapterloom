# Chapterloom landing page

Static HTML, CSS, and JavaScript. No install or build step.

## Preview

Run `python3 -m http.server 4173 --directory site` from repository root, then open `http://localhost:4173`.

## Video

Place a short, silent H.264 MP4 screen recording of the actual Chapterloom app at `site/demo.mp4`. Page then displays native video controls and a poster image. Until file exists, page shows a clear preview message. Audiobook audio should be muted in recording.

## Manual Vercel deployment

1. Import repository into Vercel.
2. Set **Root Directory** to `site`.
3. Set **Framework Preset** to **Other**. Leave **Build Command** empty.
4. Deploy.

Vercel serves `site/index.html` at site root. Keep `demo.mp4` inside `site/` so it deploys with page. Avoid committing source audiobook or excerpts.
