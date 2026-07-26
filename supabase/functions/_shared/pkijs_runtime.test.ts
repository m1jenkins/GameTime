import { assertEquals } from "@std/assert";
import { needsPkijsBrowserAlias } from "./pkijs_runtime.ts";

Deno.test("installs the PKI.js browser alias only for Supabase's undefined pid shim", () => {
  assertEquals(needsPkijsBrowserAlias({ process: { pid: undefined } }), true);

  assertEquals(needsPkijsBrowserAlias({ process: { pid: 42 } }), false);
  assertEquals(needsPkijsBrowserAlias({ process: {} }), false);
  assertEquals(needsPkijsBrowserAlias({}), false);
  assertEquals(
    needsPkijsBrowserAlias({ process: { pid: undefined }, window: undefined }),
    true,
  );
  assertEquals(needsPkijsBrowserAlias({ process: { pid: undefined }, window: {} }), false);
});
