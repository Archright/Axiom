import std/unittest, std/strutils, src/engine/proof_injector

template withMarkers(body: string): string =
  "/- AXIOM_PROOF_BEGIN -/\n" & body & "\n/- AXIOM_PROOF_END -/"

suite "proof_injector":
  test "extractCleanError preserves hypotheses":
    let rawError = "tactic failed, there are unsolved goals\n  a b : Nat\n  h1 : a > 0\n  h2 : b > 0\n  ⊢ a + b = b + a"
    let cleaned = extractCleanError(rawError)
    check cleaned.contains("a b : Nat")
    check cleaned.contains("h1 : a > 0")
    check cleaned.contains("⊢ a + b = b + a")

  test "extractCleanError fallback for unknown format":
    let rawError = "some random error"
    let cleaned = extractCleanError(rawError)
    check cleaned == "some random error"

  test "extractCleanError strips stack traces":
    let rawError = "tactic failed\n  h : P\n  ⊢ Q\nat /home/user/test.lean:12:3\nFile: ./source.lean"
    let cleaned = extractCleanError(rawError)
    check cleaned.contains("h : P")
    check cleaned.contains("⊢ Q")
    check not cleaned.contains("at /home/user/test.lean")
    check not cleaned.contains("File: ./source.lean")

  test "extractCleanError preserves error marker lines":
    let rawError = "error: tactic 'simp' failed\n  h : P\n  ⊢ Q"
    let cleaned = extractCleanError(rawError)
    check cleaned.contains("error: tactic 'simp' failed")
    check cleaned.contains("h : P")
    check cleaned.contains("⊢ Q")
  test "canonicalizeTactic removes markdown fences":
    check canonicalizeTactic("```lean\nby simp\n```") == "by simp"
    check canonicalizeTactic("```\nsimp\n```") == "by simp"

  test "canonicalizeTactic removes duplicate by":
    check canonicalizeTactic("by by simp") == "by simp"
    check canonicalizeTactic("by by by simp") == "by simp"

  test "injectTactic with anchor markers single-line":
    let code = "theorem foo : P :=" & "\n" & withMarkers("  sorry")
    let r = injectTactic(code, "simp")
    check r.contains("simp")
    check not r.contains("sorry")

  test "injectTactic with anchor markers multi-line tactic":
    let leanCode = """theorem foo : P :=
  /- AXIOM_PROOF_BEGIN -/
  sorry
  /- AXIOM_PROOF_END -/"""
    let result = injectTactic(leanCode, "induction xs with\n| nil => rfl\n| cons h t ih => simp [ih]")
    check result.contains("induction xs with")
    check result.contains("| nil => rfl")
    check not result.contains("sorry")

  test "injectTactic raises on missing start marker":
    let code = "theorem foo : P := by sorry"
    expect(ValueError):
      discard injectTactic(code, "simp")

  test "injectTactic raises on missing end marker":
    let code = "theorem foo : P :=\n  /- AXIOM_PROOF_BEGIN -/\n  sorry"
    expect(ValueError):
      discard injectTactic(code, "simp")

  test "injectTactic preserves prefix and suffix":
    let code = "theorem foo : P :=\n" & withMarkers("  sorry") & "\n\nlemma bar : Q := rfl"
    let r = injectTactic(code, "simp")
    check r.contains("theorem foo : P :=")
    check r.contains("lemma bar : Q := rfl")
    check r.contains("AXIOM_PROOF_BEGIN")
    check r.contains("AXIOM_PROOF_END")
