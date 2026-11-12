import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

import std/sequtils
import std/strutils

import core/solver/smt2_lexer
import core/crypto/hash_kernel

## AxiomIdentity — Single Source of Truth for Fingerprint Computation.
##
## Unifies all fingerprint/hash paths in the Axiom engine to eliminate
## non-deterministic divergence between vault_manager, fingerprint_engine,
## and certificate generation.

## Normalize payload for fingerprinting: strip comments, compact whitespace.
## Deterministic: same input always produces same normalized output.
# @axiom-hint: lean="payload.length ≥ 0" smt="(assert (and (>= (str.len payload) 0)))"
# @axiom-hint: lean="trimmed.length = 0" smt="(assert (and (= (str.len trimmed) 0)))"
func normalizePayloadForFingerprint*(payload: string): string {.noSideEffect.} =
  var normalized = ""
  for line in payload.splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0:
      continue
    if trimmed.startsWith("#"):
      continue
    normalized.add(trimmed & " ")
  normalized.strip()

## Hash a normalized payload using SHA-256 (cross-platform deterministic).
# @axiom-hint: lean="normalized.length ≥ 0" smt="(assert (and (>= (str.len normalized) 0)))"
func hashNormalizedPayload*(normalized: string): string {.noSideEffect.} =
  sha256Hex(normalized)

## Compute canonical Axiom fingerprint for source code + optional constraints.
## This is the ONE function that all certificate and vault fingerprinting
## must call. No module may implement its own fingerprint logic.
# @axiom-hint: lean="payload.length ≥ 0" smt="(assert (and (>= (str.len payload) 0)))"
# @axiom-hint: lean="payload.length ≥ 0 ∧ constraints.size ≥ 0 ∧ (∀ (constraintsIdx : Fin constraints.size), (constraints.get constraintsIdx).length ≥ 0)" smt="(assert (and (>= (str.len payload) 0) (>= (seq.len constraints) 0) (forall ((constraintsIdx Int)) (=> (and (>= constraintsIdx 0) (< constraintsIdx (seq.len constraints))) (>= (str.len (seq.nth constraints constraintsIdx)) 0)))))"
# @axiom-hint: lean="constraints.length > 0 ∧ (∀ (constraintsIdx : Fin constraints.size), (constraints.get constraintsIdx).length ≥ 0)" smt="(assert (and (> (str.len constraints) 0) (forall ((constraintsIdx Int)) (=> (and (>= constraintsIdx 0) (< constraintsIdx (seq.len constraints))) (>= (str.len (seq.nth constraints constraintsIdx)) 0)))))"
func computeAxiomFingerprint*(payload: string; constraints: seq[string] = @[]): string {.noSideEffect.} =
  var fullPayload = normalizePayloadForFingerprint(payload)
  if constraints.len > 0:
    fullPayload.add("\n--constraints--\n")
    fullPayload.add(constraints.join("\n"))
  hashNormalizedPayload(normalizePayloadForFingerprint(fullPayload))

## Compute tolerant fingerprint candidates for fuzzy matching.
## Used when source has drifted slightly (whitespace, case changes).
# @axiom-hint: lean="payload.length ≥ 0" smt="(assert (and (>= (str.len payload) 0)))"
# @axiom-hint: lean="payload.length ≥ 0 ∧ constraints.size ≥ 0 ∧ (∀ (constraintsIdx : Fin constraints.size), (constraints.get constraintsIdx).length ≥ 0)" smt="(assert (and (>= (str.len payload) 0) (>= (seq.len constraints) 0) (forall ((constraintsIdx Int)) (=> (and (>= constraintsIdx 0) (< constraintsIdx (seq.len constraints))) (>= (str.len (seq.nth constraints constraintsIdx)) 0)))))"
# @axiom-hint: lean="constraints.length > 0 ∧ (result ≥ 0) ∧ (∀ (constraintsIdx : Fin constraints.size), (constraints.get constraintsIdx).length ≥ 0)" smt="(assert (and (> (str.len constraints) 0) (>= result 0) (forall ((constraintsIdx Int)) (=> (and (>= constraintsIdx 0) (< constraintsIdx (seq.len constraints))) (>= (str.len (seq.nth constraints constraintsIdx)) 0)))))"
func computeAxiomFingerprintCandidates*(payload: string; constraints: seq[string] = @[]): seq[string] {.noSideEffect.} =
  var fullPayload = payload
  if constraints.len > 0:
    fullPayload.add("\n--constraints--\n")
    fullPayload.add(constraints.join("\n"))
  let compactPayload = payload.splitLines().mapIt(it.strip()).filterIt(it.len > 0).join("\n")
  let compactFull = fullPayload.splitLines().mapIt(it.strip()).filterIt(it.len > 0).join("\n")
  result = @[
    computeAxiomFingerprint(payload, constraints),
    computeAxiomFingerprint(payload.toLowerAscii, constraints),
    computeAxiomFingerprint(compactPayload, constraints),
    computeAxiomFingerprint(compactPayload.toLowerAscii, constraints),
    computeAxiomFingerprint(fullPayload, @[]),
    computeAxiomFingerprint(fullPayload.toLowerAscii, @[]),
    computeAxiomFingerprint(compactFull, @[]),
    computeAxiomFingerprint(compactFull.toLowerAscii, @[])
  ].deduplicate()

## Compute tolerant fingerprint candidates with engine topology salt.
## Backward-compatible overload: existing callers without engineSalt are unaffected.
## Appends "||SALT:{engineSalt}" to the payload before hashing when salt is non-empty.
func computeAxiomFingerprintCandidates*(payload: string; constraints: seq[string]; engineSalt: string): seq[string] {.noSideEffect.} =
  let saltedPayload = if engineSalt.len > 0: payload & "||SALT:" & engineSalt else: payload
  computeAxiomFingerprintCandidates(saltedPayload, constraints)

## Compute canonical fingerprint from Z3-normalized goal expressions.
## Uses formal SMT-LIB2 lexer for alpha-equivalence and commutative
## canonical ordering (Plan v3 Phase C).
##
## Pipeline: parse → alpha-rename (de Bruijn) → commutative sort → hash
## This makes vcHash stable across Z3 internal variable naming changes
## and semantically equivalent rewrites (e.g. (and B A) ↔ (and A B)).
func computeVCFingerprint*(canonicalExpressions: seq[string]): string {.noSideEffect.} =
  computeCanonicalFingerprint(canonicalExpressions)

{.pop.}

{.pop.}

## ─── VC Fingerprint I/O Boundary ──────────────────────────────────────────
## These procs call Z3 for canonical normalization (I/O required).

import core/solver/z3_interactive

proc computeZ3CanonicalFingerprint*(
    smt2Formula: string;
    z3Path: string = "z3";
    tactic: string = "(then simplify propagate-values ctx-solver-simplify)"
): string {.raises: [CatchableError].} =
  ## Compute VC fingerprint via Z3 canonical tactic normalization.
  ##
  ## 1. Start Z3 interactive session
  ## 2. Send the formula
  ## 3. Apply tactic for canonical normalization
  ## 4. Extract goal expressions (strip metadata)
  ## 5. Hash the canonical expressions
  ##
  ## This produces a deterministic fingerprint that is stable across
  ## source formatting changes, variable renaming, and equivalent rewrites.
  var z3 = startZ3Stream(z3Path)
  if not z3.alive:
    # Fallback: hash raw formula
    return computeVCFingerprint(@[smt2Formula])

  try:
    # Set logic and send formula
    discard z3.executeRound("(set-logic QF_LIA)")
    discard z3.executeRound(smt2Formula)

    # Apply canonical tactic
    let tacticOutput = z3.applyTactic(smt2Formula, tactic)

    # Extract goal expressions (strips :precision, :depth metadata)
    let goals = extractGoalExpressions(tacticOutput)

    if goals.len > 0:
      return computeVCFingerprint(goals)
    else:
      # No goals extracted — fallback to raw hash
      return computeVCFingerprint(@[smt2Formula])
  except CatchableError:
    return computeVCFingerprint(@[smt2Formula])
  finally:
    closeZ3Stream(z3)
