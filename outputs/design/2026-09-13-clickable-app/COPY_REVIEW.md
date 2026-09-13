# Prototype copy review — September 13, 2026

Scope: the active clickable Fieldwork Glass prototype, including the 22 screen
destinations, five-step creation and conditional agreement text. The original
study is retained. Shipping app copy, historical consent and product-authority
documents are unchanged.

## Diagnosis and repair

Applied the explicitly requested Unslop skill with the warm-human voice preset,
after reading docs/COPY.md. The 18 exact findings and minimal replacements are
in `copy-rewrites.json`. Generic headings obscured tasks or states: for example,
“Clear from the start” became “Review your challenge,” and “Every agreement has
a home” became “Your earlier challenges.” “Unresolved people” became “People
whose results we can’t confirm.” A receipt now says “reviewed” rather than
“chose,” because an invited person reviews details proposed by someone else.

The separate requested layout redesign groups the same factual content into
goal, dates, people and rules. It does not turn the copy cleanup into authority
to change the challenge policies.

## Protected copy

- All consent text, review deadlines, missing-data protections, full-day
  boundaries, amounts, fees, result conditions, privacy promises and exits.
- “It’s okay to step away” gives reassurance about an available safe exit.
- “A week well walked” describes the displayed walking result without pressure
  to exercise more or increase a simulated amount.
- Profile and community headings refer to the supplied username and shared-goal
  concepts; they were not rewritten merely to make every page terse.
- Preview, simulation and no-transmission disclosures remain at decisions and
  receipts. These are necessary limitations, not promotional repetition.

## Validation and contextual review

`copy-audit/` contains before/after text, rendered template snapshots and the
Unslop constraint, phrase, structure, silhouette, readability, preservation and
diff reports. The changed-span corpus and full sampled screen corpus have zero
banned-phrase hits after the final pass. Strict preservation passed for the one
rewritten policy sentence. Comparing all agreement branches preserved 72 complete
rule sections and the consent sentence across 18 variants, allowing only that
diagnosed wording clarification.

The preservation scanner's broad changed-span warnings were reviewed: “every”
was part of the empty history metaphor, not a rule; “No push notification is
needed” retains its negation as “You don’t need a push notification.” No promise
or requirement was reversed or weakened.

The heading-only ledger triggers short-sentence, repeated-opener and high-diff
advisories. Those entries are separate labels on separate app screens, not
consecutive prose paragraphs. The full screen corpus has natural sentence-length
variation and no one-line staccato flag. Its recurring “preview” and navigation
labels cause preexisting silhouette/opener warnings, which are protected as
literal prototype states and controls. No rewrite was made solely to satisfy
those scores. The initial flattening also joined a rules heading to adjacent
disclosure sentences; after removing newly introduced duplicate receipt text,
the full corpus has no anti-slop-register hits.

Browser checks: all 22 destinations at 320px in both appearances; invitation and
personal timed-run flows through consent and receipt; loaded decorative images;
no horizontal document overflow. JavaScript syntax passed. Native SwiftUI and
physical-device accessibility acceptance remain outside this browser study.
