import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## C1 Identity / Execution Closure — Phase C1
##
## Implements the fixed identity schema:
##   ArtifactIdentity        = H(canonical artifact)
##   ExecutionIdentity       = H(InputIdentity + ExecutionContract + CanonicalExecutionBundleFingerprint)
##   KAAIdentity             = H(CanonicalKAAProjection)
##   DecisionIdentity        = H(KAAIdentity + VerificationPolicyRevision)
##   CanonicalResultIdentity = H(DecisionIdentity + FinalVerdict)
##
## All functions are pure and deterministic. Identity digests
## exclude provenance (observedAt, timestamps, randomness).

import std/[strutils, sequtils, algorithm, os]
import core/crypto/hash_kernel
import core/trusted/semantic_profile
import verification/pipeline_state_types

# ---------------------------------------------------------------------------
# C1.1 ArtifactIdentity = H(canonical artifact)
# ---------------------------------------------------------------------------
## ArtifactIdentity is the hash of the canonical artifact content alone.
## It does NOT mix execution identity into it.

func artifactIdentity*(canonicalArtifact: string): string {.raises: [].} =
  sha256Hex(canonicalArtifact)

# ---------------------------------------------------------------------------
# C1.2a EnvVarSpec — canonical semantic environment variable
# ---------------------------------------------------------------------------
## Each allowed env var carries both its name and its canonical
## semantic value. The canonical value is computed by
## `canonicalizeEnvValue` which classifies the raw value:
##   1. unset/empty → "" (canonical empty marker)
##   2. repo-local path → project-relative normalized path (pure, no std/os relativePath)
##   3. toolchain-managed path (.elan, /lean, /lake, AXIOM_LEAN_CMD) → actual value
##   4. system path (/tmp, /var/tmp, /usr/bin, /bin, etc.) → "" (canonicalized away)
##   5. other absolute path → "__VIOLATION__" prefix (digest differs)
##   6. relative path → normalized as-is
##   7. non-path value → as-is

type EnvVarSpec* = object
  name*: string            ## environment variable name
  canonicalValue*: string  ## canonical semantic value after classification

# ---------------------------------------------------------------------------
# C1.2b canonicalizeEnvValue — pure classification of env values
# ---------------------------------------------------------------------------

func canonicalizeEnvValue*(name: string; rawValue: string; repoRoot: string): string {.raises: [].} =
  ## Classify and canonicalize an env var value for the execution contract.
  ## Pure function — no filesystem access, no side effects.
  if rawValue.len == 0:
    return ""
  let v = rawValue.replace("\\", "/")
  # PATH: colon-separated list — canonicalize each component independently.
  # Each component is canonicalized as a single-valued path (not as PATH
  # again), otherwise this recurses on the same name forever.
  if name == "PATH":
    let dirs = v.split(":")
    var canonicalDirs: seq[string] = @[]
    for dir in dirs:
      if dir.len == 0:
        continue
      let c = canonicalizeEnvValue("", dir, repoRoot)
      if c.len > 0:
        canonicalDirs.add(c)
    return canonicalDirs.sorted.join(":")
  # Single-value classification
  if v.startsWith("/"):
    if repoRoot.len > 0 and v.startsWith(repoRoot):
      # repo-local path → project-relative normalized form
      return v[repoRoot.len .. ^1].strip(chars = {'/'}).normalizedPath
    elif name == "AXIOM_LEAN_CMD" or v.contains(".elan") or v.endsWith("/lean") or v.endsWith("/lake"):
      # toolchain-managed path → actual value (deterministic, part of pinned bundle)
      return v
    elif v.startsWith("/tmp") or v.startsWith("/var/tmp") or v.startsWith("/usr/bin") or
         v == "/bin" or v.startsWith("/usr/lib") or v.startsWith("/lib") or
         v.startsWith("/sbin") or v.startsWith("/usr/sbin"):
      # system path — canonicalize away (value does not affect determinism)
      return ""
    else:
      # unexpected external absolute path → contract violation marker
      return "__VIOLATION__" & v
  elif v.contains("/"):
    # relative path with components → normalize
    return v.normalizedPath
  else:
    # non-path value (plain string) → as-is
    return v

# ---------------------------------------------------------------------------
# C1.2 ExecutionContract — canonicalized hermetic execution closure
# ---------------------------------------------------------------------------
## The ExecutionContract canonicalizes the hermetic execution closure.
## It includes: invocation, platform, working directory, allowed environment,
## filesystem boundary, network policy, mounted inputs, resource policy.
## The intent is to BLOCK disallowed environment, not to record-and-replay
## ambient state. Keep it deterministic (no timestamp/randomness).
## allowedEnv now carries both env var names AND their canonical semantic
## values (classified by canonicalizeEnvValue) so that toolchain-resolving
## environment differences produce different digests.

## Measured host platform identifier — the arch binding of the execution
## identity. Compiled in from `hostOs`/`hostCpu`, so it is a compile-time
## constant of the binary: stable across every run of this executable (it
## cannot fluctuate between two invocations on the same host) and still
## discriminating across hosts, because the binary is built on the host whose
## arch it reports. This must never be a literal — a hardcoded platform made
## `executionContractDigest` arch-blind, so every arm64 runner bound the same
## constant while `captureToolchainIdentity` (nim/lean/z3 versions only)
## carries no architecture of its own.
const hostPlatformId* = toLowerAscii($hostOs) & "-" & toLowerAscii($hostCpu)

## The verified semantic-model identity segment (base36_sizing_binding_contract
## §4 item 2). The hash is `SemanticProfileV1Hash` (core/trusted/semantic_profile)
## — the SAME constant cert_writer.nim consumes as the certificate
## `semanticProfileId` fallback — so the identity names the VERIFICATION
## DOMAIN's semantic profile (target, int width, overflow/division/modulo/
## shift/float/string/uint modes), never Axiom's own compile profile. Since the
## 2026-10-07 weakening (DEBT#494) the profile itself declares the coincidence
## semantics (spDivCoincidentNonnegative / spOverflowObligationDischarged —
## docs/spec/semantic_profile_verified_semantics.md); the suffix states the
## coincidence the encoded obligations rely on: a no-overflow obligation
## discharges overflow reachability, so checked (OverflowDefect) and wrapping
## arithmetic coincide in the verified domain — the same domain-pattern
## precedent as the div/rem segments of
## canonical_verification.captureToolchainIdentity.
const modelProfileIdentitySegment* =
  "modelprofile=" & SemanticProfileV1Hash &
  "/no-overflow-obligations/coincident-checked-wrap-domain"

type ExecutionContract* = object
  invocation*: string          ## canonical argv string
  platform*: string            ## os/arch identifier — `hostPlatformId` (e.g. "linux-amd64", "linux-arm64")
  workdir*: string             ## working directory assertion
  allowedEnv*: seq[EnvVarSpec] ## allowed environment variables with canonical values (sorted by name)
  fsBoundary*: string          ## filesystem boundary (read/write path roots)
  networkPolicy*: string       ## network access policy ("deny" | "allow-list")
  mountedInputs*: string       ## hash of mounted input artifacts
  resourcePolicy*: string      ## CPU/memory/resource limits digest

func canonicalExecutionContract*(
  invocation: string;
  platform: string;
  workdir: string;
  allowedEnv: seq[EnvVarSpec];
  fsBoundary: string;
  networkPolicy: string;
  mountedInputs: string;
  resourcePolicy: string
): ExecutionContract {.raises: [].} =
  ## Construct a canonical ExecutionContract from hermetic components.
  ## Environment variables are sorted by name for deterministic ordering.
  var sortedEnv = allowedEnv
  sortedEnv.sort(proc(a, b: EnvVarSpec): int = cmp(a.name, b.name))
  ExecutionContract(
    invocation: invocation,
    platform: platform,
    workdir: workdir,
    allowedEnv: sortedEnv,
    fsBoundary: fsBoundary,
    networkPolicy: networkPolicy,
    mountedInputs: mountedInputs,
    resourcePolicy: resourcePolicy
  )

func executionContractDigest*(contract: ExecutionContract): string {.raises: [].} =
  ## Deterministic digest of the execution contract.
  ## Hashes sorted name|canonicalValue pairs so that a changed
  ## toolchain-resolving env changes the digest, while semantically
  ## equivalent values (e.g. system paths canonicalized away) do not
  ## unnecessarily churn the digest.
  let envStr = contract.allowedEnv.mapIt(it.name & "|" & it.canonicalValue).join("|")
  sha256Hex(
    contract.invocation & "|" &
    contract.platform & "|" &
    contract.workdir & "|" &
    envStr & "|" &
    contract.fsBoundary & "|" &
    contract.networkPolicy & "|" &
    contract.mountedInputs & "|" &
    contract.resourcePolicy
  )

# ---------------------------------------------------------------------------
# C1.3 CanonicalExecutionBundleFingerprint
# ---------------------------------------------------------------------------
## The KEY piece. NOT a mere Lean toolchain fingerprint. It must be an
## immutable bundle fingerprint of the ENTIRE Axiom decision computation
## closure: Axiom executable/source, Lean, Z3, Lake, dependencies,
## required runtime, and the canonical evaluation implementation.
##
## The goal of C1.3 is "is Axiom's VERIFIED decision computation the
## same?", not "is Lean the same?".
##
## Uses immutable source/digest inputs — does not read mutable files
## lazily during hashing; captures a deterministic fingerprint.
##
## The measured digest is produced by `lean_kernel_boundary.computeBundleDigest`
## at the trust boundary and consumed as-is here — the type and functions remain
## pure: they hash whatever string inputs they are given.

type CanonicalExecutionBundle* = object
  axiomExecutableDigest*: string     ## SHA256 of the Axiom binary
  axiomSourceDigest*: string         ## SHA256 of the Axiom source bundle
  leanVersion*: string               ## Lean toolchain version (e.g. "4.33.0")
  z3Version*: string                 ## Z3 solver version (e.g. "4.13.3")
  lakeVersion*: string               ## Lake build tool version
  nimVersion*: string                ## Nim compiler version (e.g. "2.2.10")
  dependencyDigests*: seq[string]    ## SHA256 of each dependency artifact
  runtimeDigest*: string             ## SHA256 of the required runtime
  evaluationImplementationDigest*: string ## SHA256 of the canonical evaluation impl

func canonicalExecutionBundleFingerprint*(
  axiomExeDigest, axiomSourceDigest, leanVer, z3Ver, lakeVer, nimVer: string;
  dependencyDigests: seq[string];
  runtimeDigest, evaluationImplDigest: string
): string {.raises: [].} =
  ## Compute the canonical execution bundle fingerprint.
  ## This is a deterministic digest of the full decision computation closure.
  let sortedDeps = dependencyDigests.sorted
  sha256Hex(
    axiomExeDigest & "|" &
    axiomSourceDigest & "|" &
    leanVer & "|" &
    z3Ver & "|" &
    lakeVer & "|" &
    nimVer & "|" &
    sortedDeps.join("|") & "|" &
    runtimeDigest & "|" &
    evaluationImplDigest
  )

# ---------------------------------------------------------------------------
# C1.3b Dependency Digest Computation
# ---------------------------------------------------------------------------
## Computes sorted dependency digests for a set of dependency names.
## Each dependency name is hashed as sha256Hex(name) to produce a
## content-addressed digest. The result is sorted for determinism.
## This mirrors the pattern used for the unit's own inputHash
## (sha256Hex(sourcePath & "::" & funcName)) but operates on the
## callee name as the canonical identifier for the dependency.
##
## FAIL-CLOSED: every callee name found in the IR is included in
## the digest list. Unknown/unresolvable symbols are still recorded
## by name so the digest changes when the dependency set changes.
## This is a semantic contract point — dropping unknown dependencies
## would silently hide integrity gaps.

func computeDependencyDigests*(calleeNames: seq[string]): seq[string] {.raises: [].} =
  var digests: seq[string] = @[]
  for name in calleeNames:
    digests.add(sha256Hex(name))
  result = digests.sorted

# ---------------------------------------------------------------------------
# C1.3c Semantic Bundle Fingerprint
# ---------------------------------------------------------------------------
## Composes the measured toolchain fingerprint (from the LeanKernelCheckReceipt)
## with the sorted dependency digests into a single semantic bundle fingerprint.
## This is the value that feeds into executionIdentity, ensuring that a change
## to any dependency's identity changes the execution identity.
## The formula is: H(toolchainFingerprint & "|" & sortedDependencyDigests.join("|"))
## This keeps the executionIdentity formula itself unchanged (H(InputId + ContractDigest + BundleFp))
## while enriching BundleFingerprint with semantic dependency information.

func computeSemanticBundleFingerprint*(
  toolchainFingerprint: string;
  dependencyDigests: seq[string]
): string {.raises: [].} =
  let sortedDeps = dependencyDigests.sorted
  sha256Hex(toolchainFingerprint & "|" & sortedDeps.join("|"))

# ---------------------------------------------------------------------------
# C1.3d EvaluationImplementationDigest — the lowering implementation's identity
# ---------------------------------------------------------------------------
## Binds the code that GIVES the subject its verified semantics:
## pnode_to_canon.nim (PNode → canonical AST), ast_to_ir.nim (canonical AST
## → IR), the IR→Lean renderer, and proofs/IR/Denotation.lean (the Lean
## denotation of the IR). Without it, an edit that quietly widens the lowering
## semantics could keep reusing evidence produced under the old semantics.
## Every field is a measured sha256 hex digest or "" — "" is its own component
## value, so an unmeasured implementation can never be equal to a measured one.

type EvaluationImplementationDigests* = object
  pnodeToCanon*: string
  astToIr*: string
  leanRenderer*: string
  denotationLean*: string

func evaluationImplementationDigest*(d: EvaluationImplementationDigests): string {.
  raises: [].} =
  sha256Hex(
    "evaluation-implementation-v1" &
    "|pnodeToCanon=" & d.pnodeToCanon &
    "|astToIr=" & d.astToIr &
    "|leanRenderer=" & d.leanRenderer &
    "|denotationLean=" & d.denotationLean
  )

func computeSemanticBundleFingerprintBound*(
  toolchainFingerprint: string;
  dependencyDigests: seq[string];
  evaluationImplDigest: string
): string {.raises: [].} =
  ## C1.3c composition with the evaluation implementation folded in:
  ## H(toolchainFingerprint | sortedDependencyDigests | evaluationImplDigest).
  ## The canonical path must use this variant so the execution identity names
  ## the lowering implementation, not only the toolchain binaries.
  let sortedDeps = dependencyDigests.sorted
  sha256Hex(toolchainFingerprint & "|" & sortedDeps.join("|") & "|" & evaluationImplDigest)

# ---------------------------------------------------------------------------
# C1.3b ExecutionIdentity = H(InputIdentity + ExecutionContract + BundleFingerprint)
# ---------------------------------------------------------------------------

func executionIdentity*(
  inputIdentity: string;
  executionContractDigest: string;
  bundleFingerprint: string
): string {.raises: [].} =
  sha256Hex(inputIdentity & "|" & executionContractDigest & "|" & bundleFingerprint)

# ---------------------------------------------------------------------------
# C1.5 CanonicalResultIdentity = H(DecisionIdentity + FinalVerdict)
# ---------------------------------------------------------------------------

func canonicalResultIdentity*(decisionIdentity: string; finalVerdict: VerificationVerdict): string {.raises: [].} =
  sha256Hex(decisionIdentity & "|" & $finalVerdict)

{.pop.}
