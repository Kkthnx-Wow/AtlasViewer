# AtlasViewer — Changelog

All notable changes to this project are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/); versions use SemVer.

## [2.0.0] - 2026-11-18

### Changed
- Full redesign. The window is now atlas first: search returns a grid of real
  thumbnails instead of a list of texture files, with a detail drawer on the right.
- The look uses the game's own art, so nothing is shipped for it. A metal nine-slice
  frame, thin tooltip borders on panels and thumbnails, red three-slice text buttons
  (gold when active), red icon buttons, the search box frame, a minimal scrollbar
  and slider. Every piece is checked against the client first and falls back to
  flat widgets when missing. The old generated bronze textures and their script are gone.
- Resize handles on every window edge and corner. Window size and position persist.
- Search ranks name-prefix, then name-contains, then file path matches, over a flat
  atlas index built once on first open.
- The sheet view (whole texture file with outlined atlases) is reached from the
  drawer and keeps zoom, pan, coordinates, background colour and file stepping.
- `## Interface` lists one number per client: retail 120105, Classic Era 11509 and 11508,
  TBC 20506 and 20505, Wrath 38001, Cata 40402, Mists 50504 and 50503, and WoW Forever
  16001. Still one TOC, the data is gated with `AllowLoadGameType`.
- New addon icon and a two-tone name.
- `update_atlas_data.py` takes a fresh in-game dump when one exists, checks builds
  with `--check`, skips targets that are already current, and no longer waits on the
  website. Townlong-Yak now puts its download behind a browser check, which the script
  does not bypass.

### Added
- WoW Forever support (game type `camelot`) with its own bundled data file.
- Live atlas list. A game type with no bundled data reads every atlas from the
  client with `C_Texture.GetAtlasElements`, so it works without a download.
- A data file per game type (Mainline, Vanilla/Era and Anniversary, Mists,
  Forever), each auto-loaded through `AllowLoadGameType`.
- Favorites and recents, saved per account.
- Filters for tiling atlases and missing or outdated atlases.
- Thumbnail size slider and preview zoom (Fit, 1x, 2x, 4x).
- Copy as name, `SetAtlas` code, `CreateAtlasMarkup` call, texture coordinates or file.
- Arrow, Page Up and Page Down navigation through the grid.
- `/av dump` saves every atlas the running client knows, and
  `update_atlas_data.py --from-client` turns that into the Data file for exactly that
  build. `/av dump clear` removes it. `/av probe` reports which window art resolved.

### Fixed
- Bare fileDataID texture keys coerce to numbers for `SetTexture`.
- Townlong spaced path keys (`Interface/ Garrison/...`) are normalized both in
  `update_atlas_data.py` and at list build time.
- The sheet canvas reads its size from a live API atlas in preference to a missing
  backup entry, and coordinate polling runs only while the canvas is hovered.
- The build indicator no longer reads as out of date when the client is newer than
  the last published dump, since the publisher may simply not have caught up.

## [1.0.0] - 2026-07-04

First release. A clean, from-scratch texture atlas browser for retail
(Interface 120007 / Midnight 12.0.7).

### Added
- Browse every bundled texture with a virtualized, searchable file list.
- Zoom/pan canvas that draws the texture with clickable atlas-region overlays.
- Inspector panel: width, height, tex coords, and horizontal/vertical tiling,
  with a copy box for the atlas name.
- Prioritized search (name > atlas > path) with live overlay highlighting.
- Adjustable canvas background colour, atlas border toggle, reset-view, and a
  "show missing / outdated atlases" toggle (draws API-unresolved atlases in red).
- Title-bar atlas build indicator that turns red when the bundled data is older
  than the running client, nudging a re-run of the updater.
- `update_atlas_data.py` (+ `.cmd`) to refresh the bundled atlas map from
  Townlong-Yak after a patch.
- Our own shipped Blizzlike bronze/stone skin — window frame, buttons, slider,
  and icons are custom `.tga` art (no Blizzard textures or templates).
- Slash commands `/atlasviewer` and `/av` (optional search argument); closes on
  `Esc` and when entering combat.
