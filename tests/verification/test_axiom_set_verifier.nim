## Tests for axiom_set_verifier.nim — Phase 5B
## Verifies Lean axiom set parsing, categorization, and approval checking.

import std/[unittest, strutils]

import verification/axiom_set_verifier

# ═══════════════════════════════════════════════════════════════════════════════
# Test 1: parseAxiomOutput
# ═══════════════════════════════════════════════════════════════════════════════

suite "parseAxiomOutput":
  test "extracts axiom names from typical #print axioms output":
    let output = """axiom propext : {p q : Prop} → (p ↔ q) → p = q
axiom Quot.sound : ∀ {α : Sort u} {r : α → α → Prop} {a₁ a₂ : α}, r a₁ a₂ → Quot.mk r a₁ = Quot.mk r a₂
axiom Classical.choice : {α : Sort u} → Nonempty α → α
"""
    let axioms = parseAxiomOutput(output)
    check axioms.len == 3
    check axioms[0] == "propext"
    check axioms[1] == "Quot.sound"
    check axioms[2] == "Classical.choice"

  test "handles [axiom] prefix format":
    let output = """[axiom] propext : {p q : Prop} → (p ↔ q) → p = q
[axiom] Classical.choice : {α : Sort u} → Nonempty α → α
"""
    let axioms = parseAxiomOutput(output)
    check axioms.len == 2
    check axioms[0] == "propext"
    check axioms[1] == "Classical.choice"

  test "handles axiom without type annotation":
    let output = "axiom bareAxiom\n"
    let axioms = parseAxiomOutput(output)
    check axioms.len == 1
    check axioms[0] == "bareAxiom"

  test "returns empty seq for no axioms":
    let output = "Build completed successfully\nNo axioms used\n"
    let axioms = parseAxiomOutput(output)
    check axioms.len == 0

  test "deduplicates repeated axiom names":
    let output = """axiom propext : Prop
some noise
axiom propext : Prop
"""
    let axioms = parseAxiomOutput(output)
    check axioms.len == 1
    check axioms[0] == "propext"

  test "ignores non-axiom lines":
    let output = "using axiom in a sentence\nimport Foo\nanother line\n"
    let axioms = parseAxiomOutput(output)
    check axioms.len == 0

# ═══════════════════════════════════════════════════════════════════════════════
# Test 2: categorizeAxiom — approved axioms
# ═══════════════════════════════════════════════════════════════════════════════

suite "categorizeAxiom — approved axioms":
  test "propext → acProp":
    check categorizeAxiom("propext") == acProp

  test "Quot.sound → acQuotient":
    check categorizeAxiom("Quot.sound") == acQuotient

  test "Quot.lift → acQuotient":
    check categorizeAxiom("Quot.lift") == acQuotient

  test "Eq.rec → acType":
    check categorizeAxiom("Eq.rec") == acType

  test "HEq → acType":
    check categorizeAxiom("HEq") == acType

  test "cast → acType":
    check categorizeAxiom("cast") == acType

  test "False.elim → acInductive":
    check categorizeAxiom("False.elim") == acInductive

# ═══════════════════════════════════════════════════════════════════════════════
# Test 3: categorizeAxiom — unapproved axioms
# ═══════════════════════════════════════════════════════════════════════════════

suite "categorizeAxiom — unapproved axioms":
  test "Classical.choice → acClassical":
    check categorizeAxiom("Classical.choice") == acClassical

  test "Classical.em → acClassical":
    check categorizeAxiom("Classical.em") == acClassical

  test "unknown axiom → acUnapproved":
    check categorizeAxiom("SomeWeirdAxiom") == acUnapproved

# ═══════════════════════════════════════════════════════════════════════════════
# Test 4: verifyAxiomSet — all approved
# ═══════════════════════════════════════════════════════════════════════════════

suite "verifyAxiomSet — approved":
  test "approved axioms pass":
    let axioms = @["propext", "Quot.sound"]
    let (ok, unapproved) = verifyAxiomSet(axioms)
    check ok == true
    check unapproved.len == 0

  test "empty set passes":
    let (ok, unapproved) = verifyAxiomSet(@[])
    check ok == true
    check unapproved.len == 0

  test "all approved axioms pass":
    let axioms = @["propext", "Quot.sound", "Quot.lift", "Eq.rec", "HEq", "cast", "False.elim"]
    let (ok, unapproved) = verifyAxiomSet(axioms)
    check ok == true
    check unapproved.len == 0

# ═══════════════════════════════════════════════════════════════════════════════
# Test 5: verifyAxiomSet — unapproved
# ═══════════════════════════════════════════════════════════════════════════════

suite "verifyAxiomSet — unapproved":
  test "Classical.choice fails":
    let axioms = @["propext", "Classical.choice"]
    let (ok, unapproved) = verifyAxiomSet(axioms)
    check ok == false
    check unapproved.len == 1
    check "Classical.choice" in unapproved

  test "mixed set with unapproved fails":
    let axioms = @["propext", "Quot.sound", "Classical.choice", "Classical.em"]
    let (ok, unapproved) = verifyAxiomSet(axioms)
    check ok == false
    check unapproved.len == 2
    check "Classical.choice" in unapproved
    check "Classical.em" in unapproved

  test "completely unknown axiom fails":
    let axioms = @["CompletelyUnknown"]
    let (ok, unapproved) = verifyAxiomSet(axioms)
    check ok == false
    check unapproved.len == 1
    check "CompletelyUnknown" in unapproved

# ═══════════════════════════════════════════════════════════════════════════════
# Test 6: All enum values tested
# ═══════════════════════════════════════════════════════════════════════════════

suite "LeanAxiomCategory enum coverage":
  test "acProp is reachable":
    check categorizeAxiom("propext") == acProp

  test "acType is reachable":
    check categorizeAxiom("Eq.rec") == acType

  test "acInductive is reachable":
    check categorizeAxiom("False.elim") == acInductive

  test "acQuotient is reachable":
    check categorizeAxiom("Quot.sound") == acQuotient

  test "acClassical is reachable":
    check categorizeAxiom("Classical.choice") == acClassical

  test "acUnapproved is reachable":
    check categorizeAxiom("BogusAxiom") == acUnapproved

# ═══════════════════════════════════════════════════════════════════════════════
# buildAxiomVerificationResult
# ═══════════════════════════════════════════════════════════════════════════════

suite "buildAxiomVerificationResult":
  test "full result for approved set":
    let result = buildAxiomVerificationResult(@["propext", "Quot.sound"])
    check result.approved == true
    check result.unapprovedAxioms.len == 0
    check result.categories.len == 2
    check result.categories[0] == acProp
    check result.categories[1] == acQuotient

  test "full result for mixed set":
    let result = buildAxiomVerificationResult(@["propext", "Classical.choice"])
    check result.approved == false
    check result.unapprovedAxioms.len == 1
    check "Classical.choice" in result.unapprovedAxioms
    check result.categories.len == 2
    check result.categories[0] == acProp
    check result.categories[1] == acClassical
