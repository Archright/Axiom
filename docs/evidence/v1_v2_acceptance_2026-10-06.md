# V1/V2 Production Acceptance — gate-binary self-supply + phase attribution (2026-10-06)

## Scope

Production observations for the two workstream slices landed this day:

- **V1** — PR #506 (mergeCommit `9924997de`, merged 2026-10-06T11:09:32Z): base artifact self-supplies gate binaries — attest 6-binary set closed under B-cache eviction.
- **V2** — PR #503 (mergeCommit `4330f6b84`, merged 2026-10-06T10:17:37Z): `ax merge --dry-run` phase attribution instrumentation.
- Supporting: PR #505 (surface v57 — `ci-cache-publisher.yml` CONTROLLED re-registration, contract §18(c) procedure), Archright/.github PR #57 (pin rotation `22ae6bd3` → `9924997de`, merged 11:18:22Z).

## Production group — PR #506 merge group (run 37453218153)

Group wall clock ≈ **11m26s** (10:57:38Z first job start → 11:09:04Z group check) vs E-WALL sample 13m53s (#496-era observation).

### V2 attribution — verdict / admission-check (job 112236610580)

Verdict step 5m27s (11:03:32 → 11:08:59). Instrumented output (production log, verbatim):

```
[INFO] merge_cli: phase=cert-ledger-scan certs=273 elapsed_ms=306676
[INFO] merge_cli: phase=fact-certledger elapsed_ms=306676
[INFO] merge_cli: phase=collect-facts elapsed_ms=308861
[INFO] merge_cli: phase=bind-cert elapsed_ms=0
[INFO] merge_cli: phase=predicate elapsed_ms=0
[INFO] merge_cli: attribution: collect_ms=308861 bind_ms=0 predicate_ms=0 total_ms=308861
```

- cert-ledger full scan = **306.7s = 99.3% of collect-facts**; per-cert iteration ≈ 1s (cert-scan-iter samples 1022/1036/975ms — serial ledger HTTP with per-request TLS re-establishment).
- bind-cert = 0, predicate = 0 — the predicate itself is not the bottleneck.
- Conclusion: the 13m53s-class group's dominant bottleneck is now mechanically attributed to the O(N) cert-ledger scan. Optimization (skip scan when `--cert` is present, or parallel fetch) is a separate follow-up workstream — deliberately not implemented in V2.

### V1 supply evidence — attest / admission-check (job 112235813182)

Production log (verbatim):

```
AXIOM_CACHE_B_VERIFY: entry OK — bin/ax sha256=fadbd1ecf3eee46f
AXIOM_CACHE_B_VERIFY: entry OK — bin/gate_hook sha256=268a04d7b007c7e2
AXIOM_CACHE_B_VERIFY: entry OK — bin/install_ax_cas sha256=6180e5196c675c26
AXIOM_CACHE_B_VERIFY: entry OK — bin/precompile_gates sha256=732916344c962bc6
AXIOM_CACHE_B_VERIFY: RESULT OK — 4/4 entries digest-verified, buildSha=a28ee368ad2b, key exact-hit
```

- B-restore exact-key hit with all 4 gate-binary entries digest-verified — including `gate_hook` and `precompile_gates`, the two manifest entries added by V1.
- `discard_b` path present and fail-closed: "AXIOM_CACHE_B_VERIFY: DISCARDED — native build runs (fail-closed: cache is acceleration, never evidence)" — a B-verify failure discards the cache copies and falls back to the artifact/native build; the 6-binary set completes before any kernel execution either way.

## V1 three-path acceptance state

- **(a) new subject MISS → full pipeline → PASS** — observed: the #506 group above; also #503/#505/#504 landings the same day.
- **(b) same-subject HIT → reuse** — observed at the #496 window (first operational HIT) and identity-reuse push PASS telemetry (2026-10-06 03:18).
- **(c) cache eviction → rebuild → PASS** — `axiom-b-18960fa7…` was evicted and re-seeded at 09:22:22Z (deadlock fix #501 + NO-FIRE window #55). With V1, the gate-binary half of that incident class is structurally closed: cache loss degrades to native rebuild + artifact fallback, never to a missing attest supply.

## Rotation window note

During the #506 group, the org-hosted callee still executed the pre-rotation generation (`Uses: …/admission-check.yml@22ae6bd3…` visible in the job log). The rotation to `9924997de` landed at 11:18:22Z (.github #57, `7b6913363`); the DEBT#480-shaped window documented in #506's body closed with it.

## Not claimed

- In-CI attribution lines for org-hosted (pinned-generation) production runs take effect from their first firing on `9924997de` (rotation at 11:18:22Z).
- The cert-ledger scan optimization itself — follow-up workstream, not part of this record.
