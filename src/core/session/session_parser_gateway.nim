import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
## Non-deprecated replacement for session_parser_enum_types_{1,2}.nim.
## Consolidates all generateEnumGateway macro calls without {.deprecated.} pragma.
## Import scope matches original stubs to satisfy macro-expanded code symbols.

import core/gateway/gateway
import core/types/results
import core/types/domain_types
import core/session/session_parser_validators

# --- Batch 1: Client, Role, Audience, ArtifactKind ---

const specClient = GatewayEnumSpec(
  typeName: "Client",
  mappings: @[
    EnumMapping(raw: "cursor", enumVal: "clientCursor"),
    EnumMapping(raw: "windsurf", enumVal: "clientWindsurf"),
    EnumMapping(raw: "vscode", enumVal: "clientVscode"),
    EnumMapping(raw: "claude-code", enumVal: "clientClaudeCode"),
    EnumMapping(raw: "claude-desktop", enumVal: "clientClaudeDesktop"),
    EnumMapping(raw: "chatgpt", enumVal: "clientChatgpt"),
    EnumMapping(raw: "unknown", enumVal: "clientUnknown")
  ]
)
generateEnumGateway(specClient)

const specRole = GatewayEnumSpec(
  typeName: "Role",
  mappings: @[
    EnumMapping(raw: "user", enumVal: "roleUser"),
    EnumMapping(raw: "assistant", enumVal: "roleAssistant"),
    EnumMapping(raw: "tool", enumVal: "roleTool"),
    EnumMapping(raw: "system", enumVal: "roleSystem")
  ]
)
generateEnumGateway(specRole)

const specAudience = GatewayEnumSpec(
  typeName: "Audience",
  mappings: @[
    EnumMapping(raw: "public", enumVal: "audiencePublic"),
    EnumMapping(raw: "internal", enumVal: "audienceInternal"),
    EnumMapping(raw: "private", enumVal: "audiencePrivate")
  ]
)
generateEnumGateway(specAudience)

const specArtifactKind = GatewayEnumSpec(
  typeName: "ArtifactKind",
  mappings: @[
    EnumMapping(raw: "diff", enumVal: "artifactDiff"),
    EnumMapping(raw: "file", enumVal: "artifactFile"),
    EnumMapping(raw: "image", enumVal: "artifactImage"),
    EnumMapping(raw: "command", enumVal: "artifactCommand"),
    EnumMapping(raw: "log", enumVal: "artifactLog"),
    EnumMapping(raw: "link", enumVal: "artifactLink")
  ]
)
generateEnumGateway(specArtifactKind)

# --- Batch 2: ContentKind, ArtifactRefKind, Verdict, EvidenceKind ---

const specContentKind = GatewayEnumSpec(
  typeName: "ContentKind",
  mappings: @[
    EnumMapping(raw: "text", enumVal: "contentText"),
    EnumMapping(raw: "code", enumVal: "contentCode"),
    EnumMapping(raw: "artifactRef", enumVal: "contentArtifactRef")
  ]
)
generateEnumGateway(specContentKind)

const specArtifactRefKind = GatewayEnumSpec(
  typeName: "ArtifactRefKind",
  mappings: @[
    EnumMapping(raw: "diff", enumVal: "artifactRefDiff"),
    EnumMapping(raw: "file", enumVal: "artifactRefFile"),
    EnumMapping(raw: "image", enumVal: "artifactRefImage"),
    EnumMapping(raw: "url", enumVal: "artifactRefUrl")
  ]
)
generateEnumGateway(specArtifactRefKind)

const specVerdict = GatewayEnumSpec(
  typeName: "Verdict",
  mappings: @[
    EnumMapping(raw: "race_detected", enumVal: "verdictRaceDetected"),
    EnumMapping(raw: "safe_within_bound", enumVal: "verdictSafeWithinBound"),
    EnumMapping(raw: "inconclusive", enumVal: "verdictInconclusive")
  ]
)
generateEnumGateway(specVerdict)

const specEvidenceKind = GatewayEnumSpec(
  typeName: "EvidenceKind",
  mappings: @[
    EnumMapping(raw: "trace", enumVal: "evidenceTrace"),
    EnumMapping(raw: "solver", enumVal: "evidenceSolver"),
    EnumMapping(raw: "log", enumVal: "evidenceLog"),
    EnumMapping(raw: "snapshot", enumVal: "evidenceSnapshot")
  ]
)
generateEnumGateway(specEvidenceKind)

{.pop.}
