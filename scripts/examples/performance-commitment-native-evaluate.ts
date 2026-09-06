/** Test-only bridge: evaluate a private, clock-injected local snapshot from stdin.
 * The controller commits this exact decision separately and can interrupt before
 * simulation. No credentials, database connection, network, or hosted access.
 */
import { evaluatePerformanceCommitment } from "../../supabase/functions/_shared/performance_scoring.ts";
import type { PerformanceScoringInput } from "../../supabase/functions/_shared/performance_scoring.ts";

const input = JSON.parse(await new Response(Deno.stdin.readable).text()) as PerformanceScoringInput;
console.log(JSON.stringify(evaluatePerformanceCommitment(input)));
