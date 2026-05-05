// T-1.3 fixture: minimal Playwright config. No webServer block on purpose —
// Phase 1 unit-test-runner only handles the @playwright/test runner used
// outside a browser-navigation context. Browser navigation + dev-server
// orchestration is Phase 2 browser-test scope.
import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./tests",
  reporter: "list",
});
