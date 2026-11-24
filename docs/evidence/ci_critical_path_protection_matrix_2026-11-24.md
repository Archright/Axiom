# CI critical-path protection matrix — evidence that "this optimization is impossible"

> **Nature**: an observation record. No policy or config file is modified. This document
> records results computed against `main` @ `160e70cd` (queried 2026-11-24T05:43:31Z).
> **Purpose**: pin down, as an authoritative and reproducible table, which control device
> locks each file on the admission critical path — so that "impossible" is stated as
> evidence rather than as an assumption.

## 0. Measurement environment and reproduction

| item | value | measurement command |
|---|---|---|
| base commit | `160e70cda364e5745133d3f04d2e1295b4a026df` | `git rev-parse HEAD` |
| query time (UTC) | `2026-11-24T05:43:31Z` | `date -u +%Y-%m-%dT%H:%M:%SZ` |
| `repository_surface.json` `policyVersion` | `108` | `python3 -c 'import json;print(json.load(open("config/repository_surface.json"))["policyVersion"])'` |
| four source sizes | manifest 18 / trustSurface 39 / closure 891 / surface FROZEN 12 | §1 below |

The verdicts were not counted by hand. They were computed with a classifier that ports
the semantics of `tools/surface_guard.nim` one-to-one — `globMatch`
(`tools/surface_guard.nim:186`, segment-wise, where `**` swallows zero or more segments)
and `resolveClass` (`tools/surface_guard.nim:245`, PRODUCT → CONTROLLED → FROZEN
first-match followed by `defaultClass`). The reproduction script is printed in full in
§7.

## 1. The four control devices — what each one actually enforces

| # | source | size | enforcing party | verdict meaning |
|---|---|---|---|---|
| A | `config/policy/trust_surface_manifest.json` `paths` | **18** | **external** GitHub App `axiom-admission-verifier` (id `5795152`) | if `blob(G) != blob(B_mg)`, **refuses to issue** `admission-check` |
| B | `config/policy/merge_admission.json` `trustSurface` | **39** | `src/cli/merge_cli.nim` `trustSurfaceMatch` (`:954`) | on a match, refuses auto-merge → **manual merge lane** |
| C | `config/trusted_checker_closure.json` `trustedCheckerTreeClosure` | **891** | `.githooks/pre-push` rotation-pin anchor (`:565-646`) | if the pin cannot anchor the commit, **blocks the push** (`rotation pin does not anchor pushed commit`) |
| D | `config/repository_surface.json` `classes.FROZEN` + `frozenExceptions` | FROZEN 12 patterns / 116 exception paths / 8 groups | `tools/surface_guard.nim` (in-tree) + the SL-20 step | `SURFACE_FORBIDDEN` → the `admission-check` step FAILs |

**Size correction for A**: the `paths` array in `trust_surface_manifest.json` holds
**18 entries** (the file itself, `:7-24`). Several documents in this repository still
say "15-path" or "17-path" (`.github/workflows/admission-check.yml:37`,
`docs/agents/axiom_admission_verifier_ops.md:90`, DEBT#558's "17 paths" in
`data/debt_registry.json`). That is **documentation drift**; this document uses the
actual value in the file.

**B contains a glob** — `.github/actions/setup-axiom-toolchain/**` (5th of the 39).
An exact-string comparison **silently misses** this entry. The first computation here
did exactly that, and it was recomputed after fixing the match to glob semantics. This
is the empirical case for "do not count by eye".

## 2. Protection matrix over 14 files

Legend: A = App byte-identity (manifest), B = trustSurface (manual merge), C = checker
closure (891), D = repository surface class. `—` = not applicable.

| # | path | A | B | C | D (resolved class / matching pattern) | verdicts (all listed) |
|---|---|---|---|---|---|---|
| 1 | `.github/workflows/axiom-operational-slice.yml` | **Y** | **Y** | — | **FROZEN** / `.github/**` | `APP_BYTE_IDENTITY`, `ADMISSION_MANUAL_AUDIT`, `SURFACE_FROZEN` |
| 2 | `.github/workflows/admission-gate-v2.yml` | **Y** | — | — | CONTROLLED / exact | `APP_BYTE_IDENTITY`, `SURFACE_EXCEPTION(admission-mint-pin-rotation)` |
| 3 | `.github/workflows/admission-check.yml` | **Y** | **Y** | — | CONTROLLED / exact | `APP_BYTE_IDENTITY`, `ADMISSION_MANUAL_AUDIT`, `SURFACE_EXCEPTION(epoch-rotation)` |
| 4 | `.github/workflows/certificate-mint.yml` | **Y** | **Y** | — | CONTROLLED / exact | `APP_BYTE_IDENTITY`, `ADMISSION_MANUAL_AUDIT`, `SURFACE_EXCEPTION(admission-mint-pin-rotation)` |
| 5 | `.github/workflows/runner-pool-acceptance.yml` | **Y** | **Y** | — | **FROZEN** / `.github/**` | `APP_BYTE_IDENTITY`, `ADMISSION_MANUAL_AUDIT`, `SURFACE_FROZEN` |
| 6 | `.github/actions/setup-axiom-toolchain/action.yml` | **Y** | **Y** (glob `**`) | — | CONTROLLED / exact | `APP_BYTE_IDENTITY`, `ADMISSION_MANUAL_AUDIT`, `SURFACE_EXCEPTION(trust-supply-path)` |
| 7 | `src/gate/runners/readiness_start_gate.nim` | — | **Y** | — | CONTROLLED / exact (intersects the FROZEN glob `src/gate/**`) | `ADMISSION_MANUAL_AUDIT`, `SURFACE_EXCEPTION(gate-infra)` |
| 8 | `tools/readiness_evaluator.nim` | — | **Y** | — | PRODUCT (unregistered) | `ADMISSION_MANUAL_AUDIT`, `SURFACE_PRODUCT` |
| 9 | `tools/ci/readiness_collect_ci.nim` | — | **Y** | — | PRODUCT (unregistered) | `ADMISSION_MANUAL_AUDIT`, `SURFACE_PRODUCT` |
| 10 | `config/readiness_policy.json` | — | **Y** | — | PRODUCT (unregistered) | `ADMISSION_MANUAL_AUDIT`, `SURFACE_PRODUCT` |
| 11 | `tools/ci/ci_admission_observe.nim` | — | — | — | PRODUCT (unregistered) | `SURFACE_PRODUCT` |
| 12 | `tests/ci/test_ci_admission_observe.nim` | — | — | — | PRODUCT (unregistered) | `SURFACE_PRODUCT` |
| 13 | `docs/spec/ci_critical_path_metric.md` | — | — | — | PRODUCT (unregistered) | `SURFACE_PRODUCT` |
| 14 | `config/repository_surface.json` | **Y** | — | — | **FROZEN** / exact | `APP_BYTE_IDENTITY`, `SURFACE_FROZEN` |

**Why C is `—` everywhere**: the 891 entries break down as `src/` 879 + `tools/` 7 +
root 2 + `ci/` 1 + `config/` 1 + `tests/` 1, and none of the 14 files is among them.
The 7 `tools/` entries are `derive_checker_closure.nim`, `impact_closure_selector.nim`,
`proof_reconcile_gate.nim`, `hermetic_build.nim`, `safe_move.nim`, `setup_hooks.nim`,
and `sha256_native.nim`. So **C locks nothing across these 14 paths.**

**The key contrast**: two files on the same critical path sit in different grades —
`tools/readiness_evaluator.nim` (B only, `SURFACE_PRODUCT`) versus
`src/gate/runners/readiness_start_gate.nim` (B plus the `gate-infra` exception). The
surface guard passes the former as `MODIFY=PASS`, and it passes the latter too, thanks
to the exception registration (§3). Yet **both are caught by B, so auto-merge is
refused** — a pair that demonstrates the two devices are independent.

## 3. Question: does registering in `frozenExceptions` open the App's byte-identity check?

**No. It opens the repository surface guard only.** The basis is three layers.

### 3.1 the surface side — enforcement confirmed in code

| fact | evidence |
|---|---|
| `classify()` **never reads** `frozenExceptions` | `tools/surface_guard.nim:491` `classify()` → `:519` `resolveClass(policy, p)` → `:520` `ruleValue(...)` only. No exception-registry lookup. |
| the sole caller of `frozenExceptionPaths()` is a **test** | `grep -rn frozenExceptionPaths tests/ src/ tools/` → the definition (`tools/surface_guard.nim:273`) and `tests/unit/test_surface_guard.nim:766` only |
| an exception is a **policy-validity** device | `tools/surface_guard.nim:445-466`: an exact CONTROLLED/PRODUCT registration that intersects a FROZEN glob **requires** registration (`:445-460`) and (`:461-463` — an unregistered conflict is `POLICY_INVALID`), while a registration that does not intersect is **rejected** (`:464-466`, DEBT#545 dead exception) |
| what an exception actually changes | the **class registration itself**, which makes that path resolve to `CONTROLLED` in first-match. 115 of the 116 are in `classes.CONTROLLED` verbatim; the remaining one is in `classes.PRODUCT`. |

Measured confirmation — same policy, same guard binary (`bin/surface_guard`,
policyVersion 108):

```text
$ printf 'M\t.github/workflows/admission-gate-v2.yml\n' > /tmp/d.txt
$ ./bin/surface_guard --policy config/repository_surface.json --diff /tmp/d.txt
verdict=PASS reasonCode=OK                   # path registered in an exception group
exit=0

$ printf 'M\t.github/workflows/axiom-operational-slice.yml\n' > /tmp/d.txt
$ ./bin/surface_guard --policy config/repository_surface.json --diff /tmp/d.txt
verdict=FAIL reasonCode=SURFACE_FORBIDDEN    # not registered -> FROZEN
  changeClass=FROZEN op=MODIFY
exit=1
```

The authoritative document says the same thing — `docs/spec/repository_surface_contract.md:700-702`
(v108 appendix): "registration is a declaration, not a runtime carve-out; classification
follows first-match in `resolutionOrder`."

### 3.2 the App side — **external**, so documented and inferred facts are separated

| kind | content | source nature |
|---|---|---|
| **documented** | App `5795152` compares `blob(G) == blob(B_mg)`; `readFrom` is `B_mg`, not `G` | `config/policy/trust_surface_manifest.json:2-5` (`"purpose"`, `"comparison"`, `"readFrom"`) — the policy file's own declaration |
| **documented** | on mismatch, `conclusion=failure`; 17 of 18 paths are on the critical path | `data/debt_registry.json` DEBT#558 `:6057` (quoting `worker/src/index.js:309-338`, `:180-185`) |
| **inferred** | the App code **does not know** about `frozenExceptions` | the App source is outside this repository (`worker/src/index.js`) and cannot be read directly. The only input the App reads is `trust_surface_manifest.json` (`:5` `readFrom: B_mg`), and that file has **no** `frozenExceptions` key — its only top-level keys are `schema`, `purpose`, `comparison`, `readFrom`, `paths`. |

**Strength of the inference**: even if the App read `repository_surface.json`, §3.1 shows
that the file's `frozenExceptions` is a **declaration that does not change the
classification result**. Either way, the path "register an exception → pass the App"
does not exist.

**Six paths are caught by both devices at once** — in an exception group and also in the
App manifest:

| path | exception group | App manifest |
|---|---|---|
| `.github/actions/setup-axiom-toolchain/action.yml` | `trust-supply-path` | Y |
| `.github/workflows/admission-check.yml` | `epoch-rotation` | Y |
| `config/policy/epoch_manifest.json` | `epoch-rotation` | Y |
| `.github/workflows/admission-gate-v2.yml` | `admission-mint-pin-rotation` | Y |
| `.github/workflows/certificate-mint.yml` | `admission-mint-pin-rotation` | Y |
| `.github/workflows/publication-integrity.yml` | `publication-venue-split` | Y |

These six **pass the surface guard but do not pass App byte-identity**. That is why dead
exceptions and live exceptions must be distinguished — from the surface view the
exception is valid, but what actually locks the path is B (the App).

## 4. Decomposition of the critical-path wall — which seconds live inside a protected file

Measured wall: `.github/workflows/axiom-operational-slice.yml` at **591 s** (job1 283 s
+ gap 4 s + job2 302 s). The two jobs are serial via `readiness-verdict` →
`needs: [axiom-operational-slice]` (`.github/workflows/axiom-operational-slice.yml:319-320`),
so the wall is their sum.

> **Arithmetic correction**: 283 + 4 + 302 = **589**, not 591. The table below keeps the
> brief's 591 in its header but records 589 alongside it in the total row. The 2-second
> difference is left unresolved (not estimated).

| step | seconds | file that actually performs the step | A | B | C | D | protection state |
|---|---:|---|---|---|---|---|---|
| job1 setup | 28 | `.github/actions/setup-axiom-toolchain/action.yml` | **Y** | **Y** | — | CONTROLLED (`trust-supply-path`) | **blocked by A** |
| job1 build release verifier | 129 | `Makefile`, `ci/checker.mk`, `config.nims` | — | — | checker.mk **Y**, config.nims **Y** | CONTROLLED | **blocked by C** |
| job1 prove/replay | 77 | `Makefile` (`make verify-contract-release-e2e-full`, `:1170`) | — | — | — | CONTROLLED | **no lock** |
| job1 determinism ratchet | 12 | `tests/gateway/deterministic_parallel_proof_test.nim` | — | — | — | **PRODUCT** | **no lock** |
| job1 R3 | 10 | `tools/ci/wp5_relocation_measure.nim` | — | — | — | **PRODUCT** | **no lock** |
| job1 subtotal | **256** | | | | | | |
| job2 setup | 64 | `.github/actions/setup-axiom-toolchain/action.yml` | **Y** | **Y** | — | CONTROLLED (`trust-supply-path`) | **blocked by A** |
| job2 supply verification | 92 | `Makefile` (plus the `logs/run-manifest.json`, `logs/r3_relocation.json` artifacts) | — | — | — | CONTROLLED | **no lock** |
| job2 readiness decision test suite | 79 | `tests/ci/test_readiness_verdict_mapping.nim` and 4 others | — | — | — | **PRODUCT** | **no lock** |
| job2 readiness gate | 29 | `src/gate/runners/readiness_start_gate.nim` | — | **Y** | — | CONTROLLED (`gate-infra`) | **blocked by B** |
| job2 collect R1–R8 | 26 | `tools/ci/readiness_collect_ci.nim` | — | **Y** | — | **PRODUCT** | **blocked by B** |
| job2 subtotal | **290** | | | | | | |
| total (known steps) | **546** | | | | | | |
| wall (job1+gap+job2) | 589 / (591) | | | | | | |
| unattributed | 43 | gap 4 + artifact upload/download + checkout and similar | | | | | |

### 4.1 Conclusion — seconds by protection grade

| grade | seconds | share (of 546) | steps |
|---|---:|---:|---|
| **blocked by A** (App byte-identity) — without break-glass the candidate cannot pass | **92** | 16.8% | job1 setup 28, job2 setup 64 |
| **blocked by C** (checker-closure rotation pin) | **129** | 23.6% | build verifier 129 (`ci/checker.mk`, `config.nims`) |
| **B only** (trustSurface — auto-merge refused, manual merge possible) | **55** | 10.1% | readiness gate 29, collect R1–R8 26 |
| **no lock** (absent from A, B, and C — surface class is PRODUCT or CONTROLLED) | **270** | 49.5% | prove/replay 77, supply verification 92, readiness test suite 79, determinism ratchet 12, R3 10 |
| total | **546** | 100% | |

> `Makefile` is neither A, B, nor C and is surface CONTROLLED (`MODIFY=PASS`), so
> prove/replay 77 s and supply verification 92 s are classed **no lock**. By contrast the
> inputs to build verifier's 129 s — `ci/checker.mk` and `config.nims` — are in C and are
> subject to the rotation pin. Even within "Makefile steps", the grade depends on **which
> file decides those seconds**. That distinction is this document's conclusion.

### 4.2 The precise scope of "impossible"

- **Genuinely impossible (92 s, 16.8%)**: job1 + job2 setup. `action.yml` is in A
  (byte-identity), so a candidate PR cannot change this file and still receive
  `admission-check` — the App refuses to issue it and only the break-glass (MUST-T2a)
  manual lane remains.
- **Locked by C (129 s, 23.6%)**: build release verifier. `ci/checker.mk` and
  `config.nims` are in the 891 closure, so a `.githooks/pre-push` rotation-pin re-anchor
  is required. Not impossible, but every PR is forced to carry a pin-rotation commit.
- **Locked by B (55 s, 10.1%)**: collect 26 + readiness gate 29. Auto-merge is refused,
  but it can land through a one-time manual merge lane — **the optimization itself is
  possible.**
- **No lock (270 s, 49.5%)**: prove/replay 77, supply verification 92, readiness test
  suite 79, determinism ratchet 12, R3 10. The files performing these five steps are
  surface PRODUCT or CONTROLLED and appear in none of A, B, C. There is **no mechanical
  lock** here — the optimization is not "impossible", it is simply **not yet done**.

So of the 546 s critical path, **only 92 s (16.8%) is mechanically blocked**, and the
remaining 454 s can be touched through a policy PR, a pin rotation, a manual merge, or
with no constraint at all. The claim "this optimization is impossible" holds **only for
the 92 s of setup**.

## 5. Documented versus inferred (explicit)

| claim | basis | confidence |
|---|---|---|
| A/B/C/D membership of the 14 files | output of the §7 script | **measured** |
| `frozenExceptions` does not change surface classification | `classify()` / `resolveClass` code + guard-binary measurement | **measured** |
| the App does not know about `frozenExceptions` | App source is out-of-tree (`worker/src/index.js`); no such key in the manifest | **inferred** (§3.2) |
| App comparator line numbers `:309-338` | quoted from `data/debt_registry.json:6057` | **documented quotation** (original unverified) |
| wall 591 s and the per-step seconds | values supplied by the brief | **not re-measured** — no independent measurement was taken |
| "17/15 paths" | document prose | **drift** — the file's actual value is 18 |

## 6. Findings that diverge from the brief

1. **A's size is 18**, and the documents' "15-path" (`admission-check.yml:37`, verifier
   ops `:90`) and DEBT#558's "17 paths" are **stale**. The correct statement is that 18
   paths are compared.
2. **B contains a glob** — `.github/actions/setup-axiom-toolchain/**`. An exact
   comparison misses `action.yml` in B. This document's first computation was wrong and
   was corrected.
3. **Wall arithmetic**: 283 + 4 + 302 = **589**, a 2-second difference from the brief's
   591. Recorded as unresolved.
4. **The known-step total is 546** (28+129+77+12+10+64+92+79+29+26). The unattributed
   remainder is 589 − 546 = 43 s, of which 4 s is the gap.
5. **`tests/unit/test_surface_guard.nim` currently fails** — that file is outside this
   task's scope and was not modified. Details in §8.

## 7. Reproduction script

A classifier porting `globMatch` and `resolveClass` from `tools/surface_guard.nim`. Run
with `python3` from the repository root.

```python
import json, re
REPO = "."
def seg(p, s): return re.fullmatch(re.escape(p).replace(r"\*", "[^/]*"), s) is not None
def glob_match(pat, path):
    ps = [s for s in pat.split("/") if s]; xs = [s for s in path.split("/") if s]
    pi = si = 0; sp = -1; ss = 0
    while si < len(xs):
        if pi < len(ps) and ps[pi] == "**": sp, ss, pi = pi, si, pi + 1
        elif pi < len(ps) and seg(ps[pi], xs[si]): pi, si = pi + 1, si + 1
        elif sp >= 0: pi = sp + 1; ss += 1; si = ss
        else: return False
    while pi < len(ps) and ps[pi] == "**": pi += 1
    return pi == len(ps)

rs  = json.load(open(f"{REPO}/config/repository_surface.json"))
cl  = json.load(open(f"{REPO}/config/trusted_checker_closure.json"))["trustedCheckerTreeClosure"]
man = json.load(open(f"{REPO}/config/policy/trust_surface_manifest.json"))["paths"]
adm = json.load(open(f"{REPO}/config/policy/merge_admission.json"))["trustSurface"]

for p in ["<path>"]:
    cls = next((c for c in ["PRODUCT","CONTROLLED","FROZEN"]
                if any(glob_match(x, p) for x in rs["classes"][c])), rs["defaultClass"])
    print(p, "A=", p in man, "B=", [x for x in adm if glob_match(x, p)],
          "C=", p in cl, "D=", cls, "exc=", rs["frozenExceptions"]["paths"].get(p))
```

Guard measurement reproduction (§3.1):

```bash
printf 'M\t.github/workflows/admission-gate-v2.yml\n' > /tmp/d.txt
./bin/surface_guard --policy config/repository_surface.json --diff /tmp/d.txt; echo "exit=$?"
```

## 8. Out-of-scope observation (not modified)

Running `nim c -r --hints:off tests/unit/test_surface_guard.nim` produced **59 OK out of
60, with 1 failure**:

```text
tests/unit/test_surface_guard.nim(766, 48): Check failed: frozenExceptionPaths(loaded.node).len == 109
  frozenExceptionPaths(loaded.node).len was 116
tests/unit/test_surface_guard.nim(769, 38): Check failed: v["policyVersion"].getInt() == 102
  v["policyVersion"].getInt() was 108
[FAILED] shipped policy v102 is valid and registers 109 exceptions
Error: execution of an external program failed
```

Both the test name ("shipped policy **v102**") and its expectations (109/102) lag the
shipped policy (108/116) — only this test appears not to have been updated across the
v105–v108 revisions. **It is not a file of this task, so it was not fixed.** Policy
validity itself passes `isValidPolicy` (`classify()` does not emit `POLICY_INVALID` —
measured in §3.1), and every other test is `[OK]`.
