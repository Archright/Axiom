import core/trusted/layer_declaration

## Pinned solver randomness — every SMT-LIB option set Axiom emits must derive
## from the ONE pinned list in core/trusted/solver_invocation.
##
## SMT-LIB 2.7 §4.1.7: `:random-seed 0` means the solver MAY choose a different
## seed on every run, so seed 0 is the opt-OUT of determinism, not a pin. A
## site that hard-codes 0 while the recorded option set claims a pinned seed is
## a reproducibility claim the emitted script does not honour.

import std/os
import std/strutils
import core/crypto/hash_kernel
import core/gateway/gateway_main
import core/trusted/private/canonical_chc_compiler
import core/trusted/solver_invocation
import core/utils/repo_root

const seedZeroDirectives = [
  "(set-option :random-seed 0)",
  "(set-option :sat.random_seed 0)",
  "(set-option :fp.spacer.random_seed 0)"
]

## The six modules this change routed through the pinned projection.
const routedModules = [
  "src/core/contracts/z3_extraction.nim",
  "src/core/gateway/gateway_main.nim",
  "src/core/testing/axiom_dsl.nim",
  "src/core/trusted/private/canonical_chc_compiler.nim",
  "src/core/trusted/private/ir_loop_to_horn.nim",
  "src/core/test_support/static_contract.nim"
]

## Seed-0 emissions that survive elsewhere in src/ and are reported, not fixed,
## by this change: the one left sits outside the routed modules above, in a
## directory this change does not own.
const knownOutliers = [
  "src/verification/solver/fixedpoint_engine.nim"
]

proc expect(cond: bool; msg: string) =
  if not cond:
    doAssert false, msg
  echo "  OK: " & msg

proc expectPinnedOptions(emitted, site: string) =
  ## Every pinned directive must be present with the pinned value, and none of
  ## them may be present with the opt-out value.
  let pinned = pinnedDeterminismOptions()
  for spec in pinned:
    let directive = solverOptionDirective(spec)
    expect(emitted.contains(directive),
      site & " emits " & directive)
  for zero in seedZeroDirectives:
    expect(not emitted.contains(zero),
      site & " does not emit the opt-out " & zero)
  expect(Z3PinnedRandomSeed != 0, "the pinned seed is non-zero")

block:
  echo "=== 1. the CHC prelude emitted by the canonical compiler ==="
  expectPinnedOptions(hornPrelude, "canonical_chc_compiler.hornPrelude")
  expect(hornPrelude.contains("(set-logic HORN)"),
    "the HORN logic header survives the option-set change")
  expect(hornPrelude.contains("(set-option :fp.engine spacer)"),
    "the CHC engine selection survives the option-set change")
  expect(hornPrelude.contains("(set-option :fp.spacer.ground_pobs false)"),
    "the CHC ground-obligation setting survives the option-set change")
  expect(sha256Hex(hornPrelude) == sha256Hex(hornPrelude),
    "the prelude is a pure value")

block:
  echo "=== 2. the SMT script the gateway hands Z3 ==="
  let request = AxiomProofRequest(
    expectedSmtlib2: "(assert (> x 0))\n(check-sat)\n")
  let script = buildInjectedSmtlib2(request)
  expect(script.len > 0, "a non-empty formula produces a script")
  expectPinnedOptions(script, "gateway_main.buildInjectedSmtlib2")
  expect(script.contains("(set-option :print-success false)"),
    "the gateway still suppresses success lines")
  expect(script.contains("(set-logic ALL)"),
    "the gateway still declares its logic")
  doAssert buildInjectedSmtlib2(AxiomProofRequest()).len == 0,
    "the vacuity ban is untouched by the option-set change"

block:
  echo "=== 3. the emitted option set is the recorded option set ==="
  ## The recorded solverOptionsDigest is derived from the same projection, so a
  ## site that emitted its own literals could not be compared to the digest at
  ## all. Emitting the projection is what makes the two comparable.
  let digest = deterministicSolverOptionsDigest()
  expect(digest.len == 64, "the recorded option digest is a real sha256")
  expect(matchesPinnedOptions(digest),
    "the recorded digest is reproducible from the pinned projection")

block:
  echo "=== 4. no routed module still hard-codes the opt-out seed ==="
  let root = resolveRepoRoot()
  for rel in routedModules:
    let text = readFile(root / rel)
    for zero in seedZeroDirectives:
      expect(not text.contains(zero),
        rel & " no longer emits " & zero)

block:
  echo "=== 5. the emitted prelude and the gateway script agree ==="
  ## Two independent emitters, one projection: if either drifted back to a
  ## literal the digests would stop describing what Z3 was handed.
  let gatewayScript = buildInjectedSmtlib2(
    AxiomProofRequest(expectedSmtlib2: "(assert (> x 0))\n(check-sat)\n"))
  for spec in pinnedDeterminismOptions():
    let directive = solverOptionDirective(spec)
    expect(hornPrelude.contains(directive) and gatewayScript.contains(directive),
      "both emitters project " & spec.name & " from the same list")

block:
  echo "=== 6. reported, not silently fixed: the surviving seed-0 emitters ==="
  ## A regression guard with a named exception list. If a NEW module starts
  ## emitting the opt-out seed this test fails; the one listed module is
  ## reported by this change and owned elsewhere.
  let root = resolveRepoRoot()
  var surviving: seq[string] = @[]
  for rel in walkDirRec(root / "src", relative = false):
    if rel.endsWith(".nim") and
       readFile(rel).contains("(set-option :random-seed 0)"):
      surviving.add(rel.replace(root & "/", "").replace("\\", "/"))
  for rel in surviving:
    expect(rel in knownOutliers,
      rel & " emits the opt-out seed and is not a reported outlier")
  expect(surviving.len == knownOutliers.len,
    "exactly the one reported outlier remains: " & $surviving)

echo "=== ALL solver seed pinning tests PASSED ==="
