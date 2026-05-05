#!/usr/bin/env bash
# detect.sh — JS/TS unit-test framework detector.
#
# Usage:
#   detect.sh <project-root>
#
# Emits a single line of canonical JSON on stdout describing the detected
# framework, runtime, package manager, run command, and the markers that
# led to the decision. See ../references/framework-detection.md for the
# priority order + per-framework marker rules. Phase 1 / T-1.3.
#
# Exit codes:
#   0 — detected (incl. "unknown" framework)
#   2 — bad input arg (missing or non-directory)
#
# Cross-platform: BSD + GNU. Uses pwd -P (POSIX), python3 for JSON parse
# with awk fallback, no jq, no stat -c, no readlink -f.
set -uo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: detect.sh <project-root>" >&2
  exit 2
fi

input="$1"
if [[ ! -d "$input" ]]; then
  echo "detect: not a directory: $input" >&2
  exit 2
fi

project_dir="$(cd "$input" && pwd -P)"

# --- collect markers -------------------------------------------------------
markers=()        # plain bash array; sorted later via printf | sort
test_script=""    # verbatim scripts.test (may contain spaces)
has_pkg=0
has_jest_dd=0
has_vitest_dd=0
has_mocha_dd=0
has_pwtest_dd=0

note_file() {
  local f="$1"
  if [[ -e "$project_dir/$f" ]]; then
    markers+=("$f")
    return 0
  fi
  return 1
}

# Lockfiles + runtime config files
note_file package.json && has_pkg=1
note_file package-lock.json || true
note_file pnpm-lock.yaml    || true
note_file yarn.lock         || true
note_file bun.lockb         || true
note_file bun.lock          || true
note_file bunfig.toml       || true

# Framework config files
note_file jest.config.js    || true
note_file jest.config.ts    || true
note_file jest.config.cjs   || true
note_file jest.config.mjs   || true
note_file jest.config.json  || true
note_file vitest.config.ts  || true
note_file vitest.config.js  || true
note_file vitest.config.mjs || true
note_file vitest.config.mts || true
note_file playwright.config.ts || true
note_file playwright.config.js || true
note_file .mocharc.js       || true
note_file .mocharc.cjs      || true
note_file .mocharc.json     || true
note_file .mocharc.yml      || true
note_file .mocharc.yaml     || true
note_file mocha.opts        || true

# Parse package.json (for devDeps + scripts.test) using python3 with a
# best-effort grep fallback. We deliberately tolerate missing python3 so
# the detector still works on stripped-down environments.
parse_pkg_python3() {
  python3 - "$project_dir/package.json" <<'PY' 2>/dev/null
import json, sys
path = sys.argv[1]
try:
    with open(path) as f:
        d = json.load(f)
except Exception as e:
    sys.stderr.write(f"detect: package.json parse error: {e}\n")
    sys.exit(3)
def get(d, *keys):
    cur = d
    for k in keys:
        if not isinstance(cur, dict) or k not in cur:
            return None
        cur = cur[k]
    return cur
test_script = get(d, "scripts", "test") or ""
dd = get(d, "devDependencies") or {}
deps = get(d, "dependencies") or {}
def has(name):
    return (isinstance(dd, dict) and name in dd) or \
           (isinstance(deps, dict) and name in deps)
print("TEST_SCRIPT=" + test_script.replace("\n", " "))
print("HAS_JEST="            + ("1" if has("jest") else "0"))
print("HAS_VITEST="          + ("1" if has("vitest") else "0"))
print("HAS_MOCHA="           + ("1" if has("mocha") else "0"))
print("HAS_PWTEST="          + ("1" if has("@playwright/test") else "0"))
PY
}

if [[ "$has_pkg" -eq 1 ]]; then
  if command -v python3 >/dev/null 2>&1; then
    pkg_kv="$(parse_pkg_python3)"
    parse_rc=$?
    if [[ "$parse_rc" -ne 0 ]]; then
      # malformed package.json — warning already on stderr; fall through to unknown
      :
    else
      while IFS='=' read -r k v; do
        case "$k" in
          TEST_SCRIPT) test_script="$v" ;;
          HAS_JEST)    has_jest_dd="$v" ;;
          HAS_VITEST)  has_vitest_dd="$v" ;;
          HAS_MOCHA)   has_mocha_dd="$v" ;;
          HAS_PWTEST)  has_pwtest_dd="$v" ;;
        esac
      done <<<"$pkg_kv"
    fi
  else
    # awk fallback — handles standard `"name": "value"` formatting only.
    pkg="$project_dir/package.json"
    test_script="$(awk -v RS= -v ORS= '
      match($0, /"scripts"[[:space:]]*:[[:space:]]*\{[^}]*"test"[[:space:]]*:[[:space:]]*"[^"]*"/) {
        s = substr($0, RSTART, RLENGTH);
        if (match(s, /"test"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
          t = substr(s, RSTART, RLENGTH);
          sub(/^"test"[[:space:]]*:[[:space:]]*"/, "", t);
          sub(/"$/, "", t);
          print t;
        }
      }' "$pkg" 2>/dev/null)"
    grep -q '"jest"[[:space:]]*:'                  "$pkg" 2>/dev/null && has_jest_dd=1
    grep -q '"vitest"[[:space:]]*:'                "$pkg" 2>/dev/null && has_vitest_dd=1
    grep -q '"mocha"[[:space:]]*:'                 "$pkg" 2>/dev/null && has_mocha_dd=1
    grep -q '"@playwright/test"[[:space:]]*:'      "$pkg" 2>/dev/null && has_pwtest_dd=1
  fi
fi

# Append derived markers
if [[ "$has_jest_dd"   == "1" ]]; then markers+=("devDep:jest"); fi
if [[ "$has_vitest_dd" == "1" ]]; then markers+=("devDep:vitest"); fi
if [[ "$has_mocha_dd"  == "1" ]]; then markers+=("devDep:mocha"); fi
if [[ "$has_pwtest_dd" == "1" ]]; then markers+=("devDep:@playwright/test"); fi
if [[ -n "$test_script" ]]; then
  markers+=("script:test")
  case "$test_script" in
    *"bun test"*)    markers+=("script:test:contains:bun test") ;;
  esac
  case "$test_script" in
    *jest*)          markers+=("script:test:contains:jest") ;;
  esac
  case "$test_script" in
    *vitest*)        markers+=("script:test:contains:vitest") ;;
  esac
  case "$test_script" in
    *mocha*)         markers+=("script:test:contains:mocha") ;;
  esac
  case "$test_script" in
    *playwright*)    markers+=("script:test:contains:playwright") ;;
  esac
fi

# --- pick framework via priority -------------------------------------------
has_marker() {
  local needle="$1" m
  for m in "${markers[@]+"${markers[@]}"}"; do
    [[ "$m" == "$needle" ]] && return 0
  done
  return 1
}

framework="unknown"
if has_marker "vitest.config.ts"  || has_marker "vitest.config.js" \
|| has_marker "vitest.config.mjs" || has_marker "vitest.config.mts" \
|| has_marker "devDep:vitest"     || has_marker "script:test:contains:vitest"; then
  framework="vitest"
elif has_marker "jest.config.js"  || has_marker "jest.config.ts" \
  || has_marker "jest.config.cjs" || has_marker "jest.config.mjs" \
  || has_marker "jest.config.json" \
  || has_marker "devDep:jest"     || has_marker "script:test:contains:jest"; then
  framework="jest"
elif has_marker "playwright.config.ts" || has_marker "playwright.config.js" \
  || has_marker "devDep:@playwright/test" \
  || has_marker "script:test:contains:playwright"; then
  framework="playwright-runner"
elif has_marker ".mocharc.js"   || has_marker ".mocharc.cjs" \
  || has_marker ".mocharc.json" || has_marker ".mocharc.yml" \
  || has_marker ".mocharc.yaml" || has_marker "mocha.opts" \
  || has_marker "devDep:mocha"  || has_marker "script:test:contains:mocha"; then
  framework="mocha"
elif (has_marker "bun.lockb" || has_marker "bun.lock") \
  && (has_marker "script:test:contains:bun test" || [[ "$has_pkg" -eq 1 ]]); then
  framework="bun"
fi

# --- runtime + package_manager ---------------------------------------------
runtime="unknown"
package_manager="unknown"

if [[ "$framework" == "bun" ]]; then
  runtime="bun"
  package_manager="bun"
elif [[ "$has_pkg" -eq 1 ]]; then
  runtime="node"
  if   has_marker "bun.lockb"      || has_marker "bun.lock"; then
    runtime="bun"
    package_manager="bun"
  elif has_marker "pnpm-lock.yaml"; then
    package_manager="pnpm"
  elif has_marker "yarn.lock"; then
    package_manager="yarn"
  else
    package_manager="npm"
  fi
fi

# --- canonical command -----------------------------------------------------
command_str=""
if [[ "$framework" == "bun" ]]; then
  command_str="bun test"
elif [[ "$framework" != "unknown" ]]; then
  command_str="$package_manager test"
fi

# --- emit JSON (sorted keys, sorted markers) -------------------------------
markers_sorted_csv=""
if [[ "${#markers[@]}" -gt 0 ]]; then
  markers_sorted_csv="$(printf '%s\n' "${markers[@]}" | LC_ALL=C sort -u | paste -sd ',' -)"
fi

if command -v python3 >/dev/null 2>&1; then
  python3 - "$framework" "$runtime" "$package_manager" "$command_str" \
              "$project_dir" "$test_script" "$markers_sorted_csv" <<'PY'
import json, sys
fw, rt, pm, cmd, pd, ts, mk = sys.argv[1:8]
markers = [m for m in mk.split(",") if m] if mk else []
out = {
    "schema_version": "1",
    "framework": fw,
    "runtime": rt,
    "package_manager": pm,
    "command": cmd,
    "project_dir": pd,
    "test_script": ts,
    "markers": markers,
}
print(json.dumps(out, sort_keys=True))
PY
else
  # Fallback JSON encoder (no escaping of \" / \\ — best-effort only).
  esc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
  markers_json="[]"
  if [[ -n "$markers_sorted_csv" ]]; then
    markers_json="["
    first=1
    while IFS= read -r m; do
      [[ -z "$m" ]] && continue
      if [[ "$first" -eq 1 ]]; then first=0; else markers_json+=","; fi
      markers_json+="\"$(esc "$m")\""
    done <<<"$(printf '%s\n' "${markers[@]}" | LC_ALL=C sort -u)"
    markers_json+="]"
  fi
  printf '{"command":"%s","framework":"%s","markers":%s,"package_manager":"%s","project_dir":"%s","runtime":"%s","schema_version":"1","test_script":"%s"}\n' \
    "$(esc "$command_str")" "$(esc "$framework")" "$markers_json" \
    "$(esc "$package_manager")" "$(esc "$project_dir")" \
    "$(esc "$runtime")" "$(esc "$test_script")"
fi
