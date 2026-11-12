import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.pragma: axiomPure.}
import std/strutils
import std/sets
import core/contract/contract_types as ct
import core/contract/contract_param_util as cparam
import core/encoding/smt_atom_generator as satom

## Infer the "container" expression in an indexing pattern like `arr[idx]`.
## Scans backward from `[` to find the identifier or field access.
func extractIndexTarget*(expr: string; bracketIdx: int): string =
  var i = bracketIdx - 1
  while i >= 0 and expr[i] in {' ', '\t'}:
    dec i
  var endIdx = i
  while i >= 0 and (expr[i].isAlphaNumeric or expr[i] in {'_', '.'}):
    dec i
  if i < endIdx:
    result = expr[i + 1 .. endIdx]

## Infer the "index" expression in an indexing pattern like `arr[idx]`.
## Scans forward from `[` to find the expression before `]`.
func extractIndexExpr*(expr: string; bracketIdx: int): string =
  var i = bracketIdx + 1
  while i < expr.len and expr[i] in {' ', '\t'}:
    inc i
  var startIdx = i
  var depth = 0
  while i < expr.len:
    if expr[i] == '[':
      inc depth
    elif expr[i] == ']':
      if depth == 0:
        break
      dec depth
    inc i
  if startIdx < i:
    result = expr[startIdx ..< i].strip()

## Check if a line contains string-related context (str, string, char, etc.)
func isStringContext*(body: string; targetVar: string): bool {.raises: [].} =
  let lowerBody = body.toLowerAscii()
  let lowerVar = targetVar.toLowerAscii()
  if lowerVar in ["raw", "s", "str", "source", "text", "line", "content"]:
    return true
  if lowerBody.contains("string") or lowerBody.contains("strutils"):
    return true
  false

## ---------------------------------------------------------------------------
## Shared precondition helper (DRY: extracted from both extraction paths)
## ---------------------------------------------------------------------------

func addPrecondition*(pres: var seq[string]; cond: string;
    added: var HashSet[string]; paramNames: HashSet[string]) {.raises: [].} =
  ## Add a contract precondition if it's non-trivial, not duplicate,
  ## and references a known parameter. Filters vacuous or orphan conditions.
  if cond.len == 0 or cond in added:
    return
  if cond.contains(".") and not cond.contains(".length") and
     not cond.contains("seq.len") and not cond.contains("str.len"):
    return
  if paramNames.len > 0:
    var refsParam = false
    for p in paramNames:
      if cond.contains(p):
        refsParam = true
        break
    if not refsParam:
      return
  added.incl(cond)
  pres.add(cond)

## ---------------------------------------------------------------------------
## Wave Y: Extracted contract rules (tkStructuralDecomp)
## ---------------------------------------------------------------------------

func extractLenContract*(body: string; pres: var seq[string];
    added: var HashSet[string]; paramNames: HashSet[string];
    params: seq[(string, string)]) {.raises: [].} =
  for line in body.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("#") or trimmed.startsWith("##") or trimmed.startsWith("//"):
      continue
    var idx = 0
    while idx < trimmed.len:
      let dotIdx = trimmed.find(".len", idx)
      if dotIdx < 0: break
      let target = extractIndexTarget(trimmed, dotIdx)
      if target.len > 0 and not target.contains("."):
        var isStr = isStringContext(body, target)
        if not isStr and params.len > 0:
          for p in params:
            if p[0] == target and p[1] == "string":
              isStr = true; break
        if isStr: addPrecondition(pres, satom.smtStrLenPos(target), added, paramNames)
        else: addPrecondition(pres, satom.smtSeqLenPos(target), added, paramNames)
      idx = dotIdx + 4

func extractBracketContract*(body: string; pres: var seq[string];
    added: var HashSet[string]; paramNames: HashSet[string]) {.raises: [].} =
  for line in body.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("func ") or trimmed.startsWith("proc ") or
       trimmed.startsWith("template ") or trimmed.startsWith("macro ") or
       trimmed.startsWith("type "): continue
    if trimmed.find(": seq[") >= 0 or trimmed.find(": array[") >= 0 or
       trimmed.find(": openarray[") >= 0 or trimmed.find(": tuple[") >= 0: continue
    var idx = 0
    while idx < trimmed.len:
      let bracketIdx = trimmed.find('[', idx)
      if bracketIdx < 0: break
      let target = extractIndexTarget(trimmed, bracketIdx)
      let indexExpr = extractIndexExpr(trimmed, bracketIdx)
      if target.len > 0 and indexExpr.len > 0 and
         target.toLowerAscii() notin ct.smtTypeNames and
         indexExpr.toLowerAscii() notin ct.smtTypeNames and
         not target.contains(".") and not indexExpr.contains(".") and
         not indexExpr.contains("..") and not indexExpr.contains("^"):
        addPrecondition(pres, satom.smtGteZero(indexExpr), added, paramNames)
        if isStringContext(body, target):
          addPrecondition(pres, satom.smtStrLtLen(indexExpr, target), added, paramNames)
        else:
          addPrecondition(pres, satom.smtLtLen(indexExpr, target), added, paramNames)
      idx = bracketIdx + 1

func extractDivContract*(body: string; pres: var seq[string];
    added: var HashSet[string]; paramNames: HashSet[string]) {.raises: [].} =
  for line in body.splitLines():
    let trimmed = line.strip()
    var idx = 0
    while idx < trimmed.len:
      let divIdx = trimmed.find(" div ", idx)
      let slashIdx = trimmed.find(" / ", idx)
      let opIdx = if divIdx >= 0 and slashIdx >= 0: min(divIdx, slashIdx)
                  elif divIdx >= 0: divIdx elif slashIdx >= 0: slashIdx else: -1
      if opIdx < 0: break
      var i = opIdx + 5
      while i < trimmed.len and trimmed[i] in {' ', '\t'}: inc i
      var startDiv = i
      while i < trimmed.len and (trimmed[i].isAlphaNumeric or trimmed[i] in {'_', '.'}): inc i
      let divisor = trimmed[startDiv ..< i].strip()
      if divisor.len > 0:
        addPrecondition(pres, satom.smtNonZero(divisor), added, paramNames)
      idx = opIdx + 5

func extractParamTypeContract*(body: string; pres: var seq[string];
    added: var HashSet[string]; paramNames: HashSet[string]) {.raises: [].} =
  for line in body.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("func ") or trimmed.startsWith("proc "):
      let sigParams = cparam.detectParams(trimmed)
      for (name, typ) in sigParams:
        if typ in ["string", "str"]:
          addPrecondition(pres, satom.smtStrLenPos(name), added, paramNames)
        elif typ in ["seq", "array", "openarray", "openarray[", "seq[", "array["]:
          addPrecondition(pres, satom.smtSeqLenPos(name), added, paramNames)

func extractHighLowContract*(body: string; pres: var seq[string];
    added: var HashSet[string]; paramNames: HashSet[string]) {.raises: [].} =
  for line in body.splitLines():
    let trimmed = line.strip()
    var idx = 0
    while idx < trimmed.len:
      let highIdx = trimmed.find(".high", idx)
      let lowIdx = trimmed.find(".low", idx)
      let targetIdx = if highIdx >= 0 and lowIdx >= 0: min(highIdx, lowIdx)
                      elif highIdx >= 0: highIdx elif lowIdx >= 0: lowIdx else: -1
      if targetIdx < 0: break
      let target = extractIndexTarget(trimmed, targetIdx)
      if target.len > 0:
        addPrecondition(pres, satom.smtSeqLenPos(target), added, paramNames)
      idx = targetIdx + 5

func extractGuardContract*(body: string; pres: var seq[string];
    added: var HashSet[string]; paramNames: HashSet[string]) {.raises: [].} =
  for line in body.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("if "):
      let rest = trimmed[3 .. ^1].strip()
      let geIdx = rest.find(" >= 0")
      if geIdx > 0:
        let expr = rest[0 ..< geIdx].strip()
        if expr.len > 0:
          addPrecondition(pres, satom.smtGteZero(expr), added, paramNames)

func extractResultContract*(body: string; pres: var seq[string];
    added: var HashSet[string]; paramNames: HashSet[string]) {.raises: [].} =
  for line in body.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("result = ") or trimmed.startsWith("result= "):
      let expr = trimmed[8 .. ^1].strip().split({' ', '\t'})[0]
      if expr.len > 0 and expr != "result":
        addPrecondition(pres, "(assert (>= (str.len result) 0))", added, paramNames)

## Text-based fallback extraction (preserved for robustness)
func extractContractFromNimBodyText*(functionName, body: string; params: seq[(string, string)] = @[]): ct.ExtractedContract {.raises: [].} =
  if body.len == 0:
    return ct.ExtractedContract()
  var pres: seq[string] = @[]
  var added = initHashSet[string]()
  var paramNames = initHashSet[string]()
  for p in params:
    paramNames.incl(p[0])
  extractLenContract(body, pres, added, paramNames, params)
  extractBracketContract(body, pres, added, paramNames)
  extractDivContract(body, pres, added, paramNames)
  extractParamTypeContract(body, pres, added, paramNames)
  extractHighLowContract(body, pres, added, paramNames)
  extractGuardContract(body, pres, added, paramNames)
  extractResultContract(body, pres, added, paramNames)
  result.preconditions = pres

{.pop.}
