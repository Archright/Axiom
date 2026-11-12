import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
import ../../core/trusted/axiom_pragmas
import core/bmc/bmc_race
import core/utils/constants
import core/gateway/gateway
import core/parsers/expression_parser
import core/session/session_parser_gateway
import core/session/session_parser_types
import core/session/session_parser_validators
import core/types/domain_types
import core/types/results
import std/options
export session_parser_validators

## Extract Invariant Rule From Natural Text.
func extractInvariantRuleFromNaturalText*(constraint: string): Result[InvariantRule, AxiomError] {.raises: [], axiom: ["(assert (and (>= (str.len constraint) 0)))", "constraint.length ≥ 0"].} =
  parseNaturalConstraintToInvariant(constraint)
export session_parser_validators

## Extract Invariant Rule From Natural Text.
# @axiom-hint: lean="constraint.length ≥ 0" smt="(assert (and (>= (str.len constraint) 0)))"
type
  RepoInfo* = object
    remote*: Option[RepoRemote]
    branch*: Option[RepoBranch]
    commit*: Option[RepoCommit]

  SourceInfo* = object
    client*: Client
    clientVersion*: Option[ClientVersion]
    model*: Option[ModelName]
    projectPath*: Option[ProjectPath]
    repo*: Option[RepoInfo]

  RedactionInfo* = object
    applied*: bool
    policy*: PolicyName

  MessageMeta* = object
    toolName*: Option[ToolName]
    toolInput*: Option[JsonBlob]
    toolOutput*: Option[JsonBlob]

  ArtifactRefContent* = object
    kind*: ArtifactRefKind
    `ref`*: ArtifactRef

  MessageContent* = object
    case kind*: ContentKind
    of contentText:
      text*: MessageText
    of contentCode:
      lang*: CodeLang
      codeText*: CodeText
    of contentArtifactRef:
      artifactRef*: ArtifactRefContent

  Message* = object
    id*: MessageId
    ts*: Timestamp
    role*: Role
    content*: seq[MessageContent]
    meta*: Option[MessageMeta]

  Artifact* = object
    kind*: ArtifactKind
    name*: ArtifactName
    contentType*: ContentType
    content*: Option[ArtifactContent]
    uri*: Option[ArtifactUri]
    createdAt*: Timestamp

  ProofMetadata* = object
    title*: Title
    date*: IsoDate
    tags*: seq[Tag]
    bridge*: Option[JsonBlob]

  Witness* = object
    traceRef*: TraceRef
    finalState*: JsonBlob

  Evidence* = object
    kind*: EvidenceKind
    `ref`*: EvidenceRef

  Certificate* = object
    id*: CertificateId
    issuedAt*: Timestamp

  SessionProofArtifact* = object
    metadata*: ProofMetadata
    verdict*: Verdict
    claims*: seq[Claim]
    witness*: Witness
    evidence*: seq[Evidence]
    certificate*: Certificate

  Outputs* = object
    proof*: Option[SessionProofArtifact]

  AxiomSession* = object
    schemaVersion*: SchemaVersion
    sessionId*: SessionId
    title*: Title
    createdAt*: Timestamp
    updatedAt*: Timestamp
    source*: SourceInfo
    tags*: seq[Tag]
    audience*: Audience
    redaction*: RedactionInfo
    messages*: seq[Message]
    artifacts*: seq[Artifact]
    outputs*: Outputs
## Make Axiom Session.
func makeAxiomSession*(
  sessionIdRaw: string;
  titleRaw: string;
  createdAtRaw: string;
  updatedAtRaw: string;
  clientRaw: string;
  audienceRaw: string;
  redactionPolicyRaw: string;
  redactionApplied: bool
): Result[AxiomSession, AxiomError] {.
  axiom: ["(assert (and (>= policy 0) (>= client 0) (>= session 0) (>= applied 0) (or (= redactionApplied true) (= redactionApplied false))))", "(policy ≥ 0) ∧ (client ≥ 0) ∧ (session ≥ 0) ∧ (applied ≥ 0) ∧ redactionApplied = true ∨ redactionApplied = false"],
  raises: [],
  requires: updatedAtRaw >= createdAtRaw,
  ensures:
    (not result.isOk()) or (timestampString(result.get().updatedAt) >= timestampString(result.get().createdAt))
.} =
  let schemaVersionRes = ??toSchemaVersion(axiomSessionV1)

  let sessionIdRes = ??toSessionId(sessionIdRaw)

  let titleRes = ??toTitle(titleRaw)

  let createdAtRes = ??toTimestamp(createdAtRaw)

  let updatedAtRes = ??toTimestamp(updatedAtRaw)

  let clientRes = ??toClient(clientRaw)

  let audienceRes = ??toAudience(audienceRaw)

  let policyRes = ??toPolicyName(redactionPolicyRaw)

  var session: AxiomSession
  session.schemaVersion = schemaVersionRes
  session.sessionId = sessionIdRes
  session.title = titleRes
  session.createdAt = createdAtRes
  session.updatedAt = updatedAtRes
  session.source.client = clientRes
  session.tags = @[]
  session.audience = audienceRes
  session.redaction.applied = redactionApplied
  session.redaction.policy = policyRes
  session.messages = @[]
  session.artifacts = @[]
  ok(session)
func hasMessages*(session: AxiomSession): bool {.noSideEffect.} =
  session.messages.len > 0
func hasArtifacts*(session: AxiomSession): bool {.noSideEffect.} =
  session.artifacts.len > 0
## Make Axiom Session.
