# Image-generation prompts

> **Historical source prompts.** These reproduce the original raster concepts
> and intentionally retain obsolete manual-sync copy. Do not use their **Sync
> steps**, **Synced**, or final-sync language in Personal snapshot-v2 UI.

Both local references were supplied to every prompt:

- `docs/design/challenge-page-concepts/current-reference.jpg` — current layout and
  visual reference.
- `ios/GameTime/GameTime/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` —
  visual motif and color inspiration only.

## Daybreak Trail

```text
Use case: ui-mockup
Asset type: high-fidelity iOS challenge detail screen concept
Input images: Image 1 is the current GameTime challenge-detail screen and the visual/layout reference; Image 2 is the GameTime app icon and is visual motif inspiration only.
Primary request: redesign the content below the existing progress hero into a playful interactive seven-day “Daybreak Trail” dashboard. Preserve the current screen's upper section: iOS status bar, back button, centered title "Your challenge", exact yellow disclosure "Test commitment — no money will be charged.", and dark-plum progress hero with "IN PROGRESS", "$10.00", "10,000 steps a day", "17,832 steps", "2,650 to go", and a coral progress bar.
Subject: below the hero, replace the entire spreadsheet-like “WHAT YOU SIGNED UP FOR” table with one large interactive journey card titled "THIS WEEK". Show seven raised stepping-stone checkpoints curving toward a small sunrise: day 1 mint check, day 2 soft yellow missed marker, day 3 raised coral "TODAY" marker, days 4–7 quiet outlined upcoming stones. Add "Day 3 of 7", "1 goal day", and "Ends Sunday" as compact supporting stats. Beneath it, add a compact action card reading "2,650 more steps today" with a coral pill button "Sync steps". End with a quiet row "Challenge details" and chevron, implying a sheet for the frozen rules.
Style/medium: realistic shippable native SwiftUI product UI, not concept art; crisp readable typography; Bricolage Grotesque-style bold rounded display numbers and Hanken Grotesk-style UI labels.
Composition/framing: one tall portrait iPhone screen, screen-only from status bar through the bottom tab bar, no device frame, no surrounding scene. Preserve the three-tab bar "Today", "Challenges", "You" with Challenges active in coral.
Color palette: warm paper #FFF7F0, white cards, dark plum #1C1523, coral #FF5A45, sun yellow #FFB627, mint #12C08A, peach hairlines.
Materials/textures: 24pt continuous rounded cards, subtle paper warmth, very soft shadows, restrained dimensional stepping stones echoing Image 2.
Constraints: personal solo challenge only; no people, friends, leaderboards, social feed, maps, distance, calories, pace, corporate tables, data grids, orange Strava branding, logos, watermarks, or extra tabs. Keep the top hero recognizable and unchanged. Make the main body feel fun, tappable, and informative. Render all specified text verbatim and do not invent extra text.
```

## Daily Activity Feed

```text
Use case: ui-mockup
Asset type: high-fidelity iOS challenge detail screen concept
Input images: Image 1 is the current GameTime challenge-detail screen and the visual/layout reference; Image 2 is the GameTime app icon and color/mood inspiration only.
Primary request: redesign the content below the existing progress hero into an energetic Strava-like daily activity dashboard for a solo seven-day step challenge, using GameTime's own Daybreak visual identity. Preserve the current screen's upper section: iOS status bar, back button, centered title "Your challenge", exact yellow disclosure "Test commitment — no money will be charged.", and dark-plum progress hero with "IN PROGRESS", "$10.00", "10,000 steps a day", "17,832 steps", "2,650 to go", and a coral progress bar.
Subject: below the hero, remove the full “WHAT YOU SIGNED UP FOR” table. Add a section titled "YOUR WEEK" with a tappable horizontal seven-day selector for SUN MON TUE WED THU FRI SAT; Tuesday is selected in coral, one completed day has a mint check, one missed day has a small sun-yellow marker, future days are muted. Under it, show a large activity card titled "Today" with a bold "7,350 steps", "74% of your goal", a compact coral progress bar, and "2,650 to go"; include a coral pill button "Sync steps" and a small mint status "Synced 10 min ago". Below, show one compact previous-day feed card reading "Yesterday", "Goal met", and "10,482 steps" with a celebratory mint check and a tiny bar sparkline. End with a quiet row "Challenge details" and chevron for the frozen rules.
Style/medium: realistic shippable native SwiftUI product UI, not concept art; content rhythm inspired by a modern fitness activity homepage without copying another brand; crisp readable typography; bold rounded display type plus clean UI type.
Composition/framing: one tall portrait iPhone screen, screen-only from status bar through the bottom tab bar, no device frame, no surrounding scene. Preserve the three-tab bar "Today", "Challenges", "You" with Challenges active in coral.
Color palette: warm paper #FFF7F0, white cards, dark plum #1C1523, coral #FF5A45, sun yellow #FFB627, mint #12C08A, peach hairlines.
Materials/textures: 24pt continuous rounded cards, subtle paper warmth, soft shadows, clean flat native controls.
Constraints: personal solo challenge only; no people, friends, comments, kudos, leaderboards, maps, distance, calories, pace, generic athlete photography, orange Strava branding, logos, watermarks, corporate tables, data grids, or extra tabs. Keep the top hero recognizable and unchanged. Render specified text verbatim and avoid invented copy.
```

## Sunrise Stats

```text
Use case: ui-mockup
Asset type: high-fidelity iOS challenge detail screen concept
Input images: Image 1 is the current GameTime challenge-detail screen and the visual/layout reference; Image 2 is the GameTime app icon and color/mood inspiration only.
Primary request: redesign the content below the existing progress hero into a lively, highly legible “Sunrise Stats” dashboard. Preserve the current screen's upper section: iOS status bar, back button, centered title "Your challenge", exact yellow disclosure "Test commitment — no money will be charged.", and dark-plum progress hero with "IN PROGRESS", "$10.00", "10,000 steps a day", "17,832 steps", "2,650 to go", and a coral progress bar.
Subject: below the hero, remove the full “WHAT YOU SIGNED UP FOR” table. Add a section title "AT A GLANCE". Show three compact rounded stat tiles: "2,650 left today" with a walking icon, "1 of 2 days hit" with a mint check, and "5 days left" with a sun icon. Below them, add one large white analytics card titled "YOUR 7 DAYS": seven friendly rounded vertical bars labeled S M T W T F S, a clear dashed "10K GOAL" line, first bar mint above goal, second bar sun-yellow below goal, current Tuesday bar coral and highlighted, future bars quiet outlines. A small selector tooltip above the coral bar reads "Today · 7,350". Add a full-width coral pill button "Sync steps", small mint text "Synced 10 min ago", and a quiet collapsed row "Challenge details" with chevron.
Style/medium: realistic shippable native SwiftUI product UI, not concept art; bold rounded display numbers and clean UI labels; energetic fitness dashboard with strong information hierarchy.
Composition/framing: one tall portrait iPhone screen, screen-only from status bar through the bottom tab bar, no device frame, no surrounding scene. Preserve the three-tab bar "Today", "Challenges", "You" with Challenges active in coral.
Color palette: warm paper #FFF7F0, white cards, dark plum #1C1523, coral #FF5A45, sun yellow #FFB627, mint #12C08A, peach hairlines.
Materials/textures: 24pt continuous rounded cards, subtle paper warmth, very soft shadows, crisp flat data visualization.
Constraints: personal solo challenge only; no people, friends, leaderboards, maps, distance, calories, pace, orange Strava branding, logos, watermarks, corporate tables, spreadsheet rows, tiny unreadable labels, or extra tabs. Keep the top hero recognizable and unchanged. Render specified text verbatim and avoid invented copy.
```
