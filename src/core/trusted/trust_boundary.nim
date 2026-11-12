import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## P0 Invariant — Trust Boundary Freeze
##
## Trust categories are disjoint:
## - recorded != trusted  (an SMT result recorded is NOT a proof)
## - verified != trusted  (justified by other evidence, not in the trust base)
## The `exists` field prevents over-claiming trust in components not yet present.

type
  TrustCategory* = enum
    tcTrusted    ## excluded from proof obligations (trust base)
    tcVerified   ## justified by other evidence
    tcRecorded   ## provenance only; recorded != trusted

  TrustBoundary* = object
    component*: string
    category*: TrustCategory
    rationale*: string
    exists*: bool      ## false = component not yet present (no trust over-claim)

const AxiomTrustBoundary*: array[11, TrustBoundary] = [
  TrustBoundary(
    component: "SHA-256 implementation",
    category: tcTrusted,
    rationale: "hashing base",
    exists: true
  ),
  TrustBoundary(
    component: "Lean kernel",
    category: tcTrusted,
    rationale: "machine-checked core",
    exists: true
  ),
  TrustBoundary(
    component: "Proof checker",
    category: tcTrusted,
    rationale: "validates proof artifacts",
    exists: false
  ),
  TrustBoundary(
    component: "Z3 result",
    category: tcRecorded,
    rationale: "SMT unsat result recorded, not a proof",
    exists: true
  ),
  TrustBoundary(
    component: "CanonicalIRSemantics",
    category: tcTrusted,
    rationale: "formal IR semantics",
    exists: false
  ),
  TrustBoundary(
    component: "CertificateIdentity binding",
    category: tcTrusted,
    rationale: "provenance-complete identity",
    exists: false
  ),
  TrustBoundary(
    component: "BMC engine",
    category: tcVerified,
    rationale: "performs bounded model checking",
    exists: true
  ),
  TrustBoundary(
    component: "Axiom CLI",
    category: tcRecorded,
    rationale: "command-line interface, provenance only",
    exists: true
  ),
  # Rust subject boundaries (ADR-0029 D3) — declared, not yet implemented.
  TrustBoundary(
    component: "rustc to LLBC lowering",
    category: tcRecorded,
    rationale: "qualified compiler assumption, not trusted (ADR-0029 D3)",
    exists: false
  ),
  TrustBoundary(
    component: "LLBC to shared canonical translation",
    category: tcRecorded,
    rationale: "LLBC normalization into shared canonical, provenance only",
    exists: false
  ),
  TrustBoundary(
    component: "dual IR derivation from shared canonical",
    category: tcRecorded,
    rationale: "two derivation paths from shared canonical, differential agreement",
    exists: false
  ),
]

func categoryOf*(component: string): TrustCategory =
  ## Returns the trust category for a known component.
  ## Falls back to tcRecorded for unknown components (fail-closed).
  for entry in AxiomTrustBoundary:
    if entry.component == component:
      return entry.category
  tcRecorded

func isTrusted*(component: string): bool =
  ## True only for tcTrusted components.
  result = false
  for entry in AxiomTrustBoundary:
    if entry.component == component and entry.category == tcTrusted:
      result = true

func isRecorded*(component: string): bool =
  ## True for tcRecorded components.
  result = false
  for entry in AxiomTrustBoundary:
    if entry.component == component and entry.category == tcRecorded:
      result = true

func existsInTrustBoundary*(component: string): bool =
  ## True if the component is declared and marked as existing.
  result = false
  for entry in AxiomTrustBoundary:
    if entry.component == component and entry.exists:
      result = true

{.pop.}