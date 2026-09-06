import { assertEquals, assertThrows } from "@std/assert";
import { previewOptionalReminder, type ReminderPreferences } from "./engagement-preview.ts";

const at = (value: string) => Date.parse(value);
function fixture() {
  const nowMs = at("2026-09-09T17:00:00Z");
  const preferences: ReminderPreferences = {
    actorId: "actor-a",
    timezone: "America/Chicago",
    categories: { invitation: false, requested_goal: false, selected_friend: false },
    quietStartHour: 21,
    quietEndHour: 9,
    dailyCap: 1,
    weeklyCap: 3,
  };
  return {
    nowMs,
    currentActorId: "actor-a" as string | null,
    currentAccess: true,
    preferences,
    candidate: {
      actorId: "actor-a",
      eventId: "event-a",
      destinationId: "challenge-a",
      category: "requested_goal" as const,
      createdAtMs: nowMs - 1000,
      expiresAtMs: nowMs + 1000,
    },
    receipts: [] as { actorId: string; eventId: string; recordedAtMs: number }[],
  };
}
function optedIn() {
  const f = fixture();
  f.preferences.categories.requested_goal = true;
  return f;
}
Deno.test("all optional categories begin off and every decision keeps delivery disabled", () => {
  const f = fixture();
  assertEquals(previewOptionalReminder(f), {
    status: "suppressed",
    reason: "category_off",
    deliveryEnabled: false,
  });
  f.preferences.categories.requested_goal = true;
  assertEquals(previewOptionalReminder(f), {
    status: "eligible_for_local_preview",
    reason: null,
    deliveryEnabled: false,
  });
});
for (const actor of [null, "actor-b"]) {
  Deno.test(`signed out or switched actor ${actor} cannot resolve a destination`, () => {
    const f = optedIn();
    f.currentActorId = actor;
    assertEquals(previewOptionalReminder(f).reason, "signed_out");
  });
}
Deno.test("block, sharing revocation or expired access suppresses a saved event", () => {
  const f = optedIn();
  f.currentAccess = false;
  assertEquals(previewOptionalReminder(f).reason, "no_current_access");
});
Deno.test("fresh category revocation suppresses even a previously requested reminder", () => {
  const f = optedIn();
  f.preferences.categories.requested_goal = false;
  assertEquals(previewOptionalReminder(f).reason, "category_off");
});
Deno.test("expiry equality and replay are suppressed", () => {
  const f = optedIn();
  f.candidate.expiresAtMs = f.nowMs;
  assertEquals(previewOptionalReminder(f).reason, "obsolete");
  f.candidate.expiresAtMs += 1;
  f.receipts.push({ actorId: "actor-a", eventId: "event-a", recordedAtMs: f.nowMs - 1 });
  assertEquals(previewOptionalReminder(f).reason, "duplicate");
});
for (
  const [hour, reason] of [[8, "quiet_hours"], [9, null], [20, null], [21, "quiet_hours"]] as const
) {
  Deno.test(`quiet-hour boundary ${hour}`, () => {
    const f = optedIn();
    f.nowMs = at(`2026-09-09T${String(hour).padStart(2, "0")}:00:00Z`);
    f.preferences.timezone = "UTC";
    f.candidate.createdAtMs = f.nowMs - 1;
    f.candidate.expiresAtMs = f.nowMs + 1;
    assertEquals(previewOptionalReminder(f).reason, reason);
  });
}
Deno.test("timezone change recomputes quiet hours", () => {
  const f = optedIn();
  assertEquals(previewOptionalReminder(f).reason, null);
  f.preferences.timezone = "Asia/Tokyo";
  assertEquals(previewOptionalReminder(f).reason, "quiet_hours");
});
Deno.test("daily cap includes every optional category and zero is an immediate mute", () => {
  const f = optedIn();
  f.receipts.push({ actorId: "actor-a", eventId: "prior", recordedAtMs: f.nowMs - 100 });
  assertEquals(previewOptionalReminder(f).reason, "daily_cap");
  f.receipts = [];
  f.preferences.dailyCap = 0;
  assertEquals(previewOptionalReminder(f).reason, "daily_cap");
});
Deno.test("weekly cap uses local Monday boundaries through DST", () => {
  const f = optedIn();
  f.nowMs = at("2026-11-01T18:00:00Z");
  f.candidate.createdAtMs = f.nowMs - 1;
  f.candidate.expiresAtMs = f.nowMs + 1;
  f.receipts = ["2026-10-26T17:00:00Z", "2026-10-28T17:00:00Z", "2026-10-30T17:00:00Z"].map((
    date,
    i,
  ) => ({ actorId: "actor-a", eventId: `prior-${i}`, recordedAtMs: at(date) }));
  assertEquals(previewOptionalReminder(f).reason, "weekly_cap");
  f.nowMs = at("2026-11-02T18:00:00Z");
  f.candidate.createdAtMs = f.nowMs - 1;
  f.candidate.expiresAtMs = f.nowMs + 1;
  assertEquals(previewOptionalReminder(f).reason, null);
});
Deno.test("health, financial content and loss-targeted categories are rejected", () => {
  const f = optedIn();
  assertThrows(() =>
    previewOptionalReminder({ ...f, candidate: { ...f.candidate, steps: 9000 } } as never)
  );
  assertThrows(() =>
    previewOptionalReminder(
      { ...f, candidate: { ...f.candidate, category: "loss_comeback" } } as never,
    )
  );
  assertThrows(() =>
    previewOptionalReminder({ ...f, candidate: { ...f.candidate, category: "result" } } as never)
  );
});
Deno.test("invalid, foreign and future receipts cannot lower safety counts", () => {
  const f = optedIn();
  f.receipts = [{ actorId: "actor-b", eventId: "other", recordedAtMs: f.nowMs }];
  assertThrows(() => previewOptionalReminder(f));
  f.receipts = [{ actorId: "actor-a", eventId: "other", recordedAtMs: f.nowMs + 1 }];
  assertThrows(() => previewOptionalReminder(f));
  f.receipts = [];
  f.preferences.timezone = "Not/AZone";
  assertThrows(() => previewOptionalReminder(f));
});
