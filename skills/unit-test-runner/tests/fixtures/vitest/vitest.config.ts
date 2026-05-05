// T-1.3 fixture: minimal Vitest config (TS variant — exercises the
// `.config.ts` glob in the detector, not just `.config.js`).
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    include: ["tests/**/*.test.ts"],
  },
});
