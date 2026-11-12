# Evidence CAS re-arm observation — post-#56 armed generation (2026-10-06)

## What this record is

Production observation of the Evidence CAS armed generation after the
emergency-rollback cycle (`.github` #55 → #56): the callee pins were
re-rotated to `22ae6bd3…` (Axiom #502's merge commit — the
provenance-determinism fix, EvidenceKeyScheme v1 byte-identical), and the
first runs under that generation are recorded here. Companion records:
`evidence_cas_rollout_timeline_2026-10-06.md` (generation boundaries),
`evidence_cas_baseline_2026-10-06.md` (pre-activation baseline + wall#1),
`evidence_cas_acceptance_2026-10-06.md` (acceptance checklist). All times
UTC, all quotes verbatim from job logs (escape sequences stripped).

## Trigger chain (why a fresh run was needed)

#500's 07:34:16Z pull_request admission failed in the cache-eviction
deadlock era (pre-#502 base, pre-#55 rollback). `gh run rerun` re-uses the
original refs (main@07:34 — without the structural fix), so the only sound
re-admission path was a fresh synchronize run: an empty retrigger commit
(`68626fa`) was pushed to `fix/evidence-cas-empty-tree-tip`, producing run
`37448627454` — the first armed run created after the 10:07:00Z re-rotation
(org PR #56, merge commit `aadce265`).

## Armed MISS — pull_request context (run `37448627454`, job `112221385111`)

```
[check] AXIOM_EVIDENCE_CAS armed (base 18960fa7fdcf, head 6527ba2b41fa4afc5893a3e08f007a391063e999, merge a2ee23552676)
AXIOM_EVIDENCE_CAS: MISS — produced + stored record 3a02138af7e9
[cert] Attest --witness-only: PASS (chain a-f) — unsigned witness bundle witness.json
[check] evidence record staged: /home/runner/work/Axiom/Axiom/evidence-record.json
[check] attest --witness-only PASS (subject head 68626fa178826cfdbf612f9c4022f6b5bc3db384, subject tree 6527ba2b41fa4afc5893a3e08f007a391063e999, merge tree a2ee23552676906f21791fc09ebd8dab6203f736, B b2a979b47ff4, run 37448627454/1)
```

Callee binding proven in-log: `Uses:
Archright/Axiom/.github/workflows/admission-check.yml@22ae6bd3…`. The
axiom-b runner cache was healthy again (`AXIOM_CACHE_B_VERIFY: RESULT OK —
3/3 entries digest-verified, buildSha=18960fa7fdcf, key exact-hit`) — the
eviction deadlock did not recur on the armed generation.

## Armed MISS — merge_group context (#504 round, run `37448819166`)

```
[check] AXIOM_EVIDENCE_CAS armed (base 63d8ec0c43ce, head c06dc5fa678351e2edd00689435bcda9695479d0, merge baf8f9c7aebd)
AXIOM_EVIDENCE_CAS: MISS — produced + stored record 60c605e1eb5b
[check] attest --witness-only PASS (subject head 14da5c845ab95075f6af90f468d6fbba7dcc1374, subject tree c06dc5fa678351e2edd00689435bcda9695479d0, merge tree baf8f9c7aebdf96c2401c20236ce4d84b98bc157, B 4330f6b849ed, run 37448819166/1)
```

The queue-phase run executes the armed callee directly against the queue
merge tree (`gh-readonly-queue/main/pr-504-4330f6b…`); a new semantic
identity (post-#503 main) → MISS as designed. A fresh B-cache
(`63d8ec0c43ce`, 4/4 digest-verified) was seeded for the new main —
re-seeding works post-#56 (single-writer publisher intact).

## Rounds inside and after the rollback window (wall continuity)

| PR | round run | window | wall | generation |
|---|---|---|---|---|
| #502 | `37444016474` | 09:35:30→09:47:52 | 12m22s | NO-FIRE (#55 rollback) |
| #499+#503 (group) | `37447081665` | 10:02:22→10:17:11 | 14m49s | NO-FIRE; landed back-to-back 10:17:36/37 |
| #504 | `37448819166` | 10:17:41→10:32:36 | 14m55s | ARMED (#56) — merged 10:33:02 (`0b12775a`) |
| #500 | `37450522501` | 10:33:04→10:44:56 | 11m52s | ARMED (#56) — merged 10:45:20 (`b70b5f44`); round record `49d806fa0da8` |

## Key base-sensitivity observed in production (planned-slice §6 check)

The vertical-slice plan asked whether the evidence key could exclude the
base (baseSha). The armed generation answers this empirically: #500's
pull_request run stored record `3a02138af7e9` for subject head tree
`6527ba2b…` at B `b2a979b47ff4` (merge tree `a2ee2355…`); its own queue
round then ran with the SAME subject head tree `6527ba2b…` but B `4330f6b…`
→ new base build tree `a5db0191e9fb` (merge tree `a28ee368…`) — and got
**MISS**, storing `49d806fa0da8`. The implemented verifier identity
(`verifierIdentityWire`: treeOID(B) + recipe/toolchain pins + policy/scope)
therefore binds the base build tree — base movement → new key → no reuse.
This is the conservative soundness choice: the plan's baseSha-exclusion was
NOT taken, and the two records above are the production proof that base
movement cannot produce a false HIT. Same-B re-verification (PR run → solo
round with no interleaved landing) remains the HIT path, as wall#1 showed.

## HIT-path status

- wall#1 (armed era, pre-#55): run `37426625460`, HIT at 07:03:16, attest
  job 1m33s, run total 13m53s — acceptance checklist records the HIT path
  as observed (admission PASS, landed).
- Post-#56 HIT vehicle: this PR itself — its pull_request run stores the
  evidence record for its own merge tree; its solo merge_group round
  verifies the SAME tree, so the round is expected to log
  `AXIOM_EVIDENCE_CAS: HIT — reused …` and skip kernel re-execution. The
  round's admission run id and wall are readable from Actions after
  landing and are reported in the landing report (this file's table is
  frozen at record time to keep the observation append-only).

## Landing report — #507 (this record's own landing)

| phase | value |
|---|---|
| pull_request admission run | `37452415760` — armed, MISS, record `0cc9e7005bcb` (subject tree `04cd1b23…`, merge tree `4529df47…`) |
| merge_group round run | `37453932827` — armed, **MISS**, record `cda1e2e65d0b` (subject tree `04cd1b23…` UNCHANGED, merge tree `9294be9d…`, B `9924997de9d2`) |
| window | round 11:04:03→11:19:35 (15m32s); merged 11:19:58 (`7e5f597a`) |
| HIT attempt | spoiled by an interleaved landing (#506, merged after this PR's head run, before enqueue): same subject tree, moved base → per-key MISS. Contract-correct: no false reuse. |

This is the strongest base-sensitivity pair yet: one PR, one subject
tree, two B values → two distinct records. The post-#56 HIT retry is
the next PR's own round (queue empty at push, no interleave assumed —
result cited in the session landing report and Actions run logs).

## Landing report — #508 (post-#56 HIT observed)

| phase | value |
|---|---|
| pull_request admission run | `37456199924` — armed, MISS, record `59b269653825` (subject tree `fe279c63…`, merge tree `ec73da249107`) at 11:31:14 |
| merge_group round run | `37457828446` — solo round (queued ahead of #509's green); armed, **HIT — reused + rebound record `59b269653825` (evidence bytes re-verified)** at 11:45:50 (job `112251536121`) |
| window | round 11:39:13→11:53:44 (14m31s); merged 11:54:08 (`e670ed33`) |
| wall note | enqueue→merge 14m55s: HIT removes kernel re-execution inside attest only; B-build (~5m) + verdict predicate (~4.5–5.5m) dominate and are out of this slice's scope — the ≤8min HIT-wall target stays **not met** pending those follow-ups |

Terminal Outcome (production): MISS path ✓ (records `3a02138af7e9`,
`60c605e1eb5b`, `49d806fa0da8`, `0cc9e7005bcb`, `cda1e2e65d0b`,
`59b269653825`), HIT path ✓ (wall#1 `37426625460` armed era + this
`37457828446` post-#56), base-movement no-false-reuse ✓ (#500/#507
same-subject-tree pairs). This landing closes the re-arm observation.
