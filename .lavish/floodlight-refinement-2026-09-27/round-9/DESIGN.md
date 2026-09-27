# Floodlight 09 — Toned

September 27, 2026. [Open the prototype](index.html). **Adopted by the owner
the same day at the Toned level with Aero gloss** (see the top entry of
[the UI adoption history](../../../docs/design/SIGNAL_UI_MIGRATION.md)).
Rounds seven and eight stay preserved. Nothing here has changed the native app,
accounts, services or product rules yet.

## The request

The owner, on round eight: "I like this a lot. I think it's a huge step in the
right direction. Especially aero gloss. However, it might be a step a little bit
too far into 3D and Frutiger Arrow. Is there a way we could dial some of this
back a tad? While retaining the depth and overall vibe?"

## One set of paint, three levels

A depth picker at the top restyles every phone. **Toned** is the default and
the recommendation; **Round 8** reproduces round eight's values exactly;
**Quiet** shows how far down the depth can go before it turns flat. Aero gloss
is the default material; Floodlit steps down the same way.

| Part | Round 8 | Toned | Quiet |
| --- | --- | --- | --- |
| People | Gel orbs with a gloss cap | Soft spheres, small highlight | Solid color, soft shadow |
| Progress arcs | Dark gel edge, bright stripe, glow `.42` | Faint edge, softer stripe, glow `.2`, less milky start | Solid gradient, no glow |
| Pot | Aqua orb with a glossy dome | Deep blue disc `#1A76CB`→`#0A4F99`, thin crescent highlight | Flat blue disc |
| Buttons | Split-gloss Aqua pill, navy text | Deep blue pill, white text | Flat blue pill |
| Cards | Frosted, glossy top half | Frosted, top edge highlight only | Frosted, lighter shadow |
| Background | Swooshes, lens flare, flare ghosts | Faint swooshes, half-strength flare | Sky gradient only |
| Dial face and tracks | Glass plate with sheen, recessed tracks | Same, sheen at 40% | No sheen, shallower tracks |

The **Part by part** table on the page shows each row at all three levels, so a
mix (for example Toned people with Round 8 arcs) can be named directly.

## Unchanged from round eight

Layout, copy, fixtures, states, rules text, the word cuts, the stake rail, the
pot sheet and the invitation summary. The copy questions from round eight
(short freshness line, pictogram rules summary) are still open.

## Checks performed

Chromium through Playwright at 1440px and 390px ([checks.json](captures/checks.json)):
no console errors or warnings, no horizontal page overflow. A sweep of 294
combinations (two materials, three levels, every day, 2/4/6 people, Jordan's
three update states) found no malformed dial paths and no unresolved paint
references. Picking a level restyles all three phones and keeps focus on the
picker; the pot sheet still moves focus to Close and Escape returns it. On a
narrow screen the picker opens scrolled to the selected level. Contrast: white
on the Toned pot 4.67:1, on the Toned button 4.58:1 at its middle, on the Quiet
button 4.62:1. The unslop scanners report nothing on the page text.

Not performed: native SwiftUI, VoiceOver, Dynamic Type, a full contrast audit
of every state, blur performance on a phone, and any device run.
