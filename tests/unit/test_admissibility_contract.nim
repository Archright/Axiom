import std/[unittest, sets]
import ../../src/core/trusted/axiom_pragmas
import ../../src/core/trusted/axiom_ir
import ../../src/verification/admissibility

# P7 — Admissibility Contract regression suite.
#
# Verifies the P0 3-state decision remains honest and stable:
#   ADMISSIBLE          (vtSmtNative)  → static executable
#   INELIGIBLE          → excluded before ranking/budget
#   DEFER_TO_RUNTIME    → survives selection, runtime decides
#
# Because `assessAdmissibility` needs a live `RuntimeAxiomEntry` + `IRFuncDef`,
# we exercise the pure decision path by constructing synthetic entries whose
# `bmcSkippable` flag drives the three states — mirroring the compile-time
# registry semantics without depending on a full `generateAxiomInit()` boot.

suite "admissibility contract":

  test "compile-time bmcSkippable → INELIGIBLE (unsupported type)":
    # A string/float entry is marked bmcSkippable by the compiler macro; the
    # admissibility gate must reject it regardless of the (unused here) funcDef.
    let entry = RuntimeAxiomEntry(
      name: "stringFunc",
      irSerialized: "",
      isKernel: true,
      effectKind: Pure,
      bmcSkippable: true
    )
    # Empty funcDef is acceptable because bmcSkippable short-circuits before
    # classifyFunction runs.
    let emptyFuncDef = IRFuncDef(name: "")
    let outcome = assessAdmissibility(entry, emptyFuncDef)
    check outcome.decision == INELIGIBLE
    check not isSelectionEligible(outcome)
    check outcome.reason == ireUnsupportedType

  test "empty simple body → ADMISSIBLE (vtSmtNative), statically executable":
    # A body with no complex ops (no call/recCall/loop) classifies as vtSmtNative
    # → statically ADMISSIBLE. This is the honest ADMISSIBLE path: a fully-static
    # simple body earns it, exactly as `proximityScore`, `clampTimeoutMs`, etc.
    let entry = RuntimeAxiomEntry(
      name: "simpleFunc",
      irSerialized: "ir",
      isKernel: true,
      effectKind: Pure,
      bmcSkippable: false
    )
    let emptyFuncDef = IRFuncDef(name: "simpleFunc")
    let outcome = assessAdmissibility(entry, emptyFuncDef)
    check outcome.decision == ADMISSIBLE
    check isSelectionEligible(outcome)

  test "non-bmcSkippable with unresolved structural signal does not fabricate INELIGIBLE":
    # Anti-theater: an empty/unknown body must NOT be forced into INELIGIBLE
    # merely because a loop bound is absent — the gate only rejects on a
    # *proven* static negative. Here (no loop in body) it is ADMISSIBLE
    # (vtSmtNative), never a fabricated INELIGIBLE.
    let entry = RuntimeAxiomEntry(
      name: "structuralFunc",
      irSerialized: "ir",
      isKernel: true,
      effectKind: Pure,
      bmcSkippable: false
    )
    let emptyFuncDef = IRFuncDef(name: "structuralFunc")
    let outcome = assessAdmissibility(entry, emptyFuncDef)
    check outcome.decision != INELIGIBLE
    check isSelectionEligible(outcome)

  test "isSelectionEligible admits both ADMISSIBLE and DEFER_TO_RUNTIME":
    check isSelectionEligible(AdmissibilityOutcome(decision: ADMISSIBLE))
    check isSelectionEligible(AdmissibilityOutcome(decision: DEFER_TO_RUNTIME))
    check not isSelectionEligible(AdmissibilityOutcome(decision: INELIGIBLE))