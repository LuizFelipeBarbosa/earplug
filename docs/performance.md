# Web performance runbook

## Why

EarPlug's phone web experience felt slow. This runbook and its measurement tooling provide a repeatable way to identify bottlenecks, verify fixes, and prevent regressions.

## Baseline

Measured on earplug.dev 2026-09-01, desktop Chrome, warm CDN.

- `main.dart.js`: 1.15 MB brotli / 4.0 MB decoded, served with `cache-control: max-age=0, must-revalidate`
- CanvasKit loaded from `www.gstatic.com`: 5.8 MB (Chrome) / 7.2 MB (iOS Safari)
- Fonts loaded at startup: 8 Archivo/Permanent Marker TTFs ~790 KB total, Font Awesome Solid 415 KB, Font Awesome Regular 87 KB, Roboto 62 KB — all from fonts.gstatic.com
- 27 requests / 1.7 MB transferred before first frame
- Blank white page until Flutter boots
- `load` event fires at 2.5 s on fibre
- Clerk JS starts loading at 3.15 s and was awaited before `runApp`
- Map style loads at 4.8 s
- The Convex web client logged every raw WebSocket payload to the console in release builds

## How to measure load on a Netlify deploy preview

Run a mobile Lighthouse audit against the Netlify deploy-preview URL:

```sh
./tool/web_perf.sh --lighthouse https://deploy-preview.example.netlify.app
```

Record TTFB, FCP (the splash-screen paint), the User Timing marks `ep:first-frame` and `ep:feed-ready`, and total transfer size. In Chrome DevTools, disable the cache and select Slow 4G throttling so runs are comparable. Lighthouse writes its report to `build/lighthouse.html`.

To inspect the marks directly, open the preview in Chrome, then run this in the DevTools console:

```js
performance.getEntriesByType('mark')
```

## How to measure runtime

Append `?perf=1` to the app URL to enable the in-app `PerfOverlay`. Its numbers mean:

- `frames`: frames currently retained in the 180-frame buffer
- `build p50/p95`: median and 95th-percentile Flutter build duration in milliseconds
- `raster p95`: 95th-percentile raster duration in milliseconds
- `jank >16.7 ms`: percentage of frames whose combined build and raster time exceeds 16.7 ms
- `frames >33 ms`: count of frames whose combined build and raster time exceeds 33 ms
- `worst`: longest combined build and raster time in milliseconds

Use `RESET` immediately before each scenario. For deeper phone profiling, connect an Android phone and use the Performance panel through `chrome://inspect`. On iOS, connect the phone to a Mac and use Safari Web Inspector's Timelines.

## Scenarios

- S1 Home feed fling: list mode, 6 flings, 20 s
- S2 Explore All scroll
- S3 Map pan/zoom: 5 pans, 3 pinch zooms, zoom level 12 to 16
- S4 tab switches: Gigs→Explore→Profile→Gigs ×5, then Map/List toggle ×5

Run each scenario 3 times and record the median. Record the device, browser, and commit hash alongside every result.

## Budgets

- `main.dart.js` ≤ 1.0 MB brotli
- Fonts ≤ 500 KB
- First frame < 2.5 s and feed-ready < 4 s on Lighthouse mobile
- Scroll p95 build < 8 ms
- Jank < 5%
- No map frame > 50 ms during pan

## Rules

- No `BackdropFilter` over scrolling content
- No `shrinkWrap` grids inside scroll views
- No `context.watch<AppState>` in leaf list rows
- Size every network image explicitly
- Keep Clerk off the first-frame path

## Results table

| date | commit | device/browser | TTFB | FCP | first-frame | feed-ready | bytes | S1 p95 build/raster/jank | S2 | S3 | S4 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-09-01 | n/a | desktop Chrome | n/a | n/a | n/a | n/a | 1.15 MB brotli / 4.0 MB decoded (main.dart.js only) | n/a | n/a | n/a | n/a |
| 2026-09-02 | e7e990f | desktop Chrome | 299 ms | n/a | 2736 ms | 2914 ms | 25 requests / 1.40 MB before first frame; main.dart.js 1.09 MB wire / 896 KB local brotli -q 11; fonts 492 KB | n/a | n/a | n/a | n/a |

Measured on a Netlify deploy preview with a warm CDN. The load event fired at 1770 ms. The splash was removed after the first frame, no service worker was present, fonts used immutable caching, and the Convex console was silent in release builds. Image CDN delivery was verified with a 1.88 MB band photo served as 36 KB at `w=80`.

## Known follow-ups

- The Flutter engine still fetches Roboto (62 KB) from fonts.gstatic as a glyph fallback — needs a glyph audit.
- Stadia raster tiles can return 503 on the first burst for an uncached region; the client now retries with backoff and evicts errored tiles.
