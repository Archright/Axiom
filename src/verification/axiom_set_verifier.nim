## Lean Axiom Set Verifier — Phase 5B
##
## Verifies that axioms used by Lean proofs are in the approved axiom set.
## Unapproved axioms (e.g. Classical.choice) cause hard fail.
##
## AGENTS.md §0.6: All pure logic uses `func` with `{.raises: [].}`.
## AGENTS.md §0.2: Ideal (compile-time enum dispatch), Elegant (seq scan),
##   Fundamental (no hardcoded exceptions), Deterministic (identical input → output).
##
## Naming: `LeanAxiomCategory` (not `AxiomCategory`) to avoid collision
## with the Nim-verification `AxiomCategory` in verified_axioms_core.nim.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/strutils

# ═══════════════════════════════════════════════════════════════════════════════
# Types
# ═══════════════════════════════════════════════════════════════════════════════

type
  LeanAxiomCategory* = enum
    ## Categorization of Lean foundational axioms.
    ## Distinct from verified_axioms_core.AxiomCategory (Nim verification axioms).
    acProp        ## Propositional extensionality and prop-logic axioms
    acType        ## Type-theoretic axioms (Eq, HEq, cast)
    acInductive   ## Inductive type eliminators
    acQuotient    ## Quotient type axioms (Quot.sound, Quot.lift, Quot.ind)
    acClassical   ## Classical logic axioms (choice, excluded middle) — UNAPPROVED
    acUnapproved  ## Any axiom not recognized in the approved set

  ApprovedAxiom* = object
    ## A single entry in the approved axiom registry.
    name*: string
    category*: LeanAxiomCategory
    approved*: bool

  AxiomVerificationResult* = object
    ## Result of verifying a set of Lean axioms against the approved registry.
    approved*: bool               ## True if ALL axioms are approved
    unapprovedAxioms*: seq[string]## Names of axioms that failed approval
    categories*: seq[LeanAxiomCategory]  ## Categories found (one per axiom)

# ═══════════════════════════════════════════════════════════════════════════════
# Approved Axiom Set
# ═══════════════════════════════════════════════════════════════════════════════

const approvedAxioms*: seq[ApprovedAxiom] = @[
  # ── Propositional logic (approved) ────────────────────────────────────────
  ApprovedAxiom(name: "propext",
                category: acProp, approved: true),
  # ── Type theory basics (approved) ────────────────────────────────────────
  ApprovedAxiom(name: "Eq.rec",
                category: acType, approved: true),
  ApprovedAxiom(name: "HEq",
                category: acType, approved: true),
  ApprovedAxiom(name: "cast",
                category: acType, approved: true),
  # ── Inductive eliminators (approved) ─────────────────────────────────────
  ApprovedAxiom(name: "False.elim",
                category: acInductive, approved: true),
  ApprovedAxiom(name: "Nat.rec",
                category: acInductive, approved: true),
  ApprovedAxiom(name: "Nat.recAux",
                category: acInductive, approved: true),
  ApprovedAxiom(name: "WellFounded.fix",
                category: acInductive, approved: true),
  # ── Quotient axioms (approved) ───────────────────────────────────────────
  ApprovedAxiom(name: "Quot.sound",
                category: acQuotient, approved: true),
  ApprovedAxiom(name: "Quot.lift",
                category: acQuotient, approved: true),
  ApprovedAxiom(name: "Quot.ind",
                category: acQuotient, approved: true),
  # ── Classical logic (UNAPPROVED) ─────────────────────────────────────────
  ApprovedAxiom(name: "Classical.choice",
                category: acClassical, approved: false),
  ApprovedAxiom(name: "Classical.em",
                category: acClassical, approved: false),
  ApprovedAxiom(name: "Classical.byContradiction",
                category: acClassical, approved: false),
]

# ═══════════════════════════════════════════════════════════════════════════════
# Pure helpers (func)
# ═══════════════════════════════════════════════════════════════════════════════

func parseAxiomOutput*(output: string): seq[string] {.raises: [].} =
  ## Parse `#print axioms` output to extract axiom names.
  ##
  ## Handles multiple Lean output formats:
  ##   - `axiom <name> : <type>`   (standard)
  ##   - `axiom <name>`            (no type annotation)
  ##   - `[axiom] <name> : <type>` (prefixed variant)
  ##
  ## Returns deduplicated axiom names in first-seen order.
  result = @[]
  var seen: seq[string] = @[]
  for line in output.splitLines():
    let stripped = line.strip()
    var name = ""

    # Format: "[axiom] Name : ..." or "axiom Name : ..."
    if stripped.startsWith("[axiom] "):
      let rest = stripped.substr(8)  # skip "[axiom] "
      let colonPos = rest.find(" :")
      name = if colonPos > 0: rest.substr(0, colonPos - 1) else: rest.strip()
    elif stripped.startsWith("axiom "):
      let rest = stripped.substr(6)  # skip "axiom "
      let colonPos = rest.find(" :")
      name = if colonPos > 0: rest.substr(0, colonPos - 1) else: rest.strip()

    if name.len > 0 and name notin seen:
      seen.add(name)
      result.add(name)

func categorizeAxiom*(name: string): LeanAxiomCategory {.raises: [].} =
  ## Map an axiom name to its Lean axiom category.
  ##
  ## Lookup order:
  ##   1. Exact match in `approvedAxioms` registry → returns that category
  ##   2. Prefix heuristics for common Lean patterns
  ##   3. Fallback → `acUnapproved`
  for entry in approvedAxioms:
    if entry.name == name:
      return entry.category

  # Heuristic fallback for axioms not in the registry
  if name.startsWith("Classical."):
    return acClassical
  if name.startsWith("Quot."):
    return acQuotient
  if name.endsWith(".rec") or name.endsWith(".recAux") or name.endsWith(".casesOn"):
    return acInductive
  if name == "propext" or name == "Iff.rfl":
    return acProp
  if name == "Eq" or name == "HEq" or name == "cast" or name == "Eq.mpr":
    return acType

  acUnapproved

func verifyAxiomSet*(axioms: seq[string]): (bool, seq[string]) {.raises: [].} =
  ## Verify that all axioms in the list are approved.
  ##
  ## Returns:
  ##   - (true, @[])  if all axioms are approved
  ##   - (false, unapprovedList)  if any axiom is not approved
  var unapproved: seq[string] = @[]
  for axiom in axioms:
    let category = categorizeAxiom(axiom)
    # Check the registry for explicit approval status
    var found = false
    for entry in approvedAxioms:
      if entry.name == axiom:
        found = true
        if not entry.approved and axiom notin unapproved:
          unapproved.add(axiom)
        break
    # Not in registry AND unrecognizable → unapproved
    if not found and category == acUnapproved and axiom notin unapproved:
      unapproved.add(axiom)

  (unapproved.len == 0, unapproved)

func buildAxiomVerificationResult*(axioms: seq[string]): AxiomVerificationResult {.raises: [].} =
  ## Build a full AxiomVerificationResult from a list of axiom names.
  ##
  ## Enriches the basic verifyAxiomSet output with per-axiom category info.
  let (allApproved, unapprovedList) = verifyAxiomSet(axioms)
  var categories: seq[LeanAxiomCategory] = @[]
  for axiom in axioms:
    categories.add(categorizeAxiom(axiom))

  AxiomVerificationResult(
    approved: allApproved,
    unapprovedAxioms: unapprovedList,
    categories: categories,
  )

{.pop.}
