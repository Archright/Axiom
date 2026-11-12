import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Lean Hint Database Generator (Phase 3)
##
## Generates @[aesop] annotated lemma blocks from the verified_axioms
## mapping table. The hint database is injected into Leanstral prompts
## so that the agent can use `aesop`, `simp`, `omega`, or direct `apply`
## to dispatch trivial proof obligations.
##
## This module is the bridge between Nim's verified_axioms.nim (SSOT
## dictionary) and Lean's tactic automation (aesop/simp/omega).

import core/verified_axioms/verified_axioms_catalog_part1
import std/strutils
import std/options
import core/verified_axioms/verified_axioms
import ../core/trusted/axiom_pragmas
# axiomIoBoundary

# ---------------------------------------------------------------------------
# Hint Database Builders
# ---------------------------------------------------------------------------

func buildLeanHintDatabase*(): string {.raises: [], axiom: ["(assert (>= depth 0))", "depth >= 0"].} =
  ## Generates the full @[aesop] annotated lemma block from all verified axioms.
  ## This is appended to the axiom prelude in Leanstral prompts.
  result = "-- =======================================================================\n"
  result.add("-- Axiom Hint Database (auto-generated from verified_axioms.nim)\n")
  result.add("-- These lemmas are proven; use `aesop`, `simp`, `omega`, or `apply`.\n")
  result.add("-- =======================================================================\n\n")

  var addedCount = 0
  for m in axiomMappings:
    if m.verified and m.leanTheoremSource.len > 0:
      if m.axiomId in [
        "nim.string.len.isNat", "nim.seq.len.isNat", "nim.array.len.eqN",
        "nim.int.iso.lean.int", "nim.string.iso.lean.string",
        "nim.bool.iso.lean.bool", "nim.char.iso.lean.char",
        "nim.natural.iso.lean.nat", "nim.uint.bounds", "nim.float.iso.lean.float",
        "nim.option.iso.lean.option", "nim.result.iso.lean.except",
        "nim.int.add.comm", "nim.int.add.assoc", "nim.int.mul.comm",
        "nim.int.mul.assoc", "nim.int.sub.closure",
        "nim.nat.succ.gt", "nim.nat.add.comm",
        "nim.bool.not.not", "nim.eq.reflexive", "nim.eq.transitive",
        "nim.seq.add.grows", "nim.noSideEffect.isolated",
        "nim.ast.parse.failed.isolated"
      ]:
        continue
      result.add("@[aesop safe apply]\n")
      result.add(m.leanTheoremSource)
      result.add("\n")
      inc addedCount

  if addedCount == 0:
    result.add("-- (All verified axioms are already in the static axiomTheoremBlock)\n")

func buildLeanTacticHints*(axiomIds: seq[string]): string {.raises: [], axiom: ["(assert (and (>= (seq.len axiomIds) 0) (forall ((axiomIdsIdx Int)) (=> (and (>= axiomIdsIdx 0) (< axiomIdsIdx (seq.len axiomIds))) (>= (str.len (seq.nth axiomIds axiomIdsIdx)) 0))) (= (str.len axiomIds) 0) (= foundAny true) (>= foundAny 0) (>= result 0) (>= axiomIds 0) (forall ((axiomIdsIdx Int)) (=> (and (>= axiomIdsIdx 0) (< axiomIdsIdx (seq.len axiomIds))) (>= (str.len (seq.nth axiomIds axiomIdsIdx)) 0)))))", "axiomIds.size ≥ 0 ∧ (∀ (axiomIdsIdx : Fin axiomIds.size), (axiomIds.get axiomIdsIdx).length ≥ 0) ∧ axiomIds.length = 0 ∧ foundAny = true ∧ (foundAny ≥ 0) ∧ (result ≥ 0) ∧ (axiomIds ≥ 0) ∧ (∀ (axiomIdsIdx : Fin axiomIds.size), (axiomIds.get axiomIdsIdx).length ≥ 0)"].} =
  ## Generate a compact hint block for specific axiom IDs.
  ## Used when we know which axioms are relevant to a specific proof.
  if axiomIds.len == 0:
    return

  result = "-- Targeted Axiom Hints:\n"
  var foundAny = false
  for aid in axiomIds:
    let opt = lookupAxiom(aid)
    if opt.isSome and opt.get().verified:
      result.add("-- " & aid & " (v" & opt.get().axiomVersion & ") : " &
                 opt.get().proofObligation & "\n")
      foundAny = true

  if not foundAny:
    return

  result.add("-- Use `apply " & axiomIds[0] & "` or `simp [" &
             axiomIds.join(", ") & "]`\n")

func buildAesopHintBlock*(axiomIds: seq[string]): string {.raises: [], axiom: ["(assert (and (>= (seq.len axiomIds) 0) (forall ((axiomIdsIdx Int)) (=> (and (>= axiomIdsIdx 0) (< axiomIdsIdx (seq.len axiomIds))) (>= (str.len (seq.nth axiomIds axiomIdsIdx)) 0))) (= (str.len axiomIds) 0) (>= result 0) (forall ((axiomIdsIdx Int)) (=> (and (>= axiomIdsIdx 0) (< axiomIdsIdx (seq.len axiomIds))) (>= (str.len (seq.nth axiomIds axiomIdsIdx)) 0)))))", "axiomIds.size ≥ 0 ∧ (∀ (axiomIdsIdx : Fin axiomIds.size), (axiomIds.get axiomIdsIdx).length ≥ 0) ∧ axiomIds.length = 0 ∧ (result ≥ 0) ∧ (∀ (axiomIdsIdx : Fin axiomIds.size), (axiomIds.get axiomIdsIdx).length ≥ 0)"].} =
  ## Generate an `aesop` invocation block for relevant axioms.
  if axiomIds.len == 0:
    return ""
  result = "  -- Invoke aesop with registered axiom hints\n"
  result.add("  aesop\n")

func buildOmegaHintBlock*(): string {.raises: [], axiom: ["(assert (>= depth 0))", "depth >= 0"].} =
  ## Generate an `omega` invocation block for arithmetic properties.
  result = "  -- Linear arithmetic: delegate to omega\n"
  result.add("  omega\n")

{.pop.}
