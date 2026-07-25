import { assertEquals, assertThrows } from "@std/assert";
import { localPartsAt, scoreableLocalDays, UnknownTimeZoneError } from "./localdays.ts";

Deno.test("reads an instant as a local wall clock", () => {
  const parts = localPartsAt(new Date("2026-01-05T17:30:00Z"), "America/New_York");
  assertEquals(parts.year, 2026);
  assertEquals(parts.month, 1);
  assertEquals(parts.day, 5);
  assertEquals(parts.hour, 12);
  assertEquals(parts.minute, 30);
});

Deno.test("reads midnight as hour zero, not hour 24", () => {
  // With the default hour cycle some locales render midnight as 24, which would
  // make the "does the window start on local midnight" test silently false and
  // drop a whole day off the front of every contest.
  const parts = localPartsAt(new Date("2026-01-05T05:00:00Z"), "America/New_York");
  assertEquals(parts.hour, 0);
  assertEquals(parts.day, 5);
});

Deno.test("handles a zone that is not a whole number of hours from UTC", () => {
  const parts = localPartsAt(new Date("2026-01-05T05:00:00Z"), "Asia/Kathmandu");
  assertEquals(parts.hour, 10);
  assertEquals(parts.minute, 45);
  assertEquals(parts.day, 5);
});

Deno.test("a window of whole UTC days yields exactly those days", () => {
  const days = scoreableLocalDays(
    new Date("2026-01-05T00:00:00Z"),
    new Date("2026-01-08T00:00:00Z"),
    "UTC",
  );
  assertEquals(days, ["2026-01-05", "2026-01-06", "2026-01-07"]);
});

Deno.test("a window starting mid-day drops the part-day at each end", () => {
  const days = scoreableLocalDays(
    new Date("2026-01-05T13:00:00Z"),
    new Date("2026-01-08T13:00:00Z"),
    "UTC",
  );
  assertEquals(days, ["2026-01-06", "2026-01-07"]);
});

Deno.test("a fractional instant after midnight is still a part-day", () => {
  const days = scoreableLocalDays(
    new Date("2026-01-05T00:00:00.001Z"),
    new Date("2026-01-08T00:00:00Z"),
    "UTC",
  );
  assertEquals(days, ["2026-01-06", "2026-01-07"]);
});

Deno.test("whole New York days are not whole Kathmandu days", () => {
  // The asymmetry the whole design turns on. One instant range cannot be whole
  // local days in both a -05:00 zone and a +05:45 one, so the two participants
  // are asked about a different number of days and scoring has to compare rates.
  const start = new Date("2026-01-05T05:00:00Z"); // local midnight in New York
  const end = new Date("2026-01-12T05:00:00Z");

  const newYork = scoreableLocalDays(start, end, "America/New_York");
  const kathmandu = scoreableLocalDays(start, end, "Asia/Kathmandu");

  assertEquals(newYork.length, 7);
  assertEquals(newYork[0], "2026-01-05");
  assertEquals(newYork[6], "2026-01-11");

  assertEquals(kathmandu.length, 6);
  assertEquals(kathmandu[0], "2026-01-06");
  assertEquals(kathmandu[5], "2026-01-11");
});

Deno.test("a 23-hour spring-forward day is one whole day", () => {
  // 2026-03-08 is 23 hours long in New York. Counting whole days as calendar
  // dates rather than as multiples of 86,400 seconds is what gets this right.
  const days = scoreableLocalDays(
    new Date("2026-03-07T05:00:00Z"), // local midnight, EST
    new Date("2026-03-10T04:00:00Z"), // local midnight, EDT
    "America/New_York",
  );
  assertEquals(days, ["2026-03-07", "2026-03-08", "2026-03-09"]);
});

Deno.test("a 25-hour fall-back day is one whole day", () => {
  // 2026-11-01 is 25 hours long in New York.
  const days = scoreableLocalDays(
    new Date("2026-10-31T04:00:00Z"), // local midnight, EDT
    new Date("2026-11-03T05:00:00Z"), // local midnight, EST
    "America/New_York",
  );
  assertEquals(days, ["2026-10-31", "2026-11-01", "2026-11-02"]);
});

Deno.test("crosses a month and a year boundary", () => {
  const days = scoreableLocalDays(
    new Date("2025-12-30T00:00:00Z"),
    new Date("2026-01-02T00:00:00Z"),
    "UTC",
  );
  assertEquals(days, ["2025-12-30", "2025-12-31", "2026-01-01"]);
});

Deno.test("includes 29 February in a leap year", () => {
  const days = scoreableLocalDays(
    new Date("2028-02-28T00:00:00Z"),
    new Date("2028-03-01T00:00:00Z"),
    "UTC",
  );
  assertEquals(days, ["2028-02-28", "2028-02-29"]);
});

Deno.test("a window too short to contain a whole local day yields none", () => {
  const days = scoreableLocalDays(
    new Date("2026-01-05T13:00:00Z"),
    new Date("2026-01-06T09:00:00Z"),
    "UTC",
  );
  assertEquals(days, []);
});

Deno.test("a window of exactly one whole day yields that day", () => {
  const days = scoreableLocalDays(
    new Date("2026-01-05T00:00:00Z"),
    new Date("2026-01-06T00:00:00Z"),
    "UTC",
  );
  assertEquals(days, ["2026-01-05"]);
});

Deno.test("an unknown zone raises rather than yielding no days", () => {
  // The quiet failure this exists to prevent: zero scoreable days reads as
  // "nobody qualified", which would void a contest people staked money on.
  assertThrows(
    () =>
      scoreableLocalDays(
        new Date("2026-01-05T00:00:00Z"),
        new Date("2026-01-08T00:00:00Z"),
        "Mars/Olympus_Mons",
      ),
    UnknownTimeZoneError,
    "unknown IANA time zone",
  );
});
