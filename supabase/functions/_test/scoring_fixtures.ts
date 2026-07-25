/**
 * The scoring corpus. This file is the specification for who wins.
 *
 * Every case is plain data — no functions, no classes, nothing that only
 * TypeScript can read. That is deliberate and it is D3's escape hatch: if
 * optimistic offline standings ever become a product requirement and a second
 * engine has to exist in Swift, the two must agree, and the only credible way to
 * hold them to that is a corpus both run. Designing the fixtures in a portable
 * shape now costs nothing and keeps the option open;
 * `scoring_fixtures.test.ts` asserts the corpus survives a JSON round trip so it
 * cannot quietly stop being portable.
 *
 * The helpers below construct that data. They are build-time convenience, not
 * part of the corpus.
 *
 * ---------------------------------------------------------------------------
 * On the fraudulent cases
 * ---------------------------------------------------------------------------
 * They come in two kinds, and the distinction is the point.
 *
 * The first kind must not work: padding a step contest with calories, backfilling
 * outside the window, stuffing the part-days at a window edge. Each of these is
 * something a modified client can actually send, each would change who wins if
 * the engine were naive about it, and each is pinned here.
 *
 * The second kind must work, and is recorded so that nobody mistakes the
 * engine's silence for a judgement: 90,000 steps in one hour scores as 90,000,
 * and a bucket first reported eleven days late scores too. Plausibility is M5's
 * and needs a tuning parameter (D38's reasoning applies to it). What the engine
 * owes M5 is the aggregate that makes the call possible, so those fixtures assert
 * on `maxBucketValue` and `maxReportingLagMs` rather than on a rejection.
 */

import type {
  ContestMetric,
  ContestScoring,
  EvidenceBucket,
  ExclusionReason,
  Outcome,
  ScoringInput,
} from "../_shared/scoring.ts";

// ---------------------------------------------------------------------------
// Fixture shape
// ---------------------------------------------------------------------------

/** What a case asserts about one participant. Every field is optional. */
export interface ParticipantExpectation {
  readonly rank?: number;
  readonly qualified?: boolean;
  readonly total?: number;
  readonly qualifyingDays?: number;
  readonly scoreableDays?: number;
  readonly dayRate?: number;
  readonly reachedTargetAt?: string | null;
  readonly maxBucketValue?: number;
  readonly maxReportingLagMs?: number;
  readonly bucketCount?: number;
}

export interface ScoringFixture {
  readonly name: string;
  /** The property this case pins. Read this before changing an expectation. */
  readonly why: string;
  readonly input: ScoringInput;
  /** Expected outcome, or `error` when the engine must refuse to score. */
  readonly outcome?: Outcome;
  readonly error?: string;
  readonly participants?: Readonly<Record<string, ParticipantExpectation>>;
  readonly excluded?: Readonly<Partial<Record<ExclusionReason, number>>>;
  /** Asserted only when present, so a case can ignore ordering. */
  readonly order?: readonly string[];
}

// ---------------------------------------------------------------------------
// Construction helpers
// ---------------------------------------------------------------------------

const ALICE = "11111111-1111-1111-1111-111111111111";
const BOB = "22222222-2222-2222-2222-222222222222";
const CAROL = "33333333-3333-3333-3333-333333333333";

/** Minutes east of UTC. `-300` is US Eastern in winter, `345` is Nepal. */
type OffsetMinutes = number;

const UTC: OffsetMinutes = 0;
const NY_WINTER: OffsetMinutes = -300;
const NY_SUMMER: OffsetMinutes = -240;
const KATHMANDU: OffsetMinutes = 345;
const KIRITIMATI: OffsetMinutes = 840;
const HONOLULU: OffsetMinutes = -600;

/** The instant a given local hour starts, for a zone at a known offset. */
function at(localDay: string, localHour: number, offset: OffsetMinutes): string {
  const [year, month, day] = localDay.split("-").map(Number);
  const utc = Date.UTC(year ?? 0, (month ?? 1) - 1, day ?? 1, localHour);
  return new Date(utc - offset * 60_000).toISOString();
}

interface BucketOptions {
  readonly metric?: ContestMetric;
  readonly sampleCount?: number;
  readonly observationCount?: number;
  /** Milliseconds after the bucket closes that it was last reported. */
  readonly reportedLateMs?: number;
}

/** One row of `contest_evidence`, described the way a human thinks about it. */
function bucket(
  userId: string,
  localDay: string,
  localHour: number,
  value: number,
  offset: OffsetMinutes,
  options: BucketOptions = {},
): EvidenceBucket {
  const bucketStart = at(localDay, localHour, offset);
  const closesAt = Date.parse(bucketStart) + 3_600_000;
  const recordedAt = new Date(closesAt + (options.reportedLateMs ?? -1_800_000)).toISOString();

  return {
    userId,
    metric: options.metric ?? "steps",
    bucketStart,
    localDay,
    localHour,
    value,
    sampleCount: options.sampleCount ?? 12,
    observationCount: options.observationCount ?? 1,
    firstRecordedAt: recordedAt,
    lastRecordedAt: recordedAt,
  };
}

/** A day's worth of buckets, spread over waking hours. */
function day(
  userId: string,
  localDay: string,
  values: readonly number[],
  offset: OffsetMinutes,
  options: BucketOptions = {},
): EvidenceBucket[] {
  return values.map((value, index) => bucket(userId, localDay, 8 + index, value, offset, options));
}

function accepted(userId: string, timezone: string) {
  return { userId, status: "accepted" as const, timezone, charityId: null };
}

// ---------------------------------------------------------------------------
// The corpus
// ---------------------------------------------------------------------------

export const SCORING_FIXTURES: readonly ScoringFixture[] = [
  // -------------------------------------------------------------------------
  // Cumulative cadence
  // -------------------------------------------------------------------------
  {
    name: "cumulative/one-reaches-the-target",
    why: "The ordinary win: one participant clears the bar, the other does not.",
    input: {
      timezoneChanges: [],
      contest: {
        id: "a0000001-0000-0000-0000-000000000001",
        metric: "steps",
        cadence: "cumulative",
        targetValue: 50000,
        tieBreak: "integrity_score",
        startsAt: "2026-01-05T00:00:00Z",
        endsAt: "2026-01-08T00:00:00Z",
      },
      roster: [accepted(ALICE, "UTC"), accepted(BOB, "UTC")],
      evidence: [
        ...day(ALICE, "2026-01-05", [9000, 9000], UTC),
        ...day(ALICE, "2026-01-06", [9000, 9000], UTC),
        ...day(ALICE, "2026-01-07", [8000, 6000], UTC),
        ...day(BOB, "2026-01-05", [4000, 3000], UTC),
        ...day(BOB, "2026-01-06", [4000, 3000], UTC),
      ],
    },
    outcome: { kind: "winner", userId: ALICE, decidedBy: "sole_qualifier" },
    participants: {
      [ALICE]: { rank: 1, qualified: true, total: 50000 },
      [BOB]: { rank: 2, qualified: false, total: 14000 },
    },
    order: [ALICE, BOB],
  },

  {
    name: "cumulative/nobody-reaches-the-target",
    why: "The rule that makes this a goal rather than a wager. Bob walked three " +
      "times what Alice did and still owes nobody a donation, because neither " +
      "did the thing they staked money on. Changing this to 'highest total " +
      "wins' would make a losing participant pay a winner who also failed.",
    input: {
      timezoneChanges: [],
      contest: {
        id: "a0000002-0000-0000-0000-000000000002",
        metric: "steps",
        cadence: "cumulative",
        targetValue: 100000,
        tieBreak: "integrity_score",
        startsAt: "2026-01-05T00:00:00Z",
        endsAt: "2026-01-08T00:00:00Z",
      },
      roster: [accepted(ALICE, "UTC"), accepted(BOB, "UTC")],
      evidence: [
        ...day(ALICE, "2026-01-05", [3000, 2000], UTC),
        ...day(BOB, "2026-01-05", [9000, 6000], UTC),
      ],
    },
    outcome: { kind: "void", reason: "no_qualifying_participant" },
    participants: {
      [BOB]: { rank: 1, qualified: false, total: 15000 },
      [ALICE]: { rank: 2, qualified: false, total: 5000 },
    },
  },

  {
    name: "cumulative/exactly-on-target-with-fractional-values",
    why: "Landing precisely on the target must qualify. These four buckets sum to " +
      "29.999999999999996 in IEEE doubles and to exactly 30.00 in hundredths, " +
      "so a float engine denies this participant a win they earned. This is " +
      "why scoring is done in integer hundredths.",
    input: {
      timezoneChanges: [],
      contest: {
        id: "a0000003-0000-0000-0000-000000000003",
        metric: "exercise_minutes",
        cadence: "cumulative",
        targetValue: 30,
        tieBreak: "integrity_score",
        startsAt: "2026-01-05T00:00:00Z",
        endsAt: "2026-01-06T00:00:00Z",
      },
      roster: [accepted(ALICE, "UTC"), accepted(BOB, "UTC")],
      evidence: [
        ...day(ALICE, "2026-01-05", [28.45, 1.24, 0.2, 0.11], UTC, {
          metric: "exercise_minutes",
        }),
        ...day(BOB, "2026-01-05", [8.7, 0.1], UTC, { metric: "exercise_minutes" }),
      ],
    },
    outcome: { kind: "winner", userId: ALICE, decidedBy: "sole_qualifier" },
    participants: {
      [ALICE]: { qualified: true, total: 30 },
      // 8.7 + 0.1 is 8.799999999999999 as a double; the total must read 8.8.
      [BOB]: { qualified: false, total: 8.8 },
    },
  },

  {
    name: "cumulative/values-as-strings",
    why: "PostgREST can be configured to render numeric as a string to preserve " +
      "precision. A deployment setting must not change who wins.",
    input: {
      timezoneChanges: [],
      contest: {
        id: "a0000004-0000-0000-0000-000000000004",
        metric: "distance_meters",
        cadence: "cumulative",
        targetValue: "5000.00",
        tieBreak: "integrity_score",
        startsAt: "2026-01-05T00:00:00Z",
        endsAt: "2026-01-06T00:00:00Z",
      },
      roster: [accepted(ALICE, "UTC"), accepted(BOB, "UTC")],
      evidence: [
        {
          ...bucket(ALICE, "2026-01-05", 9, 0, UTC, { metric: "distance_meters" }),
          value: "2500.50",
        },
        {
          ...bucket(ALICE, "2026-01-05", 10, 0, UTC, { metric: "distance_meters" }),
          value: "2499.50",
        },
        { ...bucket(BOB, "2026-01-05", 9, 0, UTC, { metric: "distance_meters" }), value: "100.00" },
      ],
    },
    outcome: { kind: "winner", userId: ALICE, decidedBy: "sole_qualifier" },
    participants: {
      [ALICE]: { qualified: true, total: 5000 },
      [BOB]: { qualified: false, total: 100 },
    },
  },

  // -------------------------------------------------------------------------
  // Daily cadence
  // -------------------------------------------------------------------------
  {
    name: "daily/one-missed-day-loses",
    why: "Daily cadence means every day, so a single missed day is the whole " +
      "difference between winning and not.",
    input: {
      timezoneChanges: [],
      contest: {
        id: "a0000005-0000-0000-0000-000000000005",
        metric: "steps",
        cadence: "daily",
        targetValue: 10000,
        tieBreak: "integrity_score",
        startsAt: "2026-01-05T00:00:00Z",
        endsAt: "2026-01-08T00:00:00Z",
      },
      roster: [accepted(ALICE, "UTC"), accepted(BOB, "UTC")],
      evidence: [
        ...day(ALICE, "2026-01-05", [6000, 4000], UTC),
        ...day(ALICE, "2026-01-06", [7000, 3500], UTC),
        ...day(ALICE, "2026-01-07", [5000, 5000], UTC),
        ...day(BOB, "2026-01-05", [6000, 5000], UTC),
        // Bob's Tuesday: 400 steps short.
        ...day(BOB, "2026-01-06", [5000, 4600], UTC),
        ...day(BOB, "2026-01-07", [8000, 4000], UTC),
      ],
    },
    outcome: { kind: "winner", userId: ALICE, decidedBy: "sole_qualifier" },
    participants: {
      [ALICE]: { rank: 1, qualified: true, qualifyingDays: 3, scoreableDays: 3, dayRate: 1 },
      [BOB]: { rank: 2, qualified: false, qualifyingDays: 2, scoreableDays: 3 },
    },
    order: [ALICE, BOB],
  },

  {
    name: "daily/nobody-perfect-voids",
    why: "Same rule as the cumulative case: no qualifier, no settlement.",
    input: {
      timezoneChanges: [],
      contest: {
        id: "a0000006-0000-0000-0000-000000000006",
        metric: "steps",
        cadence: "daily",
        targetValue: 10000,
        tieBreak: "integrity_score",
        startsAt: "2026-01-05T00:00:00Z",
        endsAt: "2026-01-07T00:00:00Z",
      },
      roster: [accepted(ALICE, "UTC"), accepted(BOB, "UTC")],
      evidence: [
        ...day(ALICE, "2026-01-05", [6000, 4000], UTC),
        ...day(ALICE, "2026-01-06", [3000], UTC),
        ...day(BOB, "2026-01-05", [2000], UTC),
        ...day(BOB, "2026-01-06", [6000, 4000], UTC),
      ],
    },
    outcome: { kind: "void", reason: "no_qualifying_participant" },
    participants: {
      [ALICE]: { qualified: false, qualifyingDays: 1, scoreableDays: 2 },
      [BOB]: { qualified: false, qualifyingDays: 1, scoreableDays: 2 },
    },
  },

  {
    name: "daily/both-perfect-with-no-integrity-scores",
    why: "The common case in a real duel, and the reason tie_break is declared at " +
      "creation. M5 owns the integrity score, so until it exists this is not " +
      "settleable — and saying so is the only honest answer. Substituting the " +
      "higher total would silently apply a tie-break the participants did not " +
      "agree to.",
    input: {
      timezoneChanges: [],
      contest: {
        id: "a0000007-0000-0000-0000-000000000007",
        metric: "steps",
        cadence: "daily",
        targetValue: 10000,
        tieBreak: "integrity_score",
        startsAt: "2026-01-05T00:00:00Z",
        endsAt: "2026-01-07T00:00:00Z",
      },
      roster: [accepted(ALICE, "UTC"), accepted(BOB, "UTC")],
      evidence: [
        ...day(ALICE, "2026-01-05", [6000, 4000], UTC),
        ...day(ALICE, "2026-01-06", [6000, 4000], UTC),
        ...day(BOB, "2026-01-05", [20000], UTC),
        ...day(BOB, "2026-01-06", [20000], UTC),
      ],
    },
    outcome: {
      kind: "undecided",
      reason: "integrity_score_unavailable",
      tied: [BOB, ALICE],
    },
    participants: {
      [ALICE]: { qualified: true, dayRate: 1 },
      [BOB]: { qualified: true, dayRate: 1 },
    },
  },

  {
    name: "daily/both-perfect-with-integrity-scores",
    why: "The same contest once M5 supplies the numbers. Cleaner data wins the tie.",
    input: {
      timezoneChanges: [],
      contest: {
        id: "a0000008-0000-0000-0000-000000000008",
        metric: "steps",
        cadence: "daily",
        targetValue: 10000,
        tieBreak: "integrity_score",
        startsAt: "2026-01-05T00:00:00Z",
        endsAt: "2026-01-07T00:00:00Z",
      },
      roster: [accepted(ALICE, "UTC"), accepted(BOB, "UTC")],
      evidence: [
        ...day(ALICE, "2026-01-05", [6000, 4000], UTC),
        ...day(ALICE, "2026-01-06", [6000, 4000], UTC),
        ...day(BOB, "2026-01-05", [20000], UTC),
        ...day(BOB, "2026-01-06", [20000], UTC),
      ],
      integrityScores: { [ALICE]: 100, [BOB]: 62 },
    },
    outcome: { kind: "winner", userId: ALICE, decidedBy: "integrity_score" },
  },

  {
    name: "daily/zones-are-asked-about-different-numbers-of-days",
    why: "A window of whole New York days is not whole days in Kathmandu (+05:45), " +
      "so Alice is asked about seven days and Bob about six. Ranking on the raw " +
      "count would cap Bob at 6 against Alice's 7 and make him unable to win a " +
      "contest he played perfectly. Ranking on the rate is what makes the two " +
      "comparable. Bob's evidence in the part-days at each edge is dropped from " +
      "numerator and denominator alike.",
    input: {
      timezoneChanges: [],
      contest: {
        id: "a0000009-0000-0000-0000-000000000009",
        metric: "steps",
        cadence: "daily",
        targetValue: 10000,
        tieBreak: "both_donate",
        startsAt: "2026-01-05T05:00:00Z", // local midnight in New York
        endsAt: "2026-01-12T05:00:00Z",
      },
      roster: [accepted(ALICE, "America/New_York"), accepted(BOB, "Asia/Kathmandu")],
      evidence: [
        ...["05", "06", "07", "08", "09", "10", "11"].flatMap((d) =>
          day(ALICE, `2026-01-${d}`, [6000, 4000], NY_WINTER)
        ),
        ...["06", "07", "08", "09", "10", "11"].flatMap((d) =>
          day(BOB, `2026-01-${d}`, [6000, 4000], KATHMANDU)
        ),
        // Bob's part-days. Inside the window and legitimately banked, but not
        // days the contest asks about. The hours are chosen to sit inside the
        // window: Bob's 5 January begins at 10:45 local and his 12 January ends
        // there, so an 08:00 bucket would fall outside the window on the first
        // day and be excluded for that reason instead of this one.
        bucket(BOB, "2026-01-05", 12, 9000, KATHMANDU),
        bucket(BOB, "2026-01-12", 8, 9000, KATHMANDU),
      ],
    },
    outcome: { kind: "all_donate", userIds: [ALICE, BOB] },
    participants: {
      [ALICE]: { qualified: true, qualifyingDays: 7, scoreableDays: 7, dayRate: 1 },
      [BOB]: { qualified: true, qualifyingDays: 6, scoreableDays: 6, dayRate: 1 },
    },
    excluded: { partial_local_day: 2 },
  },

  {
    name: "daily/a-23-hour-day-is-still-a-day",
    why: "New York's spring-forward Sunday is 23 hours long. It is one local day " +
      "and it is scored as one, which is what aligning buckets to the local " +
      "hour rather than to multiples of 3600 seconds buys (D36).",
    input: {
      timezoneChanges: [],
      contest: {
        id: "a000000a-0000-0000-0000-00000000000a",
        metric: "steps",
        cadence: "daily",
        targetValue: 10000,
        tieBreak: "earliest_to_target",
        startsAt: "2026-03-07T05:00:00Z", // local midnight, still EST
        endsAt: "2026-03-10T04:00:00Z", // local midnight, now EDT
      },
      roster: [accepted(ALICE, "America/New_York"), accepted(BOB, "America/New_York")],
      evidence: [
        ...day(ALICE, "2026-03-07", [6000, 4000], NY_WINTER),
        ...day(ALICE, "2026-03-08", [6000, 4000], NY_SUMMER),
        ...day(ALICE, "2026-03-09", [6000, 4000], NY_SUMMER),
        ...day(BOB, "2026-03-07", [3000], NY_WINTER),
        ...day(BOB, "2026-03-08", [3000], NY_SUMMER),
        ...day(BOB, "2026-03-09", [3000], NY_SUMMER),
      ],
    },
    outcome: { kind: "winner", userId: ALICE, decidedBy: "sole_qualifier" },
    participants: {
      [ALICE]: { qualified: true, qualifyingDays: 3, scoreableDays: 3 },
      [BOB]: { qualified: false, scoreableDays: 3 },
    },
  },

  {
    name: "daily/a-civil-date-repeated-across-timezone-epochs-stays-two-days",
    why: "Relocating across the date line can repeat the same civil date. Epoch " +
      "identity keeps those two independently scoreable days from being merged.",
    input: {
      timezoneChanges: [{
        userId: ALICE,
        fromTimezone: "Pacific/Kiritimati",
        toTimezone: "Pacific/Honolulu",
        effectiveAt: "2026-01-06T10:00:00Z",
      }],
      contest: {
        id: "a0000018-0000-0000-0000-000000000018",
        metric: "steps",
        cadence: "daily",
        targetValue: 10000,
        tieBreak: "integrity_score",
        startsAt: "2026-01-05T10:00:00Z",
        endsAt: "2026-01-07T10:00:00Z",
      },
      roster: [
        accepted(ALICE, "Pacific/Kiritimati"),
        accepted(BOB, "Pacific/Kiritimati"),
      ],
      evidence: [
        bucket(ALICE, "2026-01-06", 8, 6000, KIRITIMATI),
        bucket(ALICE, "2026-01-06", 8, 6000, HONOLULU),
        bucket(BOB, "2026-01-06", 8, 10000, KIRITIMATI),
        bucket(BOB, "2026-01-07", 8, 10000, KIRITIMATI),
      ],
    },
    outcome: { kind: "winner", userId: BOB, decidedBy: "sole_qualifier" },
    participants: {
      [ALICE]: {
        qualified: false,
        total: 12000,
        qualifyingDays: 0,
        scoreableDays: 2,
      },
      [BOB]: {
        qualified: true,
        total: 20000,
        qualifyingDays: 2,
        scoreableDays: 2,
      },
    },
  },

  // -------------------------------------------------------------------------
  // Tie-breaks
  // -------------------------------------------------------------------------
  {
    name: "tie/earliest-to-target-separates",
    why: "Both cleared the bar; the one who got there in an earlier hour takes it.",
    input: {
      timezoneChanges: [],
      contest: {
        id: "a000000b-0000-0000-0000-00000000000b",
        metric: "steps",
        cadence: "cumulative",
        targetValue: 10000,
        tieBreak: "earliest_to_target",
        startsAt: "2026-01-05T00:00:00Z",
        endsAt: "2026-01-06T00:00:00Z",
      },
      roster: [accepted(ALICE, "UTC"), accepted(BOB, "UTC")],
      evidence: [
        // Alice crosses during the 09:00 hour, so at 10:00Z.
        bucket(ALICE, "2026-01-05", 8, 5000, UTC),
        bucket(ALICE, "2026-01-05", 9, 5000, UTC),
        // Bob crosses during the 11:00 hour, with a bigger total.
        bucket(BOB, "2026-01-05", 10, 6000, UTC),
        bucket(BOB, "2026-01-05", 11, 9000, UTC),
      ],
    },
    outcome: { kind: "winner", userId: ALICE, decidedBy: "earliest_to_target" },
    participants: {
      [ALICE]: { reachedTargetAt: "2026-01-05T10:00:00.000Z", total: 10000 },
      [BOB]: { reachedTargetAt: "2026-01-05T12:00:00.000Z", total: 15000 },
    },
    // Bob ranks first on total, and still loses. Display order and the outcome
    // are answers to different questions.
    order: [BOB, ALICE],
  },

  {
    name: "tie/earliest-to-target-cannot-separate",
    why: "An hour is the finest grain the ledger records, so two people crossing " +
      "in the same bucket is ordinary. There is no further evidence to appeal " +
      "to, and the engine must not reach for user id — settling a donation by " +
      "whose UUID sorts lower is indefensible.",
    input: {
      timezoneChanges: [],
      contest: {
        id: "a000000c-0000-0000-0000-00000000000c",
        metric: "steps",
        cadence: "cumulative",
        targetValue: 10000,
        tieBreak: "earliest_to_target",
        startsAt: "2026-01-05T00:00:00Z",
        endsAt: "2026-01-06T00:00:00Z",
      },
      roster: [accepted(ALICE, "UTC"), accepted(BOB, "UTC")],
      evidence: [
        bucket(ALICE, "2026-01-05", 8, 12000, UTC),
        bucket(BOB, "2026-01-05", 8, 11000, UTC),
      ],
    },
    outcome: {
      kind: "undecided",
      reason: "tie_break_inconclusive",
      tied: [ALICE, BOB],
    },
  },

  {
    name: "tie/void",
    why: "The tie-break the participants chose says nobody donates.",
    input: {
      timezoneChanges: [],
      contest: {
        id: "a000000d-0000-0000-0000-00000000000d",
        metric: "steps",
        cadence: "cumulative",
        targetValue: 10000,
        tieBreak: "void",
        startsAt: "2026-01-05T00:00:00Z",
        endsAt: "2026-01-06T00:00:00Z",
      },
      roster: [accepted(ALICE, "UTC"), accepted(BOB, "UTC")],
      evidence: [
        bucket(ALICE, "2026-01-05", 8, 12000, UTC),
        bucket(BOB, "2026-01-05", 9, 11000, UTC),
      ],
    },
    outcome: { kind: "void", reason: "tie_break_void" },
  },

  {
    name: "tie/three-way-all-donate",
    why: "`both_donate` is named for the duel it was designed around. With three " +
      "qualifiers every one of them donates, each to their own nomination.",
    input: {
      timezoneChanges: [],
      contest: {
        id: "a000000e-0000-0000-0000-00000000000e",
        metric: "steps",
        cadence: "cumulative",
        targetValue: 10000,
        tieBreak: "both_donate",
        startsAt: "2026-01-05T00:00:00Z",
        endsAt: "2026-01-06T00:00:00Z",
      },
      roster: [accepted(ALICE, "UTC"), accepted(BOB, "UTC"), accepted(CAROL, "UTC")],
      evidence: [
        bucket(ALICE, "2026-01-05", 8, 12000, UTC),
        bucket(BOB, "2026-01-05", 9, 11000, UTC),
        bucket(CAROL, "2026-01-05", 10, 10000, UTC),
      ],
    },
    outcome: { kind: "all_donate", userIds: [ALICE, BOB, CAROL] },
  },

  // -------------------------------------------------------------------------
  // Roster
  // -------------------------------------------------------------------------
  {
    name: "roster/only-accepted-participants-score",
    why: "Nobody who is merely invited, or who declined or withdrew, agreed to a " +
      "live stake. Their rows stay on the roster for M7's reliability score, " +
      "and their evidence — Carol withdrew but her client kept syncing — must " +
      "not appear in standings at all.",
    input: {
      timezoneChanges: [],
      contest: {
        id: "a000000f-0000-0000-0000-00000000000f",
        metric: "steps",
        cadence: "cumulative",
        targetValue: 10000,
        tieBreak: "integrity_score",
        startsAt: "2026-01-05T00:00:00Z",
        endsAt: "2026-01-06T00:00:00Z",
      },
      roster: [
        accepted(ALICE, "UTC"),
        accepted(BOB, "UTC"),
        { userId: CAROL, status: "withdrawn", timezone: "UTC", charityId: null },
      ],
      evidence: [
        bucket(ALICE, "2026-01-05", 8, 12000, UTC),
        bucket(BOB, "2026-01-05", 9, 3000, UTC),
        bucket(CAROL, "2026-01-05", 9, 99000, UTC),
      ],
    },
    outcome: { kind: "winner", userId: ALICE, decidedBy: "sole_qualifier" },
    excluded: { unscored_participant: 1 },
    order: [ALICE, BOB],
  },

  {
    name: "roster/one-accepted-participant-voids",
    why: "A contest is a comparison. D30 makes activation refuse a quorum of one, " +
      "so reaching the engine with one accepted participant means something " +
      "upstream is wrong, and scoring it would invent a winner out of a " +
      "contest with no meaning.",
    input: {
      timezoneChanges: [],
      contest: {
        id: "a0000010-0000-0000-0000-000000000010",
        metric: "steps",
        cadence: "cumulative",
        targetValue: 10000,
        tieBreak: "integrity_score",
        startsAt: "2026-01-05T00:00:00Z",
        endsAt: "2026-01-06T00:00:00Z",
      },
      roster: [
        accepted(ALICE, "UTC"),
        { userId: BOB, status: "declined", timezone: "UTC", charityId: null },
      ],
      evidence: [bucket(ALICE, "2026-01-05", 8, 99000, UTC)],
    },
    outcome: { kind: "void", reason: "insufficient_participants" },
  },

  {
    name: "roster/a-participant-with-no-evidence-at-all",
    why: "Silence is a score of zero, not an error and not a vacuous perfect record.",
    input: {
      timezoneChanges: [],
      contest: {
        id: "a0000011-0000-0000-0000-000000000011",
        metric: "steps",
        cadence: "daily",
        targetValue: 10000,
        tieBreak: "integrity_score",
        startsAt: "2026-01-05T00:00:00Z",
        endsAt: "2026-01-07T00:00:00Z",
      },
      roster: [accepted(ALICE, "UTC"), accepted(BOB, "UTC")],
      evidence: [
        ...day(ALICE, "2026-01-05", [6000, 4000], UTC),
        ...day(ALICE, "2026-01-06", [6000, 4000], UTC),
      ],
    },
    outcome: { kind: "winner", userId: ALICE, decidedBy: "sole_qualifier" },
    participants: {
      [BOB]: {
        qualified: false,
        total: 0,
        qualifyingDays: 0,
        scoreableDays: 2,
        dayRate: 0,
        bucketCount: 0,
      },
    },
  },

  // -------------------------------------------------------------------------
  // Fraudulent: must not work
  // -------------------------------------------------------------------------
  {
    name: "fraud/cross-metric-padding",
    why: "The ledger deliberately carries metrics the contest does not score, " +
      "because M5's strongest signal is cross-metric corroboration. That makes " +
      "'sum everything for this participant' a live attack: Bob's client reports " +
      "enormous active energy into a step contest. Only the contest's own metric " +
      "may be counted.",
    input: {
      timezoneChanges: [],
      contest: {
        id: "a0000012-0000-0000-0000-000000000012",
        metric: "steps",
        cadence: "cumulative",
        targetValue: 20000,
        tieBreak: "integrity_score",
        startsAt: "2026-01-05T00:00:00Z",
        endsAt: "2026-01-06T00:00:00Z",
      },
      roster: [accepted(ALICE, "UTC"), accepted(BOB, "UTC")],
      evidence: [
        bucket(ALICE, "2026-01-05", 8, 12000, UTC),
        bucket(ALICE, "2026-01-05", 9, 9000, UTC),
        bucket(BOB, "2026-01-05", 8, 4000, UTC),
        bucket(BOB, "2026-01-05", 9, 900000, UTC, { metric: "active_energy_kcal" }),
        bucket(BOB, "2026-01-05", 10, 900000, UTC, { metric: "exercise_minutes" }),
      ],
    },
    outcome: { kind: "winner", userId: ALICE, decidedBy: "sole_qualifier" },
    participants: {
      [ALICE]: { qualified: true, total: 21000 },
      [BOB]: { qualified: false, total: 4000 },
    },
    excluded: { other_metric: 2 },
  },

  {
    name: "fraud/backfill-outside-the-window",
    why: "Bob writes a huge figure into the day before the contest opened and the " +
      "day after it closed. The ledger refuses out-of-window buckets at write " +
      "time (D43), and the engine filters them too — because this engine is " +
      "also what re-scores a disputed contest years later, from a ledger a " +
      "migration or backfill may since have touched.",
    input: {
      timezoneChanges: [],
      contest: {
        id: "a0000013-0000-0000-0000-000000000013",
        metric: "steps",
        cadence: "cumulative",
        targetValue: 20000,
        tieBreak: "integrity_score",
        startsAt: "2026-01-05T00:00:00Z",
        // Closes at 23:30, so the final hour of the day is only half covered.
        // Nothing requires a window to be hour-aligned.
        endsAt: "2026-01-05T23:30:00Z",
      },
      roster: [accepted(ALICE, "UTC"), accepted(BOB, "UTC")],
      evidence: [
        bucket(ALICE, "2026-01-05", 8, 21000, UTC),
        bucket(BOB, "2026-01-05", 8, 5000, UTC),
        bucket(BOB, "2026-01-04", 8, 60000, UTC),
        bucket(BOB, "2026-01-06", 8, 60000, UTC),
        // Straddles the closing boundary: starts at 23:00 and so runs half an
        // hour past ends_at. A bucket must lie wholly inside, and half of one
        // is not a figure the contest agreed to score.
        bucket(BOB, "2026-01-05", 23, 60000, UTC),
      ],
    },
    outcome: { kind: "winner", userId: ALICE, decidedBy: "sole_qualifier" },
    participants: {
      [ALICE]: { qualified: true, total: 21000 },
      [BOB]: { qualified: false, total: 5000 },
    },
    excluded: { outside_window: 3 },
  },

  {
    name: "fraud/stuffing-the-part-days-at-the-window-edges",
    why: "The window opens at 06:00 local, so Bob's first and last local days are " +
      "part-days he can legitimately write into. He loads them with 50,000 " +
      "steps each to cover the Wednesday he missed. Part-days are not days the " +
      "contest asks about, so this buys nothing — which is also what stops the " +
      "same evidence from manufacturing a phantom qualifying day.",
    input: {
      timezoneChanges: [],
      contest: {
        id: "a0000014-0000-0000-0000-000000000014",
        metric: "steps",
        cadence: "daily",
        targetValue: 10000,
        tieBreak: "integrity_score",
        startsAt: "2026-01-05T11:00:00Z", // 06:00 in New York
        endsAt: "2026-01-09T11:00:00Z",
      },
      roster: [accepted(ALICE, "America/New_York"), accepted(BOB, "America/New_York")],
      evidence: [
        ...day(ALICE, "2026-01-06", [6000, 4000], NY_WINTER),
        ...day(ALICE, "2026-01-07", [6000, 4000], NY_WINTER),
        ...day(ALICE, "2026-01-08", [6000, 4000], NY_WINTER),
        ...day(BOB, "2026-01-06", [6000, 4000], NY_WINTER),
        ...day(BOB, "2026-01-07", [6000, 4000], NY_WINTER),
        // The Wednesday Bob missed.
        ...day(BOB, "2026-01-08", [1200], NY_WINTER),
        // The part-days, stuffed.
        bucket(BOB, "2026-01-05", 12, 50000, NY_WINTER),
        bucket(BOB, "2026-01-09", 2, 50000, NY_WINTER),
      ],
    },
    outcome: { kind: "winner", userId: ALICE, decidedBy: "sole_qualifier" },
    participants: {
      [ALICE]: { qualified: true, qualifyingDays: 3, scoreableDays: 3 },
      [BOB]: { qualified: false, qualifyingDays: 2, scoreableDays: 3 },
    },
    excluded: { partial_local_day: 2 },
  },

  {
    name: "fraud/a-bucket-carrying-two-local-days",
    why: "`contest_evidence` groups local_day rather than aggregating it precisely " +
      "so that a bucket which somehow acquired two arrives as two rows (D37). " +
      "The engine must refuse rather than pick one, because the row it picked " +
      "would decide a day's total and nobody could tell which it chose.",
    input: {
      timezoneChanges: [],
      contest: {
        id: "a0000015-0000-0000-0000-000000000015",
        metric: "steps",
        cadence: "daily",
        targetValue: 10000,
        tieBreak: "integrity_score",
        startsAt: "2026-01-05T00:00:00Z",
        endsAt: "2026-01-07T00:00:00Z",
      },
      roster: [accepted(ALICE, "UTC"), accepted(BOB, "UTC")],
      evidence: [
        bucket(ALICE, "2026-01-05", 8, 6000, UTC),
        { ...bucket(ALICE, "2026-01-05", 8, 6000, UTC), localDay: "2026-01-06" },
      ],
    },
    error: "carries two local days",
  },

  // -------------------------------------------------------------------------
  // Fraudulent: must work, and be visible
  // -------------------------------------------------------------------------
  {
    name: "fraud/an-implausible-single-hour-still-scores",
    why: "90,000 steps in one hour is not humanly possible and it scores as 90,000 " +
      "here. Plausibility is M5's, it needs a tuning parameter, and a scoring " +
      "engine that quietly discarded evidence would produce standings nobody " +
      "could audit. What the engine owes M5 is the aggregate that makes the " +
      "call: maxBucketValue carries the hour.",
    input: {
      timezoneChanges: [],
      contest: {
        id: "a0000016-0000-0000-0000-000000000016",
        metric: "steps",
        cadence: "cumulative",
        targetValue: 20000,
        tieBreak: "integrity_score",
        startsAt: "2026-01-05T00:00:00Z",
        endsAt: "2026-01-06T00:00:00Z",
      },
      roster: [accepted(ALICE, "UTC"), accepted(BOB, "UTC")],
      evidence: [
        bucket(ALICE, "2026-01-05", 8, 12000, UTC),
        bucket(BOB, "2026-01-05", 8, 90000, UTC, { sampleCount: 1 }),
      ],
    },
    outcome: { kind: "winner", userId: BOB, decidedBy: "sole_qualifier" },
    participants: {
      [BOB]: { qualified: true, total: 90000, maxBucketValue: 90000 },
      [ALICE]: { qualified: false, maxBucketValue: 12000 },
    },
  },

  {
    name: "fraud/a-bucket-first-reported-eleven-days-late-still-scores",
    why: "Late syncs are most syncs, so lateness cannot disqualify on its own — a " +
      "watch that syncs on Friday is the ordinary case, not an attack. But the " +
      "reporting lag is exactly what separates a late sync from a fabrication, " +
      "so it is surfaced: maxReportingLagMs is what M5's quarantine rule reads.",
    input: {
      timezoneChanges: [],
      contest: {
        id: "a0000017-0000-0000-0000-000000000017",
        metric: "steps",
        cadence: "cumulative",
        targetValue: 20000,
        tieBreak: "integrity_score",
        startsAt: "2026-01-05T00:00:00Z",
        endsAt: "2026-01-20T00:00:00Z",
      },
      roster: [accepted(ALICE, "UTC"), accepted(BOB, "UTC")],
      evidence: [
        bucket(ALICE, "2026-01-05", 8, 21000, UTC),
        bucket(BOB, "2026-01-05", 8, 21000, UTC, {
          reportedLateMs: 11 * 86_400_000,
        }),
      ],
    },
    outcome: {
      kind: "undecided",
      reason: "integrity_score_unavailable",
      tied: [ALICE, BOB],
    },
    participants: {
      [ALICE]: { qualified: true, maxReportingLagMs: 0 },
      [BOB]: { qualified: true, maxReportingLagMs: 11 * 86_400_000 },
    },
  },
];

/** Runs one fixture. Kept here so a future Swift port has the same entry point. */
export type FixtureRunner = (input: ScoringInput) => ContestScoring;
