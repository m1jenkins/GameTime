/**
 * Portable M6 integrity fixtures.
 *
 * These are validation outcomes already derived by Postgres, not invented
 * coordinates. Database and Swift suites own the geometry/dwell arithmetic;
 * this corpus pins the sidecar disposition and keeps it visibly separate from
 * metric scoring.
 */

import type { CheckInEvidence, IntegrityFlagCode } from "../_shared/integrity.ts";

export interface M6IntegrityFixture {
  readonly name: string;
  readonly why: string;
  readonly checkIn: CheckInEvidence;
  readonly expectedFlag: IntegrityFlagCode | null;
  readonly expectedPenalty: number;
}

const BASE = {
  userId: "22222222-2222-2222-2222-222222222222",
  geofenceId: "f0000001-0000-0000-0000-000000000001",
  startedAt: "2026-01-06T12:00:00.000Z",
  endedAt: "2026-01-06T12:30:00.000Z",
  attested: true,
  ruleVersion: "m6-v1",
} as const;

export const M6_INTEGRITY_FIXTURES: readonly M6IntegrityFixture[] = [
  {
    name: "accepted check-in is clean",
    why: "A successful visit is a trusted location signal, not a reward or a scoring bonus.",
    checkIn: {
      ...BASE,
      checkInId: "c0000001-0000-0000-0000-000000000001",
      outcome: "accepted",
      dwellSeconds: 1_200,
      workoutOverlapSeconds: 900,
    },
    expectedFlag: null,
    expectedPenalty: 0,
  },
  {
    name: "outside geofence remains explicit",
    why: "A signed attempt outside the venue is auditable without deleting any HealthKit total.",
    checkIn: {
      ...BASE,
      checkInId: "c0000002-0000-0000-0000-000000000002",
      outcome: "outside_geofence",
      dwellSeconds: 0,
      workoutOverlapSeconds: 0,
    },
    expectedFlag: "geofence_checkin_failure",
    expectedPenalty: 10,
  },
  {
    name: "simulated location is a geofence failure",
    why: "The source flag has its own persisted outcome and does not masquerade as bad geometry.",
    checkIn: {
      ...BASE,
      checkInId: "c0000003-0000-0000-0000-000000000003",
      outcome: "simulated_location",
      dwellSeconds: 0,
      workoutOverlapSeconds: 0,
    },
    expectedFlag: "geofence_checkin_failure",
    expectedPenalty: 10,
  },
  {
    name: "insufficient workout overlap is distinct",
    why: "Temporal validation is separately tunable from whether the participant was at the venue.",
    checkIn: {
      ...BASE,
      checkInId: "c0000004-0000-0000-0000-000000000004",
      outcome: "insufficient_workout_overlap",
      dwellSeconds: 1_200,
      workoutOverlapSeconds: 299,
    },
    expectedFlag: "workout_overlap_validation",
    expectedPenalty: 15,
  },
  {
    name: "reused workout is temporal replay",
    why: "One HealthKit workout cannot validate two accepted visits under a different check-in id.",
    checkIn: {
      ...BASE,
      checkInId: "c0000005-0000-0000-0000-000000000005",
      outcome: "reused_workout",
      dwellSeconds: 1_200,
      workoutOverlapSeconds: 900,
    },
    expectedFlag: "workout_overlap_validation",
    expectedPenalty: 15,
  },
];
