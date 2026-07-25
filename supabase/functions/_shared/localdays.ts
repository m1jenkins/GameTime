/**
 * Which local days a contest window wholly covers, in a participant's frozen
 * zone.
 *
 * This is the one piece of timezone arithmetic the scoring engine does, and it
 * is deliberately the *only* piece. Day attribution for a measurement is not
 * computed here: M3 stamps `local_day` onto every ledger row from the
 * participant's frozen zone at insert, and D37 rejected recomputing it in the
 * engine precisely so that the engine and a dashboard cannot reach different
 * days from the same row. What the engine still has to work out for itself is
 * the *denominator* — the set of days a daily-cadence contest is asking about —
 * because that is a fact about the window and the zone, not about any row, and
 * a participant who submitted nothing would otherwise have a vacuously perfect
 * record.
 *
 * Only whole local days count. A participant whose offset does not line the
 * window up with their midnight loses a partial day at each end, which is the
 * same conservative direction D36 already chose one grain down for buckets: a
 * part-day cannot be fairly judged against a whole-day target, so it is dropped
 * from the numerator *and* the denominator rather than counted as a failure.
 *
 * The consequence, which is the point: two participants in different zones can
 * be asked about a different *number* of days from the same window. New York
 * and Kathmandu (+05:45) cannot both have whole local days inside one instant
 * range. Scoring therefore compares the *rate* at which each cleared the days
 * they were asked about, never the raw count — see `scoring.ts`.
 *
 * Only forward conversion is needed (instant → local wall clock), which
 * `Intl.DateTimeFormat` does directly against ICU's tzdata. The inverse
 * (local midnight → instant) is the awkward direction, and framing the question
 * as "which local calendar dates are whole" avoids needing it at all.
 */

/** A local wall-clock reading, with no offset attached. */
export interface LocalParts {
  readonly year: number;
  readonly month: number;
  readonly day: number;
  readonly hour: number;
  readonly minute: number;
  readonly second: number;
}

/** `YYYY-MM-DD`, matching what Postgres renders a `date` as. */
export type LocalDay = string;

/**
 * Thrown for a zone ICU does not know.
 *
 * M1 validates `contest_participants.timezone` against `pg_timezone_names`, so
 * a zone reaching here that ICU rejects means Postgres's tzdata and the
 * runtime's have diverged. That is worth failing loudly over: the quiet
 * alternative is scoring a daily contest against zero days, which reads as
 * "nobody qualified" and voids a contest people staked money on.
 */
export class UnknownTimeZoneError extends Error {
  override readonly name = "UnknownTimeZoneError";
  readonly timeZone: string;

  constructor(timeZone: string) {
    super(`unknown IANA time zone: ${timeZone}`);
    this.timeZone = timeZone;
  }
}

const FORMATTERS = new Map<string, Intl.DateTimeFormat>();

function formatterFor(timeZone: string): Intl.DateTimeFormat {
  const cached = FORMATTERS.get(timeZone);
  if (cached !== undefined) return cached;

  let formatter: Intl.DateTimeFormat;
  try {
    formatter = new Intl.DateTimeFormat("en-US", {
      timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      // Without this, midnight formats as hour 24 in some locales, and the
      // "does the window start exactly at midnight" test below would miss.
      hourCycle: "h23",
      era: "narrow",
    });
  } catch {
    throw new UnknownTimeZoneError(timeZone);
  }

  FORMATTERS.set(timeZone, formatter);
  return formatter;
}

/** Reads an instant as a local wall clock in `timeZone`. */
export function localPartsAt(instant: Date, timeZone: string): LocalParts {
  const parts = formatterFor(timeZone).formatToParts(instant);

  const field = (type: Intl.DateTimeFormatPartTypes): number => {
    const found = parts.find((p) => p.type === type);
    if (found === undefined) {
      throw new Error(`Intl gave no ${type} part for ${timeZone}`);
    }
    return Number(found.value);
  };

  const era = parts.find((p) => p.type === "era")?.value;
  const year = field("year");

  return {
    // `era` matters only for dates before year 1, which no contest window
    // reaches; it is requested so that a BC year cannot silently read as AD.
    year: era === "B" ? -(year - 1) : year,
    month: field("month"),
    day: field("day"),
    hour: field("hour"),
    minute: field("minute"),
    second: field("second"),
  };
}

/** `true` when the wall clock reads exactly 00:00:00. */
function isLocalMidnight(parts: LocalParts): boolean {
  return parts.hour === 0 && parts.minute === 0 && parts.second === 0;
}

/**
 * Civil dates are counted with UTC-based `Date` arithmetic. No zone is involved
 * — this is a calendar counter, and UTC is simply the arithmetic that has no
 * daylight-saving transitions to trip over.
 */
function civilDayNumber(parts: LocalParts): number {
  return Date.UTC(parts.year, parts.month - 1, parts.day) / 86_400_000;
}

function localDayFor(dayNumber: number): LocalDay {
  const at = new Date(dayNumber * 86_400_000);
  const year = at.getUTCFullYear();
  const month = at.getUTCMonth() + 1;
  const day = at.getUTCDate();
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${String(year).padStart(4, "0")}-${pad(month)}-${pad(day)}`;
}

/**
 * The local days `[startsAt, endsAt)` wholly covers in `timeZone`, ascending.
 *
 * A local day D is whole when local midnight of D is at or after `startsAt` and
 * local midnight of D+1 is at or before `endsAt`. Both tests reduce to reading
 * the wall clock at the two bounds:
 *
 *   - the first whole day is the start's local date when the start lands exactly
 *     on local midnight, and the day after it otherwise;
 *   - the last whole day is always the day *before* the end's local date, since
 *     a day cannot be whole unless the window reaches its following midnight.
 *
 * Returns `[]` for a window too short or too badly aligned to contain one, which
 * a caller must treat as "no days to ask about" rather than as a failed record.
 */
export function scoreableLocalDays(
  startsAt: Date,
  endsAt: Date,
  timeZone: string,
): readonly LocalDay[] {
  const start = localPartsAt(startsAt, timeZone);
  const end = localPartsAt(endsAt, timeZone);

  const firstDay = civilDayNumber(start) + (isLocalMidnight(start) ? 0 : 1);
  const lastDay = civilDayNumber(end) - 1;

  const days: LocalDay[] = [];
  for (let day = firstDay; day <= lastDay; day += 1) {
    days.push(localDayFor(day));
  }
  return days;
}
