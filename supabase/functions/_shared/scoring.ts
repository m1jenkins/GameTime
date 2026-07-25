/**
 * The scoring engine. One implementation, and this is it (D3).
 *
 * A pure function from contest terms, the accepted roster, and the rows of
 * `contest_evidence` to standings and an outcome. No I/O, no clock, no
 * randomness: the same inputs give the same answer forever, which is what lets
 * a disputed contest be re-scored years later and lets the fixture corpus in
 * `_test/scoring_fixtures.ts` be the specification rather than a smoke test.
 *
 * ---------------------------------------------------------------------------
 * What decides a contest
 * ---------------------------------------------------------------------------
 * A contest is pass/fail against its own terms, and the comparison is between
 * those who passed. This is what the cadence enum already says it is:
 * `'daily'` means hit the target on each day of the window, `'cumulative'`
 * means hit it once across the whole window. Neither says "whoever did the
 * most", and the difference matters because the loser's obligation is real
 * money — a participant who did not do the thing they staked a donation on
 * should not collect one from a friend who also did not.
 *
 * So:
 *
 *   1. Every accepted participant either *qualified* or did not.
 *   2. Exactly one qualified  → that participant wins.
 *   3. Several qualified      → a tie, resolved by `contests.tie_break`.
 *   4. Nobody qualified       → void. Nobody donates.
 *
 * Ties being the *ordinary* case rather than a rare edge is why `tie_break` is
 * declared at contest creation and defaults to something (D22): in a duel where
 * both friends walk their 10,000 steps every day, the tie-break is the whole
 * settlement, not a footnote.
 *
 * Standings are still fully ordered, because a client has to render a
 * leaderboard while a contest is live. Ordering and deciding are kept apart on
 * purpose: the display order falls back to user id to stay stable, and the
 * *outcome* never does. Settling a money pledge by whose UUID sorts lower would
 * be indefensible, so a tie the declared tie-break cannot separate comes back
 * as `undecided` rather than as a winner.
 *
 * ---------------------------------------------------------------------------
 * Qualifying
 * ---------------------------------------------------------------------------
 * `cumulative` — the total over the window reaches `target_value`.
 *
 * `daily` — every whole local day the window covers reached `target_value`.
 * Whole local days only, and the *rate* is what ranks, never the raw count:
 * see `localdays.ts` for why two participants can be asked about a different
 * number of days from the same window, and why counting days rather than
 * rating them would make a Kathmandu participant unable to beat a New York one.
 *
 * ---------------------------------------------------------------------------
 * What this engine deliberately does not judge
 * ---------------------------------------------------------------------------
 * Admissibility is settled before the engine sees a row: `contest_evidence`
 * filters `is_admissible` and reduces revisions, so hand-typed values are
 * already gone and a late sync has already been collapsed to one figure (D35,
 * D38). The engine must not second-guess that, because two definitions of "the
 * value for this hour" is exactly the drift D3 exists to prevent.
 *
 * Nor does it flag: 90,000 steps in one hour scores as 90,000 here. Plausibility
 * is M5's, it needs a tuning parameter, and a scoring engine that quietly
 * discarded evidence would produce standings nobody could audit. What this does
 * instead is carry an `evidence` summary per participant — bucket counts, the
 * largest single hour, the worst reporting lag — so M5 has the aggregates it
 * needs without re-reducing the ledger.
 *
 * The one thing it will refuse outright is a ledger that contradicts itself; see
 * `ScoringError`.
 */

import { type LocalDay, scoreableLocalDays } from "./localdays.ts";

// ---------------------------------------------------------------------------
// Domain types, mirroring the schema
// ---------------------------------------------------------------------------

export type ContestMetric =
  | "steps"
  | "distance_meters"
  | "active_energy_kcal"
  | "exercise_minutes";

export type ContestCadence = "daily" | "cumulative";

export type ContestTieBreak =
  | "integrity_score"
  | "earliest_to_target"
  | "both_donate"
  | "void";

export type ParticipantStatus =
  | "invited"
  | "accepted"
  | "declined"
  | "withdrawn"
  | "lapsed";

/**
 * A numeric column as it arrives over the wire.
 *
 * PostgREST renders `numeric` as a JSON number by default and as a string when
 * configured to preserve precision. Both are accepted so that a deployment
 * setting cannot change who wins.
 */
export type NumericValue = number | string;

/** The frozen terms. `contests`, minus the columns scoring has no use for. */
export interface ContestTerms {
  readonly id: string;
  readonly metric: ContestMetric;
  readonly cadence: ContestCadence;
  readonly targetValue: NumericValue;
  readonly tieBreak: ContestTieBreak;
  /** ISO instants. The window is half-open: `[startsAt, endsAt)`. */
  readonly startsAt: string;
  readonly endsAt: string;
}

/** One row of `contest_participants`. */
export interface RosterEntry {
  readonly userId: string;
  readonly status: ParticipantStatus;
  /** IANA zone, frozen at join (D5). */
  readonly timezone: string;
  readonly charityId: string | null;
}

/** One row of `contest_evidence` — the current admissible figure for a bucket. */
export interface EvidenceBucket {
  readonly userId: string;
  readonly metric: ContestMetric;
  /** ISO instant, aligned to a whole hour in the participant's zone (D36). */
  readonly bucketStart: string;
  /** `YYYY-MM-DD`, stamped by the server from the applicable zone epoch (D37/D62). */
  readonly localDay: LocalDay;
  readonly localHour: number;
  readonly value: NumericValue;
  readonly sampleCount: number;
  readonly observationCount: number;
  readonly firstRecordedAt: string;
  readonly lastRecordedAt: string;
}

/**
 * One approved timezone change, applied prospectively during the contest.
 *
 * `RosterEntry.timezone` remains the participant's initial zone. These events
 * form a chronological chain from that base zone.
 */
export interface TimezoneChange {
  readonly userId: string;
  readonly fromTimezone: string;
  readonly toTimezone: string;
  /** ISO instant strictly inside the contest window. */
  readonly effectiveAt: string;
}

export interface ScoringInput {
  readonly contest: ContestTerms;
  readonly roster: readonly RosterEntry[];
  readonly evidence: readonly EvidenceBucket[];
  /**
   * The complete applied timezone-change ledger for this contest.
   *
   * Callers must provide this even when it is empty: silently treating an
   * omitted ledger as "no changes" could score an incomplete snapshot.
   */
  readonly timezoneChanges: readonly TimezoneChange[];
  /**
   * Integrity scores keyed by user id, supplied by M5's integrity assessor.
   *
   * Still optional because the M4 engine is independently reusable. A bare
   * caller gets `undecided` rather than a guess — see `resolveTie`.
   */
  readonly integrityScores?: Readonly<Record<string, number>>;
}

// ---------------------------------------------------------------------------
// Output
// ---------------------------------------------------------------------------

export type ExclusionReason =
  /** A metric the contest does not score. The ledger carries others for M5. */
  | "other_metric"
  /** Outside `[startsAt, endsAt)`. */
  | "outside_window"
  /** In a part-day at a window edge, which daily cadence does not ask about. */
  | "partial_local_day"
  /** The hour crosses an applied timezone change and belongs to neither epoch. */
  | "timezone_transition"
  /** Not on the accepted roster. */
  | "unscored_participant";

/** Aggregates M5 reads, so it does not have to reduce the ledger a second time. */
export interface EvidenceSummary {
  readonly bucketCount: number;
  readonly sampleCount: number;
  readonly observationCount: number;
  /** The largest single hour. A plausibility signal, not a verdict. */
  readonly maxBucketValue: number;
  /**
   * Worst gap between the end of a bucket and the last time it was reported,
   * in milliseconds. What M5's quarantine rule for retroactive samples reads.
   */
  readonly maxReportingLagMs: number;
}

export interface DayStanding {
  readonly localDay: LocalDay;
  /** The timezone epoch in which this civil day was scored. */
  readonly timezone: string;
  readonly value: number;
  readonly qualified: boolean;
  /** When this day's target was crossed, or `null` if it was not. */
  readonly reachedTargetAt: string | null;
  readonly bucketCount: number;
}

export interface ParticipantStanding {
  readonly userId: string;
  /** Competition ranking: equal scores share a rank and the next one skips. */
  readonly rank: number;
  readonly qualified: boolean;
  /** Total over every scored bucket. */
  readonly total: number;
  /** Daily cadence only; `0` for cumulative. */
  readonly qualifyingDays: number;
  readonly scoreableDays: number;
  /** `qualifyingDays / scoreableDays`, or `0` when there are none to ask about. */
  readonly dayRate: number;
  /** When the contest's goal was fully satisfied, or `null`. */
  readonly reachedTargetAt: string | null;
  /** Per-day breakdown, ascending. Empty for cumulative. */
  readonly days: readonly DayStanding[];
  readonly evidence: EvidenceSummary;
}

export type Outcome =
  | {
    readonly kind: "winner";
    readonly userId: string;
    readonly decidedBy: "sole_qualifier" | "earliest_to_target" | "integrity_score";
  }
  /** `both_donate`: every tied participant donates to their own nomination. */
  | { readonly kind: "all_donate"; readonly userIds: readonly string[] }
  | {
    readonly kind: "void";
    readonly reason: "insufficient_participants" | "no_qualifying_participant" | "tie_break_void";
  }
  /**
   * Not settleable yet, and deliberately not guessed at. M7's finaliser must
   * refuse to settle this rather than pick someone.
   */
  | {
    readonly kind: "undecided";
    readonly reason: "integrity_score_unavailable" | "tie_break_inconclusive";
    readonly tied: readonly string[];
  };

export interface ContestScoring {
  readonly contestId: string;
  readonly metric: ContestMetric;
  readonly cadence: ContestCadence;
  readonly target: number;
  /** Ranked. Ordering is for display; it never decides the outcome. */
  readonly standings: readonly ParticipantStanding[];
  readonly outcome: Outcome;
  readonly excluded: Readonly<Record<ExclusionReason, number>>;
}

/**
 * A ledger that contradicts itself.
 *
 * Not a refusal a client can cause and not a scoring result — it means an
 * invariant `contest_evidence` is supposed to guarantee did not hold, and the
 * honest response is to stop rather than to score one of the two readings and
 * call it the answer.
 */
export class ScoringError extends Error {
  override readonly name = "ScoringError";

  constructor(message: string) {
    super(message);
  }
}

// ---------------------------------------------------------------------------
// Exact arithmetic
// ---------------------------------------------------------------------------
// Every measurement and target is `numeric(12, 2)`, so all of them are whole
// hundredths. Summing them as IEEE doubles is close enough almost always and
// wrong occasionally — 0.1 + 0.2 is the famous case, and `exercise_minutes`
// and `distance_meters` are exactly the columns carrying fractional values.
// Scoring in integer hundredths makes a total exact and, more importantly,
// makes `total >= target` exact: a participant landing precisely on their
// target must qualify, and with float summation that is a coin toss.
//
// 12 digits of precision is at most 1e12 hundredths, comfortably inside the
// 2^53 range where integer arithmetic on doubles is exact.

const SCALE = 100;

function toHundredths(value: NumericValue, field: string): number {
  const asNumber = typeof value === "string" ? Number(value) : value;

  if (typeof asNumber !== "number" || !Number.isFinite(asNumber)) {
    throw new ScoringError(`${field} is not a finite number: ${JSON.stringify(value)}`);
  }

  const scaled = Math.round(asNumber * SCALE);
  if (!Number.isSafeInteger(scaled)) {
    throw new ScoringError(`${field} is outside the representable range: ${asNumber}`);
  }

  // A third decimal place cannot come from `numeric(12, 2)`, so it means the
  // caller is not reading the column it thinks it is.
  if (Math.abs(asNumber * SCALE - scaled) > 1e-6) {
    throw new ScoringError(`${field} has more than two decimal places: ${asNumber}`);
  }

  return scaled;
}

function fromHundredths(hundredths: number): number {
  return hundredths / SCALE;
}

function instantOf(iso: string, field: string): number {
  const at = Date.parse(iso);
  if (Number.isNaN(at)) {
    throw new ScoringError(`${field} is not an instant: ${JSON.stringify(iso)}`);
  }
  return at;
}

/** A bucket covers `[bucketStart, +1 hour)` — an instant span, so DST-proof. */
const BUCKET_MS = 3_600_000;

// ---------------------------------------------------------------------------
// Scoring
// ---------------------------------------------------------------------------

interface PreparedTimezoneChange {
  readonly change: TimezoneChange;
  readonly effectiveAt: number;
  readonly inputIndex: number;
}

interface TimezoneEpoch {
  readonly index: number;
  readonly startsAt: number;
  readonly endsAt: number;
  readonly timezone: string;
}

interface ScoreableEpochDay {
  readonly key: string;
  readonly localDay: LocalDay;
  readonly timezone: string;
}

/**
 * Validates accepted participants' applied events and turns them into
 * prospective, non-overlapping timezone epochs. Changes for everybody else are
 * deliberately ignored: they cannot affect standings or integrity.
 */
function timezoneEpochsByParticipant(
  scored: readonly RosterEntry[],
  changes: readonly TimezoneChange[],
  windowStart: number,
  windowEnd: number,
): ReadonlyMap<string, readonly TimezoneEpoch[]> {
  const accepted = new Map(scored.map((entry) => [entry.userId, entry]));
  const byParticipant = new Map<string, PreparedTimezoneChange[]>();
  for (const entry of scored) byParticipant.set(entry.userId, []);

  changes.forEach((change, inputIndex) => {
    const participantChanges = byParticipant.get(change.userId);
    if (participantChanges === undefined) return;

    const effectiveAt = instantOf(
      change.effectiveAt,
      `timezoneChanges[${inputIndex}].effectiveAt`,
    );
    if (effectiveAt <= windowStart || effectiveAt >= windowEnd) {
      throw new ScoringError(
        `timezoneChanges[${inputIndex}].effectiveAt must be strictly inside the contest window`,
      );
    }
    if (change.fromTimezone === change.toTimezone) {
      throw new ScoringError(
        `timezoneChanges[${inputIndex}] must change to a distinct timezone`,
      );
    }

    participantChanges.push({ change, effectiveAt, inputIndex });
  });

  const epochsByParticipant = new Map<string, readonly TimezoneEpoch[]>();
  for (const [userId, participantChanges] of byParticipant) {
    participantChanges.sort((a, b) => a.effectiveAt - b.effectiveAt);
    const participant = accepted.get(userId);
    if (participant === undefined) continue;

    let expectedFrom = participant.timezone;
    let epochStart = windowStart;
    const epochs: TimezoneEpoch[] = [];

    participantChanges.forEach((prepared, index) => {
      const previous = participantChanges[index - 1];
      if (previous !== undefined && prepared.effectiveAt <= previous.effectiveAt) {
        throw new ScoringError(
          `timezone changes for ${userId} must have strictly increasing effectiveAt instants`,
        );
      }
      if (prepared.change.fromTimezone !== expectedFrom) {
        throw new ScoringError(
          `timezoneChanges[${prepared.inputIndex}].fromTimezone must be ${
            JSON.stringify(expectedFrom)
          }`,
        );
      }

      epochs.push({
        index,
        startsAt: epochStart,
        endsAt: prepared.effectiveAt,
        timezone: expectedFrom,
      });
      epochStart = prepared.effectiveAt;
      expectedFrom = prepared.change.toTimezone;
    });

    epochs.push({
      index: participantChanges.length,
      startsAt: epochStart,
      endsAt: windowEnd,
      timezone: expectedFrom,
    });
    epochsByParticipant.set(userId, epochs);
  }

  return epochsByParticipant;
}

function epochDayKey(epochIndex: number, localDay: LocalDay): string {
  return `${epochIndex}\u0000${localDay}`;
}

interface PreparedBucket {
  readonly startsAt: number;
  readonly endsAt: number;
  readonly epochIndex: number;
  readonly localDay: LocalDay;
  readonly hundredths: number;
  readonly sampleCount: number;
  readonly observationCount: number;
  readonly reportingLagMs: number;
}

function summarise(buckets: readonly PreparedBucket[]): EvidenceSummary {
  let sampleCount = 0;
  let observationCount = 0;
  let maxBucketHundredths = 0;
  let maxReportingLagMs = 0;

  for (const bucket of buckets) {
    sampleCount += bucket.sampleCount;
    observationCount += bucket.observationCount;
    if (bucket.hundredths > maxBucketHundredths) maxBucketHundredths = bucket.hundredths;
    if (bucket.reportingLagMs > maxReportingLagMs) maxReportingLagMs = bucket.reportingLagMs;
  }

  return {
    bucketCount: buckets.length,
    sampleCount,
    observationCount,
    maxBucketValue: fromHundredths(maxBucketHundredths),
    maxReportingLagMs,
  };
}

/**
 * Walks buckets in order and returns the end of the bucket that took the running
 * total to `target`, or `null`.
 *
 * The bucket's *end* rather than its start: the hour is the finest grain the
 * ledger records, so the earliest instant at which the target is provably
 * reached is the moment that hour closed. Claiming the start would date an
 * achievement to before the evidence for it exists.
 */
function crossingInstant(
  buckets: readonly PreparedBucket[],
  targetHundredths: number,
): number | null {
  let running = 0;
  for (const bucket of buckets) {
    running += bucket.hundredths;
    if (running >= targetHundredths) return bucket.endsAt;
  }
  return null;
}

function sumHundredths(buckets: readonly PreparedBucket[]): number {
  let total = 0;
  for (const bucket of buckets) total += bucket.hundredths;
  return total;
}

export function scoreContest(input: ScoringInput): ContestScoring {
  const { contest, roster, evidence, timezoneChanges } = input;
  if (!Array.isArray(timezoneChanges)) {
    throw new ScoringError("timezoneChanges must be supplied as an array");
  }

  const windowStart = instantOf(contest.startsAt, "contest.startsAt");
  const windowEnd = instantOf(contest.endsAt, "contest.endsAt");
  if (windowEnd <= windowStart) {
    throw new ScoringError("contest.endsAt is not after contest.startsAt");
  }

  const targetHundredths = toHundredths(contest.targetValue, "contest.targetValue");
  if (targetHundredths <= 0) {
    throw new ScoringError("contest.targetValue must be positive");
  }

  // Only accepted participants score. `invited`, `declined`, `withdrawn` and
  // `lapsed` are all on the roster for M7's reliability score to read, and none
  // of them agreed to a stake that is still live.
  const scored = roster.filter((entry) => entry.status === "accepted");
  const timezoneEpochs = timezoneEpochsByParticipant(
    scored,
    timezoneChanges,
    windowStart,
    windowEnd,
  );

  const excluded: Record<ExclusionReason, number> = {
    other_metric: 0,
    outside_window: 0,
    partial_local_day: 0,
    timezone_transition: 0,
    unscored_participant: 0,
  };

  // Scoreable days per participant and timezone epoch. An applied change cuts
  // both adjoining local days at the transition instant; asking each epoch for
  // whole days drops those partial edges naturally.
  const scoreable = new Map<string, readonly ScoreableEpochDay[]>();
  const scoreableSet = new Map<string, Set<string>>();
  for (const entry of scored) {
    const days: ScoreableEpochDay[] = [];
    if (contest.cadence === "daily") {
      for (const epoch of timezoneEpochs.get(entry.userId) ?? []) {
        for (
          const localDay of scoreableLocalDays(
            new Date(epoch.startsAt),
            new Date(epoch.endsAt),
            epoch.timezone,
          )
        ) {
          days.push({
            key: epochDayKey(epoch.index, localDay),
            localDay,
            timezone: epoch.timezone,
          });
        }
      }
    }
    scoreable.set(entry.userId, days);
    scoreableSet.set(entry.userId, new Set(days.map((day) => day.key)));
  }

  const byParticipant = new Map<string, PreparedBucket[]>();
  for (const entry of scored) byParticipant.set(entry.userId, []);

  // One local day per bucket, asserted rather than assumed. `contest_evidence`
  // groups `local_day` instead of aggregating it precisely so that a bucket
  // which somehow acquired two of them arrives as two rows (D37). Picking one
  // here would hide it, and the row it picked would decide a day's total.
  const seenLocalDay = new Map<string, LocalDay>();

  for (const row of evidence) {
    const buckets = byParticipant.get(row.userId);
    if (buckets === undefined) {
      excluded.unscored_participant += 1;
      continue;
    }

    if (row.metric !== contest.metric) {
      excluded.other_metric += 1;
      continue;
    }

    const startsAt = instantOf(row.bucketStart, "evidence.bucketStart");
    const endsAt = startsAt + BUCKET_MS;

    // Whole buckets only, and the ledger already refuses anything else at write
    // time (D43). Filtering again is not redundant: this engine is also what
    // re-scores a disputed contest from a ledger a later migration or backfill
    // may have touched, and standings that disagree with the contest's own
    // window would be indefensible in exactly that argument.
    if (startsAt < windowStart || endsAt > windowEnd) {
      excluded.outside_window += 1;
      continue;
    }

    const key = `${row.userId} ${row.metric} ${row.bucketStart}`;
    const previous = seenLocalDay.get(key);
    if (previous !== undefined && previous !== row.localDay) {
      throw new ScoringError(
        `bucket ${row.bucketStart} for ${row.userId} carries two local days: ` +
          `${previous} and ${row.localDay}`,
      );
    }
    seenLocalDay.set(key, row.localDay);

    const epoch = timezoneEpochs.get(row.userId)?.find(
      (candidate) => startsAt >= candidate.startsAt && endsAt <= candidate.endsAt,
    );
    if (epoch === undefined) {
      excluded.timezone_transition += 1;
      continue;
    }

    if (
      contest.cadence === "daily" &&
      scoreableSet.get(row.userId)?.has(epochDayKey(epoch.index, row.localDay)) !== true
    ) {
      excluded.partial_local_day += 1;
      continue;
    }

    const lastRecordedAt = instantOf(row.lastRecordedAt, "evidence.lastRecordedAt");

    buckets.push({
      startsAt,
      endsAt,
      epochIndex: epoch.index,
      localDay: row.localDay,
      hundredths: toHundredths(row.value, "evidence.value"),
      sampleCount: row.sampleCount,
      observationCount: row.observationCount,
      // Negative for a bucket reported before it closed, which is ordinary for
      // a live sync; clamped, because "reported early" is not a lag.
      reportingLagMs: Math.max(0, lastRecordedAt - endsAt),
    });
  }

  const standings: ParticipantStanding[] = scored.map((entry) => {
    const buckets = (byParticipant.get(entry.userId) ?? []).slice()
      .sort((a, b) => a.startsAt - b.startsAt);

    const totalHundredths = sumHundredths(buckets);
    const summary = summarise(buckets);

    if (contest.cadence === "cumulative") {
      const reachedAt = crossingInstant(buckets, targetHundredths);
      return {
        userId: entry.userId,
        rank: 0,
        qualified: totalHundredths >= targetHundredths,
        total: fromHundredths(totalHundredths),
        qualifyingDays: 0,
        scoreableDays: 0,
        dayRate: 0,
        reachedTargetAt: reachedAt === null ? null : new Date(reachedAt).toISOString(),
        days: [],
        evidence: summary,
      };
    }

    const days = scoreable.get(entry.userId) ?? [];
    const bucketsByDay = new Map<string, PreparedBucket[]>();
    for (const bucket of buckets) {
      const key = epochDayKey(bucket.epochIndex, bucket.localDay);
      const existing = bucketsByDay.get(key);
      if (existing === undefined) bucketsByDay.set(key, [bucket]);
      else existing.push(bucket);
    }

    const dayStandings: DayStanding[] = days.map((day) => {
      const dayBuckets = bucketsByDay.get(day.key) ?? [];
      const dayHundredths = sumHundredths(dayBuckets);
      const reachedAt = crossingInstant(dayBuckets, targetHundredths);
      return {
        localDay: day.localDay,
        timezone: day.timezone,
        value: fromHundredths(dayHundredths),
        qualified: dayHundredths >= targetHundredths,
        reachedTargetAt: reachedAt === null ? null : new Date(reachedAt).toISOString(),
        bucketCount: dayBuckets.length,
      };
    });

    const qualifyingDays = dayStandings.filter((day) => day.qualified).length;
    const scoreableDays = days.length;

    // A perfect record over no days is not a perfect record. Only reachable
    // for a window too short or too badly aligned to hold one whole local day,
    // which M2's `contests_daily_needs_a_day` check makes unlikely and does not
    // make impossible for a non-whole-hour zone.
    const qualified = scoreableDays > 0 && qualifyingDays === scoreableDays;

    // The goal completes when the last day does, so the whole-contest instant
    // is the latest of the per-day crossings.
    let reachedTargetAt: string | null = null;
    if (qualified) {
      let latest = 0;
      for (const day of dayStandings) {
        const at = day.reachedTargetAt === null ? 0 : Date.parse(day.reachedTargetAt);
        if (at > latest) latest = at;
      }
      reachedTargetAt = latest === 0 ? null : new Date(latest).toISOString();
    }

    return {
      userId: entry.userId,
      rank: 0,
      qualified,
      total: fromHundredths(totalHundredths),
      qualifyingDays,
      scoreableDays,
      dayRate: scoreableDays === 0 ? 0 : qualifyingDays / scoreableDays,
      reachedTargetAt,
      days: dayStandings,
      evidence: summary,
    };
  });

  const ranked = rank(standings, contest.cadence);

  return {
    contestId: contest.id,
    metric: contest.metric,
    cadence: contest.cadence,
    target: fromHundredths(targetHundredths),
    standings: ranked,
    outcome: decide(ranked, contest, input.integrityScores),
    excluded,
  };
}

/**
 * Orders standings for display and assigns competition ranks.
 *
 * The final key is the user id, which makes the order stable and reproducible
 * for a leaderboard. It is *only* a display tiebreak: `decide` never consults
 * the ordering, so nothing about who owes money turns on a UUID.
 */
function rank(
  standings: readonly ParticipantStanding[],
  cadence: ContestCadence,
): readonly ParticipantStanding[] {
  const ordering = (a: ParticipantStanding, b: ParticipantStanding): number => {
    if (cadence === "daily" && a.dayRate !== b.dayRate) return b.dayRate - a.dayRate;
    if (a.total !== b.total) return b.total - a.total;

    // Whoever got there first shows higher among otherwise equal scores.
    const aReached = a.reachedTargetAt === null ? Infinity : Date.parse(a.reachedTargetAt);
    const bReached = b.reachedTargetAt === null ? Infinity : Date.parse(b.reachedTargetAt);
    if (aReached !== bReached) return aReached - bReached;

    return a.userId < b.userId ? -1 : a.userId > b.userId ? 1 : 0;
  };

  const sorted = standings.slice().sort(ordering);

  const sameScore = (a: ParticipantStanding, b: ParticipantStanding): boolean =>
    (cadence !== "daily" || a.dayRate === b.dayRate) && a.total === b.total;

  const ranks: ParticipantStanding[] = [];
  let currentRank = 0;
  sorted.forEach((standing, index) => {
    const previous = index === 0 ? undefined : sorted[index - 1];
    if (previous === undefined || !sameScore(previous, standing)) currentRank = index + 1;
    ranks.push({ ...standing, rank: currentRank });
  });
  return ranks;
}

function decide(
  standings: readonly ParticipantStanding[],
  contest: ContestTerms,
  integrityScores: Readonly<Record<string, number>> | undefined,
): Outcome {
  // A contest is a comparison and there is nothing to compare one person
  // against. D30 makes activation refuse a quorum of one, so reaching here
  // means something upstream went wrong; scoring it anyway would invent a
  // winner out of a contest with no meaning.
  if (standings.length < 2) {
    return { kind: "void", reason: "insufficient_participants" };
  }

  const qualifiers = standings.filter((standing) => standing.qualified);

  if (qualifiers.length === 0) {
    return { kind: "void", reason: "no_qualifying_participant" };
  }

  const sole = qualifiers[0];
  if (qualifiers.length === 1 && sole !== undefined) {
    return { kind: "winner", userId: sole.userId, decidedBy: "sole_qualifier" };
  }

  return resolveTie(qualifiers, contest.tieBreak, integrityScores);
}

function resolveTie(
  qualifiers: readonly ParticipantStanding[],
  tieBreak: ContestTieBreak,
  integrityScores: Readonly<Record<string, number>> | undefined,
): Outcome {
  const tied = qualifiers.map((standing) => standing.userId);

  switch (tieBreak) {
    case "void":
      return { kind: "void", reason: "tie_break_void" };

    case "both_donate":
      // Named for the duel it was designed around; with more than two
      // qualifiers every one of them donates, each to their own nomination.
      return { kind: "all_donate", userIds: tied };

    case "earliest_to_target":
      return byEarliest(qualifiers, tied);

    case "integrity_score":
      return byIntegrity(qualifiers, tied, integrityScores);
  }
}

function byEarliest(
  qualifiers: readonly ParticipantStanding[],
  tied: readonly string[],
): Outcome {
  let best: ParticipantStanding | undefined;
  let bestAt = Infinity;
  let drawn = false;

  for (const standing of qualifiers) {
    // A qualifier always has a crossing instant; the guard keeps a malformed
    // standing from reading as "reached the target at the epoch".
    if (standing.reachedTargetAt === null) continue;
    const at = Date.parse(standing.reachedTargetAt);
    if (at < bestAt) {
      bestAt = at;
      best = standing;
      drawn = false;
    } else if (at === bestAt) {
      drawn = true;
    }
  }

  if (best === undefined || drawn) {
    // The ledger's finest grain is an hour, so two people finishing in the same
    // bucket is an ordinary outcome rather than a freak one. There is no
    // further evidence to appeal to, and inventing one would be arbitrary.
    return { kind: "undecided", reason: "tie_break_inconclusive", tied };
  }

  return { kind: "winner", userId: best.userId, decidedBy: "earliest_to_target" };
}

function byIntegrity(
  qualifiers: readonly ParticipantStanding[],
  tied: readonly string[],
  integrityScores: Readonly<Record<string, number>> | undefined,
): Outcome {
  // M5 owns the number. A bare M4 caller may still omit it, and the three wrong
  // answers are all worse than saying so: picking the higher total silently
  // substitutes a different tie-break than the one the participants agreed to
  // at creation, voiding cancels a contest somebody won, and ordering by user id
  // settles money by UUID.
  if (integrityScores === undefined) {
    return { kind: "undecided", reason: "integrity_score_unavailable", tied };
  }

  let best: ParticipantStanding | undefined;
  let bestScore = -Infinity;
  let drawn = false;

  for (const standing of qualifiers) {
    const score = integrityScores[standing.userId];
    if (score === undefined) {
      return { kind: "undecided", reason: "integrity_score_unavailable", tied };
    }
    if (score > bestScore) {
      bestScore = score;
      best = standing;
      drawn = false;
    } else if (score === bestScore) {
      drawn = true;
    }
  }

  if (best === undefined || drawn) {
    return { kind: "undecided", reason: "tie_break_inconclusive", tied };
  }

  return { kind: "winner", userId: best.userId, decidedBy: "integrity_score" };
}
