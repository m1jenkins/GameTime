# Floodlight 07 — Club chronograph

Design-only proposal, September 27, 2026. [Open the prototype](index.html).

## Status and authority

This refines the owner's selected round-six dial and pot. Selection of that
starting point does not adopt round seven's typography, palette or native UI.
Round six remains preserved. No native, account, service or product-rule changes
are part of this artifact.

[Project memory](../../../PROJECT_MEMORY.md) and the current adoption in
[Signal migration](../../../docs/design/SIGNAL_UI_MIGRATION.md) remain the native
authority: the September 22 approved presentation and its later follow-through.
[README](../../../README.md) points to the current product and delivery contracts.

## Proposed visual direction

- **Type:** embedded Barlow Condensed for titles and athletic numbers; embedded
  Barlow for names, rules and actions. The fonts do not require a network request.
- **Composition:** white phone, open ruled rows, uppercase display titles,
  flat member markers and a 270° dial. The dark center makes the pot a distinct
  object; its former multicolor border is hidden.
- **Home:** a compact dial and the person's saved distance share a steel-blue
  field. Challenge and invitation use the larger white composition.
- **Meaning:** each ring measures progress against that person's own target.
  Fixed member order is not a ranking. Color identifies a person, never a
  winner, a protected stake or a final result. Rings stop at the goal; numeric
  detail can show activity beyond it.

| Token | Built value |
| --- | --- |
| White phone / primary ink | `#FFFFFF` / `#192326` |
| Secondary text / rules | `#556168` / `#D9E0E4` |
| Home field / Home track | `#243E48` / `#36505B` |
| White-face pot / pot type | `#27343A` / `#FFFFFF` |
| You / Sam / Jordan / Priya | `#BD482D` rust / `#2877A5` blue / `#557851` green / `#8764AA` violet |
| Six-person additions: Maya / Theo | `#9A7324` ochre / `#BA5880` rose |
| Review page / bezel | `#E8ECEF` / `#263035` |
| After-dark phone / ink | `#1B292F` / `#FAFCFD` |

After dark is an alternate proposal, not a change to the adopted light-only app.
Its pot is light (`#E8EEF1`); Home also uses a light hub against the blue field.
On dark surfaces, member hues use `#FF9A78`, `#73C9EE`, `#9DC88A`, `#C3AAF1`,
`#E7C66C` and `#EEA4CB`, with dark initials. Night tracks use `#31464F`.
These overrides preserve arc contrast without changing member identities.

## Reference interpretation

The parent design session viewed the Mobbin screenshots. This record preserves
the particular lessons used, without claiming a broader audit of either app:

- [Nike Run Club](https://mobbin.com/screens/3b656c09-f15a-4bab-8339-a40afd3cf5f9):
  confident athletic numerals with quieter supporting facts.
- [WHOOP](https://mobbin.com/screens/aac78ccc-35b7-459d-abe3-5256ba4dfd6b):
  readable active arcs separated from a stable track.

## Fixed fixtures and working interactions

All people, distances, update times and amounts are fictional constants.
The default is Tuesday, four people, recent Jordan data, with You selected.
Tuesday's values are You 6.4/20 km, Sam 7.8/20, Jordan 1.2/15 and Priya 10.0/10.
The six-person fixture adds Maya 9.5/25 and Theo 3.0/12. Every stake is a
nonredeemable simulated $20; the group pot is $40, $80 or $120.

- Shared controls switch appearance, seven fixed daily snapshots, 2/4/6 people,
  Jordan's recent/late/missing update and a 1.3× browser text scale. Jordan's
  controls are disabled for the two-person You/Sam fixture.
- Challenge member names or markers open numeric detail; Close or Escape closes
  it. The pot hub and “How the pot works” toggle the same explanation.
- Each phone navigates independently between Home, Challenge and Invitation.
  Home opens the goal or invitation. The bottom tabs are contextual artwork.
- Rules expand. Phone content scrolls. The invitation is a reading preview for
  You and Jordan at 20 km each and a $40 pot; joining and declining are absent.
- Progress transitions use fixed arrays; reduced-motion preference skips them.
  Names expose keyboard buttons and spoken values alongside the visual SVG.
- Feedback can queue through Lavish when available. Otherwise it remains in the
  current form; there is no implemented durable save or automatic chat send.

These controls do not ingest activity, synchronize accounts, calculate real
results or move money. Goal completion display is not final settlement.

## Preserved rules and validation limits

The existing rules remain unchanged: simulated amounts, eligible recorded runs,
saved dates and deadlines, review windows, voluntary leaving and limited sharing.
Missing or partial activity never counts as a miss. Amount-adjacent wording makes
simulation and final-result timing explicit; this is no new financial policy.

This document was checked against the artifact's source. It does not establish
browser test results, contrast compliance, native parity, physical-device
acceptance, Dynamic Type support or VoiceOver acceptance. The text-size toggle,
ARIA labels and reduced-motion code are browser provisions; native validation
and adoption require separate work and a separate decision.
