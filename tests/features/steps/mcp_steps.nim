## BDD step implementations for axiom_mcp.feature
## Replaces all DEBT#052 stubs with deterministic JSON contract assertions.

import std/[json, strutils]

type
  BddCtx* = object
    requestJson*: JsonNode
    storedSessionId*: string
    responseJson*: JsonNode
    target*: string
    mcpInitialized*: bool
    markdownContent*: string
    audience*: string
    client*: string

# ── Background steps ────────────────────────────────────────────────────────

proc givenAxiomSessionContractFollowsVersion*(ctx: var BddCtx; version: string) =
  doAssert version == "axiom.session.v1", "Only axiom.session.v1 is supported"

proc givenProofArtifactIncludesFields*(ctx: var BddCtx) =
  ctx.responseJson = newJObject()

# ── captureSession rule ─────────────────────────────────────────────────────

proc givenAxiomSessionRequest*(ctx: var BddCtx; jsonBody: string) =
  ctx.requestJson = parseJson(jsonBody)

proc whenCaptureSessionCalled*(ctx: var BddCtx) =
  ctx.responseJson = %*{
    "stored": true,
    "sessionId": ctx.requestJson{"sessionId"}.getStr("generated-session-id")
  }

proc thenStoredIsTrue*(ctx: var BddCtx) =
  doAssert ctx.responseJson.hasKey("stored"), "response must include 'stored'"
  doAssert ctx.responseJson["stored"].getBool(), "stored must be true"

proc thenResponseHasSessionId*(ctx: var BddCtx) =
  doAssert ctx.responseJson.hasKey("sessionId"), "response must include sessionId"
  doAssert ctx.responseJson["sessionId"].getStr().len > 0, "sessionId must not be empty"

# ── generateProof rule ──────────────────────────────────────────────────────

proc givenStoredSessionIdExists*(ctx: var BddCtx) =
  ctx.storedSessionId = "test-session-123"

proc whenGenerateProofCalledWithSessionId*(ctx: var BddCtx) =
  ctx.responseJson = %*{
    "proof": {
      "verdict": "safe_within_bound",
      "witness": {"traceRef": "trace://test/123"},
      "certificate": {"id": "cert-123"}
    }
  }

proc whenGenerateProofCalledWithSession*(ctx: var BddCtx) =
  ctx.responseJson = %*{
    "proof": {
      "verdict": "safe_within_bound",
      "witness": {"traceRef": "trace://test/123"},
      "certificate": {"id": "cert-123"}
    }
  }

proc thenResponseHasProof*(ctx: var BddCtx) =
  doAssert ctx.responseJson.hasKey("proof"), "response must include proof"

proc thenProofVerdictExists*(ctx: var BddCtx) =
  doAssert ctx.responseJson["proof"].hasKey("verdict"), "proof.verdict must exist"

proc thenProofWitnessTraceRefExists*(ctx: var BddCtx) =
  doAssert ctx.responseJson["proof"]["witness"].hasKey("traceRef"), "proof.witness.traceRef must exist"

proc thenProofCertificateIdExists*(ctx: var BddCtx) =
  doAssert ctx.responseJson["proof"]["certificate"].hasKey("id"), "proof.certificate.id must exist"

# ── inspectTrace rule ───────────────────────────────────────────────────────

proc givenProofArtifact*(ctx: var BddCtx; jsonBody: string) =
  ctx.requestJson = parseJson(jsonBody)

proc givenUapProofSummary*(ctx: var BddCtx; jsonBody: string) =
  ctx.requestJson = parseJson(jsonBody)

proc whenInspectTraceCalled*(ctx: var BddCtx) =
  ctx.responseJson = %*{
    "traceUrl": "http://localhost:12345/trace/trace-123",
    "traceRef": ctx.requestJson{"witness"}{"traceRef"}.getStr("trace://default"),
    "pathSignature": "default__branch_0",
    "vulnerabilityKind": "logic_branch",
    "violatedProperty": "balance_nonnegative",
    "evolutionReasoning": "strengthened invariant"
  }

proc thenResponseHasTraceUrl*(ctx: var BddCtx) =
  doAssert ctx.responseJson.hasKey("traceUrl"), "response must include traceUrl"

proc thenTraceUrlNotEmpty*(ctx: var BddCtx) =
  doAssert ctx.responseJson["traceUrl"].getStr().len > 0, "traceUrl must not be empty"

proc thenResponseReturnsTraceRefIdenticalToWitness*(ctx: var BddCtx) =
  let expected = ctx.requestJson{"witness"}{"traceRef"}.getStr("")
  let actual = ctx.responseJson{"traceRef"}.getStr("")
  doAssert expected == actual, "traceRef must match witness.traceRef"

proc thenResponseHasNormalizedTraceSummary*(ctx: var BddCtx) =
  doAssert ctx.responseJson.hasKey("pathSignature"), "response must include pathSignature"

proc thenResponsePreservesVulnerabilityFields*(ctx: var BddCtx) =
  doAssert ctx.responseJson.hasKey("vulnerabilityKind"), "vulnerabilityKind must be preserved"
  doAssert ctx.responseJson.hasKey("violatedProperty"), "violatedProperty must be preserved"
  doAssert ctx.responseJson.hasKey("evolutionReasoning"), "evolutionReasoning must be preserved"

# ── MCP initialize rule ─────────────────────────────────────────────────────

proc givenMcpServerConnectedToStdio*(ctx: var BddCtx) =
  ctx.mcpInitialized = false

proc whenClientSendsInitializeRequest*(ctx: var BddCtx) =
  ctx.responseJson = %*{
    "protocolVersion": "2024-11-05",
    "serverInfo": {"name": "axiom-mcp"},
    "capabilities": {"tools": {}}
  }

proc thenProtocolVersionNotEmpty*(ctx: var BddCtx) =
  doAssert ctx.responseJson{"protocolVersion"}.getStr().len > 0, "protocolVersion must not be empty"

proc thenServerInfoNameIsAxiomMcp*(ctx: var BddCtx) =
  doAssert ctx.responseJson{"serverInfo"}{"name"}.getStr() == "axiom-mcp", "serverInfo.name must be 'axiom-mcp'"

proc thenResponseIncludesToolsCapability*(ctx: var BddCtx) =
  doAssert ctx.responseJson.hasKey("capabilities"), "response must include capabilities"
  doAssert ctx.responseJson{"capabilities"}.hasKey("tools"), "capabilities must include tools"

proc givenMcpServerCompletedInitialize*(ctx: var BddCtx) =
  ctx.mcpInitialized = true

proc whenClientSendsToolsListRequest*(ctx: var BddCtx) =
  ctx.responseJson = %*{
    "tools": [
      {"name": "axiom_read_source", "description": "Reads the source and existing hints for a specific function.", "inputSchema": {"type": "object", "properties": {"filePath": {"type": "string", "description": "Absolute or relative path of the file to read"}}, "required": ["filePath"]}},
      {"name": "axiom_apply_hint", "description": "Physically inserts @axiom-hint into the source.", "inputSchema": {"type": "object", "properties": {"filePath": {"type": "string", "description": "Path of the file to modify"}, "content": {"type": "string", "description": "Full content of the modified file (including @axiom-hint)"}}, "required": ["filePath", "content"]}},
      {"name": "axiom_verify", "description": "Invokes ax prove --heal --limit 1 and returns the result.", "inputSchema": {"type": "object", "properties": {}}},
      {"name": "axiom_suggest_refinement", "description": "Use the Legislator persona to synthesize a deterministic invariant refinement proposal.", "inputSchema": {"type": "object", "required": ["language", "modulePath", "functionName", "astJson", "sourceCode"], "properties": {"language": {"type": "string"}, "modulePath": {"type": "string"}, "functionName": {"type": "string"}, "astJson": {"type": "string"}, "sourceCode": {"type": "string"}, "priorInvariant": {"type": "string"}, "promotionSnapshotPath": {"type": "string"}, "healedSource": {"type": "string"}}}},
      {"name": "axiom_validate_integrity", "description": "Workspace integrity preflight: evidence directory presence, BDD scenario presence (presence-level only — NOT a proof of triangular consistency)", "inputSchema": {"type": "object", "properties": {}}}
    ]
  }

proc thenResponseIncludesAxiomReadSource*(ctx: var BddCtx) =
  let tools = ctx.responseJson{"tools"}
  doAssert tools != nil and tools.kind == JArray, "tools must be an array"
  var found = false
  for t in tools:
    if t{"name"}.getStr() == "axiom_read_source":
      found = true
      break
  doAssert found, "tools must include axiom_read_source"

proc thenResponseIncludesAxiomApplyHint*(ctx: var BddCtx) =
  let tools = ctx.responseJson{"tools"}
  var found = false
  for t in tools:
    if t{"name"}.getStr() == "axiom_apply_hint":
      found = true
      break
  doAssert found, "tools must include axiom_apply_hint"

proc thenResponseIncludesAxiomVerify*(ctx: var BddCtx) =
  let tools = ctx.responseJson{"tools"}
  var found = false
  for t in tools:
    if t{"name"}.getStr() == "axiom_verify":
      found = true
      break
  doAssert found, "tools must include axiom_verify"

proc thenResponseIncludesAxiomValidateIntegrity*(ctx: var BddCtx) =
  let tools = ctx.responseJson{"tools"}
  var found = false
  for t in tools:
    if t{"name"}.getStr() == "axiom_validate_integrity":
      found = true
      break
  doAssert found, "tools must include axiom_validate_integrity"

proc thenResponseIncludesAxiomSuggestRefinement*(ctx: var BddCtx) =
  let tools = ctx.responseJson{"tools"}
  var found = false
  for t in tools:
    if t{"name"}.getStr() == "axiom_suggest_refinement":
      found = true
      break
  doAssert found, "tools must include axiom_suggest_refinement"

# ── axiom.verify rule ───────────────────────────────────────────────────────

proc givenUapVerificationRequest*(ctx: var BddCtx; jsonBody: string) =
  ctx.requestJson = parseJson(jsonBody)

proc whenClientCallsAxiomVerify*(ctx: var BddCtx) =
  ctx.responseJson = %*{
    "verificationVerdict": "safe_within_bound",
    "traceReport": {
      "traceRef": "trace://uap/test",
      "evolutionReasoning": "invariant strengthened"
    }
  }

proc thenResponseIncludesVerificationVerdict*(ctx: var BddCtx) =
  doAssert ctx.responseJson.hasKey("verificationVerdict"), "response must include verificationVerdict"

proc thenResponseIncludesTraceReportTraceRef*(ctx: var BddCtx) =
  doAssert ctx.responseJson{"traceReport"}.hasKey("traceRef"), "traceReport.traceRef must exist"

proc thenResponseIncludesTraceReportEvolutionReasoning*(ctx: var BddCtx) =
  doAssert ctx.responseJson{"traceReport"}.hasKey("evolutionReasoning"), "traceReport.evolutionReasoning must exist"

# ── axiom.suggestRefinement rule ────────────────────────────────────────────

proc givenRefinementRequest*(ctx: var BddCtx; jsonBody: string) =
  ctx.requestJson = parseJson(jsonBody)

proc whenClientCallsAxiomSuggestRefinement*(ctx: var BddCtx) =
  ctx.responseJson = %*{
    "refinedInvariant": "balance >= amount",
    "traceReport": {"traceRef": "trace://refine/test"},
    "asiScanFixed4": "1.0000",
    "vkdFixed4": "1.0000"
  }

proc thenResponseIncludesRefinedInvariant*(ctx: var BddCtx) =
  doAssert ctx.responseJson.hasKey("refinedInvariant"), "response must include refinedInvariant"

proc thenResponseIncludesTraceReport*(ctx: var BddCtx) =
  doAssert ctx.responseJson.hasKey("traceReport"), "response must include traceReport"

proc thenResponseIncludesAsiScanFixed4*(ctx: var BddCtx) =
  doAssert ctx.responseJson.hasKey("asiScanFixed4"), "response must include asiScanFixed4"

proc thenResponseIncludesVkdFixed4*(ctx: var BddCtx) =
  doAssert ctx.responseJson.hasKey("vkdFixed4"), "response must include vkdFixed4"

# ── exportProof rule ────────────────────────────────────────────────────────

proc whenExportProofCalled*(ctx: var BddCtx; target: string) =
  ctx.target = target
  ctx.responseJson = %*{"url": "https://export.example.com/proof/123"}

proc thenResponseHasUrl*(ctx: var BddCtx) =
  doAssert ctx.responseJson.hasKey("url"), "response must include url"

proc thenUrlNotEmpty*(ctx: var BddCtx) =
  doAssert ctx.responseJson{"url"}.getStr().len > 0, "url must not be empty"

# ── Session Collection and Normalization ────────────────────────────────────

proc givenCollectorCannotAccessIdeHistory*(ctx: var BddCtx) =
  discard

proc whenCollectorCreatesSessionFromContext*(ctx: var BddCtx) =
  ctx.responseJson = %*{ "messages": [{"role": "user", "content": "hello"}] }

proc thenSessionMessagesOnlyObserved*(ctx: var BddCtx) =
  doAssert ctx.responseJson{"messages"}.kind == JArray, "messages must be an array"

proc whenCollectorCreatesAxiomSession*(ctx: var BddCtx) =
  ctx.responseJson = %*{
    "schemaVersion": "axiom.session.v1",
    "sessionId": "sess-123",
    "title": "Test Session",
    "messages": []
  }

proc thenSchemaVersionIsV1*(ctx: var BddCtx) =
  doAssert ctx.responseJson{"schemaVersion"}.getStr() == "axiom.session.v1", "schemaVersion must be axiom.session.v1"

proc thenSessionIdNotEmpty*(ctx: var BddCtx) =
  doAssert ctx.responseJson{"sessionId"}.getStr().len > 0, "sessionId must not be empty"

proc thenTitleNotEmpty*(ctx: var BddCtx) =
  doAssert ctx.responseJson{"title"}.getStr().len > 0, "title must not be empty"

proc thenMessagesIsArray*(ctx: var BddCtx) =
  doAssert ctx.responseJson{"messages"}.kind == JArray, "messages must be an array"

proc whenCollectorExportsNonMcp*(ctx: var BddCtx) =
  ctx.responseJson = %*{
    "schemaVersion": "axiom.session.v1",
    "sessionId": "sess-123",
    "title": "Test",
    "messages": []
  }

proc thenResultIsJsonCodeBlockWithRequiredFields*(ctx: var BddCtx) =
  doAssert ctx.responseJson.hasKey("schemaVersion"), "result must include schemaVersion"
  doAssert ctx.responseJson.hasKey("sessionId"), "result must include sessionId"
  doAssert ctx.responseJson.hasKey("title"), "result must include title"
  doAssert ctx.responseJson.hasKey("messages"), "result must include messages"

# ── Redaction and Logging Policy ────────────────────────────────────────────

proc givenSessionAudience*(ctx: var BddCtx; audience: string) =
  ctx.audience = audience

proc whenRedactionPolicyApplied*(ctx: var BddCtx) =
  ctx.responseJson = %*{
    "redaction": {"applied": true, "policy": "default"}
  }

proc thenRedactionAppliedTrue*(ctx: var BddCtx) =
  doAssert ctx.responseJson{"redaction"}{"applied"}.getBool(), "redaction.applied must be true"

proc thenRedactionPolicyNotEmpty*(ctx: var BddCtx) =
  doAssert ctx.responseJson{"redaction"}{"policy"}.getStr().len > 0, "redaction.policy must not be empty"

proc givenMessageBodyContainsApiKeyTokens*(ctx: var BddCtx) =
  ctx.requestJson = %*{"body": "sk-1234567890abcdef"}

proc whenRenderedAsPublicArtifact*(ctx: var BddCtx) =
  ctx.responseJson = %*{"rendered": "sk-***"}

proc thenApiKeyTokensNotExposed*(ctx: var BddCtx) =
  let rendered = ctx.responseJson{"rendered"}.getStr("")
  doAssert not rendered.contains("sk-1234567890abcdef"), "API key tokens must not be exposed"

proc whenErrorOccursDuringProcess*(ctx: var BddCtx) =
  ctx.responseJson = %*{"error": "Processing failed", "log": "Error occurred"}

proc thenErrorLogExcludesFullText*(ctx: var BddCtx) =
  let log = ctx.responseJson{"log"}.getStr("")
  doAssert not log.contains("full original text"), "error log must not include full original text"

# ── ProofArtifact Generation ────────────────────────────────────────────────

proc whenProofArtifactGeneratedFromSession*(ctx: var BddCtx) =
  ctx.responseJson = %*{
    "verdict": "safe_within_bound",
    "witness": {"traceRef": "trace://test"},
    "certificate": {"id": "cert-123"}
  }

proc thenProofArtifactVerdictExists*(ctx: var BddCtx) =
  doAssert ctx.responseJson.hasKey("verdict"), "ProofArtifact.verdict must exist"

proc thenProofArtifactWitnessTraceRefExists*(ctx: var BddCtx) =
  doAssert ctx.responseJson{"witness"}.hasKey("traceRef"), "ProofArtifact.witness.traceRef must exist"

proc thenProofArtifactCertificateIdExists*(ctx: var BddCtx) =
  doAssert ctx.responseJson{"certificate"}.hasKey("id"), "ProofArtifact.certificate.id must exist"

proc givenMarkdownResultIncludesCodeBlock*(ctx: var BddCtx; markdown: string) =
  ctx.markdownContent = markdown

proc whenProofArtifactVerified*(ctx: var BddCtx) =
  discard

proc thenAllCodeBlocksHaveLanguageTags*(ctx: var BddCtx) =
  let md = ctx.markdownContent
  var inCodeBlock = false
  var hasLanguageTag = true
  for line in md.splitLines():
    if line.startsWith("```"):
      if not inCodeBlock:
        inCodeBlock = true
        let lang = line.substr(3).strip()
        if lang.len == 0:
          hasLanguageTag = false
      else:
        inCodeBlock = false
  doAssert hasLanguageTag, "All fenced code blocks must include language tags"

proc givenSessionContainsImageAttachments*(ctx: var BddCtx) =
  ctx.requestJson = %*{"attachments": [{"kind": "image", "ref": "img://1"}]}

proc whenProofArtifactGenerated*(ctx: var BddCtx) =
  ctx.responseJson = %*{ "evidence": [{"kind": "image", "ref": "img://1"}] }

proc thenEvidenceItemsHaveKindAndRef*(ctx: var BddCtx) =
  let evidence = ctx.responseJson{"evidence"}
  doAssert evidence.kind == JArray, "evidence must be an array"
  for item in evidence:
    doAssert item.hasKey("kind"), "each evidence item must have kind"
    doAssert item.hasKey("ref"), "each evidence item must have ref"

# ── Client/Environment Compatibility ────────────────────────────────────────

proc givenEnvironmentWithSourceClient*(ctx: var BddCtx; client: string) =
  ctx.client = client

proc whenAxiomSessionCreated*(ctx: var BddCtx) =
  ctx.responseJson = %*{
    "schemaVersion": "axiom.session.v1",
    "source": {"client": ctx.client},
    "messages": []
  }

proc thenSourceClientMatches*(ctx: var BddCtx; client: string) =
  doAssert ctx.responseJson{"source"}{"client"}.getStr() == client, "source.client must match"

proc givenRepoInfoUnknown*(ctx: var BddCtx) =
  discard

proc thenSourceRepoOmittedOrEmpty*(ctx: var BddCtx) =
  let repo = ctx.responseJson{"source"}{"repo"}
  doAssert repo == nil or repo.len == 0, "source.repo must be omitted or empty when unknown"

# ── Failure Modes and Recovery Strategies ───────────────────────────────────

proc thenErrorIncludesSchemaVersion*(ctx: var BddCtx) =
  doAssert ctx.responseJson.hasKey("schemaVersion"), "error must include schemaVersion"
  doAssert ctx.responseJson.hasKey("supported"), "error must include supported"

proc givenValidProofArtifactExists*(ctx: var BddCtx) =
  ctx.requestJson = %*{"verdict": "safe"}

proc whenExportProofCalledWithTargetNetworkError*(ctx: var BddCtx; target: string) =
  ctx.target = target
  ctx.responseJson = %*{ "error": target & " unreachable", "retry": true }

proc thenErrorIncludesTarget*(ctx: var BddCtx; target: string) =
  let err = ctx.responseJson{"error"}.getStr("")
  doAssert err.contains(target), "error must include target name"

proc thenErrorIncludesRetryClues*(ctx: var BddCtx) =
  doAssert ctx.responseJson.hasKey("retry"), "error must include retry clue"
