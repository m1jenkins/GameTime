# Signal theme exploration — sources

Prepared September 21, 2026. This is a local design exploration using fictional mockup content. Reference screenshots belong to their respective products and are shown for visual research, not as GameTime product artwork. The original current Signal mockup remains the baseline.

## Mobbin visual references

These files were downloaded at their returned image URLs from the user-requested Mobbin search. The canonical screen links are the durable citations. Files retain their delivered WebP format.

| Local asset | Product and reference | Canonical source | Download source |
| --- | --- | --- | --- |
| `assets/mobbin-nike.webp` | Nike Run Club — guided run card | [Mobbin screen](https://mobbin.com/screens/1db5604d-bdab-4920-8ca9-8df36d77312c) | [Original image](https://mobbin.com/api/mcp/short/aJtLbuXY) |
| `assets/mobbin-strava.webp` | Strava — route result | [Mobbin screen](https://mobbin.com/screens/125cbc4d-55cc-4abc-82d0-4ff489ed616e) | [Original image](https://mobbin.com/api/mcp/short/p2mD2wJl) |
| `assets/mobbin-alltrails.webp` | AllTrails — trail | [Mobbin screen](https://mobbin.com/screens/7cf211f4-28a7-4818-bd53-0f3521d1bf57) | [Original image](https://mobbin.com/api/mcp/short/7nmD0GIk) |

## Existing GameTime artwork

The following two assets are copies of previously generated GameTime artwork, not documentary photography or activity records. Original generation date: September 13, 2026. Generator recorded by the original manifest: built-in `image_gen`. Exact original prompts and style-reference paths are preserved in [assets/fieldwork-provenance.json](assets/fieldwork-provenance.json).

| Study asset | Original file | Description |
| --- | --- | --- |
| `assets/field-running.webp` | `outputs/design/2026-09-13-clickable-app/assets/running-print-v1.webp` | Generated forest-green halftone running illustration. |
| `assets/field-club.webp` | `outputs/design/2026-09-13-clickable-app/assets/club-morning-v1.webp` | Generated editorial photograph of two friends walking; fictional people. |

Original full provenance: `outputs/design/2026-09-13-clickable-app/asset-provenance.json`.

## Current Signal baseline

`assets/signal-current.png` is copied without editing from `.lavish/signal-complete-2026-09-21/verification/home-light.png` (1512 × 1300). It documents the existing local mockup used as the starting point. [Original Lavish session](http://127.0.0.1:4387/session/06bb462a4d13bd01).

## Typography

Font files are Latin-subset WOFF2 files delivered by the official Google Fonts CSS API. Barlow Condensed is included at 600, 700 and 800; DM Sans uses a single variable font binary for requested 400–700 weights; Fraunces is included at 600 normal and italic. Raw returned CSS is preserved in `assets/fonts-source.css`, and exact binary URLs are in [assets/font-provenance.json](assets/font-provenance.json).

Official family pages: [Barlow Condensed](https://fonts.google.com/specimen/Barlow+Condensed), [DM Sans](https://fonts.google.com/specimen/DM+Sans), [Fraunces](https://fonts.google.com/specimen/Fraunces).

SIL Open Font License 1.1 copies are included: [Barlow Condensed](assets/licenses/barlow-condensed-OFL.txt), [DM Sans](assets/licenses/dm-sans-OFL.txt), [Fraunces](assets/licenses/fraunces-OFL.txt). Downloaded from the official Google Fonts repository: [Barlow Condensed source](https://github.com/google/fonts/blob/main/ofl/barlowcondensed/OFL.txt), [DM Sans source](https://github.com/google/fonts/blob/main/ofl/dmsans/OFL.txt), [Fraunces source](https://github.com/google/fonts/blob/main/ofl/fraunces/OFL.txt).

[Official CSS API request](https://fonts.googleapis.com/css2?family=Barlow+Condensed:wght@600;700;800&family=DM+Sans:wght@400;500;600;700&family=Fraunces:ital,wght@0,600;1,600&display=swap).

| Local font | Style / weight | Official binary |
| --- | --- | --- |
| `assets/barlow-condensed-600.woff2` | Barlow Condensed / normal / 600 | [fonts.gstatic.com](https://fonts.gstatic.com/s/barlowcondensed/v13/HTxwL3I-JCGChYJ8VI-L6OO_au7B4873z3bWuYMBYro.woff2) |
| `assets/barlow-condensed-700.woff2` | Barlow Condensed / normal / 700 | [fonts.gstatic.com](https://fonts.gstatic.com/s/barlowcondensed/v13/HTxwL3I-JCGChYJ8VI-L6OO_au7B46r2z3bWuYMBYro.woff2) |
| `assets/barlow-condensed-800.woff2` | Barlow Condensed / normal / 800 | [fonts.gstatic.com](https://fonts.gstatic.com/s/barlowcondensed/v13/HTxwL3I-JCGChYJ8VI-L6OO_au7B47b1z3bWuYMBYro.woff2) |
| `assets/dm-sans-variable.woff2` | DM Sans / normal / 400 700 | [fonts.gstatic.com](https://fonts.gstatic.com/s/dmsans/v17/rP2Yp2ywxg089UriI5-g4vlH9VoD8Cmcqbu0-K6z9mXg.woff2) |
| `assets/fraunces-600-italic.woff2` | Fraunces / italic / 600 | [fonts.gstatic.com](https://fonts.gstatic.com/s/fraunces/v38/6NVf8FyLNQOQZAnv9ZwNjucMHVn85Ni7emAe9lKqZTnbB-gzTK0K1ChJdt9vIVYX9G37lvd9sPEKsxx664UJf1iVSs7RrU9kMz3lR24.woff2) |
| `assets/fraunces-600-normal.woff2` | Fraunces / normal / 600 | [fonts.gstatic.com](https://fonts.gstatic.com/s/fraunces/v38/6NUh8FyLNQOQZAnv9bYEvDiIdE9Ea92uemAk_WBq8U_9v0c2Wa0K7iN7hzFUPJH58nib1603gg7S2nfgRYIcaRyTCf7Tp05GNyXk.woff2) |


## New imagegen artwork

All three assets were created with the built-in `image_gen` tool, copied into this study, inspected and optimized to WebP with `cwebp`. They are fictional artwork, not participant photos or actual activity records. Functional navigation icons and progress graphics are authored SVG/CSS so they remain crisp and consistent.

### Pace photograph

Files: [PNG](assets/pace-runner.png), [WebP used in preview](assets/pace-runner.webp).
Original: `/Users/user/.codex/generated_images/01a0c496-d9c4-7871-8698-81fec61d2eca/exec-277c2882-3189-400b-9f88-60bcbf1e5788.png`.

Prompt:

> Use case: photorealistic-natural. Asset type: horizontal editorial sports photograph for a mobile athletic goal app theme called Pace. Create one premium, natural photograph of an anonymous adult runner in motion on a rust/clay running track in warm early morning sunlight. Dynamic close crop from shoulders to shoes, face outside the composition, believable healthy athletic movement and anatomically correct limbs. Cream running singlet and red-orange shorts, no branding. Track lane curves and long morning shadows convey forward momentum. Authentic tactile track, slight motion blur in the background, softly sunlit fabric, warm cream and terracotta palette. Landscape 3:2 composition that also crops well to a wide mobile hero. The feeling is energized, human, inviting and focused, like a refined independent running magazine. No text, no logos, no watermark, no device mockup, no graphical UI overlays. This is atmospheric editorial imagery, not a real participant portrait.

### Rally shoe

Files: [PNG](assets/rally-shoe.png), [WebP used in preview](assets/rally-shoe.webp).
Original: `/Users/user/.codex/generated_images/01a0c496-d9c4-7871-8698-81fec61d2eca/exec-4862ca41-4786-4685-8a32-04c40c80443c.png`.

Initial prompt:

> Use case: stylized-concept. Asset type: bespoke square running shoe pictogram for the Rally athletic app theme, displayed at 80–100px. Create a bold sport-poster running shoe silhouette at a dynamic three-quarter angle pointing up and to the right. The main shoe is vivid yellow #e5f44a, the sole is peach #ffaf81, and one restrained detail is lavender #d2b9ed. Use crisp graphic cut-paper and screen-print shapes, minimal internal lines, no tiny decorative detail, and a few subtle trailing graphic streaks behind the shoe. Solid uniform exact aubergine #27162d background edge to edge, no frame or card border. Square composition tightly framed with the shoe large and immediately legible at small size. Flat 2D pictogram, refined playful athletic energy, hard clear edges. No logos, no text, no letters, no trophy, no checkmark, no photographic rendering, no 3D lighting, no drop shadow.

Refinement prompt:

> Refine this running-shoe pictogram. Keep the square framing, shoe shape, yellow #e5f44a, peach #ffaf81 sole and lavender #d2b9ed tongue, and graphic trailing streaks. Change only these two defects: 1) make every background pixel a perfectly flat solid aubergine #27162d, absolutely no texture, vignette, gradient, lighting or shadow; 2) remove the large lavender curved stripe from the side of the shoe entirely, leaving a plain yellow side panel so there is no brand-like symbol. Crisp flat 2D cut-paper pictogram intended for tiny 80–100px display. No text or logo.

The resulting background retains faint tonal texture; exact hexadecimal matching is not claimed.

### Fieldwork emblem

Files: [PNG](assets/fieldwork-emblem.png), [WebP used in preview](assets/fieldwork-emblem.webp).
Original: `/Users/user/.codex/generated_images/01a0c499-b43f-79f1-885a-feda16974931/exec-cac311fa-e602-48b7-9af6-49f3b11f8de7.png`.

Prompt:

> Use case: stylized-concept. Asset type: bespoke Fieldwork outdoor running club emblem, raster illustration for a premium mobile app design exploration. Primary request: a vintage outdoor running club screen-print badge. Subject: a circular warm butter-yellow medallion (#e9ce7b) containing a simple deep forest-green (#244b3b) side silhouette of a running shoe above two clean rolling hills and a sunrise. Style/medium: refined flat two-ink screen-print illustration, restrained natural ink texture, warm tactile palette, confident simple shapes. Composition/framing: square, tight centered framing, emblem fills approximately 88% of canvas, strong recognizable silhouette designed to remain legible at 85px. Background: flat exact warm paper color #f3eddd, no gradient or shadow. Constraints: standalone illustrated emblem, no UI, no text, no letters, no logos or brand marks, no trophies, no checkmarks, no monetary imagery, no extra objects, no glossy 3D, no photorealism.
