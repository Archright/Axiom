import std/[unittest, strutils]
import core/proof/vk_properties
import core/proof/proof_vacuity_gate

const runRealIntegration = defined(integration)

suite "Vacuity Defense — VK Property SSOT":

  test "VK property template produces non-empty output for all known VKs":
    check vkPropertySmt("vkBufferOverflow").len > 0
    check vkPropertySmt("vkNullPointerDereference").len > 0
    check vkPropertySmt("vkIntegerOverflowUnderflow").len > 0
    check vkPropertySmt("vkGhostUpdate").len > 0
    check vkPropertySmt("vkDeadlockRaceCondition").len > 0

  test "Unknown VK falls back to true":
    check vkPropertySmt("unknown") == "true"
    check vkPropertySmt("") == "true"

  test "No raw dollar-sign placeholders remain after default substitution":
    check "$" notin vkPropertySmt("vkBufferOverflow")
    check "$" notin vkPropertySmt("vkNullPointerDereference")
    check "$" notin vkPropertySmt("vkIntegerOverflowUnderflow")
    check "$" notin vkPropertySmt("vkGhostUpdate")
    check "$" notin vkPropertySmt("vkDeadlockRaceCondition")

  test "SSA suffix mapping for CHC synthesizer":
    let result = vkPropertySmt("vkBufferOverflow", [("idx", "idx_0"), ("length", "length")])
    check result == "(and (>= idx_0 0) (< idx_0 length))"

  test "Longer placeholder $version_next not corrupted by shorter $version":
    let result = vkPropertySmt("vkGhostUpdate", [("version", "version_0"), ("version_next", "version_1")])
    check result == "(>= version_1 version_0)"
    check "version_0_next" notin result

  test "Default substitution produces expected SMT-LIB2":
    check vkPropertySmt("vkBufferOverflow") == "(and (>= idx 0) (< idx length))"
    check vkPropertySmt("vkGhostUpdate") == "(>= version_next version)"
    check vkPropertySmt("vkNullPointerDereference") == "(not (= ptr nil))"
    check vkPropertySmt("vkIntegerOverflowUnderflow") == "(and (>= amount 0) (<= amount balance))"
    check vkPropertySmt("vkDeadlockRaceCondition") == "lockHeld"

suite "4-Layer Vacuity Defense — Deterministic Integration":

  test "Genuinely proven: all layers pass":
    let status = VacuityProofStatus(
      leanReplayPass: true,
      z3NonTrivialityPass: true,
      negativeMutationPass: true,
      nonVerifiedFallback: false,
      fallbackReason: ""
    )
    check isGenuinelyProven(status) == true

  test "Vacuous invariant blocked: LeanReplay layer rejects":
    let status = VacuityProofStatus(
      leanReplayPass: false,
      z3NonTrivialityPass: true,
      negativeMutationPass: true,
      nonVerifiedFallback: false,
      fallbackReason: ""
    )
    check isGenuinelyProven(status) == false

  test "Trivial invariant blocked: Z3 layer rejects":
    let status = VacuityProofStatus(
      leanReplayPass: true,
      z3NonTrivialityPass: false,
      negativeMutationPass: true,
      nonVerifiedFallback: false,
      fallbackReason: ""
    )
    check isGenuinelyProven(status) == false

  test "Mutation test fails: negative mutation layer rejects":
    let status = VacuityProofStatus(
      leanReplayPass: true,
      z3NonTrivialityPass: true,
      negativeMutationPass: false,
      nonVerifiedFallback: false,
      fallbackReason: ""
    )
    check isGenuinelyProven(status) == false

  test "Pass with Warning: Z3 timeout but still passes":
    let status = VacuityProofStatus(
      leanReplayPass: true,
      z3NonTrivialityPass: true,
      negativeMutationPass: true,
      nonVerifiedFallback: true,
      fallbackReason: "z3_timeout_or_error"
    )
    check isGenuinelyProven(status) == true
    check status.nonVerifiedFallback == true

  test "hasSecurityConstraintsInSource detects assertions":
    check hasSecurityConstraintsInSource("assert x >= 0") == true
    check hasSecurityConstraintsInSource("if x > 0: return") == true
    check hasSecurityConstraintsInSource("proc foo(): int = 42") == false

  test "hasSecurityConstraintsInSource handles empty input":
    check hasSecurityConstraintsInSource("") == false
    check hasSecurityConstraintsInSource("   ") == false

  test "VacuityProofStatus default values":
    let status = VacuityProofStatus()
    check status.leanReplayPass == false
    check status.z3NonTrivialityPass == false
    check status.negativeMutationPass == false
    check status.nonVerifiedFallback == false
    check status.fallbackReason == ""
    check isGenuinelyProven(status) == false

suite "End-to-End Real Validation (Conditional)":

  test "Real Z3 + Lean integration":
    if not runRealIntegration:
      echo "[SKIP] Real Integration Test (Use -d:integration to run)"
      skip()
    else:
      let result = verifyNonTrivialityWithFallback(
        @["(>= idx 0)"],
        @[("idx", "Int"), ("length", "Int")],
        "proc foo(idx: int, length: int) = assert idx >= 0",
        5000
      )
      check result.nonTrivial == true
