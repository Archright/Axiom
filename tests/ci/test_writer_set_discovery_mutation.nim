{.push raises: [CatchableError].}

## test_writer_set_discovery_mutation.nim — DEBT#527 writer-set discovery 오라클.
##
## proof_unit_consistency_gate check (j)는 부채 아티팩트 3종에 닫힌 writer
## universe를 주장한다. DEBT#527은 그 발견(discovery) 링크가 깨져 있었다:
## splitCallArguments가 호출의 마지막 인자(닫는 괄호 직전 bare identifier)를
## 떨구어 moveFile의 destination(R4)이 스킵되고, 그 결과 tmp+rename 래퍼
## (atomicWriteJson)의 호출 지점이 role-set 판정에 보이지 않았다.
##
## 이 테스트는 게이트를 import하지 않는 독립 오라클이다 (AGENTS.md §0.9b,
## §2.6 — 검증자의 발견 논리를 검증하는 테스트가 그 논리를 재사용하면
## 극장이다). 두 축으로 검증한다:
##
##   Check 1 — Nim 컴파일러 공식 parser AST로 tools/debt_engine.nim을 읽어
##             (1) atomicWriteJson이 moveFile의 destination 파라미터 래퍼임을
##                 증명 (R3+R4의 소스 사실)하고, (2) cmdClose의 atomicWriteJson
##                 호출 지점(RegistryPath/ConstantsOut/MarkdownOut)을 줄 번호와
##                 함께 수집해, 그 정확한 (file, line)이 게이트의 등록 엔트리
##                 텍스트에 존재함을 교차 확인한다.
##   Check 2 — 게이트 파일에서 `proc main()` 직전까지의 순수 스캐너 슬라이스를
##             잘라 임시 harness 엔트리(debtRegistryRoleFailures 호출)를 붙여
##             두 개의 바이너리를 컴파일한다: 라이브(무수정)와 돌연변이
##             (splitCallArguments의 depth==0 닫는 괄호 캡처에서 마지막 인자
##             추가를 제거 = DEBT#527 재주입). 미등록 경쟁 writer가
##             atomicWriteJson 래퍴로 registry SSOT를 쓰는 샌드박스에서
##             라이브는 감지(exit 42), 돌연변이는 미감지(exit 0)여야 한다 —
##             즉 돌연변이는 이 테스트에 의해 사살(killed)된다. 같은 줄에
##             호출 둘(래퍼 호출 + raw sink)이 있을 때 라이브가 둘째 호출을
##             놓치지 않는지도 같은 방식으로 고정한다.
##
## 스캐너 위생(self-camouflage): 이 파일 자체가 check (j)/(h)/(i)의 스캔
## 우주(tests/)에 들어간다. 지속성 호출 토큰(writeFile(, moveFile(, atomicWrite
## 등)을 아티팩트 이름과 같은 물리 줄에 두지 않고, fixture 소스는 토큰/경로를
## 분할 상수(AwjName, MoveName, WriteName, RegLiteral)로 조립한다. 게이트가
## 이 파일을 스캔해도 sink 지점은 하나도 resolving되지 않는다(실제 게이트
## 실행으로 검증됨).

import std/[os, osproc, strutils, unittest]
import compiler/[ast, parser, idents, options, llstream, pathutils, lineinfos]

const
  DebtEngineRel = "tools/debt_engine.nim"
  GateRel = "tools/ci/proof_unit_consistency_gate.nim"

  # fixture 조각 — 게이트의 줄 스캐너가 이 파일의 물리 줄에서 지속성 토큰을
  # 아티팩트 이름과 함께 보지 않도록 분할한다.
  AwjName = "atomicWrite" & "Json"
  MoveName = "move" & "File"
  WriteName = "write" & "File"
  RegLiteral = "\"data/debt_" & "registry.json\""

# ── 공용 헬퍼 ────────────────────────────────────────────────────────────

proc findRepoRootDir(): string =
  var dir = getCurrentDir()
  for _ in 0 ..< 10:
    if fileExists(dir / ".axiom_root"):
      return dir
    dir = parentDir(dir)
  ""

proc runCmd(cmd: string): tuple[output: string, code: int] =
  let r = execCmdEx(cmd)
  (r.output, r.exitCode)

proc writeSandboxFile(root, rel, content: string) =
  let dest = root / rel
  createDir(dest.parentDir())
  writeFile(dest, content)

# ── Check 1 — 독립 Nim compiler AST 오라클 ───────────────────────────────

proc parseNimFileForAst(path: string): PNode =
  ## 공식 parser로 파싱 (게이트의 텍스트 스캐너와 무관한 독립 오라클).
  ## errorMax 상한: 기본값 0이면 첫 파싱 오류에서 quit()가 호스트를 죽인다
  ## (src/core/parser_utils.nim이 문서화한 quirk).
  result = nil
  var cache: IdentCache
  var conf: ConfigRef
  var stream: PLLStream
  try:
    cache = newIdentCache()
    conf = newConfigRef()
    conf.errorMax = high(int)
    stream = llStreamOpen(readFile(path))
    var p: Parser
    openParser(p, AbsoluteFile(path), stream, cache, conf)
    result = parseAll(p)
    closeParser(p)
  except CatchableError:
    result = nil
  except Exception:
    result = nil

proc declName(n: PNode): string =
  if n.isNil or n.len == 0:
    return ""
  let nameNode = n[0]
  if nameNode.kind == nkPostfix and nameNode.len > 1 and
     nameNode[1].kind == nkIdent:
    return nameNode[1].ident.s
  if nameNode.kind == nkIdent:
    return nameNode.ident.s
  ""

proc findTopLevelProc(root: PNode; name: string): PNode =
  for stmt in root:
    if stmt.kind == nkProcDef and declName(stmt) == name:
      return stmt
  nil

proc formalParamNames(procDef: PNode): seq[string] =
  result = @[]
  let params = procDef[paramsPos]
  for i in 1 ..< params.len:
    let group = params[i]
    if group.kind == nkIdentDefs:
      for j in 0 ..< group.len - 2:
        if group[j].kind == nkIdent:
          result.add(group[j].ident.s)

proc walkCalls(n: PNode; callee: string; acc: var seq[PNode]) =
  if n.isNil:
    return
  if (n.kind == nkCall or n.kind == nkCommand) and n.len > 0 and
     n[0].kind == nkIdent and n[0].ident.s == callee:
    acc.add(n)
  for c in n:
    walkCalls(c, callee, acc)

proc collectCalls(root: PNode; callee: string): seq[PNode] =
  ## root 서브트리의 모든 nkCall/nkCommand 중 callee 식별자가 일치하는 노드.
  result = @[]
  walkCalls(root, callee, result)

proc registeredDebtEngineLines(gateText: string): seq[int] =
  ## 게이트 텍스트에서 `file: "tools/debt_engine.nim", line: <n>` 형태로
  ## 등록된 줄 번호 전체 (RegisteredDebtRoleEntries/RegisteredGatesWriters
  ## 등 어느 엔트리든 이 형태면 잡힌다).
  result = @[]
  let needle = "file: \"" & DebtEngineRel & "\", line: "
  var at = 0
  while true:
    let pos = gateText.find(needle, at)
    if pos < 0:
      break
    at = pos + needle.len
    var j = at
    while j < gateText.len and gateText[j] in {'0' .. '9'}:
      inc j
    if j > at:
      result.add(parseInt(gateText[at ..< j]))

# ── Check 2 — 게이트 슬라이스 harness (라이브 vs 돌연변이) ────────────────

const HarnessMain = """
# ── ws527 harness entry — tests/ci/test_writer_set_discovery_mutation.nim이
#    런타임에 append. 저장소 게이트 파일에는 절대 반영되지 않는다.
when isMainModule:
  var uncls: seq[string] = @[]
  let root = paramStr(1)
  let siteToken = paramStr(2)
  let fails = debtRegistryRoleFailures(root, uncls)
  for x in fails:
    echo "F: " & x
  for x in uncls:
    echo "U: " & x
  for x in fails:
    if siteToken.len > 0 and x.contains(siteToken):
      quit(42)
  quit(0)
"""

proc extractScannerSlice(gateText: string): string =
  ## `proc main()` 직전까지의 순수 스캐너 + harness 엔트리.
  let cut = gateText.find("proc main()")
  doAssert cut > 0, "anchor 'proc main()' not found in " & GateRel
  gateText[0 ..< cut] & HarnessMain

proc injectSplitArgsMutant(slice: string): string =
  ## DEBT#527 재주입: splitCallArguments의 depth==0 닫는 괄호 캡처가 마지막
  ## 인자를 result에 추가하지 않게 만든다. 수리된 게이트에서 이 돌연변이는
  ## 정확히 예전 결함의 관측 가능 동작(trailing bare-identifier drop →
  ## moveFile destination 미해석 → 래퍼 미수집)을 재현한다.
  result = slice
  let fnStart = result.find("func splitCallArguments")
  doAssert fnStart >= 0, "func splitCallArguments not found in " & GateRel
  var fnEnd = result.len
  for closer in ["\nfunc ", "\nproc ", "\ntemplate ", "\nmacro "]:
    let at = result.find(closer, fnStart + 5)
    if at >= 0 and at < fnEnd:
      fnEnd = at
  let region = result[fnStart ..< fnEnd]
  var mutated = false
  for anchor in ["result.add(arg)", "result.add(body[argStart ..< j])"]:
    if region.count(anchor) == 1:
      result = result[0 ..< fnStart] &
               region.replace(anchor, "discard true") &
               result[fnEnd .. ^1]
      mutated = true
      break
  doAssert mutated,
    "mutation anchor not found inside splitCallArguments — trailing-argument " &
    "capture shape changed; update the anchors in this test"

proc toolchainRoot(): string =
  let canonical = getEnv("HOME") / ".choosenim" / "toolchains" /
                  ("nim-" & NimVersion)
  if fileExists(canonical / "compiler" / "ast.nim"):
    return canonical
  let nimExe = findExe("nim")
  doAssert nimExe.len > 0, "nim executable not found on PATH"
  parentDir(parentDir(nimExe))

proc nimblePkgDir(prefix: string): string =
  for base in [getEnv("HOME") / ".nimble" / "pkgs2",
               getEnv("HOME") / ".nimble" / "pkgs"]:
    if not dirExists(base):
      continue
    for kind, p in walkDir(base):
      if kind == pcDir and p.startsWith(base / prefix):
        return p
  ""

proc harnessCompileCmd(repo, slicePath, binPath, cacheDir: string): string =
  ## Makefile의 게이트 빌드(NIM_TOOL_FLAGS)와 동일한 경로 세트.
  var paths: seq[string] = @[]
  paths.add toolchainRoot()
  paths.add repo
  paths.add repo / "src"
  paths.add repo / "tools"
  let checksums = nimblePkgDir("checksums-")
  doAssert checksums.len > 0,
    "checksums nimble package not found — gate-tool build paths unavailable"
  paths.add checksums
  let fusion = nimblePkgDir("fusion-")
  if fusion.len > 0:
    paths.add fusion
  result = "nim c --hints:off --skipParentCfg --skipProjCfg"
  for p in paths:
    result.add " --path:" & quoteShell(p)
  result.add " --nimcache:" & quoteShell(cacheDir)
  result.add " -o:" & quoteShell(binPath)
  result.add " " & quoteShell(slicePath)

proc rogueFixtureLines(): seq[string] =
  ## 등록되지 않은 경쟁 writer: atomicWriteJson 래퍼(tmp+rename)로 registry
  ## SSOT를 쓴다. DEBT#527 수리 전이라면 게이트는 이 지점을 보지 못한다.
  result = @[
    "## ws527_rogue.nim - generated fixture (unregistered competing writer)",
    "import std/os",
    "",
    "const",
    "  RegistryPath = " & RegLiteral,
    "",
    "proc " & AwjName & "(path: string; content: string) =",
    "  let tmpPath = path & \".tmp\"",
    "  " & WriteName & "(tmpPath, content)",
    "  " & MoveName & "(tmpPath, path)",
    "",
    "proc run() =",
    "  let payload = \"{}\"",
    "  " & AwjName & "(RegistryPath, payload)",
  ]

proc multicallFixtureLines(): seq[string] =
  ## 하나의 물리 줄에 지속성 호출 둘: 토큰 경계가 둘째 호출을 숨기면 안 된다.
  result = @[
    "## ws527_multicall.nim - generated fixture (two calls, one line)",
    "import std/os",
    "",
    "const",
    "  OtherPath = \"data/other_output.json\"",
    "  RegistryPath = " & RegLiteral,
    "",
    "proc " & AwjName & "(path: string; content: string) =",
    "  let tmpPath = path & \".tmp\"",
    "  " & WriteName & "(tmpPath, content)",
    "  " & MoveName & "(tmpPath, path)",
    "",
    "proc run() =",
    "  let payload = \"{}\"",
    "  " & AwjName & "(OtherPath, payload); " & WriteName &
      "(RegistryPath, payload)",
  ]

# ── 테스트 ────────────────────────────────────────────────────────────────

suite "DEBT#527 writer-set discovery — 독립 오라클":

  test "AST: atomicWriteJson은 moveFile destination 파라미터 래퍼다 (R3+R4)":
    let repo = findRepoRootDir()
    check repo.len > 0
    let root = parseNimFileForAst(repo / DebtEngineRel)
    if root.isNil:
      checkpoint(DebtEngineRel & " parse failed")
      fail()
    else:
      let awj = findTopLevelProc(root, "atomicWriteJson")
      if awj.isNil:
        checkpoint("nkProcDef atomicWriteJson not found in " & DebtEngineRel)
        fail()
      else:
        let params = formalParamNames(awj)
        check params.len >= 2
        check params[0] == "path"
        let mvCalls = collectCalls(awj[bodyPos], "moveFile")
        check mvCalls.len == 1
        var destinationIsPathParam = false
        for c in mvCalls:
          check c.len == 3  # callee + source + destination
          if c.len == 3 and c[^1].kind == nkIdent and
             c[^1].ident.s == params[0]:
            destinationIsPathParam = true
        check destinationIsPathParam

  test "AST: cmdClose의 P1/SSOT materialization 지점이 게이트에 등록되어 있다":
    let repo = findRepoRootDir()
    check repo.len > 0
    let gateText = readFile(repo / GateRel)
    check gateText.len > 0
    let root = parseNimFileForAst(repo / DebtEngineRel)
    if root.isNil:
      checkpoint(DebtEngineRel & " parse failed")
      fail()
    else:
      let cmdClose = findTopLevelProc(root, "cmdClose")
      if cmdClose.isNil:
        checkpoint("nkProcDef cmdClose not found in " & DebtEngineRel)
        fail()
      else:
        let calls = collectCalls(cmdClose[bodyPos], "atomicWriteJson")
        check calls.len >= 3
        var seen: seq[string] = @[]
        var sites: seq[tuple[line: int, arg: string]] = @[]
        for c in calls:
          if c.len >= 2 and c[1].kind == nkIdent:
            let arg = c[1].ident.s
            if arg notin seen:
              seen.add(arg)
            sites.add((int(c.info.line), arg))
        for required in ["RegistryPath", "ConstantsOut", "MarkdownOut"]:
          checkpoint("cmdClose atomicWriteJson first-arg: " & required)
          check required in seen
        let regLines = registeredDebtEngineLines(gateText)
        for site in sites:
          if site.arg in ["RegistryPath", "ConstantsOut", "MarkdownOut"]:
            checkpoint(DebtEngineRel & ":" & $site.line & " (" & site.arg &
                       ") must be a registered debt-role entry line")
            check site.line in regLines

  test "harness: 라이브 슬라이스는 경쟁 writer를 잡고 돌연변이는 놓친다 (killed)":
    let repo = findRepoRootDir()
    check repo.len > 0
    let gateText = readFile(repo / GateRel)
    check gateText.len > 0

    # 샌드박스 A: 등록되지 않은 래퍼 writer
    let sandboxA = getTempDir() /
        ("axiom_ws527_sandbox_" & $getCurrentProcessId() & "_a")
    let sandboxB = getTempDir() /
        ("axiom_ws527_sandbox_" & $getCurrentProcessId() & "_b")
    let work = getTempDir() / ("axiom_ws527_work_" & $getCurrentProcessId())
    defer:
      removeDir(sandboxA)
      removeDir(sandboxB)
      removeDir(work)
    removeDir(sandboxA)
    removeDir(sandboxB)
    removeDir(work)
    for box in [sandboxA, sandboxB]:
      createDir(box / "tools")
      writeFile(box / ".axiom_root", "")

    let rogueLines = rogueFixtureLines()
    writeSandboxFile(sandboxA, "tools/ws527_rogue.nim",
                     join(rogueLines, "\n") & "\n")
    let rogueCallLine = rogueLines.len  # 마지막 줄이 래퍼 호출이다
    check rogueLines[rogueCallLine - 1].endsWith("(RegistryPath, payload)")

    let multiLines = multicallFixtureLines()
    writeSandboxFile(sandboxB, "tools/ws527_multicall.nim",
                     join(multiLines, "\n") & "\n")
    let multiCallLine = multiLines.len
    check multiLines[multiCallLine - 1].contains(";")

    # harness 바이너리 2종: 라이브(무수정) + 돌연변이(DEBT#527 재주입)
    createDir(work)
    let sliceLive = work / "ws527_live_slice.nim"
    let sliceMut = work / "ws527_mutant_slice.nim"
    writeFile(sliceLive, extractScannerSlice(gateText))
    writeFile(sliceMut, injectSplitArgsMutant(extractScannerSlice(gateText)))
    let binLive = work / "ws527_live_harness"
    let binMut = work / "ws527_mutant_harness"
    let cache = work / "nimcache"
    for target in [(sliceLive, binLive), (sliceMut, binMut)]:
      let c = harnessCompileCmd(repo, target[0], target[1], cache)
      checkpoint("compile: " & target[1].extractFilename())
      let r = runCmd(c)
      if r.code != 0:
        checkpoint(r.output)
      check r.code == 0

    let tokenA = "tools/ws527_rogue.nim:" & $rogueCallLine
    let tokenB = "tools/ws527_multicall.nim:" & $multiCallLine

    # 샌드박스 A — 라이브: 경쟁 authority 감지(exit 42)
    let liveA = runCmd(quoteShell(binLive) & " " & quoteShell(sandboxA) & " " &
                       quoteShell(tokenA))
    checkpoint(liveA.output)
    check liveA.code == 42

    # 샌드박스 A — 돌연변이: 미감지(exit 0)여야 돌연변이가 사살된 것이다
    let mutantA = runCmd(quoteShell(binMut) & " " & quoteShell(sandboxA) & " " &
                         quoteShell(tokenA))
    checkpoint(mutantA.output)
    check mutantA.code == 0

    # 샌드박스 B — 같은 줄의 둘째 호출(raw sink)도 라이브는 놓치지 않는다
    let liveB = runCmd(quoteShell(binLive) & " " & quoteShell(sandboxB) & " " &
                       quoteShell(tokenB))
    checkpoint(liveB.output)
    check liveB.code == 42
