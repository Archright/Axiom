import std/[unittest, os, osproc, strutils]
import ../../src/core/crypto/hash_kernel
import ../../src/core/results
import ../../src/verification/obligation/lean_evidence

## W1-B unit tests — Acceptance/Validation separation + Obligation Binding.
##
## Pure by design: no real `lean` is required. The validateEvidence rejection
## paths tested here (sorry scan, binding mismatch, hash mismatch, kernel
## rejection) all fire BEFORE any lean process is launched. Axiom-profile
## parsing/allowlist logic is tested through the pure `parseAxiomProfile` and
## `validateAxiomProfile` functions so no extractor round-trip is needed.
## Two integration tests at the end are gated on `lean` presence (the suite
## passes without it), following the tests/unit/lean_replay_sorry_gate_test.nim
## idiom.

let hasLean = (execCmdEx("which lean 2>/dev/null").exitCode == 0)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc makeBinding(): ObligationBinding =
  ## Binding for an artifact theorem named `obligation_O1` proving `42 = 42`.
  let source = "theorem obligation_O1 : 42 = 42 := by\n  rfl\n"
  result = bindObligation("O1", "42 = 42", "module/function_src.nim")

proc makeCleanKernel(): LeanKernelResult =
  LeanKernelResult(
    kernelAccepted: true,
    exitStatus: 0,
    diagnostics: "no output",
    diagnosticsHash: sha256Hex("no output")
  )

const cleanSource = """theorem obligation_O1 : 42 = 42 := by
  rfl
"""

suite "ObligationBinding (pure)":
  test "bindObligation is deterministic and stable":
    let a = bindObligation("O1", "x = 1", "src.nim")
    let b = bindObligation("O1", "x = 1", "src.nim")
    check a.obligationId == "O1"
    check a.propositionHash == b.propositionHash
    check a.sourceHash == b.sourceHash
    check a.propositionHash == sha256Hex("x = 1")
    check a.sourceHash == sha256Hex("src.nim")
    check a.propositionHash.len == 64
    check a.sourceHash.len == 64

  test "bindObligation distinguishes propositions and sources":
    let p1 = bindObligation("O1", "x = 1", "a.nim")
    let p2 = bindObligation("O1", "x = 2", "a.nim")
    let s1 = bindObligation("O1", "x = 1", "b.nim")
    check p1.propositionHash != p2.propositionHash
    check p1.sourceHash != s1.sourceHash

suite "axiomProfile parsing and allowlist (pure)":
  test "parseAxiomProfile extracts bracketed dependency lists":
    check parseAxiomProfile("'clamp' depends on axioms: [propext, Classical.choice]") ==
      @["propext", "Classical.choice"]
    check parseAxiomProfile("'x' does not depend on any axioms").len == 0
    check parseAxiomProfile("unrelated output\nno brackets here").len == 0
    check parseAxiomProfile("").len == 0

  test "parseAxiomProfile aggregates and de-duplicates multi-line output":
    let raw = "info: 'a' depends on axioms: [propext]\n" &
              "info: 'b' depends on axioms: [Classical.choice, propext]"
    check parseAxiomProfile(raw) == @["propext", "Classical.choice"]

  test "parseAxiomProfile surfaces sorryAx verbatim":
    let prof = parseAxiomProfile("'a' depends on axioms: [propext, sorryAx]")
    check prof == @["propext", "sorryAx"]

  test "validateAxiomProfile accepts empty and fully allow-listed profiles":
    check validateAxiomProfile(@[]).isOk
    check validateAxiomProfile(@["propext", "Classical.choice", "Quot.sound", "funext"]).isOk

  test "validateAxiomProfile rejects sorry-based and foreign axioms":
    check validateAxiomProfile(@["sorryAx"]).isErr
    check validateAxiomProfile(@["Lean.sorryAx"]).isErr
    check validateAxiomProfile(@["Some.Other.axiom"]).isErr
    check validateAxiomProfile(@["propext", "sorryAx"]).isErr
    check validateAxiomProfile(@["propext", "Z3.counterexample"]).isErr
    let reason = validateAxiomProfile(@["sorryAx"]).error
    check reason.startsWith("invalid: ")
    check "sorryAx" in reason

suite "validateEvidence rejection paths (no lean needed)":
  test "rejects sorry marker in kernel diagnostics (simulated diagnostics string)":
    let kernel = LeanKernelResult(
      kernelAccepted: true,
      exitStatus: 0,
      diagnostics: "warning: declaration uses 'sorry'\n",
      diagnosticsHash: sha256Hex("warning: declaration uses 'sorry'\n")
    )
    let res = validateEvidence(makeBinding(), kernel, cleanSource, axiomTarget = "obligation_O1")
    check res.isErr
    check res.error.contains("sorry")

  test "rejects sorry marker in the artifact source":
    let sorrySource = """theorem obligation_O1 : 42 = 42 := by
  sorry
"""
    let res = validateEvidence(makeBinding(), makeCleanKernel(), sorrySource, axiomTarget = "obligation_O1")
    check res.isErr
    check res.error.contains("invalid: sorry")

  test "rejects artifact theorem not bound to the obligationId":
    let foreignSource = """theorem unrelated_thm : 42 = 42 := by
  rfl
"""
    let res = validateEvidence(makeBinding(), makeCleanKernel(), foreignSource, axiomTarget = "unrelated_thm")
    check res.isErr
    check "does not bind" in res.error

  test "rejects artifact without any theorem declaration":
    let res = validateEvidence(makeBinding(), makeCleanKernel(), "import Std\n", axiomTarget = "obligation_O1")
    check res.isErr
    check "no theorem declaration" in res.error

  test "rejects axiomTarget mismatching the artifact theorem":
    let res = validateEvidence(makeBinding(), makeCleanKernel(), cleanSource, axiomTarget = "wrong_target")
    check res.isErr
    check "axiomTarget" in res.error

  test "rejects mismatched canonical propositionHash":
    let res = validateEvidence(
      makeBinding(), makeCleanKernel(), cleanSource,
      axiomTarget = "obligation_O1", canonicalProposition = "41 = 41")
    check res.isErr
    check "propositionHash" in res.error

  test "accepts consistent canonical propositionHash (no lean reached)":
    ## Reaches the axiom-probe step only if real lean runs were allowed; with
    ## no lean this stays in the pure region — the point here is the
    ## propositionHash check itself passes (next failure would be kernel-level).
    let kernel = LeanKernelResult(
      kernelAccepted: false,   # force stop before any lean invocation
      exitStatus: 3,
      diagnostics: "kernel says no",
      diagnosticsHash: sha256Hex("kernel says no")
    )
    let res = validateEvidence(
      makeBinding(), kernel, cleanSource,
      axiomTarget = "obligation_O1", canonicalProposition = "42 = 42")
    check res.isErr
    check "propositionHash" notin res.error
    check "kernel rejected" in res.error

  test "rejects kernel non-acceptance with typed outcome":
    let kernel = LeanKernelResult(
      kernelAccepted: false,
      exitStatus: 3,
      diagnostics: "error: unknown identifier\n",
      diagnosticsHash: sha256Hex("error: unknown identifier\n")
    )
    let res = validateEvidence(makeBinding(), kernel, cleanSource, axiomTarget = "obligation_O1")
    check res.isErr
    check res.error.startsWith("invalid: lean kernel rejected")
    check outcomeFromReason(res.error) == voInvalid

  test "rejects tampered diagnosticsHash":
    let kernel = LeanKernelResult(
      kernelAccepted: true,
      exitStatus: 0,
      diagnostics: "clean",
      diagnosticsHash: sha256Hex("not the same content")
    )
    let res = validateEvidence(makeBinding(), kernel, cleanSource, axiomTarget = "obligation_O1")
    check res.isErr
    check "diagnosticsHash" in res.error

  test "rejects expectedArtifactHash mismatch":
    let res = validateEvidence(
      makeBinding(), makeCleanKernel(), cleanSource,
      axiomTarget = "obligation_O1", expectedArtifactHash = sha256Hex("a different artifact"))
    check res.isErr
    check "artifact hash mismatch" in res.error

  test "outcomeFromReason classifies prefixes":
    check outcomeFromReason("invalid: something") == voInvalid
    check outcomeFromReason("unverifiable: timeout") == voUnverifiable
    check outcomeFromReason("other") == voValid

suite "extractTheoremName":
  test "single-line theorem":
    check extractTheoremName("theorem obligation_O1 : 42 = 42 := by\n  rfl\n") == "obligation_O1"
  test "theorem with parameters":
    check extractTheoremName("theorem add_comm (a b : Nat) : a + b = b + a := by\n  omega\n") == "add_comm"
  test "no theorem":
    check extractTheoremName("import Std\n#print axioms foo\n") == ""
  test "comment lines are ignored":
    let src = "-- preamble comment\nimport Std\n\ntheorem foo : True := by\n  trivial\n"
    check extractTheoremName(src) == "foo"

suite "runLeanKernelCheck":
  test "empty source is an error":
    let res = runLeanKernelCheck("", timeoutMs = 5_000)
    check res.isErr
    check "empty" in res.error

  test "kernel result mirrors exit status (no lean required for the shape)":
    ## Without lean installed bash reports 127 and kernelAccepted=false; with
    ## lean installed a trivial theorem is accepted. In both environments the
    ## Result itself succeeds and carries a pure acceptance fact.
    let res = runLeanKernelCheck("theorem t : True := by\n  trivial\n", timeoutMs = 60_000)
    check res.isOk
    let kernel = res.get
    check kernel.kernelAccepted == (kernel.exitStatus == 0)
    check kernel.diagnosticsHash == sha256Hex(kernel.diagnostics)

  test "integration (lean): clean theorem is kernel-accepted and yields voValid evidence":
    if hasLean:
      let kernel = runLeanKernelCheck(cleanSource, timeoutMs = 60_000).get
      check kernel.kernelAccepted
      let evidence = validateEvidence(makeBinding(), kernel, cleanSource, axiomTarget = "obligation_O1")
      check evidence.isOk
      let ev = evidence.get
      check ev.validation == voValid
      check ev.artifactHash == sha256Hex(cleanSource)
      check ev.axiomProfile.len == 0
      check ev.binding.obligationId == "O1"
      check ev.acceptance.kernelAccepted
    else:
      echo "SKIP: lean not available"

  test "integration lean: sorry theorem is rejected by validateEvidence":
    if hasLean:
      let sorrySrc = """theorem obligation_O1 : 42 = 42 := by
  sorry
"""
      let kernel = runLeanKernelCheck(sorrySrc, timeoutMs = 60_000).get
      check kernel.kernelAccepted  # lean itself accepts `sorry` (warning only)
      let res = validateEvidence(binding = bindObligation("O1", "42 = 42", "src"), kernel, sorrySrc, axiomTarget = "obligation_O1")
      check res.isErr
      check "sorry" in res.error
      check outcomeFromReason(res.error) == voInvalid
    else:
      echo "SKIP: lean not available"

  test "integration (lean): vacuous theorem is rejected by the negative mutation":
    if hasLean:
      let vacuous = """theorem obligation_vac (h : False) : 1 = 1 := by
  cases h
"""
      let kernel = runLeanKernelCheck(vacuous, timeoutMs = 60_000).get
      check kernel.kernelAccepted
      let res = validateEvidence(
        binding = bindObligation("vac", "1 = 1", "source"),
        kernel, vacuous, axiomTarget = "obligation_vac", timeoutMs = 60_000)
      check res.isErr
      check "negative mutation compiled" in res.error
      check outcomeFromReason(res.error) == voInvalid
    else:
      echo "SKIP: lean not available"

  test "integration (lean): newline-form `:=\\nby` artifact yields voValid evidence":
    ## irFuncDefToTheorem emits `:=\nby`; the negative mutation must be
    ## buildable from that shape (regression: single-line `:= by` anchor
    ## made every rendered artifact report an unbuildable mutation).
    if hasLean:
      let src = "theorem obligation_O1 : 42 = 42 :=\nby\n  rfl\n"
      let kernel = runLeanKernelCheck(src, timeoutMs = 60_000).get
      check kernel.kernelAccepted
      let evidence = validateEvidence(makeBinding(), kernel, src, axiomTarget = "obligation_O1")
      check evidence.isOk
      check evidence.get.validation == voValid
    else:
      echo "SKIP: lean not available"

  test "integration (lean): vacuous newline-form artifact is rejected by the negative mutation":
    if hasLean:
      let vacuous = """theorem obligation_vac (h : False) : 1 = 1 :=
by
  cases h
"""
      let kernel = runLeanKernelCheck(vacuous, timeoutMs = 60_000).get
      check kernel.kernelAccepted
      let res = validateEvidence(
        binding = bindObligation("vac", "1 = 1", "source"),
        kernel, vacuous, axiomTarget = "obligation_vac", timeoutMs = 60_000)
      check res.isErr
      check "negative mutation compiled" in res.error
      check outcomeFromReason(res.error) == voInvalid
    else:
      echo "SKIP: lean not available"