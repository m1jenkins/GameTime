# Next task: plan the adopted GameTime business model

> Completed as documentation on September 4, 2026. This original brief is
> preserved for provenance. See [BUSINESS_MODEL.md](BUSINESS_MODEL.md) and
> [PLAN.md](../PLAN.md); the next build prompt is at the end of PLAN.md.
> No application feature, payment or deployment was enabled by this task.

Copy the following prompt into GPT/Codex with this repository available:

```text
Work in /Users/user/Documents/GitHub/GameTime.

GameTime's new business model is decided: friend duels and personal performance
commitments for competitive recreational athletes. Read AGENTS.md,
PROJECT_MEMORY.md, and CLAUDE.md first. This is an instruction to update project
files and produce an actionable implementation plan, not merely discuss ideas.

The two core products are:
1. Friend duels: friends accept a defined athletic contest with meaningful
   financial stakes, follow progress, receive a credible result, and rematch.
   Example: fastest qualifying 5K this month, $20 each.
2. Personal performance commitments: commit money to a measurable milestone by
   a deadline. Example: run a mile under six minutes before December 1 or lose
   the committed amount. Include longer-term goals and progress friends can
   follow. Distinguish actual locked deposits from charging a saved card later.

First inspect git status, current code, README.md, PLAN.md, DECISIONS.md,
docs/COPY.md, and relevant beta, design, and archived social/Solo documents.
Preserve unrelated changes. Determine what is implemented, reusable, dormant,
incompatible, and missing. Do not assume old social code or generic distance
fields already provide a working running duel or Garmin integration.

Update files now:
- Add docs/BUSINESS_MODEL.md defining the audience, positioning, both core
  journeys, engagement loops, monetization hypotheses, and validation plan.
- Rewrite PLAN.md around a dependency-ordered roadmap for this pivot. Preserve
  the prior plan in docs/archive with clear historical status and references.
- Update README.md to distinguish today's working app from the adopted target.
- Append a new decision to DECISIONS.md; preserve earlier decisions and terms.
- Reconcile PROJECT_MEMORY.md, CLAUDE.md, docs/COPY.md, and relevant active docs
  so old solo-only or no-participant-payout rules do not override the new future
  scope. Keep historical agreements and current sandbox restrictions explicit.

Recommend a narrow first sport, metric, contest format, and supported data
source. Running is the leading candidate. Define verification, fairness,
acceptance, deadlines, ties, both-miss outcomes, cancellation/injury handling,
late or missing data, disputes, settlement, and rematches. Separate the two new
product lifecycles from historical Personal, Solo, and charity agreements.

Research current official Garmin/platform/payment requirements where needed.
Do not assume API access, trustworthy performance proof, or approval to handle
stakes and payouts. Document exact funds-flow options, who receives forfeited
money, fees, and launch-jurisdiction/provider decisions still needing resolution.
Treat prices and audience demand as hypotheses, not established facts.

Create milestones with concrete repository areas, dependencies, acceptance
criteria, appropriate tests, and smallest reviewable implementation slices.
Separate work that can proceed locally with simulated stakes from external
approvals needed for real money. Include a pilot measuring accepted invitations,
completed contests, rematches, return after losses, and willingness to pay.

Do not add spectator betting or a public prediction exchange to the initial
scope. Do not implement application features, change existing agreements,
enable real money, deploy, publish, or contact anyone in this planning task.
Choose reasonable reversible defaults and label them as recommendations;
do not ask me to reconfirm this business-model decision.

Finish with the files changed, the recommended first implementation slice,
material unresolved decisions, and a copy-ready prompt to implement that slice.
```
