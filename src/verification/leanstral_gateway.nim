import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import ../core/trusted/axiom_pragmas
import ../core/trusted/env_access
import core/utils/constants
import core/crypto/hash_kernel
import core/json/json_utils
import core/json/std_redirect
import core/utils/file_utils
import std/options
import std/os
import std/strutils
import std/times
import verification/llm_backend
type
  LeanstralGatewayResult* = object
    success*: bool
    theoremSource*: string
    tacticTrace*: seq[string]
    premises*: seq[string]
    diagnostics*: string
    rawOutput*: string
    timedOut*: bool
const
  LeanstralModel = "labs-leanstral-2603"
proc leanstralCacheDir(): string {.raises: [], axiom: ["(assert (>= depth 0))", "depth >= 0"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    let cwd = getCurrentDir()
    result = joinPath(cwd, "logs", "leanstral_cache")
  except CatchableError:
    result = "logs/leanstral_cache"
func cacheKey(prompt: string): string {.raises: [], axiom: ["(assert (and (>= (str.len prompt) 0) ast_parse_failed_isolated))", "prompt.length ≥ 0 ∧ ast_parse_failed_isolated"].} =
  sha256Hex(prompt)
proc readLeanstralCache(key: string): LeanstralGatewayResult {.raises: [], axiom: ["(assert (and (>= result 0) external_io_isolated))", "(result ≥ 0) ∧ external_io_isolated"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let path = joinPath(leanstralCacheDir(), key & ".json")
  try:
    if not fileExists(path):
      return LeanstralGatewayResult(success: false)
    let raw = readFileSafe(path)
    let node = parseJsonOpt(raw).get(newJObject())
    result.success = node["success"].getBool()
    result.theoremSource = node["theoremSource"].getStr()
    if node.hasKey("tacticTrace"):
      for item in node["tacticTrace"]:
        result.tacticTrace.add(item.getStr())
    if node.hasKey("premises"):
      for item in node["premises"]:
        result.premises.add(item.getStr())
    result.diagnostics = ""
    result.timedOut = false
  except CatchableError:
    result = LeanstralGatewayResult(success: false)
proc writeLeanstralCache(key: string; res: LeanstralGatewayResult) {.raises: [], axiom: ["(assert (and (or (= res_success true) (= res_success false)) (or (= res_timedOut true) (= res_timedOut false)) external_io_isolated))", "res_success = true ∨ res_success = false ∧ res_timedOut = true ∨ res_timedOut = false ∧ external_io_isolated"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    let dir = leanstralCacheDir()
    discard existsOrCreateDir(dir)
    let path = joinPath(dir, key & ".json")
    let node = %*{
      "success": res.success,
      "theoremSource": res.theoremSource,
      "tacticTrace": res.tacticTrace,
      "premises": res.premises,
      "cachedAt": now().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")
    }
    discard writeFileSafe(path, $node)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

## Strip Ansi Codes.
func stripAnsiCodes*(raw: string): string {.raises: [], axiom: ["(assert (and (< i (str.len raw)) (and (>= i 0) (< i raw))))", "i < raw.length ∧ ((i ≥ 0) ∧ (i < raw))"].} =
  ## Remove ANSI escape sequences (e.g. \x1b[0m, \x1b[91m) from terminal output.
  var i = 0
  while i < raw.len:
    if i + 1 < raw.len and raw[i] == '\x1b' and raw[i+1] == '[':
      i += 2
      while i < raw.len and raw[i] != 'm':
        inc i
      if i < raw.len:
        inc i
      continue
    result.add(raw[i])
    inc i

## I Agent Behavior Detected.
func isAgentBehaviorDetected*(raw: string): bool {.raises: [], axiom: ["(assert (and ast_parse_failed_isolated true (>= (str.len raw) 0)))", "ast_parse_failed_isolated ∧ true ∧ raw.length ≥ 0"].} =
  ## Detect if leanstral responded with agent/tool actions instead of pure code.
  const markers = [
    "$ ", "→ ", "✗ ", "✱ ", "bash", "grep", "webfetch",
    "Skill ", "permission requested", "auto-rejecting", "Error: offset",
    "tool_use", "step_start", "step_finish", "List files", "Find files"
  ]
  for marker in markers:
    if raw.find(marker) >= 0:
      return true
  false

## Extract Lean Block.
func extractLeanBlock*(raw: string): string {.raises: [], axiom: ["(assert (and (= (str.len stripped) 0) (and (>= startIdx 0) (>= endIdx startIdx)) (= startIdx i) (= endIdx i) (>= endIdx 0) (>= startIdx 0)))", "stripped.length = 0 ∧ startIdx ≥ 0 ∧ endIdx ≥ startIdx ∧ startIdx = i ∧ endIdx = i ∧ (endIdx ≥ 0) ∧ (startIdx ≥ 0)"].} =
  ## Extract a contiguous Lean source block from import/namespace/theorem/def/lemma to end.
  let lines = raw.splitLines()
  var startIdx = -1
  var endIdx = -1
  for i, line in lines.pairs():
    let stripped = line.strip()
    if stripped.len == 0:
      continue
    if startIdx < 0 and (
      stripped.startsWith("import ") or
      stripped.startsWith("namespace ") or
      stripped.startsWith("theorem ") or
      stripped.startsWith("def ") or
      stripped.startsWith("lemma ")
    ):
      startIdx = i
    if startIdx >= 0 and stripped.startsWith("end "):
      endIdx = i
  if startIdx >= 0 and endIdx >= startIdx:
    for i in startIdx .. endIdx:
      result.add(lines[i] & "\n")

## Validate Leanstral Source Policy.
func validateLeanstralSourcePolicy*(source: string): string {.raises: [], axiom: ["(assert (and (>= (str.len source) 0)))", "source.length ≥ 0"].} =
  const allowedPrefixes = ["Std", "Mathlib", "Init", "Lean", "Aesop"]
  for line in source.splitLines():
    let stripped = line.strip()
    if not stripped.startsWith("import "):
      continue
    let moduleName = stripped["import ".len .. ^1].strip()
    var isAllowed = false
    for prefix in allowedPrefixes:
      if moduleName.startsWith(prefix):
        isAllowed = true
        break
    if not isAllowed:
      return "forbidden Lean import: " & moduleName & "; only Std/Mathlib/Init/Lean imports are allowed"
  ""

## I Leanstral Source Policy Diagnostic.
func isLeanstralSourcePolicyDiagnostic*(diagnostic: string): bool {.raises: [], axiom: ["(assert (and (>= (str.len diagnostic) 0)))", "diagnostic.length ≥ 0"].} =
  diagnostic.startsWith("forbidden Lean import:")
func sanitizeLeanstralOutput(raw: string): string {.raises: [], axiom: ["(assert (and (and capture (> (str.len stripped) 0)) (> (str.len result) 0) (> (str.len leanBlock) 0) (= capture true) (= capture false) (= result cleaned) result leanBlock (=> (> (str.len result) 0) (= result result)) (=> (> (str.len leanBlock) 0) (= result leanBlock)) (>= result 0) (>= capture 0)))", "capture ∧ stripped.length > 0 ∧ result.length > 0 ∧ leanBlock.length > 0 ∧ capture = true ∧ capture = false ∧ result = cleaned ∧ result ∧ leanBlock ∧ result.length > 0 → result = result ∧ leanBlock.length > 0 → result = leanBlock ∧ (result ≥ 0) ∧ (capture ≥ 0)"].} =
  let cleaned = stripAnsiCodes(raw)

  # Strategy 1: Markdown ```lean block extraction
  var capture = false
  for line in cleaned.splitLines():
    let stripped = line.strip()
    if stripped.startsWith("```lean") or stripped.startsWith("```lean4"):
      capture = true
      continue
    if capture and stripped.startsWith("```"):
      capture = false
      continue
    if capture and stripped.len > 0:
      result.add(stripped & "\n")
  if result.len > 0:
    return result

  # Strategy 2: Structured block extraction (import/theorem/def/lemma ... end)
  let leanBlock = extractLeanBlock(cleaned)
  if leanBlock.len > 0:
    return leanBlock

  # Fallback: return cleaned text
  result = cleaned
# @axiom-hint: lean="(result ≥ 0)" smt="(assert (and (>= result 0)))"
proc parseLeanstralJson(raw: string): LeanstralGatewayResult {.raises: [], axiom: ["(assert (and (>= result 0)))", "(result ≥ 0)"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result.rawOutput = raw
  try:
    let node = parseJsonOpt(raw).get(newJObject())
    if node.hasKey("theoremSource"):
      result.theoremSource = node["theoremSource"].getStr()
    if node.hasKey("tacticTrace"):
      for item in node["tacticTrace"]:
        result.tacticTrace.add(item.getStr())
    if node.hasKey("premises"):
      for item in node["premises"]:
        result.premises.add(item.getStr())
    if node.hasKey("success"):
      result.success = node["success"].getBool()
    result.diagnostics = ""
  except CatchableError:
    result.success = false
    result.diagnostics = "leanstral response parse failed"

## Call Leanstral.
proc callLeanstral*(prompt: string; timeoutMs: int = leanstralTimeoutMs; backend: LLMBackend = nil): LeanstralGatewayResult {.raises: [], axiom: ["(assert (and (= (str.len prompt) 0) (= (str.len policyViolation) 0) (= (str.len opencodePath) 0) (> (str.len policyViolation) 0) (= result cached) (= opencodePath fallback) (>= opencodePath 0) (>= result 0)))", "prompt.length = 0 ∧ policyViolation.length = 0 ∧ opencodePath.length = 0 ∧ policyViolation.length > 0 ∧ result = cached ∧ opencodePath = fallback ∧ (opencodePath ≥ 0) ∧ (result ≥ 0)"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if prompt.len == 0:
    result.success = false
    result.diagnostics = "empty prompt"
    return

  let key = cacheKey(prompt)
  let cached = readLeanstralCache(key)
  if cached.success and cached.theoremSource.len > 0:
    let policyViolation = validateLeanstralSourcePolicy(cached.theoremSource)
    if policyViolation.len == 0:
      result = cached
      result.diagnostics = "cache hit"
      return

  # Resolve backend: use provided or auto-detect
  var activeBackend: LLMBackend
  if backend != nil:
    activeBackend = backend
  else:
    let resolved = resolveDefaultBackend()
    if resolved.isNone:
      return LeanstralGatewayResult(
        success: false,
        diagnostics: "FATAL: No LLM backend available. Set AXIOM_LLM_API_URL + AXIOM_LLM_API_KEY environment variables. Leanstral synthesis cannot proceed without an LLM backend.",
        timedOut: false
      )
    activeBackend = resolved.get()

  let model = getAxiomEnv(evLlmModel, LeanstralModel)
  let req = buildDefaultRequest(prompt, model = model, timeoutMs = timeoutMs)
  let llmRes = activeBackend(req)

  result.timedOut = llmRes.timedOut
  result.rawOutput = llmRes.content

  if llmRes.timedOut:
    result.success = false
    result.diagnostics = "leanstral invocation timed out after " & $timeoutMs & "ms"
    return

  if not llmRes.success:
    result.success = false
    result.diagnostics = llmRes.error
    return

  if isAgentBehaviorDetected(llmRes.content):
    result.success = false
    result.diagnostics = "EnvironmentError: Agent behavior detected in leanstral response."
    return

  let sanitized = sanitizeLeanstralOutput(llmRes.content)
  if sanitized.len > 0 and sanitized.startsWith("{"):
    result = parseLeanstralJson(sanitized)
  else:
    result.success = true
    result.theoremSource = sanitized
    result.diagnostics = ""

  if result.success and result.theoremSource.len > 0:
    let policyViolation = validateLeanstralSourcePolicy(result.theoremSource)
    if policyViolation.len > 0:
      result.success = false
      result.diagnostics = policyViolation
      return
    writeLeanstralCache(key, result)

{.pop.}
