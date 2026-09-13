# Signal — Liquid Glass review

Applied the requested `build-ios-apps:swiftui-liquid-glass` skill. Checked current official Apple [Materials](https://developer.apple.com/design/human-interface-guidelines/materials), [custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views), and [adoption guidance](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass).

| Component | Browser study | Native implementation direction, if later adopted |
| --- | --- | --- |
| Bottom navigation | One translucent capsule; selected inset, shared outline and dimensional rim | Prefer system `TabView` with iOS 26 system styling |
| Back / close / add | 44 px circular glass controls, pointer and press response | Prefer system toolbar items; otherwise `.buttonStyle(.glass)` |
| Main action | Tinted interactive capsule, explicit disabled state | `.buttonStyle(.glassProminent)`; no custom blur under native glass |
| Related custom controls | Shared capsule layer and consistent inset geometry | Wrap coexisting custom effects in `GlassEffectContainer(spacing:)`; tune spacing deliberately |
| Selected-day callout | Translucent optical lens tied to a keyboard/pointer chart control | A custom capsule/rounded rect with `.glassEffect(.regular, in: ...)` after layout and appearance modifiers; the readout itself is not a button, so do not mark it `.interactive()` |
| Custom touch action | Pointer-reactive highlight on a real button | `.glassEffect(.regular.tint(...).interactive(), in: ...)` only for an actual interactive control |
| Charts, numbers, rankings, rules, consent, result | Solid content, no backdrop filter | Ordinary solid content; no glass modifier |
| Morphing | Not claimed by the browser prototype | Use `glassEffectID` with `@Namespace` only for a deliberate, animated hierarchy change, with reduced-motion behavior |
| Accessibility / older OS | Opaque controls, no blur, preserved geometry, selected/focus states | Gate all iOS 26 APIs using `if #available(iOS 26, *)`; provide opaque or ordinary-material controls earlier. Respect Reduce Transparency, Increase Contrast and Reduce Motion separately. |

The controls use a translucent body, a refractive-looking bright/dark rim, reflected blue tones and soft offset shadows. Pointer highlights follow the actual point of interaction. No blur or glare is placed over the underlying readable content. The chart readout is the single intentionally moving piece of glass.

Solid mode, reduced transparency, increased contrast and unsupported-filter fallback remove backdrop filtering and reflective overlays. Reduced motion removes animated movement and press scaling without hiding values. Forced-colors styling retains actionable outlines and visible data.

Browser checks verify placement, grouping, sizing, CSS fallbacks and the day-selection interaction. They **do not** prove native optics, material blending, `GlassEffectContainer` performance, SwiftUI modifier correctness, native animation, VoiceOver, Dynamic Type or physical-device accessibility. This task adds no Swift file and claims no native acceptance.
