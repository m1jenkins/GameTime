/**
 * Pure local rehearsal for optional reminder suppression. No delivery adapter,
 * token, permission request, scheduler or enabled notification route exists.
 * Result/review and security notices deliberately require a separate policy.
 */
export const OPTIONAL_REMINDER_CATEGORIES = [
  "invitation",
  "requested_goal",
  "selected_friend",
] as const;
type Category = typeof OPTIONAL_REMINDER_CATEGORIES[number];
export interface ReminderPreferences {
  actorId: string;
  timezone: string;
  categories: Record<Category, boolean>;
  quietStartHour: number;
  quietEndHour: number;
  dailyCap: number;
  weeklyCap: number;
}
export interface ReminderCandidate {
  actorId: string;
  eventId: string;
  destinationId: string;
  category: Category;
  createdAtMs: number;
  expiresAtMs: number;
}
export interface ReminderReceipt {
  actorId: string;
  eventId: string;
  recordedAtMs: number;
}
export type ReminderSuppression =
  | "signed_out"
  | "no_current_access"
  | "category_off"
  | "obsolete"
  | "duplicate"
  | "quiet_hours"
  | "daily_cap"
  | "weekly_cap";

function requireFact(value: unknown, reason: string): asserts value {
  if (!value) throw new Error(reason);
}
function keys(value: unknown, expected: string[]): asserts value is Record<string, unknown> {
  requireFact(
    value !== null && typeof value === "object" && !Array.isArray(value),
    "invalid_object",
  );
  requireFact(Object.keys(value).sort().join(",") === expected.sort().join(","), "invalid_fields");
}
function id(value: unknown): asserts value is string {
  requireFact(typeof value === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(value), "invalid_id");
}
function integer(value: unknown, lower: number, upper: number): asserts value is number {
  requireFact(
    Number.isSafeInteger(value) && Number(value) >= lower && Number(value) <= upper,
    "invalid_integer",
  );
}
function localParts(at: number, zone: string): { day: string; week: number; hour: number } {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-CA", {
      timeZone: zone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      hourCycle: "h23",
    }).formatToParts(new Date(at)).map((part) => [part.type, part.value]),
  );
  const day = `${parts.year}-${parts.month}-${parts.day}`;
  const date = Date.parse(`${day}T00:00:00Z`);
  return {
    day,
    week: date - ((new Date(date).getUTCDay() + 6) % 7) * 86_400_000,
    hour: Number(parts.hour),
  };
}

/**
 * An eligible preview still cannot send. Reevaluate authorization, preferences,
 * staleness and caps transactionally immediately before any eventual delivery.
 * Caps are caller-supplied trial ceilings, never approved launch defaults.
 */
export function previewOptionalReminder(input: {
  nowMs: number;
  currentActorId: string | null;
  currentAccess: boolean;
  preferences: ReminderPreferences;
  candidate: ReminderCandidate;
  receipts: ReminderReceipt[];
}): {
  status: "suppressed" | "eligible_for_local_preview";
  reason: ReminderSuppression | null;
  deliveryEnabled: false;
} {
  keys(input, ["nowMs", "currentActorId", "currentAccess", "preferences", "candidate", "receipts"]);
  integer(input.nowMs, 0, 8_000_000_000_000_000);
  requireFact(
    input.currentActorId === null || typeof input.currentActorId === "string",
    "invalid_actor",
  );
  requireFact(typeof input.currentAccess === "boolean", "invalid_access");
  const p = input.preferences, c = input.candidate;
  keys(p, [
    "actorId",
    "timezone",
    "categories",
    "quietStartHour",
    "quietEndHour",
    "dailyCap",
    "weeklyCap",
  ]);
  keys(c, ["actorId", "eventId", "destinationId", "category", "createdAtMs", "expiresAtMs"]);
  keys(p.categories, [...OPTIONAL_REMINDER_CATEGORIES]);
  id(p.actorId);
  id(c.actorId);
  id(c.eventId);
  id(c.destinationId);
  requireFact(p.actorId === c.actorId, "actor_mismatch");
  requireFact(OPTIONAL_REMINDER_CATEGORIES.includes(c.category), "unsupported_category");
  for (const category of OPTIONAL_REMINDER_CATEGORIES) {
    requireFact(typeof p.categories[category] === "boolean", "invalid_consent");
  }
  requireFact(typeof p.timezone === "string" && p.timezone.length > 0, "invalid_timezone");
  integer(p.quietStartHour, 0, 23);
  integer(p.quietEndHour, 0, 23);
  requireFact(p.quietStartHour !== p.quietEndHour, "ambiguous_quiet_hours");
  integer(p.dailyCap, 0, 100);
  integer(p.weeklyCap, 0, 700);
  integer(c.createdAtMs, 0, input.nowMs);
  integer(c.expiresAtMs, c.createdAtMs + 1, 8_000_000_000_000_000);
  requireFact(Array.isArray(input.receipts) && input.receipts.length <= 10_000, "invalid_receipts");
  const unique = new Set<string>();
  for (const receipt of input.receipts) {
    keys(receipt, ["actorId", "eventId", "recordedAtMs"]);
    id(receipt.actorId);
    id(receipt.eventId);
    integer(receipt.recordedAtMs, 0, input.nowMs);
    requireFact(
      receipt.actorId === c.actorId && !unique.has(receipt.eventId),
      "invalid_receipt_binding",
    );
    unique.add(receipt.eventId);
  }
  const current = localParts(input.nowMs, p.timezone);
  const suppress = (reason: ReminderSuppression) => ({
    status: "suppressed" as const,
    reason,
    deliveryEnabled: false as const,
  });
  if (input.currentActorId !== c.actorId) return suppress("signed_out");
  if (!input.currentAccess) return suppress("no_current_access");
  if (!p.categories[c.category]) return suppress("category_off");
  if (input.nowMs >= c.expiresAtMs) return suppress("obsolete");
  if (unique.has(c.eventId)) return suppress("duplicate");
  const quiet = p.quietStartHour < p.quietEndHour
    ? current.hour >= p.quietStartHour && current.hour < p.quietEndHour
    : current.hour >= p.quietStartHour || current.hour < p.quietEndHour;
  if (quiet) return suppress("quiet_hours");
  const times = input.receipts.map((r) => localParts(r.recordedAtMs, p.timezone));
  if (times.filter((t) => t.day === current.day).length >= p.dailyCap) return suppress("daily_cap");
  if (times.filter((t) => t.week === current.week).length >= p.weeklyCap) {
    return suppress("weekly_cap");
  }
  return { status: "eligible_for_local_preview", reason: null, deliveryEnabled: false };
}
