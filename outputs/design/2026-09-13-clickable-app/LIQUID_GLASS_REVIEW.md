# Fieldwork Glass — material and imagery review

September 13, 2026. Applied the requested `build-ios-apps:swiftui-liquid-glass`
skill and checked Apple's current guidance. The owner-supplied brand-kit JSON
remains visual authority. These additions are proposals for comparison.

## Material review

| Area | Design treatment | Native implementation contract |
| --- | --- | --- |
| Back, close, add, options | Consistent circular glass controls, 44px or larger | System navigation/toolbar first; otherwise `.buttonStyle(.glass)` or `.glassEffect(.regular.interactive(), in: .circle)` after layout and appearance modifiers |
| Primary action | One tinted capsule per action group | `.buttonStyle(.glassProminent)`; do not stack custom blur underneath |
| Related controls | A single material container around each segmented switch or bottom navigation | Prefer system Picker/TabView; for multiple custom glass views use `GlassEffectContainer` and deliberate spacing |
| Scores, charts, rules, amounts and receipts | Solid green, paper or sage | Ordinary fills; no glass on the data layer |
| Photography and graphic | Small solid images separate from text | Plain Image; no decorative glass or `.interactive()` |
| Morphing | Not introduced | `glassEffectID` and `@Namespace` only for deliberate animated hierarchy changes; respect Reduce Motion |
| OS and accessibility fallback | Solid comparison and opaque no-blur/reduced-transparency/increased-contrast CSS | `#available(iOS 26, *)`; opaque controls for earlier OS versions; respect Reduce Transparency, Increase Contrast and Reduce Motion |

The review found incomplete primary-button fallback: reduced transparency covered
navigation but not the main action. It now becomes opaque and loses blur/shadows.
Unsupported blur also receives opaque controls. Selected segmented/tab content
gets an opaque fallback. Segmented controls and detail-summary rows now have
at least 44px interaction height.

**Conformance boundary:** these are browser designs, not SwiftUI views. Material
placement, shape consistency, control size, fallback CSS and visual hierarchy
were checked. `GlassEffectContainer`, modifier order, `.interactive()`, OS
availability, native optics/performance and accessibility require native
implementation and verification. No Swift source changed; no native conformance
or physical-device acceptance is claimed.

Sources: [Apple Materials](https://developer.apple.com/design/human-interface-guidelines/materials),
[custom Liquid Glass views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views),
[adoption guidance](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass).

## Imagery

Built-in Imagegen produced **Club morning**, a candid photo of anonymous adult
friends walking, and a four-image **Stride print** collection: walking stride,
lace up, fist bump and running. The three companion images use the original
walking print as a visual style reference, matching forest-green photographic
halftone, restrained citrus registration and warm paper. The Visual accent selector
compares Photography, Stride print collection and Original. These are generated decorative
images, not actual participants or activity records. Profile monograms remain.

Home uses the original walking thumbnail. Creation and draft review use the
lace-up print; invitation uses running in a 170px paper inset. Invitation preview
uses the fist bump; agreement review uses a small print beside its heading
(fist bump for friends, lace up for a personal goal). The checkbox and terms stay
on plain solid content, separate from the image. Images stay off the existing
challenge detail, standings, chart, results, result-review and safety screens.
No factual text is baked into the images. Decorative
images have empty alt text and are hidden from assistive technology.

No asset was added to the adopted brand-kit JSON. Original PNGs and compressed
WebP previews are saved under `assets/`; full prompts and saved paths are in
`asset-provenance.json`. Images are embedded as data URLs for the inline preview.

## Mobbin references inspected

- [Strava](https://mobbin.com/screens/50763ff9-a5fa-4fb2-aafb-bcca4fd03b2c): shallow running-group photo header, floating controls, solid detail area. Transfer bounded imagery, not its rewards or 5K contract.
- [Garmin Connect](https://mobbin.com/screens/a603a303-54ff-49b3-bf77-742dd7e1164d): narrow outdoor running photo above solid challenge information; closest reference for a small atmospheric strip.
- [Apple Fitness](https://mobbin.com/screens/397e4e9d-aab0-476f-8c4b-764f78a3cb4f): workout photos with distinct title/control regions. Transfer separation, not workout recommendations.
- [Future Pro](https://mobbin.com/screens/186461a8-d5e5-44f1-b990-5414b3886019): a large runner image leads Today; too dominant for this request.
- [Tonal](https://mobbin.com/screens/9e3ecc20-23ec-4ee6-bcbf-1cbe5c71d50b) and [Tempo](https://mobbin.com/screens/e36affec-339c-439d-800b-b3ebbfff66a2): larger workout/campaign photography; contrasting scale references.

No Mobbin artwork was embedded in the prototype.

## Verification

Latest iteration: all 22 destinations checked at 320px in both light and dark
mode (44 combinations), with no document horizontal overflow or broken print
assets. Invitation, agreement and the timed-run draft were inspected visually.
Invitation → agreement → receipt and personal timed run → draft → agreement →
receipt were clicked through. Consent remained disabled until explicitly checked.
The rule comparison preserved 72 complete sections and consent across 18 agreement
variants; the one wording clarification is recorded in COPY_REVIEW.md.
Twelve additional 398px checks covered Home, invitation, agreement and invitation
preview in all three imagery modes, with loaded images, no horizontal overflow
and no backdrop filter on main content. Temporary viewport settings were reset;
the browser is left on the invitation with the print collection selected.

Earlier imagery iteration:

- Assembled JavaScript passes `node --check`.
- 48 combinations passed: four destinations × three image choices × two
  appearances × 320px/398px widths. Images loaded, no document horizontal
  overflow, and no backdrop filter on image/content panels.
- Home photography and creation print graphic visually inspected.
- Solid-mode navigation and primary-action computed styles checked separately.
- OS accessibility media-query fallbacks inspected in source. This browser tool
  did not emulate OS accessibility preferences. Native VoiceOver, Dynamic Type,
  real glass rendering and human accessibility acceptance remain unperformed.
