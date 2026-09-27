# Floodlight refinement — September 27, 2026

Proposed visual refinement, not an adopted contract or native implementation.
The user supplied https://claude.ai/artifact/8CfAk9nqDSLvSoEpYnck8r as the
reference after asking for the design to feel less AI-generated.

`index.html` compares recreated Home and challenge screens from that rendered
reference with a focused refinement. The reference is a mock, not an installed
app capture. All people and activity values are fictional. The prototype uses
the reference's chalk/ink/amber palette and Archivo, with normal system type for
supporting content. Google Fonts provides Archivo; a system fallback remains.

Proposed changes: concentrate display type on the main score, remove extra
containers and decorative icon tiles, give friends consistent total/target
rows, retain visible state words and show source freshness legibly. Home,
Challenges and You remain. No native code, account state or service changed.

Copy corrections are distinct from the styling: individual targets replace
the contradictory “20 km each”; invitation dates have no incorrect weekday;
results/review timing follows the saved agreement rather than inventing a
September 30 deadline; simulated amounts are explicitly disclosed. Rules text
is a reading preview, not consent. `docs/COPY.md`, `LiveGoalRules.swift` and the
current Beta contract govern any later implementation. The September 22/24
adoption remains current until the owner chooses a revision.

Prototype interactions: select Home/Challenge, tap the proposed Home board to
open the challenge, return to Home, inspect the invitation, expand the rule summary, and
toggle larger text. Larger-text web checks are not native Dynamic Type or
VoiceOver acceptance. Feedback selection stays local until explicitly queued
through Lavish. No choice by itself authorizes native implementation.

The screens are presentation excerpts. Tabs and Park runs are shown for
context; a later native change must preserve full rules with exact deadlines,
refresh, leave and report. The expanded “How it works” is a summary, not the
full agreement.

## Performed checks

- Viewed the linked Floodlight preview and its screen markup in the browser.
- Viewed the recreated/proposed Home and challenge compositions.
- Exercised Home → challenge → Home → invitation preview → Home and the
  expandable rule text.
- Checked the proposed challenge and invitation at larger text, including a
  390px browser viewport. No horizontal overflow was reported in the phone
  content or document. The content scrolls vertically where needed.
- Browser warning/error log was empty at completion; `git diff --check`
  passed. These are bounded HTML checks, not a native app acceptance run.
