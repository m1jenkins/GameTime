import { oneServiceRow, serviceRpc } from "../_shared/service_rpc.ts";
import type { AccountDeletionDatabase, AccountDeletionProviderIds } from "./handler.ts";

interface PostgrestConfig {
  readonly url: string;
  readonly serviceRoleKey: string;
  readonly authorizationBearer: boolean;
}

export function postgrestAccountDeletionDatabase(
  config: PostgrestConfig,
): AccountDeletionDatabase {
  return {
    async providerIds(ownerId): Promise<AccountDeletionProviderIds> {
      const row = oneServiceRow(
        await serviceRpc(
          config,
          "account_deletion_provider_ids",
          { p_actor_id: ownerId },
        ),
        "account_deletion_provider_ids",
      );
      const value = row["stripe_customer_id"];
      return typeof value === "string" ? { stripeCustomerId: value } : {};
    },

    async deleteAccount(ownerId) {
      await serviceRpc(config, "delete_account", { p_actor_id: ownerId });
    },
  };
}
