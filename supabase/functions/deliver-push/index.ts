import { dataApiConfig, requireEnv } from "../_shared/env.ts";
import { ApnsTokenTransport } from "./apns.ts";
import { postgrestPushDeliveryDatabase } from "./database.ts";
import { createDeliverPushHandler } from "./handler.ts";

export const handler = createDeliverPushHandler({
  deploymentEnvironment: requireEnv("GAMETIME_ENV"),
  dispatchSecret: requireEnv("GAMETIME_PUSH_DISPATCH_SECRET"),
  database: postgrestPushDeliveryDatabase(dataApiConfig()),
  transport: new ApnsTokenTransport({
    teamId: requireEnv("APNS_TEAM_ID"),
    keyId: requireEnv("APNS_KEY_ID"),
    privateKeyPem: requireEnv("APNS_PRIVATE_KEY"),
  }),
});

if (import.meta.main) {
  Deno.serve(handler);
}
