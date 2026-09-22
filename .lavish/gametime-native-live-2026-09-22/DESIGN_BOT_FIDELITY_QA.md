# Fidelity QA from Design Bot

Compare against locked mocks in `.lavish/gametime-live-goal-2026-09-21/captures/` and native review in `.lavish/gametime-native-live-2026-09-22/`.

1) Create flow drift: native `captures/create.png` shows a 4-step Type/Goal/Challenge/Friends stepper with wrapping labels (“Go al”, “Challen ge”). Locked create/invite is 3 steps: Goal → Challenge → Friends (see create-goal.png / create-challenge.png / invite-friends.png). Align create to the locked 3-step flow; don’t reintroduce “Who’s it for?” leaderboard/personal type picker as step 1 unless product requires it behind Advanced.

2) Cold launch: simulator currently lands on Sign in, not the live Home fixture. Ensure demo/`Try demo mode` (or the fixture client path used for captures) is the default for the LiveDesign sim so Home matches `captures/home.png` without Apple sign-in.

3) Keep Home / Goal / Challenges / You as already captured — those look faithful. Don’t restyle palette.

4) Re-capture create screens after the fix into `.lavish/gametime-native-live-2026-09-22/captures/` and update the review board if needed.
