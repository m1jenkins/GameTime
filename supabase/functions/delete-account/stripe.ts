import type Stripe from "stripe";
import type { StripeCustomerDeleter } from "./handler.ts";

function isResourceMissing(error: unknown): boolean {
  return typeof error === "object" && error !== null &&
    "code" in error && (error as { code?: unknown }).code === "resource_missing";
}

export function stripeCustomerDeleter(
  stripe: Stripe,
): StripeCustomerDeleter {
  return {
    async deleteTestCustomer(customerId) {
      let customer: Stripe.Customer | Stripe.DeletedCustomer;
      try {
        customer = await stripe.customers.retrieve(customerId);
      } catch (error) {
        if (isResourceMissing(error)) return;
        throw new Error("Stripe Customer lookup failed");
      }

      if (customer.deleted === true) return;
      if (customer.livemode) {
        throw new Error("a live Stripe Customer cannot be deleted from beta");
      }

      try {
        await stripe.customers.del(customerId);
      } catch (error) {
        // A retry after a successful DELETE sees resource_missing. Treat that
        // as completion so the durable account deletion can safely continue.
        if (!isResourceMissing(error)) {
          throw new Error("Stripe Customer deletion failed");
        }
      }
    },
  };
}
