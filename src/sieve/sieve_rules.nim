import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
## Pure rule chain for Pre-Sieve analysis.
## Each rule is a deterministic function: SieveContext → Option[RuleResult].
## AST parsing happens at SieveContext construction time (I/O boundary),
## so rules remain pure functions operating on cached data.

import std/options
import std/strutils
import compiler/ast
import std/json
import std/os
import sieve/sieve_types
import sieve/sieve_bridge
import sieve/subjective_logic
import core/parsers/pnode_nav # findNodesP, findFirstNodeP, pNodeText, declarationTags, ProcDefKinds

const
  maxAstAnalysisMs* = 50
  maxCorrelationVars* = 50

# ── PNode AST helpers (pure, operate on cached PNode) ──

func pnodeHasKind*(node: PNode; kind: TNodeKind): bool =
  if node.isNil: return false
  if node.kind == kind: return true
  for child in node:
    if not child.isNil and pnodeHasKind(child, kind): return true
  false

func pnodeFindFirstKind*(node: PNode; kind: TNodeKind): Option[PNode] =
  if node.isNil: return none(PNode)
  if node.kind == kind: return some(node)
  for child in node:
    if not child.isNil:
      let found = pnodeFindFirstKind(child, kind)
      if found.isSome: return found
  none(PNode)

func pnodeExtractIdent*(node: PNode): string =
  if node.isNil: return ""
  if node.kind == nkIdent: return node.ident.s
  if node.kind == nkSym: return node.sym.name.s
  for child in node:
    if not child.isNil:
      let t = pnodeExtractIdent(child)
      if t.len > 0: return t
  ""

# ── AST analysis (pure, on cached PNode) ──

func hasLoopInAst*(ast: PNode): bool {.raises: [].} =
  if ast.isNil: return false
  for node in findNodesP(ast, {nkForStmt, nkWhileStmt}):
    return true
  false

func hasRecursionInAst*(ast: PNode; funcName: string): bool {.raises: [].} =
  if ast.isNil: return false
  var name = funcName
  if name.len == 0:
    for procDef in findNodesP(ast, ProcDefKinds):
      if procDef.len > 0 and not procDef[0].isNil:
        let idOpt = findFirstNodeP(procDef[0], {nkIdent})
        if idOpt.isSome:
          name = pNodeText(idOpt.get())
          break
  if name.len == 0: return false
  let target = name.toLowerAscii()
  for callNode in findNodesP(ast, {nkCall}):
    if callNode.len > 0 and not callNode[0].isNil:
      let callee = pNodeText(callNode[0]).toLowerAscii()
      if callee == target:
        return true
  false

func hasNonLinearOp*(ast: PNode): bool {.raises: [].} =
  if ast.isNil: return false
  proc checkBinOp(node: PNode; ops: set[char]): bool =
    if node.kind == nkInfix and node.len > 1 and not node[1].isNil:
      let opText = pNodeText(node[1])
      if opText.len == 1 and opText[0] in ops: return true
    for child in node:
      if not child.isNil and checkBinOp(child, ops): return true
    false
  checkBinOp(ast, {'*', '/'})

# ── Rule 0: Axiomatic File Validity (before any gas consumption) ──

func evaluateFileValidity*(ctx: SieveContext): Option[RuleResult] {.raises: [].} =
  ## 공리적 파일 유효성 검증 — Subjective Logic 엔진보다 먼저 실행.
  ## 가스를 소비하기 전, 결정론적으로 불합격 노드를 차단.
  ##
  ## Rule 1: 비-Nim 파일 필터링
  ##   .nim 확장자가 아닌 파일(PDF, TOML, PY 등)은 검증 대상이 아님.
  ## Rule 2: 빈 소스 코드 / 파싱 불능
  ##   소스가 비어있으면 검증 자체가 불가능.
  ##
  ## 이론적 근거: Subjective Logic에서 d=1.0은 완전한 불신(decisional disbelief).
  ## 불확실성 u=0으로 설정하면 Cumulative Fusion 결과도 d=1.0 → BLOCKED 확정.

  # Rule 1: 비-Nim 파일 필터링
  let filePath = ctx.modulePath
  if filePath.len > 0:
    let ext = filePath.splitFile.ext.toLower
    if ext.len > 0 and ext != ".nim":
      return some(RuleResult(
        source: rsTopology,
        opinion: BinomialOpinion(b: 1.0, d: 0.0, u: 0.0, a: 0.5),
        verdict: "blocked_non_nim",
        warning: "Non-Nim file: " & ext
      ))

  # Rule 2: 빈 소스 코드 (Nim 파일이 아닌 경우만)
  # Nim 파일의 소스는 파이프라인 후반에 로드되므로 여기서 차단하지 않음
  if filePath.len > 0:
    let ext = filePath.splitFile.ext.toLower
    if ext != ".nim" and (ctx.sourceCode.len == 0 or ctx.sourceCode.strip().len == 0):
      return some(RuleResult(
        source: rsTopology,
        opinion: BinomialOpinion(b: 1.0, d: 0.0, u: 0.0, a: 0.5),
        verdict: "blocked_empty_source",
        warning: "Empty source code for non-Nim file"
      ))

  # 통과 — 불확실성만 높임 (기존 Subjective Logic 엔진으로 토스)
  none(RuleResult)

# ── Rule 0b: Symbol Validity (AST-based routine whitelist) ──

func findDeclarationByTag*(node: PNode; targetName: string;
    tags: openArray[string]): bool {.raises: [].} =
  ## PNode equivalent — checks if any descendant node with a matching
  ## declaration kind contains an identifier child equal to targetName.
  if node.isNil: return false
  
  # Build set of all matching Kinds from tag strings
  var matchingKinds: set[TNodeKind] = {}
  for t in tags:
    let kinds = tagToKinds(t)
    for k in kinds:
      matchingKinds.incl(k)
  
  # Check this node
  if node.kind in matchingKinds:
    for child in node:
      if not child.isNil and child.kind == nkIdent:
        if child.ident.s == targetName:
          return true
  
  # Recurse into children
  for child in node:
    if not child.isNil:
      if findDeclarationByTag(child, targetName, tags):
        return true
  false

func evaluateSymbolValidity*(ctx: SieveContext): Option[RuleResult] {.raises: [].} =
  ## 심볼 유효성 검증 — 구조체 필드, 타입 정의, 상수를 결정론적으로 필터링.
  ##
  ## 3단계 검증:
  ##   1. 토폴로지 nodeType 필드 (항상 사용 가능, 가장 신뢰도 높음)
  ##   2. 소스 코드에서 루틴 키워드 + 심볼명 패턴 매칭
  ##   3. AST declarationTags (astCache 사용 가능 시)
  ##
  ## 문제: results.nim::err (template) 같은 비실행 심볼이 검증 큐에 진입.
  if ctx.functionName.len == 0:
    return none(RuleResult)

  let symName = ctx.functionName

  # 실행 가능한 루틴 키워드
  const routineKeywords = ["proc", "func", "method", "iterator", "converter"]
  # 비실행 선언 키워드 (template, macro, type, const 등)
  const nonRoutineKeywords = ["template", "macro", "type", "const", "var", "let"]

  # 1단계: 토폴로지 nodeType 확인 (가장 신뢰도 높음)
  if ctx.nodeType.len > 0:
    if ctx.nodeType in routineKeywords:
      return none(RuleResult)  # 루틴이면 통과
    if ctx.nodeType in nonRoutineKeywords:
      # template, macro, type, const 등 → 차단
      return some(RuleResult(
        source: rsTopology,
        opinion: BinomialOpinion(b: 1.0, d: 0.0, u: 0.0, a: 0.5),
        verdict: "blocked_non_routine",
        warning: "Symbol '" & symName & "' is '" & ctx.nodeType & "' (not an executable routine)"
      ))

  # 2단계: 소스 코드에서 루틴 선언 패턴 검색
  if ctx.sourceCode.len > 0:
    let srcLower = ctx.sourceCode.toLower
    let symLower = symName.toLower
    for kw in ["proc ", "func ", "method ", "iterator ", "converter "]:
      if (kw & symLower) in srcLower:
        return none(RuleResult)  # 루틴으로 확인됨 → 통과

  # 3단계: AST 기반 확인 (astCache 사용 가능 시)
  if ctx.astCache.isSome:
    let root = ctx.astCache.get()
    if findDeclarationByTag(root, symName, declarationTags):
      return none(RuleResult)  # AST에서 루틴으로 확인됨 → 통과

  # 루틴이 아닌 심볼 → 차단
  some(RuleResult(
    source: rsTopology,
    opinion: BinomialOpinion(b: 1.0, d: 0.0, u: 0.0, a: 0.5),
    verdict: "blocked_non_routine",
    warning: "Symbol '" & symName & "' is not a routine declaration"
  ))

# ── Rule 1: Topology-based ──

func evaluateTopology*(ctx: SieveContext): Option[RuleResult] {.raises: [].} =
  if ctx.topology.nestingDepth > 4:
    return some(RuleResult(
      source: rsTopology,
      opinion: BinomialOpinion(b: 0.70, d: 0.05, u: 0.25, a: 0.5),  # high danger belief
      verdict: "nonlinear",
      warning: "Nesting depth " & $ctx.topology.nestingDepth,
      metadata: newJNull()
    ))
  if ctx.topology.branchCount > 20:
    return some(RuleResult(
      source: rsTopology,
      opinion: BinomialOpinion(b: 0.60, d: 0.10, u: 0.30, a: 0.5),  # b=belief in danger
      verdict: "nonlinear",
      warning: "Branch count " & $ctx.topology.branchCount,
      metadata: newJNull()
    ))
  some(RuleResult(
    source: rsTopology,
    opinion: BinomialOpinion(b: 0.05, d: 0.70, u: 0.25, a: 0.5),  # low danger belief (safe)
    verdict: "linear",
    metadata: newJNull()
  ))

# ── Rule 2: AST-based ──

func evaluateAst*(ctx: SieveContext): Option[RuleResult] {.raises: [].} =
  if ctx.astCache.isNone:
    return none(RuleResult)
  let ast = ctx.astCache.get()
  if ctx.sourceCode.len > 0 and hasRecursionInAst(ast, ""):
    return some(RuleResult(
      source: rsAstAnalysis,
      opinion: BinomialOpinion(b: 0.70, d: 0.20, u: 0.10, a: 0.3),  # b=belief in danger
      verdict: "recursive",
      warning: "Recursive call detected in AST",
      metadata: newJNull()
    ))
  if hasNonLinearOp(ast):
    return some(RuleResult(
      source: rsAstAnalysis,
      opinion: BinomialOpinion(b: 0.50, d: 0.40, u: 0.10, a: 0.3),  # b=belief in danger
      verdict: "nonlinear",
      warning: "Non-linear arithmetic operator (* /) in AST",
      metadata: newJNull()
    ))
  if hasLoopInAst(ast):
    return some(RuleResult(
      source: rsAstAnalysis,
      opinion: BinomialOpinion(b: 0.30, d: 0.60, u: 0.10, a: 0.3),  # b=belief in danger
      verdict: "nonlinear",
      warning: "Loop structure detected in AST",
      metadata: newJNull()
    ))
  some(RuleResult(
    source: rsAstAnalysis,
    opinion: BinomialOpinion(b: 0.10, d: 0.80, u: 0.10, a: 0.3),  # low danger belief (safe)
    verdict: "linear",
    metadata: newJNull()
  ))

# ── Rule 3: Unsat Core ──

func evaluateUnsatCore*(ctx: SieveContext): Option[RuleResult] {.raises: [].} =
  if ctx.unsatCoreVars.len == 0:
    return none(RuleResult)
  let opinion = mapUnsatCoreToOpinion(ctx.unsatCoreVars, ctx.sourceCode)
  let isDanger = opinion.d > opinion.b
  some(RuleResult(
    source: rsUnsatCore,
    opinion: opinion,
    verdict: if isDanger: "conflicting" else: "linear",
    warning: if isDanger: "Unsat core conflict: " & $ctx.unsatCoreVars.len & " vars"
             else: "",
    metadata: newJNull()
  ))

# ── Rule 4: I/O Boundary Detection ──

const ioPatterns: array[12, string] = [
  "readFile", "writeFile", "readLines", "open", "close",
  "writeLine", "readAll", "writeStream", "readStream",
  "fileExists", "dirExists", "removeFile"
]

func detectIoOperations*(sourceCode: string): seq[string] {.raises: [].} =
  ## Detect I/O operation calls in source code. Pure function.
  result = @[]
  for pattern in ioPatterns:
    if pattern in sourceCode:
      result.add(pattern)

func evaluateIoBoundary*(ctx: SieveContext): Option[RuleResult] {.raises: [].} =
  ## I/O boundary detection — identifies filesystem effect operations.
  ## Functions with I/O effects are harder to verify because:
  ## 1. File system state is not captured in the function signature
  ## 2. Read/write ordering affects correctness
  ## 3. I/O side effects break pure reasoning chains
  ##
  ## When I/O is detected, apply d=0.30 uncertainty reduction,
  ## making it harder to pass the sieve (higher E score).
  if ctx.sourceCode.len == 0:
    return none(RuleResult)
  let ioOps = detectIoOperations(ctx.sourceCode)
  if ioOps.len == 0:
    return none(RuleResult)
  # I/O detected — apply uncertainty reduction
  # d=0.30 means 30% doubt about the function's verifiability
  let doubtLevel = min(0.30, 0.10 * ioOps.len.float)
  some(RuleResult(
    source: rsIOEffect,
    opinion: BinomialOpinion(b: 0.05, d: doubtLevel, u: 0.95 - doubtLevel, a: 0.5),
    verdict: "io_boundary",
    warning: "I/O operations detected: " & ioOps.join(", "),
    metadata: newJNull()
  ))
{.pop.}
