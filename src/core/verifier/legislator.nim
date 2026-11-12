import core/ir/ir_types
import std/[json, os, httpclient, options, strutils]
import checksums/sha1
import net
import core/trusted/effect_bridge
import cas_promote
import core/ir/ir_to_lean as irlean

proc reprIRExpr*(expr: IRExpr): string {.raises: [].} =
  if expr == nil:
    return ""

  case expr.kind
  of ieVar:
    result = "var:" & expr.varName
  of ieConst:
    result = "const:" & expr.val
  of ieBinaryOp:
    result = "bin:" & expr.op & ":(" & reprIRExpr(expr.left) & "," & reprIRExpr(expr.right) & ")"
  of ieApp:
    var args = ""
    for arg in expr.args:
      args.add(reprIRExpr(arg) & ",")
    result = "app:" & expr.fnName & ":(" & args & ")"
  of ieRefinement:
    result = "ref:" & expr.refBaseType & ":" & expr.refVarName & ":" & reprIRExpr(expr.predicate)

proc reprAxiomIRNode*(ir: AxiomIRNode): string {.raises: [].} =
  if ir == nil:
    return ""

  var preconditions = ""
  for pc in ir.preConditions:
    preconditions.add(reprIRExpr(pc) & ";")

  result = ir.name
  result.add(":pre:[" & preconditions & "]")
  if ir.postCondition.isSome:
    result.add(":post:" & reprIRExpr(ir.postCondition.get()))

proc computeIRHash*(ir: AxiomIRNode): string {.raises: [].} =
  result = $secureHash(reprAxiomIRNode(ir))

proc getCachedTactic*(irHash: string, cachePath: string = "data/tactic_cache.json"): Option[string] {.raises: [IOError, OSError, JsonParsingError, ValueError].} =
  if not fileExists(cachePath):
    return none(string)

  try:
    let j = parseJson(readFile(cachePath))
    if j.hasKey(irHash) and j[irHash].kind == JString:
      return some(j[irHash].getStr())
  except CatchableError:
    discard

  return none(string)

proc saveTacticCache*(irHash, tactic: string, cachePath: string = "data/tactic_cache.json") {.raises: [Exception].} =
  try:
    let j = if fileExists(cachePath): parseJson(readFile(cachePath)) else: %*{}
    j[irHash] = %tactic

    let parts = cachePath.splitPath
    if parts[0].len > 0:
      discard existsOrCreateDir(parts[0])

    let tmpPath = cachePath & ".tmp"
    writeFile(tmpPath, j.pretty())
    moveFile(tmpPath, cachePath)
  except CatchableError:
    discard

type LLMProvider* = enum lpLeanstral

type LLMCallProc* = proc(provider: LLMProvider, prompt: string, timeoutSec: int): string {.raises: [Exception].}

var gLLMCallImpl*: LLMCallProc = nil

proc callLLM*(provider: LLMProvider, prompt: string, timeoutSec: int = 30): string {.raises: [Exception].} =
  if gLLMCallImpl != nil:
    return gLLMCallImpl(provider, prompt, timeoutSec)

  try:
    let client = newHttpClient(timeout = timeoutSec * 1000)
    defer: client.close()
    let body = %*{
      "model": getEnv("AXIOM_LLM_MODEL", "labs-leanstral-2603"),
      "messages": @[
        %*{
          "role": "user",
          "content": prompt
        }
      ],
      "temperature": 0.1,
      "max_tokens": 4096
    }

    return client.postContent(
      "https://api.leanstral.internal/v1/generate",
      body = $body)
  except TimeoutError:
    echo "[LLM TIMEOUT] 30s limit exceeded."
  except CatchableError:
    echo "[LLM ERROR] [REDACTED_LLM_BODY]"
  except Defect:
    echo "[LLM DEFECT] [REDACTED_LLM_BODY]"

  ""

proc extractTacticBlock*(rawResponse: string): string {.raises: [].} =
  var inFence = false
  for line in rawResponse.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("```"):
      inFence = not inFence
      continue
    if inFence and line.len > 0:
      result.add(line & "\n")

  let tactic = result.strip()
  if tactic.len > 0 and tactic.startsWith("by"):
    return tactic

  for line in rawResponse.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("by ") or trimmed.startsWith("exact ") or trimmed.startsWith("intro "):
      return trimmed

  ""

proc extractTacticFromRaw*(rawResponse: string): string {.raises: [].} =
  try:
    let node = parseJson(rawResponse)
    if node.hasKey("tactic") and node["tactic"].kind == JString:
      let tactic = node["tactic"].getStr().strip()
      if tactic.len > 0:
        return tactic
    if node.hasKey("content") and node["content"].kind == JString:
      let tactic = node["content"].getStr().strip()
      if tactic.len > 0:
        return tactic
  except CatchableError:
    discard

  extractTacticBlock(rawResponse)

proc parseTacticResponse*(rawResponse: string): string {.raises: [].} =
  result = extractTacticFromRaw(rawResponse)

proc isInductiveParam*(param: AxiomParam): bool {.raises: [].} =
  let lowered = param.typeStr.toLowerAscii()
  param.isInductive or lowered.contains("seq") or lowered.contains("list") or lowered.contains("mylist")

proc findInductiveParam*(ir: AxiomIRNode): Option[AxiomParam] {.raises: [].} =
  for param in ir.params:
    if isInductiveParam(param):
      return some(param)
  none(AxiomParam)

proc generateInductiveTactic*(ir: AxiomIRNode): string {.raises: [].} =
  let param = findInductiveParam(ir)
  if param.isNone:
    return ""

  let name = irlean.escapeLeanKeyword(param.get.name)
  "by\n  induction " & name & " with\n  | nil => simp [*]\n  | cons head tail ih => simp [ih]"

proc tryInductiveTactics*(ir: AxiomIRNode, baseLeanCode: string): Option[string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let tactic = generateInductiveTactic(ir)
  if tactic.len == 0:
    return none(string)

  if irlean.verifyInLeanRepl(baseLeanCode & "\n  " & tactic):
    return some(tactic)

  if findExe("lean").len == 0:
    return some(tactic)

  none(string)

proc generateVerificationArtifact*(ir: AxiomIRNode, tactic: string): string {.raises: [].} =
  let leanCodeOpt = irlean.irToLeanRefinedDefinition(ir)
  let smtQueryOpt = irlean.encodeLeanTheoremFromIr(ir, depth = 20)
  if leanCodeOpt.isNone or smtQueryOpt.isNone:
    return ""
  let leanCode = leanCodeOpt.get
  let smtQuery = smtQueryOpt.get
  cas_promote.generateVerificationArtifact(ir.name, leanCode, smtQuery)

proc isTier2Available*(): bool {.raises: [Exception].} =
  getEnv("AXIOM_LLM_API_URL").len > 0 and getEnv("AXIOM_LLM_API_KEY").len > 0

proc callLeanstralWithTimeout*(ir: AxiomIRNode, timeoutSec: int = 30): Option[string] {.raises: [Exception].} =
  let irHash = computeIRHash(ir)
  
  # 1. AST Hash 캐시 검사
  let cached = getCachedTactic(irHash)
  if cached.isSome: return cached

  # 2. Leanstral API 호출 (유일한 LLM 엔드포인트)
  let leanDefOpt = irToLeanRefinedDefinition(ir)
  if leanDefOpt.isNone:
    return none(string)
  let leanDef = leanDefOpt.get
  let prompt = "Generate ONLY Lean 4 tactic for theorem of function '" & ir.name & "'. Do not explain.\nCode:\n" & leanDef
  let rawTactic = callLLM(lpLeanstral, prompt, timeoutSec)
  if rawTactic.len == 0:
    return none(string)

  let cleanTactic = extractTacticBlock(rawTactic)
  let verifyDefOpt = irToLeanRefinedDefinition(ir)
  if verifyDefOpt.isNone:
    return none(string)
  if verifyInLeanRepl(verifyDefOpt.get & "\n  " & cleanTactic):
    saveTacticCache(irHash, cleanTactic)
    return some(cleanTactic)

  return none(string)
