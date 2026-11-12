import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import core/gateway/gateway
import core/types/results
import core/types/domain_types
import core/session/session_parser_validators

const epSchemaVersion = GatewayEndpoint(
  typeName: "SchemaVersion",
  predicate: "isValidSchemaVersion",
  errValue: "axiomErrSchemaVersionUnsupported",
  requires: ""
)
generateGateway(epSchemaVersion)

const epSessionId = GatewayEndpoint(
  typeName: "SessionId",
  predicate: "isValidUuidV4",
  errValue: "axiomErrUuidInvalid",
  requires: "raw.len == 36"
)
generateGateway(epSessionId)

const epUserId = GatewayEndpoint(
  typeName: "UserId",
  predicate: "isValidUuid",
  errValue: "axiomErrUuidInvalid",
  requires: ""
)
generateGateway(epUserId)

const epProofId = GatewayEndpoint(
  typeName: "ProofId",
  predicate: "isValidUuid",
  errValue: "axiomErrUuidInvalid",
  requires: ""
)
generateGateway(epProofId)

const epClientId = GatewayEndpoint(
  typeName: "ClientId",
  predicate: "isValidUuid",
  errValue: "axiomErrUuidInvalid",
  requires: ""
)
generateGateway(epClientId)

const epTimestamp = GatewayEndpoint(
  typeName: "Timestamp",
  predicate: "isValidIso8601",
  errValue: "axiomErrTimestampInvalid",
  requires: ""
)
generateGateway(epTimestamp)

const epIsoDate = GatewayEndpoint(
  typeName: "IsoDate",
  predicate: "isValidIsoDate",
  errValue: "axiomErrIsoDateInvalid",
  requires: "raw.len == 10"
)
generateGateway(epIsoDate)

const epTitle = GatewayEndpoint(
  typeName: "Title",
  predicate: "isNonEmpty",
  errValue: "axiomErrEmptyString",
  requires: ""
)
generateGateway(epTitle)

const epTag = GatewayEndpoint(
  typeName: "Tag",
  predicate: "isNonEmpty",
  errValue: "axiomErrEmptyString",
  requires: ""
)
generateGateway(epTag)

const epPolicyName = GatewayEndpoint(
  typeName: "PolicyName",
  predicate: "isNonEmpty",
  errValue: "axiomErrEmptyString",
  requires: ""
)
generateGateway(epPolicyName)

const epClientVersion = GatewayEndpoint(
  typeName: "ClientVersion",
  predicate: "isNonEmpty",
  errValue: "axiomErrEmptyString",
  requires: ""
)
generateGateway(epClientVersion)

const epModelName = GatewayEndpoint(
  typeName: "ModelName",
  predicate: "isNonEmpty",
  errValue: "axiomErrEmptyString",
  requires: ""
)
generateGateway(epModelName)

const epProjectPath = GatewayEndpoint(
  typeName: "ProjectPath",
  predicate: "isNonEmpty",
  errValue: "axiomErrEmptyString",
  requires: ""
)
generateGateway(epProjectPath)

const epRepoRemote = GatewayEndpoint(
  typeName: "RepoRemote",
  predicate: "isNonEmpty",
  errValue: "axiomErrEmptyString",
  requires: ""
)
generateGateway(epRepoRemote)

const epRepoBranch = GatewayEndpoint(
  typeName: "RepoBranch",
  predicate: "isNonEmpty",
  errValue: "axiomErrEmptyString",
  requires: ""
)
generateGateway(epRepoBranch)

const epRepoCommit = GatewayEndpoint(
  typeName: "RepoCommit",
  predicate: "isNonEmpty",
  errValue: "axiomErrEmptyString",
  requires: ""
)
generateGateway(epRepoCommit)

const epMessageId = GatewayEndpoint(
  typeName: "MessageId",
  predicate: "isNonEmpty",
  errValue: "axiomErrEmptyString",
  requires: ""
)
generateGateway(epMessageId)

const epMessageText = GatewayEndpoint(
  typeName: "MessageText",
  predicate: "isAnyString",
  errValue: "axiomErrInvalidValue",
  requires: ""
)
generateGateway(epMessageText)

const epCodeLang = GatewayEndpoint(
  typeName: "CodeLang",
  predicate: "isAnyString",
  errValue: "axiomErrInvalidValue",
  requires: ""
)
generateGateway(epCodeLang)

const epCodeText = GatewayEndpoint(
  typeName: "CodeText",
  predicate: "isAnyString",
  errValue: "axiomErrInvalidValue",
  requires: ""
)
generateGateway(epCodeText)

const epArtifactRef = GatewayEndpoint(
  typeName: "ArtifactRef",
  predicate: "isNonEmpty",
  errValue: "axiomErrEmptyString",
  requires: ""
)
generateGateway(epArtifactRef)

const epArtifactName = GatewayEndpoint(
  typeName: "ArtifactName",
  predicate: "isNonEmpty",
  errValue: "axiomErrEmptyString",
  requires: ""
)
generateGateway(epArtifactName)

const epContentType = GatewayEndpoint(
  typeName: "ContentType",
  predicate: "isValidMimeType",
  errValue: "axiomErrMimeTypeInvalid",
  requires: ""
)
generateGateway(epContentType)

const epArtifactContent = GatewayEndpoint(
  typeName: "ArtifactContent",
  predicate: "isAnyString",
  errValue: "axiomErrInvalidValue",
  requires: ""
)
generateGateway(epArtifactContent)

const epArtifactUri = GatewayEndpoint(
  typeName: "ArtifactUri",
  predicate: "isNonEmpty",
  errValue: "axiomErrEmptyString",
  requires: ""
)
generateGateway(epArtifactUri)

const epMarkdown = GatewayEndpoint(
  typeName: "Markdown",
  predicate: "isAnyString",
  errValue: "axiomErrInvalidValue",
  requires: ""
)
generateGateway(epMarkdown)

const epAssetPath = GatewayEndpoint(
  typeName: "AssetPath",
  predicate: "isNonEmpty",
  errValue: "axiomErrEmptyString",
  requires: ""
)
generateGateway(epAssetPath)

const epBase64Data = GatewayEndpoint(
  typeName: "Base64Data",
  predicate: "isValidBase64",
  errValue: "axiomErrBase64Invalid",
  requires: ""
)
generateGateway(epBase64Data)

const epToolName = GatewayEndpoint(
  typeName: "ToolName",
  predicate: "isNonEmpty",
  errValue: "axiomErrEmptyString",
  requires: ""
)
generateGateway(epToolName)

const epJsonBlob = GatewayEndpoint(
  typeName: "JsonBlob",
  predicate: "isValidJsonBlob",
  errValue: "axiomErrJsonBlobInvalid",
  requires: ""
)
generateGateway(epJsonBlob)

const epClaim = GatewayEndpoint(
  typeName: "Claim",
  predicate: "isNonEmpty",
  errValue: "axiomErrEmptyString",
  requires: ""
)
generateGateway(epClaim)

const epTraceRef = GatewayEndpoint(
  typeName: "TraceRef",
  predicate: "isNonEmpty",
  errValue: "axiomErrEmptyString",
  requires: ""
)
generateGateway(epTraceRef)

const epEvidenceRef = GatewayEndpoint(
  typeName: "EvidenceRef",
  predicate: "isNonEmpty",
  errValue: "axiomErrEmptyString",
  requires: ""
)
generateGateway(epEvidenceRef)

const epCertificateId = GatewayEndpoint(
  typeName: "CertificateId",
  predicate: "isNonEmpty",
  errValue: "axiomErrEmptyString",
  requires: ""
)
generateGateway(epCertificateId)

{.pop.}
