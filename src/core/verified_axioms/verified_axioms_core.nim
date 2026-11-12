import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import ../../core/trusted/axiom_pragmas
import core/crypto/hash_kernel
import core/utils/ident_utils
import std/strutils
# ---------------------------------------------------------------------------
# Axiom Category
# ---------------------------------------------------------------------------

type
  AxiomCategory* = enum
    acLengthNonNeg      ## .len / .size ≥ 0 guarantee
    acTypeCoercion      ## Nim type ↔ Lean type isomorphism
    acArithmetic        ## Arithmetic operation closure / commutativity
    acMemory            ## Memory access boundary safety
    acEffectIsolation   ## Side-effect isolation (purity)
    acLogicOperator     ## Logical operator equivalence
    acContainerOps      ## Container accessor semantics (get, contains, etc.)
# ---------------------------------------------------------------------------
# Axiom Mapping (The Bridge Record)
# ---------------------------------------------------------------------------

type
  AxiomMapping* = object
    axiomId*: string              ## Unique identifier (e.g. "nim.string.len.isNat")
    nimSymbol*: string            ## Nim stdlib symbol path (e.g. "system.len(string)")
    leanTheorem*: string          ## Lean theorem name (e.g. "String.length")
    leanType*: string             ## Return-type guarantee (e.g. "Nat")
    nimSignature*: string         ## Nim function signature
    leanSignature*: string        ## Lean theorem signature
    axiomVersion*: string         ## Version (semver)
    proofObligation*: string      ## Human-readable proof obligation
    verified*: bool               ## Has this axiom been verified?
    sourceHash*: string           ## SHA-256 of (axiomId + nimSignature + leanSignature)
    leanTheoremSource*: string    ## Lean theorem source code
    nimAstHash*: string           ## SHA-256 of IR function structure (Phase 5A)
    leanAstHash*: string          ## SHA-256 of normalized Lean output (Phase 5A)
    category*: AxiomCategory      ## Semantic domain
# ---------------------------------------------------------------------------
# Legacy Types (backward compatibility)
# ---------------------------------------------------------------------------

type
  VerifiedAxiom* = object
    name*: string
    tokens*: seq[string]
    approved*: bool
    asiWeight*: float  ## 0.0 = trivial (statically guaranteed), 1.0 = runtime-meaningful
# ---------------------------------------------------------------------------
# Hash computation
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Hash computation
# ---------------------------------------------------------------------------
func computeAxiomHash*(axiomId, nimSig, leanSig: string): string {.raises: [], axiom: ["(assert (and (>= (str.len axiomId) 0) (>= (str.len nimSig) 0) (>= (str.len leanSig) 0) (>= result 0)))", "axiomId.length ≥ 0 ∧ nimSig.length ≥ 0 ∧ leanSig.length ≥ 0 ∧ (result ≥ 0)"].} =
  ## Deterministic SHA-256 of the axiom identity.
  ## Hash covers: axiomId + nimSignature + leanSignature.
  result = hash_kernel.computeContentHash(axiomId & "|" & nimSig & "|" & leanSig)
func normalizeVerifiedAxiomProp*(prop: string): string {.raises: [], axiom: ["(assert (and (>= (str.len prop) 0)))", "prop.length ≥ 0"].} =
  prop
    .replace("≥", ">=")
    .replace("≤", "<=")
    .replace("∧", "/\\")
    .replace("∨", "\\/")
    .replace("∀", "forall")
    .replace("∃", "exists")
    .replace("→", "->")
    .replace("≠", "!=")
    .replace("ℕ", "Nat")
    .toLowerAscii()
const naturalDomainBaseNames = [
  "depth", "count", "size", "length", "index", "idx"
]
func previousNonSpaceChar(prop: string; pos: int): char {.raises: [], axiom: ["(assert (and (>= (str.len prop) 0) (and (>= pos -9223372036854775808) (<= pos 9223372036854775807)) (>= i 0)))", "prop.length ≥ 0 ∧ pos ≥ -9223372036854775808 ∧ pos ≤ 9223372036854775807 ∧ i ≥ 0"].} =
  var i = pos - 1
  while i >= 0:
    if prop[i] notin {' ', '\t', '\r', '\n'}:
      return prop[i]
    dec i
  '\0'
func hasDomainSuffixBoundary(name: string; suffix: string): bool {.raises: [], axiom: ["(assert (and (>= (str.len name) 0) (>= (str.len suffix) 0)))", "name.length ≥ 0 ∧ suffix.length ≥ 0"].} =
  if name.len <= suffix.len:
    return false
  let suffixStart = name.len - suffix.len
  let lowerName = name.toLowerAscii()
  if not lowerName.endsWith(suffix):
    return false
  name[suffixStart].isUpperAscii() or name[suffixStart - 1] == '_'
func isNaturalDomainVariableName*(name: string): bool {.raises: [], axiom: ["(assert (and (>= (str.len name) 0)))", "name.length ≥ 0"].} =
  let lower = name.toLowerAscii()
  if lower in naturalDomainBaseNames:
    return true
  for suffix in naturalDomainBaseNames:
    if hasDomainSuffixBoundary(name, suffix):
      return true
  false
func extractAxiomIdentifiers(prop: string): seq[string] {.raises: [], axiom: ["(assert (and (>= (str.len prop) 0) (< i (str.len prop)) (and (>= i 0) (< i prop))))", "prop.length ≥ 0 ∧ i < prop.length ∧ ((i ≥ 0) ∧ (i < prop))"].} =
  var i = 0
  while i < prop.len:
    if isIdentStart(prop[i]):
      let start = i
      var ident = ""
      while i < prop.len and isIdentPart(prop[i]):
        ident.add(prop[i])
        inc i
      if previousNonSpaceChar(prop, start) != '.' and ident.len > 0 and ident notin result:
        result.add(ident)
    else:
      inc i
func compactAxiomComparison*(prop: string): string {.raises: [], axiom: ["(assert (and (>= (str.len prop) 0) (>= prop 0)))", "prop.length ≥ 0 ∧ (prop ≥ 0)"].} =
  for ch in prop:
    if ch notin {' ', '\t', '\r', '\n'}:
      result.add(ch)
func hasNaturalNonnegativeShape(compactProp: string; name: string): bool {.raises: [], axiom: ["(assert (and (>= (str.len compactProp) 0) (>= (str.len name) 0)))", "compactProp.length ≥ 0 ∧ name.length ≥ 0"].} =
  let lowerName = name.toLowerAscii()
  compactProp.contains(lowerName & ">=0") or compactProp.contains("0<=" & lowerName)
func naturalDomainAxiomName*(leanProp: string): string {.raises: [], axiom: ["(assert (and (>= (str.len leanProp) 0)))", "leanProp.length ≥ 0"].} =
  let normalized = normalizeVerifiedAxiomProp(leanProp)
  let compact = compactAxiomComparison(normalized)
  for ident in extractAxiomIdentifiers(leanProp):
    if isNaturalDomainVariableName(ident) and hasNaturalNonnegativeShape(compact, ident):
      return "natural-nonneg"
  ""
func hasBoolExhaustiveShape(compactProp: string; name: string): bool {.raises: [], axiom: ["(assert (and (>= (str.len compactProp) 0) (>= (str.len name) 0)))", "compactProp.length ≥ 0 ∧ name.length ≥ 0"].} =
  let lowerName = name.toLowerAscii()
  compactProp.contains(lowerName & "=true\\/" & lowerName & "=false") or
    compactProp.contains(lowerName & "=false\\/" & lowerName & "=true")
func boolCasesAxiomName*(leanProp: string): string {.raises: [], axiom: ["(assert (and (>= (str.len leanProp) 0)))", "leanProp.length ≥ 0"].} =
  let normalized = normalizeVerifiedAxiomProp(leanProp)
  let compact = compactAxiomComparison(normalized)
  for ident in extractAxiomIdentifiers(leanProp):
    let lower = ident.toLowerAscii()
    if lower in ["true", "false"]:
      continue
    if hasBoolExhaustiveShape(compact, ident):
      return "bool-cases"
  ""

{.pop.}
