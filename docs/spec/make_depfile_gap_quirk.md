# Make stub-only deps — stale prebuilt binaries re-run retired writer code

**Discovered**: 2026-11-05, P5 check-arch battery on canonical main (f5810012)
— `make check-arch` created `.nimcache/` at the repo root (root surface 49→50),
while `make ci-compile` ×2 and `make build` left the root untouched.

**Quirk.** Nim emits no dependency information for make (`--depfile` does not
exist — verified, see the `DEBT_AUDIT_SRCS` comment in `Makefile`). A rule like

```make
bin/nimtry: src/gate/nimtry.nim
	$(NIM) c $(NIM_TOOL_FLAGS) -o:$@ $<
```

tracks only the forwarding stub. When an implementation file changes —
PR #1278 (4ca79b42e) moved nimtry's runtime facts cache from
`.nimcache/nimtry` to `build/nimcache/nimtry` in
`src/gate/nimtry/nimtry_cache.nim` — make considers the prebuilt binary
up-to-date and re-runs the OLD binary. The retired root writer path executes
again: a `bin/nimtry` built 2026-10-11 (pre-fix) wrote 1330 module-fact JSONs
into `.nimcache/nimtry/` at the root on 2026-11-05.

**Blast radius.** Fresh clones are immune: `bin/*` is git-ignored, so CI and
new workspaces always build the current source. The hazard is a local
artifact that predates a writer-path fix. Detection is fail-closed —
`make validate-root-layout` reports `FAIL: .nimcache forbidden` and the
pre-push snapshot gate blocks the push — but the verdict names the symptom
(pollution), not the cause (stale binary), which makes it confusing to triage.

**Mitigation.** Widen prerequisites with a wildcard of the implementation
tree — the same pattern `DEBT_AUDIT_SRCS` already uses:

```make
bin/nimtry: src/gate/nimtry.nim $(wildcard src/gate/nimtry/*.nim)
```

Verified 2026-11-05: `touch src/gate/nimtry/nimtry_cli.nim` → `make check-arch`
rebuilds `bin/nimtry`; after the run `.nimcache/` is absent, root surface is
49, and the facts cache lands in `build/nimcache/nimtry`. Any other
stub-forwarded tool binary with prebuilt local copies has the same gap —
widen its rule the same way when a source-level writer-path fix lands.
