/** Read rollback-only local SQL fixtures and exercise the unchanged pure scorer. */
import { evaluateDuel } from "../supabase/functions/_shared/duel_scoring.ts";
import type { DuelScoringInput } from "../supabase/functions/_shared/duel_scoring.ts";

// An optional port selects another disposable stack; the host stays loopback.
const port = Deno.args[0] ?? "54322";
if (
  Deno.args.length > 1 || !/^[1-9][0-9]{0,4}$/.test(port) ||
  Number(port) > 65535
) {
  throw new Error("Expected one local PostgreSQL port (1–65535)");
}
const file = new URL("./examples/duel-proof.sql", import.meta.url);
const result = await new Deno.Command("psql", {
  args: [
    `postgresql://postgres:postgres@127.0.0.1:${port}/postgres`,
    "-X",
    "-qAt",
    "-v",
    "ON_ERROR_STOP=1",
    "-f",
    file.pathname,
  ],
  stdout: "piped",
  stderr: "piped",
}).output();
if (!result.success) {
  throw new Error(new TextDecoder().decode(result.stderr));
}
const samples = JSON.parse(new TextDecoder().decode(result.stdout)) as {
  name: string;
  input: DuelScoringInput;
  receipt: Record<string, unknown>;
  expected_winner: string;
}[];
if (samples.length !== 2) {
  throw new Error("Expected initial and correction snapshots");
}
for (const sample of samples) {
  const decision = evaluateDuel(sample.input);
  const revision = sample.name === "initial" ? 1 : 2;
  if (
    decision.phase !== "provisional" || decision.outcome?.kind !== "winner" ||
    decision.outcome.winnerId !== sample.expected_winner ||
    decision.proofRevision !== revision || decision.disputeClosesAt !== null ||
    sample.receipt.proofRevision !== revision
  ) throw new Error(`Unexpected ${sample.name} decision`);
  const keys = Object.keys(sample.receipt).sort().join(",");
  if (keys !== "challengeId,proofRevision,recordedAt,termsDigest") {
    throw new Error("Participant projection leaked additional fields");
  }
  if (sample.input.proofRevisions.length !== revision) {
    throw new Error("Proof chain is incomplete");
  }
  console.log(
    `PASS: ${sample.name} SQL snapshot → evaluator, revision ${revision}`,
  );
}
console.log(
  "All fictional rows and gate changes rolled back; no result was persisted.",
);
