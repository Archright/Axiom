import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import ../../core/trusted/axiom_pragmas
import core/verified_axioms/axiom_catalog_validator
import core/verified_axioms/verified_axioms_core
import std/options
import std/os
import std/strutils
# ---------------------------------------------------------------------------
# Comprehensive Axiom Mapping Table (SSOT)
# ---------------------------------------------------------------------------
#
# Data loaded from external JSON with compile-time schema validation.
# Edit data/axiom_catalog.json to add/modify axiom mappings.
# Validation: missing required fields or invalid category = compile error.

const dataPath = currentSourcePath().parentDir().parentDir().parentDir().parentDir() / "data" / "axiom_catalog.json"
const axiomMappings*: seq[AxiomMapping] = loadAndValidateAxiomCatalog(dataPath)
# ---------------------------------------------------------------------------
# Legacy Interface (backward-compatible)
# ---------------------------------------------------------------------------
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func axiomMappingsWithHashes*(): seq[AxiomMapping] {.raises: [], axiom: ["(assert (>= depth 0))", "depth >= 0"].} =
  ## Returns the mapping table with computed hashes.
  ## The hash is computed at call time to ensure freshness.
  result = axiomMappings
  for i in 0 ..< result.len:
    if result[i].sourceHash.len == 0:
      let h = computeAxiomHash(result[i].axiomId, result[i].nimSignature, result[i].leanSignature)
      result[i].sourceHash = h

# ---------------------------------------------------------------------------
# Axiom Lookup Functions
# ---------------------------------------------------------------------------
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func lookupAxiom*(axiomId: string): Option[AxiomMapping] {.raises: [], axiom: ["(assert (and (>= (str.len axiomId) 0) (>= axiomMappings 0)))", "axiomId.length ≥ 0 ∧ (axiomMappings ≥ 0)"].} =
  for m in axiomMappings:
    if m.axiomId == axiomId:
      return some(m)
  none(AxiomMapping)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func lookupAxiomByNimSymbol*(nimSymbol: string): Option[AxiomMapping] {.raises: [], axiom: ["(assert (and (>= (str.len nimSymbol) 0) (>= axiomMappings 0)))", "nimSymbol.length ≥ 0 ∧ (axiomMappings ≥ 0)"].} =
  for m in axiomMappings:
    if m.nimSymbol == nimSymbol:
      return some(m)
  none(AxiomMapping)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func lookupAxiomByLeanTheorem*(leanTheorem: string): Option[AxiomMapping] {.raises: [], axiom: ["(assert (and (>= (str.len leanTheorem) 0) (>= axiomMappings 0)))", "leanTheorem.length ≥ 0 ∧ (axiomMappings ≥ 0)"].} =
  for m in axiomMappings:
    if m.leanTheorem == leanTheorem:
      return some(m)
  none(AxiomMapping)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func axiomsByCategory*(category: AxiomCategory): seq[AxiomMapping] {.raises: [], axiom: ["(assert (and (>= depth 0) (>= axiomMappings 0)))", "depth >= 0 ∧ (axiomMappings ≥ 0)"].} =
  for m in axiomMappings:
    if m.category == category:
      result.add(m)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func verifiedAxiomCount*(): int {.raises: [], axiom: ["(assert (>= depth 0))", "depth >= 0"].} =
  for m in axiomMappings:
    if m.verified:
      inc result
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func unverifiedAxiomCount*(): int {.raises: [], axiom: ["(assert (>= depth 0))", "depth >= 0"].} =
  for m in axiomMappings:
    if not m.verified:
      inc result

# ---------------------------------------------------------------------------
# Axiom Hash Verification
# ---------------------------------------------------------------------------
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func verifyAxiomHash*(axiomId: string; expectedHash: string): bool {.raises: [], axiom: ["(assert (and (>= (str.len axiomId) 0) (>= (str.len expectedHash) 0) (= (option.isNone opt) true) false (=> (= (option.isNone opt) true) (= result false))))", "axiomId.length ≥ 0 ∧ expectedHash.length ≥ 0 ∧ opt.isNone = true ∧ false ∧ opt.isNone = true → result = false"].} =
  ## Returns true if the current axiom definition hash matches the expected hash.
  ## This is used to verify that an axiom referenced in a certificate has not
  ## been modified since the certificate was issued.
  let opt = lookupAxiom(axiomId)
  if opt.isNone:
    return false
  let m = opt.get()
  let currentHash = computeAxiomHash(m.axiomId, m.nimSignature, m.leanSignature)
  currentHash == expectedHash
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func axiomMatchesNormalizedShape(axiomId: string; normalized: string): bool {.raises: [], axiom: ["(assert (and (>= (str.len axiomId) 0) (>= (str.len normalized) 0)))", "axiomId.length ≥ 0 ∧ normalized.length ≥ 0"].} =
  let compact = compactAxiomComparison(normalized)
  case axiomId
  of "nim.string.len.isNat":
    compact.contains(".length>=0") and not normalized.contains("seq")
  of "nim.seq.len.isNat":
    compact.contains(".length>=0") and
      (normalized.contains("seq") or normalized.contains("list"))
  of "nim.array.len.eqN":
    compact.contains(".size=")
  else:
    false
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func axiomMatchesLeanProposition*(leanProp: string): Option[AxiomMapping] {.raises: [], axiom: ["(assert (and (>= (str.len leanProp) 0) (= (str.len normalized) 0) (>= axiomMappings 0)))", "leanProp.length ≥ 0 ∧ normalized.length = 0 ∧ (axiomMappings ≥ 0)"].} =
  ## Check if a Lean proposition string matches any axiom's proof obligation.
  let normalized = normalizeVerifiedAxiomProp(leanProp)
  if normalized.len == 0:
    return none(AxiomMapping)
  for m in axiomMappings:
    if not m.verified:
      continue
    let obl = normalizeVerifiedAxiomProp(m.proofObligation)
    if obl.len > 0 and normalized.contains(obl):
      return some(m)
    if axiomMatchesNormalizedShape(m.axiomId, normalized):
      return some(m)
    # Also check against signature keywords
    let sig = normalizeVerifiedAxiomProp(m.nimSignature & " " & m.leanSignature)
    if sig.len > 0 and sig.contains(normalized):
      return some(m)
  none(AxiomMapping)

# ---------------------------------------------------------------------------
# Legacy Interface (backward-compatible)
# ---------------------------------------------------------------------------
const verifiedAxiomRegistry*: seq[VerifiedAxiom] = @[
  VerifiedAxiom(name: "string-length-nonneg", tokens: @[".length >= 0"], approved: true, asiWeight: 0.0),
  VerifiedAxiom(name: "seq-size-nonneg", tokens: @[".size >= 0"], approved: true, asiWeight: 0.0),
  VerifiedAxiom(name: "uint-nonneg", tokens: @["uint", ">= 0"], approved: true, asiWeight: 0.0),
  VerifiedAxiom(name: "natural-nonneg", tokens: @["natural", ">= 0"], approved: true, asiWeight: 0.0),
  VerifiedAxiom(name: "external-io-isolated", tokens: @["external_io_isolated"], approved: true, asiWeight: 1.0),
  VerifiedAxiom(name: "ast-parse-failed-isolated", tokens: @["ast_parse_failed_isolated"], approved: true, asiWeight: 1.0),
]
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func verifiedAxiomName*(leanProp: string): string {.raises: [], axiom: ["(assert (and (>= (str.len leanProp) 0) (= (str.len normalized) 0) (> (str.len domainAxiom) 0) (> (str.len boolAxiom) 0) (= (option.isSome mappingOpt) true) matched (= matched false) domainAxiom boolAxiom (=> (> (str.len domainAxiom) 0) (= result domainAxiom)) (=> (> (str.len boolAxiom) 0) (= result boolAxiom)) (>= matched 0) (>= verifiedAxiomRegistry 0)))", "leanProp.length ≥ 0 ∧ normalized.length = 0 ∧ domainAxiom.length > 0 ∧ boolAxiom.length > 0 ∧ mappingOpt.isSome = true ∧ matched ∧ matched = false ∧ domainAxiom ∧ boolAxiom ∧ domainAxiom.length > 0 → result = domainAxiom ∧ boolAxiom.length > 0 → result = boolAxiom ∧ (matched ≥ 0) ∧ (verifiedAxiomRegistry ≥ 0)"].} =
  ## Legacy: Returns the matching verified axiom name from the registry.
  ## Also checks the new AxiomMapping table.
  let normalized = normalizeVerifiedAxiomProp(leanProp)
  if normalized.len == 0:
    return ""
  let domainAxiom = naturalDomainAxiomName(leanProp)
  if domainAxiom.len > 0:
    return domainAxiom
  let boolAxiom = boolCasesAxiomName(leanProp)
  if boolAxiom.len > 0:
    return boolAxiom
  # First check new mapping table
  let mappingOpt = axiomMatchesLeanProposition(leanProp)
  if mappingOpt.isSome:
    return mappingOpt.get().axiomId
  # Fallback to legacy registry
  for axiom in verifiedAxiomRegistry:
    if not axiom.approved:
      continue
    var matched = true
    for token in axiom.tokens:
      if not normalized.contains(token):
        matched = false
        break
    if matched:
      return axiom.name
  ""
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func isVerifiedAxiomProperty*(leanProp: string): bool {.raises: [], axiom: ["(assert (and (>= (str.len leanProp) 0)))", "leanProp.length ≥ 0"].} =
  verifiedAxiomName(leanProp).len > 0
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func allVerifiedAxiomsApproved*(): bool {.raises: [], used, axiom: ["(assert (>= depth 0))", "depth >= 0"].} =
  ## Returns true if all axioms in both registry and mapping table are approved.
  for axiom in verifiedAxiomRegistry:
    if not axiom.approved:
      return false
  for m in axiomMappings:
    if not m.verified:
      return false
  true

# ---------------------------------------------------------------------------
# Lean Theorem Source Aggregation
# ---------------------------------------------------------------------------
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func buildVerifiedAxiomTheorems(): string {.used, raises: [], axiom: ["(assert (>= depth 0))", "depth >= 0"].} =
  ## Collect all verified axiom Lean theorem sources into a single block.
  ## Used to build the extended axiom prelude for Lean skeleton injection.
  result = "-- Verified Axiom Theorems (auto-generated from verified_axioms.nim)\n"
  for m in axiomMappings:
    if m.verified and m.leanTheoremSource.len > 0:
      result.add("\n-- " & m.axiomId & " (v" & m.axiomVersion & ")\n")
      result.add(m.leanTheoremSource)
      result.add("\n")
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func getAxiomWeight*(axiomId: string): float {.raises: [], axiom: ["(assert (and (>= (str.len axiomId) 0) (>= (str.len axiomId) 0)))", "axiomId.length ≥ 0 ∧ axiomId.length ≥ 0"].} =
  ## Return the ASI weight for a given axiom.
  ## 0.0 for properties statically guaranteed by the Nim type system.
  ## 1.0 for runtime-meaningful invariants.
  case axiomId
  of "nim.string.len.isNat", "nim.seq.len.isNat", "nim.array.len.isNat":
    return 0.0
  else:
    return 1.0
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func totalVerifiedAxiomWeight*(): float {.raises: [], axiom: ["(assert (>= depth 0))", "depth >= 0"].} =
  ## Sum of ASI weights for all approved verified axioms.
  ## Trivial axioms (e.g. length >= 0) contribute 0.0.
  for axiom in verifiedAxiomRegistry:
    if axiom.approved:
      result += axiom.asiWeight
  for m in axiomMappings:
    if m.verified:
      result += getAxiomWeight(m.axiomId)

{.pop.}
