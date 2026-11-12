import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
import core/api/axiom_api
import core/boundary/persona_interface
import core/utils/constants
import core/gateway/gateway
import core/json/std_redirect
import core/logic/pipeline_fingerprint_engine
import core/orchestration/pipeline_dispatch
import core/translator/universal_mapper
import core/types/results
import core/utils/file_utils
import core/utils/io_utils
import mcp/mcp_params
import personas/legislator
import std/os
import std/osproc
import std/re
import std/strformat
import std/strutils
import std/streams
import verification/pipeline_core_types
import verification/pipeline_negative_scan
import verification/pipeline_state_types
import verification/universal_pipeline
type
  ValidationLevel* {.pure.} = enum
    PresenceOnly = "presence_only"
    TriangularConsistency = "triangular_consistency"

  IntegrityResponse* = object
    status*: string
    level*: ValidationLevel
    passed*: bool
    evidenceCheck*: bool
    contextCheck*: bool
    bddCheck*: bool

const
  featuresDir = "tests/features"
  mcpServerLogPath = "logs/mcp_server.log"

  integrityLevelKey* = "level"
  integrityPassedKey* = "passed"
  integrityEvidenceCheckKey* = "evidenceCheck"
  integrityContextCheckKey* = "contextCheck"
  integrityBddCheckKey* = "bddCheck"

func toJson*(r: IntegrityResponse): JsonNode =
  ## Serialize an IntegrityResponse into a JSON object matching the MCP
  ## tool-response schema. Uses named constants to avoid hardcoded string keys.
  %*{
    statusKey: r.status,
    integrityLevelKey: $r.level,
    integrityPassedKey: r.passed,
    integrityEvidenceCheckKey: r.evidenceCheck,
    integrityContextCheckKey: r.contextCheck,
    integrityBddCheckKey: r.bddCheck
  }

## Axiom Read Source.
# @axiom-hint: lean="external_io_isolated" smt="(assert (and external_io_isolated))"
# @axiom-hint: lean="filePath.length = 0 ∧ errorMsg.length > 0 ∧ fileFound = true ∧ (errorMsg ≥ 0) ∧ (fileFound ≥ 0) ∧ (content ≥ 0) ∧ external_io_isolated" smt="(assert (and (= (str.len filePath) 0) (> (str.len errorMsg) 0) (= fileFound true) (>= errorMsg 0) (>= fileFound 0) (>= content 0) external_io_isolated))"
proc axiomReadSource*(params: JsonNode): JsonNode  =
  ## Reads a source file and returns its content.
  let filePath = params{"filePath"}.getStr()
  if filePath.len == 0:
    return %*{"error": "filePath parameter is required"}
  
  var content = ""
  var fileFound = false
  var errorMsg = ""
  
  if fileExists(filePath):
    fileFound = true
    try:
      content = readFileSafe(filePath)
    except CatchableError as e:
      errorMsg = &"Failed to read file: {e.msg}"
  
  if not fileFound:
    return %*{"error": &"File not found: {filePath}"}
  
  if errorMsg.len > 0:
    return %*{"error": errorMsg}
    
  return %*{"content": content, "filePath": filePath}

## Axiom Apply Hint.
# @axiom-hint: lean="external_io_isolated" smt="(assert (and external_io_isolated))"
# @axiom-hint: lean="filePath.length = 0 ∨ content.length = 0 ∧ errorMsg.length > 0 ∧ (errorMsg ≥ 0) ∧ external_io_isolated" smt="(assert (and (or (= (str.len filePath) 0) (= (str.len content) 0)) (> (str.len errorMsg) 0) (>= errorMsg 0) external_io_isolated))"
proc axiomApplyHint*(params: JsonNode): JsonNode =
  ## Writes the given content back to the file, physically inserting the hint.
  let filePath = params{"filePath"}.getStr()
  let content = params{"content"}.getStr()
  
  if filePath.len == 0 or content.len == 0:
    return %*{"error": "filePath and content parameters are required"}
    
  var errorMsg = ""
  try:
    if not writeFileSafe(filePath, content):
      errorMsg = "Failed to write file"
  except CatchableError as e:
    errorMsg = &"Failed to write file: {e.msg}"
    
  if errorMsg.len > 0:
    return %*{"error": errorMsg}
  return %*{statusKey: "success", "message": &"Successfully wrote to {filePath}"}

## Axiom Verify.
# @axiom-hint: lean="errorMsg.length > 0 ∧ (output ≥ 0) ∧ (errorMsg ≥ 0) ∧ (axCmd ≥ 0) ∧ external_io_isolated" smt="(assert (and (> (str.len errorMsg) 0) (>= output 0) (>= errorMsg 0) (>= axCmd 0) external_io_isolated))"
proc axiomVerify*(params: JsonNode): JsonNode =
  ## Self-healing via ax prove --heal.
  let exeDir = getAppDir()
  let axCmd = exeDir / ".." / ".." / "ax.cmd"
  var output = ""
  var exitCode = -1
  var errorMsg = ""
  
  try:
    let p = startProcess(command=axCmd, args = @["heal", "--limit", "1"], options={poUsePath, poStdErrToStdOut})
    output = p.outputStream.readAll()
    exitCode = waitForExit(p)
    close(p)
  except CatchableError as e:
    errorMsg = &"Failed to execute verification: {e.msg}"
    
  if errorMsg.len > 0:
    return %*{"error": errorMsg}

  if exitCode != 0:
    return %*{
      "error": &"Verification failed with exit code {exitCode}",
      "command": axCmd & " heal --limit 1",
      "exitCode": exitCode,
      "output": output
    }

  return %*{
    "command": axCmd & " heal --limit 1",
    "exitCode": exitCode,
    "output": output
  }

## Axiom Verify In Mem.
# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
# @axiom-hint: lean="finalRes ∧ (pipelineRes ≥ 0) ∧ (finalRes ≥ 0)" smt="(assert (and finalRes (>= pipelineRes 0) (>= finalRes 0)))"
proc axiomVerifyInMem*(params: JsonNode): JsonNode =
  ## Runs the Universal Acceptance Pipeline in memory.
  let languageRes = stringField(params, "language")
  if languageRes.isErr(): return %*{"error": describeError(languageRes.error)}
  
  let modulePathRes = stringField(params, modulePathKey)
  if modulePathRes.isErr(): return %*{"error": describeError(modulePathRes.error)}
  
  let functionNameRes = stringField(params, functionNameKey)
  if functionNameRes.isErr(): return %*{"error": describeError(functionNameRes.error)}
  
  let astJsonRes = stringField(params, "astJson")
  if astJsonRes.isErr(): return %*{"error": describeError(astJsonRes.error)}
  
  let sourceCodeRes = stringField(params, "sourceCode")
  if sourceCodeRes.isErr(): return %*{"error": describeError(sourceCodeRes.error)}
  
  let maxRoundsRes = optionalIntField(params, "maxRounds", 6)
  if maxRoundsRes.isErr(): return %*{"error": describeError(maxRoundsRes.error)}
  
  let proofVaultDirRes = optionalStringField(params, "proofVaultDir", defaultProofVaultDir())
  if proofVaultDirRes.isErr(): return %*{"error": describeError(proofVaultDirRes.error)}
  
  let bddDirRes = optionalStringField(params, "bddDir", defaultBddDir())
  if bddDirRes.isErr(): return %*{"error": describeError(bddDirRes.error)}

  var pipelineRes: VerificationOutcome
  
  try:
    let request = UniversalPipelineRequest(
      language: languageRes.get(),
      modulePath: modulePathRes.get(),
      functionName: functionNameRes.get(),
      astJson: astJsonRes.get(),
      sourceCode: sourceCodeRes.get(),
      maxRounds: maxRoundsRes.get(),
      proofVaultDir: proofVaultDirRes.get(),
      bddDir: bddDirRes.get()
    )
    pipelineRes = universal_pipeline.runUniversalAcceptanceWorkflow(request, createDefaultPipelineDispatch())
  except CatchableError as e:
    return %*{"error": &"Failed to run UAP: {e.msg}"}
    
  if pipelineRes.exitKind == pekFailure:
    return %*{"error": describeError(pipelineRes.error)}
    
  var finalRes: JsonNode
  try:
    finalRes = jsonFromUniversalPipelineResult(pipelineRes.result)
  except CatchableError as e:
    return %*{"error": &"Failed to format result: {e.msg}"}
    
  return finalRes

## Axiom Suggest Refinement.
# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
# @axiom-hint: lean="errorMsg.length > 0 ∧ payload ∧ (initialScan ≥ 0) ∧ (errorMsg ≥ 0) ∧ (finalScan ≥ 0) ∧ (payload ≥ 0) ∧ (normalizedTrace ≥ 0) ∧ (mapped ≥ 0) ∧ (legislativeRes ≥ 0)" smt="(assert (and (> (str.len errorMsg) 0) payload (>= initialScan 0) (>= errorMsg 0) (>= finalScan 0) (>= payload 0) (>= normalizedTrace 0) (>= mapped 0) (>= legislativeRes 0)))"
proc axiomSuggestRefinement*(params: JsonNode): JsonNode =
  ## Synthesize a deterministic invariant refinement proposal.
  let languageRes = stringField(params, "language")
  if languageRes.isErr(): return %*{"error": describeError(languageRes.error)}
  let modulePathRes = stringField(params, modulePathKey)
  if modulePathRes.isErr(): return %*{"error": describeError(modulePathRes.error)}
  let functionNameRes = stringField(params, functionNameKey)
  if functionNameRes.isErr(): return %*{"error": describeError(functionNameRes.error)}
  let astJsonRes = stringField(params, "astJson")
  if astJsonRes.isErr(): return %*{"error": describeError(astJsonRes.error)}
  let sourceCodeRes = stringField(params, "sourceCode")
  if sourceCodeRes.isErr(): return %*{"error": describeError(sourceCodeRes.error)}
  let priorInvariantRes = optionalStringField(params, "priorInvariant", "")
  if priorInvariantRes.isErr(): return %*{"error": describeError(priorInvariantRes.error)}
  let promotionSnapshotPathRes = optionalStringField(params, "promotionSnapshotPath", "")
  if promotionSnapshotPathRes.isErr(): return %*{"error": describeError(promotionSnapshotPathRes.error)}
  let healedSourceRes = optionalStringField(params, "healedSource", sourceCodeRes.get())
  if healedSourceRes.isErr(): return %*{"error": describeError(healedSourceRes.error)}
  
  let language = languageRes.get()
  let modulePath = modulePathRes.get()
  let functionName = functionNameRes.get()
  let astJson = astJsonRes.get()
  let sourceCode = sourceCodeRes.get()
  let priorInvariant = priorInvariantRes.get()
  let promotionSnapshotPath = promotionSnapshotPathRes.get()
  let healedSource = healedSourceRes.get()

  var mapped: Result[UniversalTranslation, AxiomError]
  try:
    mapped = mapAstJsonToUniversalTranslation(language, astJson)
  except CatchableError as e:
    return %*{"error": &"Failed to map AST: {e.msg}"}
  if mapped.isErr():
    return %*{"error": describeError(mapped.error)}

  let request = UniversalPipelineRequest(
    language: language,
    modulePath: modulePath,
    functionName: functionName,
    astJson: astJson,
    sourceCode: sourceCode,
    maxRounds: 1,
    proofVaultDir: defaultProofVaultDir(),
    bddDir: defaultBddDir()
  )
  let translation = mapped.get()
  var initialScan: NegativeInvariantScan
  var legislativeRes: Result[LegislatorArtifact, AxiomError]
  var errorMsg = ""
  
  try:
    initialScan = runNegativeInvariantSearch(
      translation,
      sourceCode,
      priorInvariant
    )
    legislativeRes = legislator.legislate(
      request,
      translation,
      initialScan,
      (
        invariant: priorInvariant,
        snapshotPath: promotionSnapshotPath
      ),
      healedSource
    )
  except CatchableError as e:
    errorMsg = &"Failed to legislate: {e.msg}"

  if errorMsg.len > 0:
    return %*{"error": errorMsg}
  if legislativeRes.isErr():
    return %*{"error": describeError(legislativeRes.error)}

  var normalizedTrace: TraceReport
  var finalScan: NegativeInvariantScan
  
  try:
    normalizedTrace = normalizeTraceReport(
      legislativeRes.get().traceReport,
      modulePath,
      functionName,
      legislativeRes.get().evolutionReasoning
    )
    finalScan = runNegativeInvariantSearch(
      translation,
      healedSource,
      legislativeRes.get().activeInvariant
    )
  except CatchableError as e:
    errorMsg = &"Failed during normalization/scan: {e.msg}"
    
  if errorMsg.len > 0:
    return %*{"error": errorMsg}

  let payload = newJObject()
  payload["baselineInvariant"] = newJString(legislativeRes.get().baselineInvariant)
  payload["refinedInvariant"] = newJString(legislativeRes.get().refinedInvariant)
  payload["activeInvariant"] = newJString(legislativeRes.get().activeInvariant)
  payload[evolutionReasoningKey] = newJString(legislativeRes.get().evolutionReasoning)
  payload[traceReportKey] = jsonFromTraceReport(normalizedTrace)
  let scanAsiFixed4 = computeAsiFixed4(finalScan)
  payload[asiScanFixed4Key] = newJString(scanAsiFixed4)
  payload[vkdFixed4Key] = newJString(scanAsiFixed4)
  
  let logLinesNode = newJArray()
  for line in legislativeRes.get().logLines:
    logLinesNode.add(newJString(line))
  payload["logLines"] = logLinesNode
  
  return payload

## Axiom Validate Integrity.
# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
# @axiom-hint: lean="contextRes.isOk = true ∧ isValid ∧ isValid = false ∧ (isValid ≥ 0) ∧ (contextContent ≥ 0) ∧ (hasBddFiles ≥ 0) ∧ (hasEvidenceFiles ≥ 0)" smt="(assert (and (= (option.isSome contextOpt) true) isValid (= isValid false) (>= isValid 0) (>= contextContent 0) (>= hasBddFiles 0) (>= hasEvidenceFiles 0)))"
proc axiomValidateIntegrity*(params: JsonNode): IntegrityResponse =
  ## Workspace integrity preflight: evidence directory presence, BDD scenario
  ## presence (presence-level only — NOT a proof of triangular consistency).
  var outputMsg = ""
  var isValid = true
  var contextContent = ""
  var hasEvidenceFiles = false
  var hasBddFiles = false

  # 1. Evidence Check
  let evDirRes = walkDirOpt("docs/evidence")
  hasEvidenceFiles = evDirRes.isOk and evDirRes.get().len > 0

  let contextRes = readFileOpt("AGENTS.md")
  if contextRes.isOk:
    contextContent = contextRes.get()

  if not hasEvidenceFiles:
    outputMsg &= "Evidence Check Failed: No evidence files found in docs/evidence/.\n"
    isValid = false

  # 2. Context Check — section-structure validation of AGENTS.md
  # (## §N. HEADER format).
  var sectionCount = 0
  let headerPattern = re(r"^## §(\d+)\. (.+)$")
  let lines = contextContent.splitLines()
  for line in lines:
    var matches: array[2, string]
    if line.match(headerPattern, matches):
      inc sectionCount
  let sectionCountOk = sectionCount >= 4
  if not sectionCountOk:
    outputMsg &= "Context Check Failed: AGENTS.md section-structure check failed (preflight level). "
    outputMsg &= &"Found {sectionCount} matching headers.\n"
    outputMsg &= "  - Insufficient section headers (need >= 4 matching `## §N. HEADER`).\n"
    isValid = false

  # 3. BDD Check
  let bddDirRes = walkDirOpt(featuresDir)
  hasBddFiles = bddDirRes.isOk and bddDirRes.get().len > 0

  if not hasBddFiles:
    outputMsg &= "BDD Check Failed: No BDD scenarios (.feature) found in tests/features/.\n"
    isValid = false

  ## intentional-discard: legacy-approved (spec §4.1)
  discard appendFileLineOpt(mcpServerLogPath, @[
    "=== axiom_validate_integrity ===",
    if isValid: "Preflight checks passed (presence-level only — NOT a proof of triangular consistency)." else: "Failed:\n" & outputMsg
  ])

  let evidenceCheck = hasEvidenceFiles
  let contextCheck = sectionCountOk
  let bddCheck = hasBddFiles

  if not isValid:
    result = IntegrityResponse(
      status: "failed_presence",
      level: ValidationLevel.PresenceOnly,
      passed: false,
      evidenceCheck: evidenceCheck,
      contextCheck: contextCheck,
      bddCheck: bddCheck
    )
  else:
    result = IntegrityResponse(
      status: "success_presence_only",
      level: ValidationLevel.PresenceOnly,
      passed: true,
      evidenceCheck: evidenceCheck,
      contextCheck: contextCheck,
      bddCheck: bddCheck
    )

## Get Mcp Tools.
# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"
func getMcpTools*(): JsonNode =
  return %*[
    {
      "name": "axiom_read_source",
      "description": "Reads the source and existing hints for a specific function.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "filePath": {
            "type": "string",
            "description": "Absolute or relative path of the file to read"
          }
        },
        "required": ["filePath"]
      }
    },
    {
      "name": "axiom_apply_hint",
      "description": "Physically inserts @axiom-hint into the source.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "filePath": {
            "type": "string",
            "description": "Path of the file to modify"
          },
          "content": {
            "type": "string",
            "description": "Full content of the modified file (including @axiom-hint)"
          }
        },
        "required": ["filePath", "content"]
      }
    },
    {
      "name": "axiom_verify",
      "description": "Invokes ax prove --heal --limit 1 and returns the result.",
      "inputSchema": {
        "type": "object",
        "properties": {}
      }
    },
    {
      "name": "axiom_verify_in_memory",
      "description": "Run the universal acceptance pipeline and return the normalized verification summary in memory.",
      "inputSchema": {
        "type": "object",
        "required": ["language", modulePathKey, functionNameKey, "astJson", "sourceCode"],
        "properties": {
          "language": {"type": "string"},
          modulePathKey: {"type": "string"},
          functionNameKey: {"type": "string"},
          "astJson": {"type": "string"},
          "sourceCode": {"type": "string"},
          "maxRounds": {"type": "integer"},
          "proofVaultDir": {"type": "string"},
          "bddDir": {"type": "string"}
        }
      }
    },
    {
      "name": "axiom_suggest_refinement",
      "description": "Use the Legislator persona to synthesize a deterministic invariant refinement proposal.",
      "inputSchema": {
        "type": "object",
        "required": ["language", modulePathKey, functionNameKey, "astJson", "sourceCode"],
        "properties": {
          "language": {"type": "string"},
          modulePathKey: {"type": "string"},
          functionNameKey: {"type": "string"},
          "astJson": {"type": "string"},
          "sourceCode": {"type": "string"},
          "priorInvariant": {"type": "string"},
          "promotionSnapshotPath": {"type": "string"},
          "healedSource": {"type": "string"}
        }
      }
    },
    {
      "name": "axiom_validate_integrity",
      "description": "Workspace integrity preflight: evidence directory presence, BDD scenario presence (presence-level only — NOT a proof of triangular consistency)",
      "inputSchema": {
        "type": "object",
        "properties": {}
      }
    }
  ]
{.pop.}

