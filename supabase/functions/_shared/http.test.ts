import { assertEquals } from "@std/assert";
import { HttpFailure, respond } from "./http.ts";

function captureConsole(): {
  warnings: string[];
  errors: string[];
  restore: () => void;
} {
  const originalWarn = console.warn;
  const originalError = console.error;
  const warnings: string[] = [];
  const errors: string[] = [];

  console.warn = (...values: unknown[]) => {
    warnings.push(values.map(String).join(" "));
  };
  console.error = (...values: unknown[]) => {
    errors.push(values.map(String).join(" "));
  };

  return {
    warnings,
    errors,
    restore() {
      console.warn = originalWarn;
      console.error = originalError;
    },
  };
}

Deno.test("expected refusals log only the handler label and failure kind", async () => {
  const consoleCapture = captureConsole();
  const publicMessage = "sign in again";
  const privateValues = [
    "eyJhbGciOiJIUzI1NiJ9.private-access-token",
    '{"steps":9876543,"assertion":"private-signed-body"}',
    "postgresql://service_role:private-password@example.test/postgres",
    "sk_test_private-provider-key",
  ];

  try {
    const response = await respond("personal-sync-coverage", () =>
      Promise.reject(
        new HttpFailure(
          "unauthorized",
          publicMessage,
          privateValues.join(" | "),
        ),
      ));

    assertEquals(response.status, 401);
    assertEquals(await response.json(), {
      error: "unauthorized",
      message: publicMessage,
    });
    assertEquals(consoleCapture.warnings, [
      "personal-sync-coverage: unauthorized",
    ]);
    assertEquals(consoleCapture.errors, []);

    const logs = consoleCapture.warnings.join("|");
    assertEquals(logs.includes(publicMessage), false);
    for (const privateValue of privateValues) {
      assertEquals(logs.includes(privateValue), false);
    }
  } finally {
    consoleCapture.restore();
  }
});

Deno.test("unexpected throws cannot place their values or an unsafe label in logs", async () => {
  const consoleCapture = captureConsole();
  const privateValues = [
    "private unexpected error message",
    "private-object-token",
    "private-thrown-string",
    "private-label-token",
  ];

  try {
    for (
      const thrown of [
        new Error(privateValues[0]),
        { token: privateValues[1], body: { steps: 9_876_543 } },
        privateValues[2],
      ]
    ) {
      const response = await respond(
        `unsafe label ${privateValues[3]}`,
        () => Promise.reject(thrown),
      );

      assertEquals(response.status, 500);
      assertEquals(await response.json(), {
        error: "internal",
        message: "the request could not be processed",
      });
    }

    assertEquals(consoleCapture.warnings, []);
    assertEquals(consoleCapture.errors, [
      "edge-handler: unhandled exception",
      "edge-handler: unhandled exception",
      "edge-handler: unhandled exception",
    ]);

    const logs = consoleCapture.errors.join("|");
    for (const privateValue of privateValues) {
      assertEquals(logs.includes(privateValue), false);
    }
  } finally {
    consoleCapture.restore();
  }
});
