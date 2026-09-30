# Scoped rendered-rank test repair — September 30, 2026

The unchanged mounted correction test failed before any overlapping response
was held. Its screenshots show the correct rank, but the whole-viewport OCR
omitted the isolated first-place digit beside You. The repair changes only
`ios/GameTime/GameTimeTests/ChallengeOverlappingResponseTests.swift` and keeps
the exact displayed **1 → 2 → 2** expectation.

## Initial failure preserved

The initial native run reported 673 passed, 2 failed and 11 skipped. One
failure was
`ChallengeOverlappingResponseTests/testMountedDetailKeepsCorrectedTotalAndRankAfterLateDetail()`
at original line 477: the OCR regex did not find visible rank 1 beside You.
The native agent reproduced the failure without source changes before repair.
The other failure, a creation geometry test, has a separate repair and receipt.

The failing phase was `ordinary-detail-correction-before`. The test begins
holding overlapping responses only after that phase at original line 479.
The pre-correction fixture has a larger own score than its friend, so rank 1
is expected. The later own downward correction must produce rank 2, which must
remain after the older detail arrives.

Original evidence beneath
`tmp/testflight-readiness-2026-09-30/native/initial-attachments/`:

| Attachment | File | Observation |
| --- | --- | --- |
| Initial before viewport, page 0 | `3A419BD6-022F-46FD-9E3D-6BF04F72B835.png` | Visually inspected: rank 1 beside You; friend rank 2. |
| Initial before viewport, page 1 | `C2F6FA51-5040-4236-8E95-744A0008D3E0.png` | Visually inspected: the same correct ranks remain visible. |
| Initial before OCR transcript | `3B9265A3-CF04-447B-8698-61C8722D10A8.txt` | Omits the numeric rank near You; appends an unrelated `w 1` observation. |
| Initial after-late-response viewport, page 0 | `403D01BA-B83C-49AE-B7D4-C82DC680699B.png` | Visually inspected: friend rank 1; You rank 2 with the corrected score. |

`native-focused.xcresult`, `native-focused-summary.json` and
`native-focused.log` preserve the initial run.
`native-failed-methods-retry.xcresult` preserves the unchanged reproduction.
The source's ordinary-response tests separately assert the lowered own fact,
its revision, rank 2 and unchanged accepted latest row after the late response
(`ChallengeOverlappingResponseTests.swift:216–289`). No correction-ordering
defect was found in this investigation.

## Test-only change

The dedicated mounted assertion locates the actual You glyph bounding box in
the rendered viewport and crops the small adjacent rank/name region. The crop
includes You as text-reading context and is enlarged four times. The accurate
recognizer runs once on this crop with language correction disabled.

The assertion independently locates You again inside the crop. It accepts
only a whole numeric candidate, or an exact numeric-and-You candidate, whose
numeric glyph bounds lie to the left of You and within one name-height of its
vertical center. The associated numeral array must be exactly
`[String(expectedRank)]`. Combined `1 You` and separate `1` / `You` observations
can both supply the same strict glyph check; `w1` cannot. No expected rank is
given to Vision, alternate OCR candidates are not used, and no character is
normalized to a digit. A missing, wrong or duplicate associated rank fails.

The name locator permits an OCR line containing the participant name and its
adjacent rank/status so it can obtain the You glyph's own bounds. Those tokens
do not satisfy the rank assertion. A stray number elsewhere, another person's
rank, `w1`, or a nonnumeric cropped result cannot make this check pass.

- Before correction: the cropped rendered own rank must be exactly **1**.
- After the current response: it must be exactly **2**.
- After the older response: it must still be exactly **2**.
- Whole-route text checks still verify corrected score/unit, removal of the
  prior score, the friend's identity and final-result visibility.
- Existing final row equality and no-extra-fetch assertions remain. The
  test does not remount the screen or add a server read to conceal ordering.
- No production view, presentation model, source rule, shared capture helper
  or agreement changed.

Each phase now retains three attachments:
`<phase>-own-rank-context` (number beside You),
`<phase>-own-rank-crop` (the enlarged rank/name region), and
`<phase>-own-rank-recognized` (viewport/crop bounds, raw recognized text and
the exact numeral associated with You).
The native validation agent owns simulator execution and attachment export.

## Verification status

- `xcrun swiftc -frontend -parse -D DEBUG ios/GameTime/GameTimeTests/ChallengeOverlappingResponseTests.swift`:
  exit 0. This is a syntax check, not a successful native typecheck or test.
- `git diff --check` on the changed test file: clean.
- First crop-only native rerun: the final-state method passed; the correction
  method still failed at the before rank with `[]` rather than `["1"]`.
  The actual first-place glyph was fully visible in the crop. The accepted
  and after-late second-place crops each recognized `["2"]` and passed.
  This result led to the bounded fast-recognizer fallback, not acceptance of
  an arbitrary number elsewhere.
- First crop-only evidence beneath
  `tmp/testflight-readiness-2026-09-30/native/rank-fixed-attachments/`:
  `9EB01908-82C4-44F0-8C98-82A161BA6939.png` (crisp enlarged 1),
  `967E29EE-F8AC-4C79-9CD0-F95F087F1588.png` (1 beside You), and
  `1BC7A7D4-8319-4B1A-924C-852894278B08.txt` (the exact detected bounds and
  empty recognition). These were visually inspected.
- The second bounded attempt, adding the fast recognizer on the same isolated
  glyph, also reported 1 failed / 1 passed. The first-place crop returned no
  observation in either mode; second-place crops remained correct. Evidence
  beneath `native/rank-fixed-fast-attachments/` includes
  `5AF06426-8E7C-4C51-941B-A66B141E641F.png` (isolated 1),
  `20355AB3-A867-448F-8D9D-745EDE759FB3.png` (adjacent 1 and You), and
  `7E943A99-8139-4CD9-9106-4CA2048F4460.txt` (both empty observations).
  The final helper removes the fast fallback.
- Before the contextual repair, a bounded offline macOS Vision probe on the
  retained context images independently read **1 You** and **2 You** at their
  original size. After enlargement by four, its top observations were exact
  separate **1** / **You** and **2** / **You**, each at confidence 1.0, with
  language correction disabled. The original sandboxed probe returned
  `nilError`; the same PNG-only, CPU probe succeeded through an auto-reviewed
  sandbox escalation. These are fictional fixture images, and the probe did
  not access a device or hosted service. Its scratch script is ignored at
  `tmp/testflight-readiness-2026-09-30/health-ocr-readonly.swift`.
- The final contextual native rerun passed both
  `testMountedDetailKeepsCorrectedTotalAndRankAfterLateDetail` and
  `testMountedDetailKeepsFinalResultAfterLatePreFinalDetail`:
  **2 passed, 0 failed, 0 skipped** (native command wall time 37.9 seconds).
  `tmp/testflight-readiness-2026-09-30/native/rank-context-targeted.xcresult`
  retains the run, with `rank-context-targeted.log` and
  `rank-context-targeted-summary.json` beside it.
- The full `ChallengeOverlappingResponseTests` class subsequently passed
  **21 passed, 0 failed, 0 skipped** (native command wall time 49.6 seconds).
  `tmp/testflight-readiness-2026-09-30/native/overlap-context-class.xcresult`,
  `overlap-context-class.log`, `overlap-context-class-summary.json` and
  `overlap-context-class-attachments/manifest.json` retain the run and export.
  The targeted and full-class summary JSON files were independently read and
  report `Passed`, with no test failures or runtime warnings. Both use the
  iPhone 17 Pro / iOS 27.0 simulator; no physical-device check is implied.

## Final rendered evidence

The three enlarged targeted crops were visually inspected. They show the
same participant label with exact **1 → 2 → 2**. The transcripts independently
report `accurate: ["1", "You", "Agree"]; associated rank: ["1"]` before
correction and `accurate: ["2", "You", "Agree"]; associated rank: ["2"]`
after correction and after the late response. The full-class rerun records
the same exact sequence.

Targeted files beneath
`tmp/testflight-readiness-2026-09-30/native/rank-context-targeted-attachments/`:

| Phase | Raw context PNG | Enlarged crop PNG | Recognition transcript |
| --- | --- | --- | --- |
| Before correction: 1 | `422C556D-7FB0-4D1F-AADA-FCD813441B8D.png` | `5CE53150-93B9-4A93-8FF6-BBEDC86BC85E.png` | `10AF07EF-02C0-4414-B9F2-9FDAD50A196A.txt` |
| Accepted correction: 2 | `EB250513-0558-4B0B-864F-F8D2B1D6FAF7.png` | `A59D4AA0-0618-4867-9EA8-18A2648A8D37.png` | `9B180CE6-20C4-4FF1-89FA-EE1D475691DB.txt` |
| After late response: 2 | `3DF5C983-BAC9-4133-8203-F949F7DEDFBB.png` | `14BCD7C9-DC49-4EC0-B7B6-E68C9DC03B2F.png` | `CE3212A3-FD04-477E-9815-022D36ABC773.txt` |

Full-class files beneath
`tmp/testflight-readiness-2026-09-30/native/overlap-context-class-attachments/`:

| Phase | Raw context PNG | Enlarged crop PNG | Recognition transcript |
| --- | --- | --- | --- |
| Before correction: 1 | `46DD4D31-A6C0-4E9D-BA5D-B34CE80FF52D.png` | `7FE496C6-9094-40E5-9A71-5FBEFD63E853.png` | `75732ED9-FD1D-497A-8120-0834D36C8CB6.txt` |
| Accepted correction: 2 | `09BBD1F9-C759-442A-9265-64CF06CE73D4.png` | `5F838EF2-5AE8-43CA-921D-6E4C6A07CE77.png` | `5EB985DF-8ECA-4C5C-9479-55EF44E37B61.txt` |
| After late response: 2 | `08740D56-4EAF-4379-AE9E-CE0AA8E701B8.png` | `CB04EC25-A22D-4737-880B-3897DC0F5320.png` | `74988A0D-EF78-4F5F-A04A-D9051290E178.txt` |

The exported fixtures and build/test bundles remain under ignored scratch.
This receipt preserves their filenames; it does not claim that binary test
bundles are committed. The native validation receipt owns the build commands
and broader acceptance result. The repair fixes a rendered-text observation
defect in this test; the completed checks found no production correction-order
defect and do not replace real-Health/device acceptance.

No physical-device action occurred during this repair. TestFlight upload,
credentials, hosted changes and the owner's active Staging app are unchanged.
