# Lean Pre-Flight Probe Assurance Matrix (2026-11-23)

## 1. Subject and method

`verifyInfrastructure` (`src/verification/batch_uap/loop_driver.nim:784`) ran two shell probes before every batch run:

- a Z3 query probe (`src/verification/batch_uap/loop_driver.nim:790-799`, kept by this change);
- a Lean compile of `theorem axiomPreFlightProbe : True := trivial` through `lake env lean` (`src/verification/batch_uap/loop_driver.nim:801-810` at `5b14bbfc`, removed by this change), which issued no receipt and wrote no artifact.

Its single caller is `src/verification/batch_uap/loop_driver.nim:820` (was `:830` at `5b14bbfc`), which ran before `generatePbtRegistry()` (`src/verification/batch_uap/loop_driver.nim:828`) and before any IR, vault, or certificate write.

Issue #351 asks whether that Lean probe carries assurance the per-obligation kernel path lacks. Method: read every producing and consuming site at `5b14bbfc`; re-measure the probe command on this host; compile and run `tests/unit/batch_uap_orchestrator_test.nim`, which exercises the pre-flight and its bypass. Nothing here is inferred from a green build.

## 2. Verdict

**The Lean pre-flight probe carries no unique assurance, so it was removed.** It can only change the *message* and the *timing* of a failure, never the run verdict, and in the one reachable shape where it fires alone it would demote a verdict the authority reached without Lean.

## 3. Assurance matrix

| check | what it observes | where | cost on this host |
|---|---|---|---|
| Lean pre-flight | one Lean process accepts `True := trivial` | `loop_driver.nim:801-810` at `5b14bbfc` | 465-485 ms, 5-run median 482 ms |
| per-obligation kernel check | the real artifact's theorem is accepted by the resolved kernel; issues a receipt on exit 0 only | `src/verification/obligation/lean_kernel_boundary.nim:346-352`, invocation `:426-428`, decline `:453-473` | 456-495 ms per obligation (`--threads=1`) |
| Z3 pre-flight | z3 answers `sat` on `(assert true)` | `src/verification/batch_uap/loop_driver.nim:790-799` | kept, out of scope |

Two claims that were circulating before this note do not survive the code:

- The probe is **not** the weaker invocation. It runs `lake env lean <file>`, which is the same executable and the same `lake` resolution the receipt path uses: `canonicalLeanKernelCheck` builds `resolvedCmd & " --threads=1 " & quoteShell(artifactPath)` with `resolvedCmd = "lake env lean"` (`lean_kernel_boundary.nim:357-360`, `:417`). `resolveLeanBinaryPath` (`lean_kernel_boundary.nim:366`) is used for the *binary digest* fed into the toolchain fingerprint, not to pick the invoker. `QUIRK(DEBT#427)` (`lean_kernel_boundary.nim:146-150`) is about identity measurement, so it cannot apply to a probe that asserts no identity.
- The probe is **not** the only check that runs before a write. It is the only check that runs before a write *and returns a dedicated line*, which is attribution, not coverage.

## 4. The one gap that is real, and why it does not reach a verdict

The probe's only candidate for unique assurance is a run in which **zero Lean kernel checks are issued**, where the per-obligation path observes nothing by construction. That shape is reachable: `runVerificationWaves` runs a wave even with an empty frontier when the run is targeted (`src/cli/axiom_engine.nim:6211`, `:6222-6229`), and `runBatchVerification` forwards that empty request set to the orchestrator (`src/cli/axiom_engine.nim:6118` -> `:719`), where the probe was the first statement. `tests/unit/batch_uap_orchestrator_test.nim:19-29` calls `runBatchUapOrchestration(state, @[], ...)` with no bypass env and is therefore already that shape.

In that shape the run-level authority already decides without Lean, and it does not decide PASS from an empty universe:

| shape | verdict | citation |
|---|---|---|
| zero units | INCONCLUSIVE, never PASS ("0 units is not a PASS") | `src/verification/obligation/verification_decision_authority.nim:276-279` |
| units present, all NOT_REQUIRED, universe enumerated | PASS basis NO_OBLIGATION | `src/verification/obligation/verification_decision_authority.nim:271-275` |

INCONCLUSIVE maps to UNRESOLVED and a non-zero exit (`src/core/utils/decision_algebra.nim:228-230`, consumed once at `src/cli/wf_runners.nim:46-72`), so in the zero-unit case the removal changes no exit code and no verdict class. In the NO_OBLIGATION case the probe changed a verdict that never depended on Lean: a subject with nothing to prove was failed because a tool it never invoked was broken. Removing the probe removes that false negative.

## 5. Failure semantics after removal

- One or more obligations reach the kernel: a broken toolchain surfaces as N node-level proof failures, each carrying the kernel's own first diagnostic lines (`lean_kernel_boundary.nim:453-473`), instead of one infrastructure line and one empty `BatchUapReport`.
- Zero obligations, zero units: unchanged. The run is INCONCLUSIVE and exits non-zero.
- Zero obligations, units present and all NOT_REQUIRED: the run now reaches its PASS(NO_OBLIGATION) verdict instead of failing on an unused toolchain.
- What is genuinely lost: the single `CRITICAL: Lean compiler dysfunctional` line, and the abort at `loop_driver.nim:820` before `generatePbtRegistry()` (`:828`) and before any IR, vault, or certificate write. A dead toolchain is now discovered at the first kernel check rather than before the first write. No artifact from such a run can claim Lean acceptance: certificates stay z3-candidate until a receipt exists.

## 6. Not claimed

- No end-to-end run against a deliberately broken Lean toolchain was executed for this note. The verdict-class equivalence above is established by reading the decision path, not by observing it, and the 263 ms figure in the issue was not reproduced: this host measures 465-485 ms.
- The Z3 pre-flight has the same structural property (it too runs when zero obligations are generated) and was kept out of scope by issue #351. Whatever argument applies to it was not measured here.
- Removing the probe does not land the issue's third acceptance criterion (duplicate `lake env which lean` resolution reduced to once per run). That duplication lives in the fingerprint path, not in the removed block.

## 7. Reproduction

```bash
# the removed invocation, timed on this host (5 runs)
printf 'theorem axiomPreFlightProbe : True := trivial\n' > /tmp/p.lean
lake env lean /tmp/p.lean

# the one caller of the pre-flight (no other caller existed at 5b14bbfc)
grep -rn "verifyInfrastructure" src tests

# the bypass the tests already used
sed -n '170,190p' tests/unit/batch_uap_orchestrator_test.nim

# the zero-request shape that reaches the pre-flight with no obligations
sed -n '19,29p' tests/unit/batch_uap_orchestrator_test.nim
```

Test result after the change: `tests/unit/batch_uap_orchestrator_test.nim` compiled and ran with `make test-fast-one`, 0 failed checks.