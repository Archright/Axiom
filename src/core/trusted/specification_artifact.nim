import core/trusted/layer_declaration
axiomLayer "trusted"
{.push raises: [].}

## SpecificationArtifact is the spec's identity/authority record.
## Its identity (SpecID) is INDEPENDENT of source/IR/semantic-profile hashes —
## each is its own artifact's identity. Derived as
## SpecID = H(canonicalSpecIR, origin, ruleVersion).
##
## soMined (LLM/auto) specs are NOT authorized for V1 verification input
## (per policy). Only soExplicit and soCanonicalDerived are authorized.
##
## canonicalSpecIR uses seq[string] (a canonical serialization of
## pre/postcondition IR expressions) rather than importing the heavy IR
## module. This keeps the module self-contained and compilable as a
## CONTRACT/view type; real IRExpr threading happens in Phase 3.

import std/algorithm
import std/json
import std/strutils
import core/crypto/hash_kernel
import core/results
import core/trusted/axiom_ir

type
  SpecOrigin* = enum
    ## Maps to CandidateEvidenceSource:
    ##   soExplicit         -> cesUser
    ##   soCanonicalDerived -> cesSynthesizer
    ##   soMined            -> cesSolver (LLM/auto — NOT authorized for V1)
    soExplicit
    soCanonicalDerived
    soMined

  SpecificationArtifact* = object
    canonicalSpecIR*: seq[string]   ## canonical serialized pre/post conditions (identity)
    rawPreConditions*: seq[IRExpr]  ## ORIGINAL IRExpr preserved (no reconstruction)
    rawPostConditions*: seq[IRExpr] ## ORIGINAL IRExpr preserved (no reconstruction)
    origin*: SpecOrigin
    ruleId*: string
    ruleVersion*: string

  SpecID* = string                 ## SHA-256 hex digest of canonical spec identity

func specIdentity*(spec: SpecificationArtifact): SpecID {.raises: [].} =
  let sortedIR = spec.canonicalSpecIR.sorted()
  let data = sortedIR.join("|") & "|" & $ord(spec.origin) & "|" & spec.ruleVersion
  sha256Hex(data)

func isAuthorizedForVerification*(origin: SpecOrigin): bool {.raises: [].} =
  ## true only for soExplicit and soCanonicalDerived; soMined is NOT
  ## authorized for V1 verification input per policy.
  origin in {soExplicit, soCanonicalDerived}

func `==`*(a, b: SpecificationArtifact): bool {.raises: [].} =
  a.canonicalSpecIR == b.canonicalSpecIR and
  a.origin == b.origin and
  a.ruleId == b.ruleId and
  a.ruleVersion == b.ruleVersion

func `$`*(spec: SpecificationArtifact): string {.raises: [].} =
  "SpecificationArtifact(ruleId=" & spec.ruleId &
  ", ruleVersion=" & spec.ruleVersion &
  ", origin=" & $spec.origin &
  ", specIdentity=" & spec.specIdentity &
  ")"

func explicitSpecFromOverlay*(overlay: JsonNode): Result[SpecificationArtifact, string] {.
  raises: [].} =
  ## Out-of-tree spec overlay (config/spec/*.json, Axiom-owned) →
  ## SpecificationArtifact. The origin is PINNED to soExplicit: an overlay
  ## authorizes verification only when it declares soExplicit, and any other
  ## declared origin fails closed — the overlay path can never mint
  ## soMined/LLM authority (claim_authority derives NOT PROVED for those).
  if overlay.isNil or overlay.kind != JObject:
    return err("spec overlay: not a JSON object")
  if overlay{"specOrigin"}.getStr("") != $soExplicit:
    return err("spec overlay: specOrigin must be soExplicit (fail-closed)")
  let ruleId = overlay{"ruleId"}.getStr("")
  let ruleVersion = overlay{"ruleVersion"}.getStr("")
  if ruleId.len == 0 or ruleVersion.len == 0:
    return err("spec overlay: ruleId and ruleVersion are required")
  let irNode = overlay{"canonicalSpecIR"}
  if irNode.isNil or irNode.kind != JArray or irNode.len == 0:
    return err("spec overlay: canonicalSpecIR must be a non-empty array")
  var ir: seq[string] = @[]
  for node in irNode:
    if node.kind != JString or node.getStr("").len == 0:
      return err("spec overlay: canonicalSpecIR entries must be non-empty strings")
    ir.add(node.getStr(""))
  ok(SpecificationArtifact(
    canonicalSpecIR: ir,
    rawPreConditions: @[],
    rawPostConditions: @[],
    origin: soExplicit,
    ruleId: ruleId,
    ruleVersion: ruleVersion))

{.pop.}