import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
import ../core/trusted/env_access
import core/sync/sync_utils_process
import std/options
import std/os
import std/strutils
import core/trusted/axiom_pragmas

type
  LLMRequest* = object
    prompt*: string
    model*: string
    temperature*: float
    maxTokens*: int
    timeoutMs*: int

  LLMResponse* = object
    success*: bool
    content*: string
    error*: string
    timedOut*: bool

  LLMBackend* = proc(req: LLMRequest): LLMResponse {.gcsafe, raises: [].}
const
  DefaultModel = "labs-leanstral-2603"
  DefaultTemperature = 0.2
  DefaultMaxTokens = 4096
  DefaultTimeoutMs = 30_000

## Build default LLM request from a prompt string.
func buildDefaultRequest*(prompt: string; model: string = DefaultModel;
    timeoutMs: int = DefaultTimeoutMs): LLMRequest {.raises: [].} =
  LLMRequest(
    prompt: prompt,
    model: model,
    temperature: DefaultTemperature,
    maxTokens: DefaultMaxTokens,
    timeoutMs: timeoutMs
  )

## HTTP LLM Backend (legacy compatibility shim).
## Eliminates duplicate HTTP client code — delegates to the same CLI subprocess
## mechanism as legislator.solveGoal() via AXIOM_LLM_CMD / kimi.
## The apiUrl and apiKey parameters are retained for backward compatibility.
func httpLLMBackend*(apiUrl: string; apiKey: string): LLMBackend =
  let _ = apiUrl  # retained for backward compatibility
  let _ = apiKey  # retained for backward compatibility
  let llmCmd = getEnv("AXIOM_LLM_CMD", "kimi")
  result = proc(req: LLMRequest): LLMResponse {.gcsafe, raises: [].} =
    {.cast(raises: []).}:
      try:
        let procRes = runProcessWithTimeout(
          command = llmCmd,
          args = @[],
          timeoutMs = req.timeoutMs,
          input = req.prompt
        )
        if procRes.timedOut:
          return LLMResponse(success: false, error: "LLM request timed out", timedOut: true)
        if procRes.exitCode != 0:
          return LLMResponse(success: false,
            error: "LLM process exited with code " & $procRes.exitCode & ": [REDACTED_LLM_BODY]")
        if procRes.output.len == 0:
          return LLMResponse(success: false, error: "LLM returned empty output")
        result = LLMResponse(success: true, content: procRes.output)
      except CatchableError as e:
        let msg = e.msg
        if "timeout" in msg.toLowerAscii() or "timed out" in msg.toLowerAscii():
          result = LLMResponse(success: false, error: "LLM request timed out", timedOut: true)
        elif "connection" in msg.toLowerAscii() or "refused" in msg.toLowerAscii():
          result = LLMResponse(success: false, error: "LLM connection failed: [REDACTED_LLM_BODY]")
        else:
          result = LLMResponse(success: false, error: "LLM request failed: [REDACTED_LLM_BODY]")

## Process LLM Backend.
## Creates a backend that calls an external CLI process (legacy opencode).
func processLLMBackend*(processPath: string): LLMBackend =
  let capturedPath = processPath
  result = proc(req: LLMRequest): LLMResponse {.gcsafe, raises: [].} =
    let args = @[
      "run",
      "--model", req.model,
      "--pure"
    ]

    let procRes = runProcessWithTimeout(
      command = capturedPath,
      args = args,
      timeoutMs = req.timeoutMs,
      input = req.prompt
    )

    if procRes.timedOut:
      return LLMResponse(success: false, error: "LLM process timed out after " &
          $req.timeoutMs & "ms", timedOut: true)

    if procRes.exitCode != 0:
      return LLMResponse(success: false,
        error: "LLM process exited with code " & $procRes.exitCode & ": [REDACTED_LLM_BODY]")

    if procRes.output.len == 0:
      return LLMResponse(success: false, error: "LLM process returned empty output")

    result = LLMResponse(success: true, content: procRes.output)
## Load leanstral configuration from axiom.toml as fallback when environment
## variables are not set. Keeps environment variables as the primary source
## per AGENTS.md §0.2 (deterministic precedence).
proc loadLeanstralConfigFromToml(): tuple[apiUrl, apiKey, apiModel: string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    let content = readFile("axiom.toml")
    var inLeanstralSection = false
    for line in content.splitLines():
      let stripped = line.strip()
      if stripped == "[leanstral]":
        inLeanstralSection = true
        continue
      if stripped.len > 0 and stripped[0] == '[' and stripped[^1] == ']':
        inLeanstralSection = false
        continue
      if not inLeanstralSection:
        continue
      if stripped.startsWith("api_url"):
        let idx = stripped.find('=')
        if idx >= 0:
          result.apiUrl = stripped[idx + 1 .. ^1].strip().strip(chars = {'"', '\''})
      elif stripped.startsWith("api_key"):
        let idx = stripped.find('=')
        if idx >= 0:
          result.apiKey = stripped[idx + 1 .. ^1].strip().strip(chars = {'"', '\''})
      elif stripped.startsWith("model"):
        let idx = stripped.find('=')
        if idx >= 0:
          result.apiModel = stripped[idx + 1 .. ^1].strip().strip(chars = {'"', '\''})
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

## Resolve Default Backend.
## Auto-detects available LLM backend in priority order:
##   1. HTTP API via AXIOM_LLM_API_URL + AXIOM_LLM_API_KEY
##   2. Fallback to axiom.toml [leanstral] section
##   3. CLI process via `opencode` in PATH
##   4. None (caller must handle with clear error)
proc resolveDefaultBackend*(): Option[LLMBackend] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  # Priority 1: HTTP API environment variables
  var apiUrl = getAxiomEnv(evLlmApiUrl)
  var apiKey = getAxiomEnv(evLlmApiKey)
  var apiModel = getAxiomEnv(evLlmModel)

  # Priority 2: axiom.toml fallback (only for missing env vars)
  if apiUrl.len == 0 or apiKey.len == 0:
    let toml = loadLeanstralConfigFromToml()
    if apiUrl.len == 0:
      apiUrl = toml.apiUrl
    if apiKey.len == 0:
      apiKey = toml.apiKey
    if apiModel.len == 0:
      apiModel = toml.apiModel

  if apiUrl.len > 0 and apiKey.len > 0:
    return some(httpLLMBackend(apiUrl, apiKey))

  # Priority 2: opencode CLI in PATH
  var opencodePath = ""
  try:
    opencodePath = findExe("opencode")
  except CatchableError:
    opencodePath = ""
  if opencodePath.len == 0:
    when defined(windows):
      let appData = getEnv("APPDATA")
      if appData.len > 0:
        let candidate = joinPath(appData, "npm", "opencode.cmd")
        try:
          if fileExists(candidate):
            opencodePath = candidate
        except CatchableError:
          discard  # axiom:best-effort(ioboundary catch)
    else:
      let fallback = getHomeDir() & ".opencode/bin/opencode"
      try:
        if fileExists(fallback):
          opencodePath = fallback
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
  if opencodePath.len > 0:
    return some(processLLMBackend(opencodePath))

  # No backend available
  result = none(LLMBackend)

{.pop.}
