# T-1.3 fixture — unknown

Empty/non-JS project used to exercise the detector's `framework: unknown`
fallback (AC-2). Intentionally has no `package.json`, no lockfile, no test
runner config. The detector should still emit a well-formed JSON document
with `framework=unknown`, `runtime=unknown`, `package_manager=unknown`,
`command=""` and exit 0.
