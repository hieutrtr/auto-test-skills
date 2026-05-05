# Framework Detection Reference

> Detail-level reference loaded by the `unit-test-runner` skill on demand.
> Source for the heuristic: `docs/ARCHITECTURE.md` §(e); implementation:
> `scripts/detect.sh`. Phase 1 / T-1.3.

## Output JSON Shape

`scripts/detect.sh <project-root>` writes one line of canonical JSON to
stdout. Fields (sorted alphabetically by `python3 json.dumps(...,
sort_keys=True)`):

| Field | Type | Notes |
|---|---|---|
| `command` | string | Empty string when `framework == "unknown"`; otherwise the canonical PM-prefixed command (`npm test`, `pnpm test`, `yarn test`, `bun test`). |
| `framework` | string | One of `jest`, `vitest`, `bun`, `mocha`, `playwright-runner`, `unknown`. |
| `markers` | array of string | Sorted list of detected signals (e.g. `["devDep:jest","jest.config.js","script:test"]`) — used by the dashboard for explainability. |
| `package_manager` | string | One of `bun`, `pnpm`, `yarn`, `npm`, `unknown`. |
| `project_dir` | string | Canonical absolute path (`pwd -P`) of the input directory. |
| `runtime` | string | `bun` when bun runtime is the primary; `node` for jest/vitest/mocha/playwright-runner; `unknown` when no `package.json`. |
| `schema_version` | string | `"1"` for Phase 1. |
| `test_script` | string | Verbatim `scripts.test` from `package.json` (empty string when missing). |

## Markers Catalog

The detector inspects the project root only (no recursion). Each detected
signal is appended to `markers` so that downstream consumers can explain
"why did the detector pick X?":

| Marker token | Source check |
|---|---|
| `package.json` | `[[ -f package.json ]]` |
| `package-lock.json` | npm lockfile present |
| `pnpm-lock.yaml` | pnpm lockfile present |
| `yarn.lock` | yarn lockfile present |
| `bun.lockb` | bun (binary) lockfile present |
| `bun.lock` | bun (text) lockfile present (Bun ≥ 1.1.30) |
| `jest.config.js` / `jest.config.ts` / `jest.config.cjs` / `jest.config.mjs` / `jest.config.json` | jest config file present |
| `vitest.config.ts` / `vitest.config.js` / `vitest.config.mjs` / `vitest.config.mts` | vitest config file present |
| `playwright.config.ts` / `playwright.config.js` | playwright config file present |
| `.mocharc.js` / `.mocharc.cjs` / `.mocharc.json` / `.mocharc.yml` / `.mocharc.yaml` / `mocha.opts` | mocha config marker present |
| `bunfig.toml` | bun runtime config present (counted only as runtime evidence, not framework evidence) |
| `devDep:jest` | `package.json` `devDependencies.jest` defined |
| `devDep:vitest` | same for `vitest` |
| `devDep:mocha` | same for `mocha` |
| `devDep:@playwright/test` | same for `@playwright/test` |
| `script:test` | `package.json` `scripts.test` is non-empty |
| `script:test:contains:bun test` | `scripts.test` contains the literal `bun test` token (key signal for the `bun` framework) |

The marker list is informational; the routing decision still flows through
the priority + heuristic table below.

## Detection Priority

When multiple framework markers are present in one project (common during
migration or in monorepos), the detector picks the first match in this order:

1. **vitest** — `vitest.config.*` OR `devDep:vitest` OR
   `script:test:contains:vitest`.
2. **jest** — `jest.config.*` OR `devDep:jest` OR
   `script:test:contains:jest`.
3. **playwright-runner** — `playwright.config.*` OR
   `devDep:@playwright/test` OR `script:test:contains:playwright`.
4. **mocha** — any `.mocharc*` / `mocha.opts` OR `devDep:mocha` OR
   `script:test:contains:mocha`.
5. **bun** — `bun.lockb` / `bun.lock` AND
   (`script:test:contains:bun test` OR no other framework matched). The
   `bun` framework keyword represents the **built-in `bun:test` runner**;
   it never co-exists with jest/vitest/etc as the primary framework
   because if those are present, the tests are run via that framework
   under the bun runtime.

If none of 1–5 match → `framework: "unknown"`, `runtime: "unknown"`,
`package_manager: "unknown"`, `command: ""`. Never exit 1 — only exit 2
on bad input arg (missing or non-directory).

## Runtime + Package-Manager Heuristic

Once a framework is fixed, the detector picks `runtime` + `package_manager`
from lockfile presence (priority order):

| Lockfile present | runtime | package_manager |
|---|---|---|
| `bun.lockb` or `bun.lock` | `bun` | `bun` |
| `pnpm-lock.yaml`          | `node` | `pnpm` |
| `yarn.lock`               | `node` | `yarn` |
| `package-lock.json`       | `node` | `npm` |
| (none)                    | `node` (when `package.json` exists), else `unknown` | `npm` (default — same fallback as ARCHITECTURE §(e)), else `unknown` |

Special case: when the framework is `bun` we always set
`runtime: bun, package_manager: bun` regardless of which lockfile is
present, because `bun:test` only runs under the bun binary.

## Command Resolution

The canonical command emitted to `command` is the package-manager
invocation of the npm script `test` whenever `scripts.test` is non-empty.
That covers jest / vitest / mocha / playwright-runner uniformly.

For the `bun` framework the canonical command is the bare `bun test`,
which works whether or not `package.json#scripts.test` exists.

| framework | command |
|---|---|
| jest, vitest, mocha, playwright-runner | `<pm> test` (e.g. `npm test`, `pnpm test`, `yarn test`, `bun test`) |
| bun | `bun test` |
| unknown | `""` (empty) |

The orchestrator (T-1.5) is responsible for `eval`-ing the string under
the project root.

## Edge Cases (documented, deferred to later phases)

| # | Edge case | Phase 1 behavior | Future task |
|---|---|---|---|
| E-1 | Project has both `jest.config.js` and `vitest.config.ts` | Returns `vitest` (priority order) | T1.3-12 fixture asserts this |
| E-2 | Project root has `package.json` but `scripts.test` missing AND no config files | Returns `unknown`, command empty | Phase 4: fall back to ARCHITECTURE §(e) CLAUDE.md «Build & Test» grep |
| E-3 | `package.json` is malformed JSON | Detector logs a stderr warning and returns `unknown` (does not crash) | — |
| E-4 | yarn workspaces root with no `yarn.lock` (workspace lockfile lives elsewhere) | Returns `package_manager: npm` (default fallback) | Phase 3 monorepo support |
| E-5 | Custom JS test runner (e.g. ava, tap, uvu) | Returns `unknown` | Phase 4 polish |
| E-6 | Pytest / Cargo / Go / RSpec project | Returns `unknown` (this skill is JS-only) | Phase 3 multi-runtime |
| E-7 | Playwright tests that DO call `page.goto(...)` | Still returns `playwright-runner` here — but the orchestrator (T-1.5) re-routes any project with a `tests/browser/` folder to `browser-test` first | Phase 2 `browser-test` |

## Cross-Platform Notes

- macOS / BSD + Linux / GNU compatible. Uses `pwd -P` (POSIX), `python3`
  for JSON parse with awk fallback, no `jq`, no `stat -c`, no `find -printf`.
- The `bun.lockb` file is binary; the detector only checks `[[ -f ... ]]` —
  it never reads the file's contents.
- `python3` is required to parse `package.json` reliably. When absent the
  detector falls back to a grep-based heuristic that handles the common
  case (`scripts.test` literal, `devDependencies.<framework>` literal) but
  may misclassify exotic `package.json` formatting (e.g. devDeps spread
  across multi-line objects with comments — non-standard JSON anyway).
