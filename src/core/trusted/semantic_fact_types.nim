import core/trusted/layer_declaration
import core/trusted/axiom_ir
import core/crypto/hash_kernel
axiomLayer "trusted.core.semantic-fact-types"
{.push raises: [].}

## semantic_fact_types.nim — WP4-j.2 Phase C + WP4-j.4 Evidence Ladder.
##
## Value types only (no procs). Represents the projection of compile-time
## literal bindings and template instantiation observations into IR-shaped
## propositions (boEq(irVar, irLit)).
## SMT expressions are NOT used here — propositions remain IR-shaped.
##
## Fact origin: foCompileTimeBinding — facts derived from isCompileTime=true
## irLet nodes with literal values.
## Fact origin: foTemplateInstantiation — facts derived from observed
## template instantiation bindings (witness consumption, not AST re-interpretation).

## ── Fact origin ──────────────────────────────────────────

type
  FactOrigin* = enum
    foCompileTimeBinding
    foTemplateInstantiation

## ── Fact status (evidence ladder strength) ───────────────

type
  FactStatus* = enum
    fsObserved
    fsMechanicalDerived
    fsDerived
    fsUnknown

## ── Provenance ───────────────────────────────────────────

type
  FactProvenance* = object
    origin*: FactOrigin
    occurrenceRef*: string   ## deterministic traversal-path string
    sourceRef*: string       ## source identity (external=rawSource, self=astRepr)
    ## Binding provenance. Internal only, never serialized: the v3 certificate
    ## identity is a fixed 13-key projection (verification/certificate_identity),
    ## so a 14th key would fork the writer, the verifier projection and the
    ## golden byte vectors for no reader that exists today.
    ##
    ## The four binding fields together answer "which lexical binding discharged
    ## which free variable, with what value, and where" without inlining the
    ## bound expression. The value travels as a digest: the reader can confirm
    ## the binding they found in source still hashes to what was discharged,
    ## and cannot be handed a forged RHS as if it were observed evidence.
    bindingSymbol*: string       ## lexical binder that discharged the variable
    bindingKind*: string         ## "let" | "const" | "param" | "template" | ...
    boundVariable*: string       ## free variable this binding resolved
    bindingValueDigest*: string  ## sha256Hex of the bound RHS; "" = not established
    sourceLine*: int             ## 1-based line of the binding site; 0 = unavailable
    sourceColumn*: int           ## 1-based column of the binding site; 0 = unavailable

## ── Semantic Fact ────────────────────────────────────────
## Proposition is IR-shaped: boEq(irVar(name,ty), irLit(v)).
## No SMT expressions — keep the fact in IR domain.

type
  SemanticFact* = object
    id*: string
    proposition*: IRExpr
    provenance*: FactProvenance

## ── Semantic Environment ─────────────────────────────────────

type
  BoundaryRecord* = object
    symbol*: string
    reason*: string

  SemanticEnvironment* = object
    facts*: seq[SemanticFact]
    boundaryRecords*: seq[BoundaryRecord]

## ── Completeness Evidence ────────────────────────────────────
## Independent evidence for whether fact emission is allowed.
## v1: two-axis completeness (translationLossFree ∧ bindingUniverseComplete).

type
  CompletenessEvidence* = object
    translationLossFree*: bool
    bindingUniverseComplete*: bool
    opaqueExpansionStatus*: string
    sourceBindingCount*: int
    irBindingCount*: int

## ── Evidence Ladder fact types (WP4-j.4) ────────────────────
## Each fact's id = sha256Hex(self-input-only material).
## Previous fact id/value must NOT be referenced in a later fact's id.

type
  TypeIdentityFact* = object
    id*: string                ## sha256Hex("typealias:" & sourceType)
    sourceType*: string        ## e.g. "BiggestUInt"
    canonicalType*: string     ## e.g. "uint64"
    status*: FactStatus        ## fsObserved
    observationSource*: string ## "toolchain-system-nim"
    toolchainIdentity*: string ## "nim-2.2.10"

  IRRepresentationFact* = object
    id*: string                ## sha256Hex("repr:" & sourceType & ":" & irTypeKind)
    sourceType*: string        ## e.g. "uint64"
    irTypeKind*: string        ## e.g. "BitVec64"
    status*: FactStatus        ## fsDerived
    representationScope*: string ## "Axiom current IR representation contract"
    contractId*: string        ## SemanticProfileV1Hash (proxy identity)

  SizeFact* = object
    id*: string                ## sha256Hex("size:" & sourceType)
    sourceType*: string        ## e.g. "uint64"
    bytes*: int                ## e.g. 8
    bits*: int                 ## e.g. 64
    status*: FactStatus        ## fsDerived

  ConstArithmeticFact* = object
    id*: string                ## sha256Hex("arith:" & $a & "*" & $b)
    expression*: string        ## e.g. "8*8"
    value*: int64              ## e.g. 64
    status*: FactStatus        ## fsDerived

  InstantiationBindingFact* = object
    id*: string                ## sha256Hex("inst:" & moduleIdentity & ":" & path & ":" & genericSymbol & ":" & concreteTypeIdent)
    genericSymbol*: string     ## e.g. "getBitsBE"
    typeParam*: string         ## e.g. "T"
    concreteType*: string      ## e.g. "BiggestUInt"
    status*: FactStatus        ## fsDerived
    scopeLimitation*: string   ## "observed instantiation-scoped binding — positional correspondence only"
    provenance*: FactProvenance  ## occurrenceRef + instantiationSite

{.pop.}
