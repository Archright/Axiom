import core/trusted/layer_declaration
axiomLayer "trusted"
{.push raises: [].}

import std/algorithm
import infrastructure/cas_index
import core/trusted/semantic_profile

## Canonical verification-scope identity (Wave 0e / Step 5).
##
## Scope identity is a CANONICAL SEMANTIC serialization of the scope contract —
## NOT a raw byte-hash of the lock file. This makes identity robust to:
##   * key ordering / whitespace churn in the lock file,
##   * schema-version tags that don't change the semantic contract,
##   * unrelated metadata added alongside the kernel scope.
##
## The scope digest binds: sorted kernel symbols ∪ sorted exclusions ∪
## kernel_total ∪ vks_total ∪ profile hash into one deterministic SHA-256 via
## combineHashes (order-sensitive, domain-separated).
##
## Fail-closed note (I5): callers MUST NOT pass an empty/zeroed scope as if it
## were canonical. computeCanonicalScopeDigest is pure; the fail-closed decision
## (reject unknown/empty scope) lives at the caller, which decides whether a
## missing lock means "no scope to commit against" (stop) vs degraded empty.

type
  CanonicalScopeInput* = object
    kernelSymbols*: seq[string]
    kernelExemptSymbols*: seq[string]
    kernelTotal*: int
    vksTotal*: int
    profileIdentity*: string      ## SemanticProfileV1Hash
    protocolVersion*: string      ## lock registry_version / protocol tag ("" if absent)

func canonicalScopeDigest*(input: CanonicalScopeInput): string {.raises: [].} =
  ## Deterministic SHA-256 over the canonical semantic scope serialization.
  ## Inputs are sorted inside this function, so the digest is independent of the
  ## order kernel_symbols / exclusions appear in the source lock file.
  var ks = input.kernelSymbols
  var ex = input.kernelExemptSymbols
  ks.sort()
  ex.sort()
  combineHashes(
    ks &
    ex &
    @[$input.kernelTotal] &
    @[$input.vksTotal] &
    @[input.profileIdentity] &
    @[input.protocolVersion]
  )

func configIdentityDigest*(profileIdentity, scopeLockHash: string): string {.raises: [].} =
  ## Deterministic config identity = profile identity ‖ scope lock hash.
  ## Mirrors resolvedConfigDigest (project_setup) while staying pure.
  combineHashes([profileIdentity, scopeLockHash])

func scopeInputFromSynthetic*(
  kernelSymbols, kernelExemptSymbols: seq[string];
  kernelTotal, vksTotal: int;
  profileIdentity, protocolVersion: string
): CanonicalScopeInput {.inline, raises: [].} =
  CanonicalScopeInput(kernelSymbols: kernelSymbols, kernelExemptSymbols: kernelExemptSymbols,
    kernelTotal: kernelTotal, vksTotal: vksTotal, profileIdentity: profileIdentity,
    protocolVersion: protocolVersion)

{.pop.}