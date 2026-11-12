import std/json

## Phase-4b: Legacy Certificate Classifier
## Classifies certificates from the old schema (schemaVersion "1" or absent,
## no claim identity) as legacy (csbNotCurrent). Pure/read-only — never rewrites.
## Reference: src/core/types/certificate_types.nim — csbNotCurrent was added in Phase-4 seed.

const
  LegacyStatuses*: seq[string] = @[
    "certGreen", "certRed", "certPending", "certYellow",
    "certNoObligation", "certStale",
    "certVerifiedAxiom", "certPseudoVerified"
  ]

func classifyLegacyCert*(node: JsonNode): bool {.raises: [].} =
  ## Returns true if the certificate is LEGACY and must be demoted to csbNotCurrent.
  ## A certificate is legacy if any of these hold:
  ##   1. schemaVersion is absent or "1"
  ##   2. OR no claimId/specificationId (no claim identity)
  ##   3. OR status is a legacy-only status (from the old V1 schema)
  ## A V2 cert with schemaVersion "2" and a valid claimId is NOT legacy (false).
  let schemaVersion = node.getOrDefault("schemaVersion")
  if schemaVersion != nil and schemaVersion.kind == JString and schemaVersion.getStr() == "2":
    let claimId = node.getOrDefault("claimId")
    let specificationId = node.getOrDefault("specificationId")
    if claimId != nil and claimId.kind == JString and claimId.getStr().len > 0 and
       specificationId != nil and specificationId.kind == JString and specificationId.getStr().len > 0:
      return false
  if schemaVersion == nil or schemaVersion.kind == JNull or schemaVersion.getStr() == "1":
    return true
  let claimId = node.getOrDefault("claimId")
  let specificationId = node.getOrDefault("specificationId")
  if claimId == nil or claimId.kind == JNull or claimId.getStr().len == 0 or
     specificationId == nil or specificationId.kind == JNull or specificationId.getStr().len == 0:
    return true
  let status = node.getOrDefault("status")
  if status != nil and status.kind == JString and status.getStr("") in LegacyStatuses:
    return true
  false

func demoteStatus*(node: JsonNode): string {.raises: [].} =
  ## For a legacy cert, returns "certNotCurrent" (the status it must be demoted to).
  ## For a non-legacy cert, returns the original status unchanged.
  ## Reference: src/core/types/certificate_types.nim — csbNotCurrent added in Phase-4 seed.
  if classifyLegacyCert(node):
    "certNotCurrent"
  else:
    let status = node.getOrDefault("status")
    if status != nil and status.kind == JString:
      status.getStr("")
    else:
      ""