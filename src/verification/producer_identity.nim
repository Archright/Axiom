## producer_identity.nim — Producer Boundary Contract
##
## PROVISIONAL. Separates the VERIFICATION computation from the
## computation that PRODUCES the verifier; semantic closure vs
## producer closure.
##
## Precedent: verification/semantic_query_types.nim
## (provisionalQueryID / hexToBytes raw-32-byte concat pattern).

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/[algorithm, strutils]
import verification/semantic_query_types
import verification/verification_dependency
import core/crypto/hash_kernel

# ---------------------------------------------------------------------------
# Producer Phase & Dependency Domain enums
# ---------------------------------------------------------------------------

type
  ProducerPhase* = enum
    ppProducer
    ppVerification

  DependencyDomain* = enum
    ddSemantic
    ddProducer
    ddProvenance
    ddInternal
    ddOutput
    ddUnknown

func `$`*(d: DependencyDomain): string {.raises: [].} =
  case d
  of ddSemantic:   "SEMANTIC"
  of ddProducer:   "PRODUCER"
  of ddProvenance: "PROVENANCE"
  of ddInternal:   "INTERNAL"
  of ddOutput:     "OUTPUT"
  of ddUnknown:    "UNKNOWN"

# ---------------------------------------------------------------------------
# Pure path classifiers
# ---------------------------------------------------------------------------

func isSystemRuntimePath*(path: string): bool {.raises: [].} =
  ## Conservative match for OS runtime / ABI paths shared across any phase.
  let p = path.replace('\\', '/')
  if p.contains("/lib/"): return true
  if p.contains("/usr/lib/"): return true
  if p.contains("/etc/ld.so"): return true
  if p.contains("/etc/ld-"): return true
  if p.contains("/proc/self/exe"): return true
  if p.contains("/usr/share/locale"): return true
  if p.contains("/etc/localtime"): return true
  if p.contains("/usr/lib/locale"): return true
  if p.contains("libc.so"): return true
  if p.contains(".so.") and (p.contains("/lib/") or p.contains("/usr/lib/")):
    return true
  false

func isGateBinaryPath*(path: string): bool {.raises: [].} =
  ## True iff the path points to the verification auditor binary.
  path.contains("bin/verification_auditor")

# ---------------------------------------------------------------------------
# Contract adapter: ReadClass + path + phase -> DependencyDomain
# ---------------------------------------------------------------------------

func dependencyDomain*(rc: ReadClass; path: string; phase: ProducerPhase): DependencyDomain {.raises: [].} =
  ## Producer-Boundary Contract adapter.
  ## Rule (documented, deterministic):
  ##   1. isSystemRuntimePath(path) -> ddProducer  (runtime/ABI identity of ANY phase)
  ##   2. phase == ppProducer -> ddProducer        (all compile-time/toolchain reads)
  ##   3. verification phase:
  ##        rcModuleContent|rcTestGateway|rcManualFeature|rcBaseline|
  ##          rcLockFile|rcPolicy        -> ddSemantic
  ##        rcCommitId                   -> ddProvenance
  ##        rcTimestamp|rcHistory        -> ddInternal
  ##        rcGateOutput                 -> ddOutput
  ##        rcModuleExistence            -> ddProducer if isGateBinaryPath(path)
  ##                                             else ddUnknown
  ##        rcEnvVar|rcCwd|rcCompilerSubprocess|rcOther (and any unclassified)
  ##                                             -> ddUnknown  (fail-closed)
  if isSystemRuntimePath(path):
    return ddProducer
  if phase == ppProducer:
    return ddProducer
  # Verification phase below.
  case rc
  of rcModuleContent, rcTestGateway, rcManualFeature,
     rcBaseline, rcLockFile, rcPolicy:
    result = ddSemantic
  of rcCommitId:
    result = ddProvenance
  of rcTimestamp, rcHistory:
    result = ddInternal
  of rcGateOutput:
    result = ddOutput
  of rcModuleExistence:
    if isGateBinaryPath(path):
      result = ddProducer
    else:
      result = ddUnknown
  of rcEnvVar, rcCwd, rcCompilerSubprocess, rcOther:
    result = ddUnknown

# ---------------------------------------------------------------------------
# ProducerIdentity object
# ---------------------------------------------------------------------------

type
  ProducerIdentity* = object
    gateSourceClosure*: string
    auditorSourceClosure*: string
    compilerExeDigest*: string
    compilerVersion*: string
    hostIdentity*: string
    nimLibClosure*: string
    buildConfig*: string
    provisional*: bool

func newProducerIdentity*(
  gateSourceClosure = ""; auditorSourceClosure = "";
  compilerExeDigest = ""; compilerVersion = "";
  hostIdentity = ""; nimLibClosure = "";
  buildConfig = ""
): ProducerIdentity {.raises: [].} =
  ## Constructor with defaults; provisional defaults to true.
  ProducerIdentity(
    gateSourceClosure: gateSourceClosure,
    auditorSourceClosure: auditorSourceClosure,
    compilerExeDigest: compilerExeDigest,
    compilerVersion: compilerVersion,
    hostIdentity: hostIdentity,
    nimLibClosure: nimLibClosure,
    buildConfig: buildConfig,
    provisional: true
  )

# ---------------------------------------------------------------------------
# Digest: boundary-preserving raw-byte concat then SHA-256
# ---------------------------------------------------------------------------

func producerIdentityDigest*(pi: ProducerIdentity): string {.raises: [].} =
  ## Boundary-preserving digest.
  ## Decode each non-empty hex component via hexToBytes, concatenate
  ## raw bytes in the canonical field order, then SHA-256 hex.
  ## Empty components are skipped (no separator; matches
  ## provisionalQueryID precedent in semantic_query_types.nim).
  var raw: seq[byte] = @[]
  for comp in [pi.gateSourceClosure, pi.auditorSourceClosure,
               pi.compilerExeDigest, pi.compilerVersion,
               pi.hostIdentity, pi.nimLibClosure, pi.buildConfig]:
    if comp.len > 0:
      raw.add hexToBytes(comp)
  sha256Hex(cast[string](raw))

# ---------------------------------------------------------------------------
# provisionalVerificationIdentity: H(SemanticQuery, ProducerIdentity)
# ---------------------------------------------------------------------------

func provisionalVerificationIdentity*(sq: SemanticQuery; pi: ProducerIdentity): string {.raises: [].} =
  ## H(SemanticQuery, ProducerIdentity): raw-byte concat of
  ## provisionalQueryID(sq) bytes + producerIdentityDigest(pi) bytes -> sha256 hex.
  let sqBytes = hexToBytes(string(provisionalQueryID(sq)))
  let piBytes = hexToBytes(producerIdentityDigest(pi))
  sha256Hex(cast[string](sqBytes & piBytes))

{.pop.}

import verification/observation_pipeline

func dependencyClosureDigest*(deps: seq[ValidatedDependency]): string {.raises: [].} =
  ## Canonical digest over the validated dependency closure.
  ## Per-entry format mirrors repo_snapshot_digest (path|kind|status|contentDigest),
  ## sorted, deduplicated, newline-joined, sha256. Order-independent and
  ## duplicate-safe. The kind/status fields carry the VALIDATED DOMAIN — a
  ## dependency whose classification flips (e.g. semantic <-> unknown) MUST
  ## change the closure digest.
  var entries: seq[string] = @[]
  for dep in deps:
    entries.add(depPath(dep) & "|" & $(depKind(dep)) & "|" & $(depStatus(dep)) & "|" & depContentDigest(dep))
  entries.sort()
  var uniq: seq[string] = @[]
  for e in entries:
    if uniq.len == 0 or e != uniq[^1]:
      uniq.add(e)
  sha256Hex(uniq.join("\n"))

type
  CanonicalVerificationIdentity* = distinct string
    ## Typed canonical verification identity (PROMOTED: Provisional -> Validated -> Canonical).

func newCanonicalVerificationIdentity*(hex: string): CanonicalVerificationIdentity {.raises: [].} =
  CanonicalVerificationIdentity(hex)

func `$`*(i: CanonicalVerificationIdentity): string {.raises: [].} = string(i)
func `==`*(a, b: CanonicalVerificationIdentity): bool {.raises: [].} = string(a) == string(b)
func `!=`*(a, b: CanonicalVerificationIdentity): bool {.raises: [].} = string(a) != string(b)

func canonicalVerificationIdentity*(sq: SemanticQuery; pi: ProducerIdentity; closureDigest: string): string {.raises: [].} =
  ## PROMOTED canonical identity: H(SemanticQuery, ProducerIdentity,
  ## validatedDependencyClosure) — boundary-preserving raw-byte concat of
  ## provisionalQueryID(sq) + producerIdentityDigest(pi) + closureDigest,
  ## then sha256 hex (mirrors provisionalQueryID/producerIdentityDigest).
  ## Any verification-phase Unknown dependency keeps the closure honest:
  ## the identity changes if the unknown set changes.
  let raw = hexToBytes(string(provisionalQueryID(sq))) &
            hexToBytes(producerIdentityDigest(pi)) &
            hexToBytes(closureDigest)
  sha256Hex(cast[string](raw))

func canonicalVerificationIdentity*(sq: SemanticQuery; pi: ProducerIdentity; deps: seq[ValidatedDependency]): string {.raises: [].} =
  ## Overload: compute the closure digest from the deps first.
  canonicalVerificationIdentity(sq, pi, dependencyClosureDigest(deps))