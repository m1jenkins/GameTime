# Better Bet — Privacy Policy

**Draft for review. This is not legal advice.** It describes what the app in
this repository actually does, verified against the code, the schema, and
`PrivacyInfo.xcprivacy`. Have someone qualified read it before you publish it.

## Before you publish

Three things in this document are not derivable from the codebase, and nobody
should guess them:

- `[SUPPORT EMAIL]` — the monitored inbox. It appears in the app as well.
- `[LEGAL ENTITY]` — whoever is accountable for the data. A personal name is
  fine for a ten-tester beta; it has to be someone real.
- `[JURISDICTION]` — where that entity is. It decides which law applies and
  which rights section below is accurate.

Publish the result at a stable URL, then put that URL in App Store Connect and
in `GAMETIME_PRIVACY_POLICY_URL`. Apple requires the URL before a build can go
to external testers.

---

**Last updated:** August 7, 2026

Better Bet lets you set a step goal for a week, put money behind it, and see
how you did. This policy explains what we collect, why, and how to get rid of
it.

Better Bet is operated by [LEGAL ENTITY] in [JURISDICTION]. This version of the
app is an invite-only beta for a small number of testers.

## The short version

- We read the step count Apple Health combines from your available Health
  sources. Nothing else in Apple Health is ever read.
- We never sell your data, never share it for advertising, and there are no
  advertising or analytics trackers in the app.
- No money moves. Payments in this beta run entirely in Stripe's test mode.
- You can delete your account from inside the app, and most of what we hold
  goes with it.

## What we collect

**Your account.** When you sign in with Apple, Apple gives us an account
identifier. If you choose to share your name at that moment, we store it. We do
not ask Apple for your email address and we never receive it. You also pick a
username and a time zone.

**Your steps.** With your permission, we read step counts from Apple Health —
only step counts. Apple Health combines compatible sources such as your iPhone,
Apple Watch, and other Health writers. We exclude a step entry only when Apple
marks it as manually entered. If another writer fails to supply that marker,
the app cannot distinguish that entry from automatic data. Nothing else in
Apple Health is read.

While a challenge is open, the app keeps one protected seven-day snapshot on
your phone and sends the same seven daily totals to our server through your
signed-in account. A newer complete snapshot replaces the prior one, including
when an Apple Health correction lowers a total. The server keeps that mutable
snapshot only until the challenge result is finalized.

**Your challenges.** The goal you set, the amount you committed, when it runs,
your progress, and how it turned out.

**Historical device checks.** Older challenge and dormant feature records may
include an Apple App Attest key identifier, counter, and sealed receipt. New
Personal Apple Health snapshots do not use App Attest. We preserve old audit
records only so historical results do not change.

**Payments.** Every payment in this beta is a Stripe test-mode transaction. No
real card is ever charged and no real money moves. Stripe holds the test
payment details; we keep only a reference to them, the brand and last four
digits of the test card, and the status of a test charge. We never see or store
a full card number.

**Support messages.** If you email us, we have your message and your email
address.

**What we do not collect.** No location. No contacts. No photos. No browsing or
advertising identifiers. No third-party analytics or advertising software of
any kind is in the app.

## Why we hold it

Only to run the product: to show current progress, score and freeze your week,
show your history, run the test payment when a challenge is confirmed missed,
and answer you when you write to us.

We do not use your data for advertising, we do not sell it, and we do not share
it with anyone for their own purposes.

## Who else touches it

- **Apple** — Sign in with Apple, Apple Health, and App Attest only for retained
  historical or unrelated device-check paths. Apple's own privacy policy covers
  what Apple does.
- **Stripe** — test-mode payment processing. Stripe holds the test payment
  details.
- **Supabase** — the hosting and database provider that stores the data above
  on our behalf.

These are service providers acting on our instructions. Nobody else gets your
data unless the law requires it.

## How long we keep it

Your account, challenges, and results are kept while your account exists.

Raw material we no longer need is removed on a schedule, automatically:

- The mutable seven-day server snapshot is removed when the result freezes. The
  seven daily totals copied into that result and the record that the week
  happened remain with challenge history.
- Historical raw metric material, device registrations, and sealed App Attest
  receipts follow their existing 90-day policy after workflow finality. New
  Personal snapshots do not create that material.
- If exact location is ever recorded by a future feature, it is removed after
  30 days. The current app does not record location.

For historical retention work, we keep a digest — a one-way fingerprint, not
the removed data — and the deletion time. Snapshot-v2 history keeps the frozen
daily totals used for the published result.

## Deleting your account

You can delete your account inside the app, under **You → Account & Support →
Delete Account**. We ask you to sign in again first, so nobody who picks up
your unlocked phone can do it for you.

When you delete:

- Your sign-in is revoked with Apple and your login is removed. You cannot sign
  back into the same account.
- Your name, username, and profile are replaced with an anonymous placeholder.
- Your device registrations are revoked.
- Your test payment customer record and saved test payment method are deleted
  at Stripe.
- Your step data stops being readable and is removed on the schedule above.

What stays is a small amount of anonymous history: that a challenge existed and
how it was scored, with no name, username, or profile attached to it. We keep
that because a result someone was charged for — even a test charge — has to
remain auditable after the fact. It cannot be traced back to you from the
outside.

If you would rather email us than use the app, write to [SUPPORT EMAIL] and we
will do it for you.

## Your rights

Depending on where you live, you may have the right to see what we hold about
you, correct it, delete it, or get a copy. Email [SUPPORT EMAIL] and we will
answer. Deletion is available directly in the app, described above.

## Children

Better Bet is not for anyone under 18. We do not knowingly collect data from
children. If you believe a child has an account, email [SUPPORT EMAIL] and we
will remove it.

## Security

Data in transit is encrypted. Step totals are cryptographically signed by your
device before they reach us, so we can tell if they were altered on the way.
Access to production data is limited to the people who operate the service. No
system is perfect, and we will tell affected testers promptly if something goes
wrong.

## Changes

If this policy changes in a way that matters, we will tell beta testers by
email before the change takes effect.

## Contact

[SUPPORT EMAIL]
