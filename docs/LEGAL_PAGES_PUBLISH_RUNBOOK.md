# Legal pages and support contact — publish runbook

Clears three `scripts/check-beta-candidate.sh --testflight` blockers:
`privacy-policy-url`, `beta-terms-url` and `support-contact`. Prepared
September 27, 2026.

**Status, September 27.** Step 1 is done: the owner named the operator
(Mason Jenkins), jurisdiction (State of Texas, United States) and support
inbox (`gametime-support@agentmail.to`), and the final pages are committed to
`main`. The owner has authorized publishing on GitHub Pages and the support
inbox. Steps 2–4 (publish, inbox check, configuration) are left for the
driver and have not been run. `PublicClient.xcconfig` stays `UNCONFIGURED`
until step 4.

## What exists

- `docs/legal-site/` — static pages: `index.html`, `privacy.html`,
  `beta-terms.html`, and `.nojekyll`. They are self-contained HTML with inline
  CSS. The committed pages are a `--final` build; a draft build would carry a
  "Draft — not published" banner and `noindex`.
- `scripts/build-legal-site.py` renders them from `docs/PRIVACY_POLICY.md` and
  `docs/BETA_TERMS.md`. `docs/BETA_PRIVACY_TERMS_DRAFT.md` stays the
  implementation record and is not published. Don't edit the HTML by hand. `--check`
  fails when the pages are stale, and `--final` drops the banner but refuses
  while a source still has a placeholder or an internal draft note.
- `scripts/tests/build-legal-site.test.py` covers the generator. The
  `check-beta-candidate` fixtures now prove that literal `UNCONFIGURED` blocks
  all three, and that the escaped `https:/$()/` form below passes.

## Step 1: make the text publishable — done September 27

Done on `claude/legal-pages-final`, merged to `main`. The list below records
what the step required; each item is resolved as noted.

1. **Name the legal entity, jurisdiction and support inbox.** These fill
   `[LEGAL ENTITY]`, `[JURISDICTION]` and `[SUPPORT EMAIL]` in the privacy
   policy. They are open owner inputs in the
   [friends TestFlight plan](FRIENDS_TESTFLIGHT_PLAN.md#open-owner-inputs).
   *Done:* Mason Jenkins; State of Texas, United States;
   `gametime-support@agentmail.to`.
2. **Revise the privacy policy for the TestFlight build.** Its own scope note
   says it describes only the Personal steps app. The TestFlight build is
   different in at least three ways:
   - It reads step count, exercise minutes, walking and running distance, and
     workouts from Apple Health. The draft says "only step counts."
   - It has open Apple sign-up and friends.
   - It has no payment provider. The draft describes Stripe test mode.

   *Done:* verified against the Health readers, permission service, upload
   payload, `PrivacyInfo.xcprivacy` and `TestFlight.xcconfig`. The policy says
   payments are off in the TestFlight build. Its account-deletion section
   describes the in-app flow, so `delete-account` must be deployed on
   `gametime-p11b` (Phase 5 step 3) before testers are invited.
3. **Write tester-facing beta terms.** `BETA_PRIVACY_TERMS_DRAFT.md` is an
   implementation record of a local preview with fictional accounts, and its
   last section lists its own publication blockers. Keep that file as the
   record, and write the terms a tester reads. Either replace its contents or
   point `PAGES` in the generator at a new file. *Done:* new
   `docs/BETA_TERMS.md`, and `PAGES` points at it.
4. **Have someone qualified read both texts.** Not done. The owner chose to
   publish for the friends beta first; formal review remains advisable before
   any wider cohort or real money.
5. Remove the internal notes (the scope note, "Before you publish",
   "Publication blockers"), then run:

   ```sh
   python3 scripts/build-legal-site.py --final
   python3 scripts/build-legal-site.py --final --check
   python3 scripts/tests/build-legal-site.test.py
   ```

   Commit the final pages to `main`. *Done:* all three pass.

## Step 2: publish on GitHub Pages (needs approval)

**Host: GitHub Pages on `m1jenkins/GameTime`.** The repository is already
public, `gh` is already signed in on this Mac, and nothing new needs an account
or a bill. Pages is not enabled today: `has_pages` is false, and there is no
`gh-pages` branch. Pages serves a `gh-pages` branch holding only
`docs/legal-site/`, so no other file under `docs/` becomes a web page.

```sh
cd /Users/user/Documents/GitHub/GameTime
git switch main && git pull --ff-only
python3 scripts/build-legal-site.py --final --check

git subtree split --prefix docs/legal-site -b legal-pages
git push origin legal-pages:gh-pages
git branch -D legal-pages

gh api -X POST repos/m1jenkins/GameTime/pages \
  -f 'source[branch]=gh-pages' -f 'source[path]=/'
```

The resulting public URLs:

| Page | URL |
| --- | --- |
| Index | `https://m1jenkins.github.io/GameTime/` |
| Privacy policy | `https://m1jenkins.github.io/GameTime/privacy.html` |
| Beta terms | `https://m1jenkins.github.io/GameTime/beta-terms.html` |

The path is case-sensitive: `GameTime`, as the repository is named.

**Readback.** The first build takes a minute or two.

```sh
gh api repos/m1jenkins/GameTime/pages --jq '{status, html_url, https_enforced}'
curl -fsSI https://m1jenkins.github.io/GameTime/privacy.html | head -1
curl -fsSI https://m1jenkins.github.io/GameTime/beta-terms.html | head -1
curl -fsS https://m1jenkins.github.io/GameTime/privacy.html | grep -c 'Draft — not published'
```

Expect `status` built, `https_enforced` true, `HTTP/2 200` twice, and a
banner count of `0`.

**Updating later.** Rebuild, commit to `main`, then repeat the `subtree split`
and the push. The split is deterministic, so the push fast-forwards.

**Rollback.** Run `gh api -X DELETE repos/m1jenkins/GameTime/pages`, then
`git push origin --delete gh-pages`. Copies may already be cached or archived.
A build that shipped with these URLs keeps linking to them, so re-publish
rather than leave testers with a dead link.

The URL is compiled into every build. If a custom domain is ever wanted,
choose it before the first TestFlight upload.

## Step 3: support inbox

The owner named `gametime-support@agentmail.to` and authorized it. It
appears in the app, in the privacy policy and terms, and as the TestFlight
feedback email. Per `BETA_PRIVACY_TERMS_DRAFT.md`, send a real test message and confirm
the reply only after the owner authorizes it. Staffing and coverage are in
[support preparation](BETA_SUPPORT_RETENTION_PREPARATION.md).

## Step 4: set the configuration (after steps 2 and 3)

In `ios/GameTime/Configuration/PublicClient.xcconfig`, replace the three
`UNCONFIGURED` lines. An xcconfig treats `//` as a comment, so each URL uses
`https:/$()/`, like `SUPABASE_URL`:

```
GAMETIME_PRIVACY_POLICY_URL = https:/$()/m1jenkins.github.io/GameTime/privacy.html
GAMETIME_BETA_TERMS_URL = https:/$()/m1jenkins.github.io/GameTime/beta-terms.html
GAMETIME_SUPPORT_EMAIL = gametime-support@agentmail.to
```

Then:

```sh
bash scripts/tests/check-beta-candidate.test.sh
bash scripts/check-beta-candidate.sh --testflight
```

The three blockers should read `PASS`. The same URLs and inbox go into App
Store Connect in [Phase 6](FRIENDS_TESTFLIGHT_PLAN.md#phase-6--testflight-explicit-approval).
