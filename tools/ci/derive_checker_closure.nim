## derive_checker_closure.nim — H 실행 코드 closure 유도자 (ADR C2 derivation authority)
##
## 브랜치의 H 트리에서 gateway 실행 코드 closure(= Tier C)를 정적으로 유도한다.
## Trusted(성분 B)에서 실행되며, 워킹 트리를 읽지 않고 오직
## `git ls-tree <ref>` / 장수 `git cat-file --batch`(blob OID 직독, spawn 1회)
## 로만 H를 분석한다:
##
##   derive_checker_closure --ref <git-ref> [--repo <dir>]
##   derive_checker_closure --tree <git-tree-oid> [--repo <dir>]
##
## stdout = closure 멤버십 전체(LC_ALL=C 정렬된 `<mode> <type> <sha>\t<path>` —
## git ls-tree 포맷 그대로, Evidence[0]가 `sort | sha256sum`으로 소비하는 형태).
## stderr = UNRESOLVED 진단. exit: 0 = 성공, 1 = 미해소 존재(fail-closed red),
## 2 = 사용법/ref 오류.
##
## Walk 진입점:
##   (a) `.github/workflows/runner-pool-acceptance.yml` @ref — `run:` 블록의
##       make 타깃 / `nim c` 소스 / 스크립트 경로 (워크플로 YAML 자체는 멤버가
##       아니다 — 플랫폼 SHA 소관, closure 팽창 금지).
##   (b) `ci/checker.mk` @ref — make 타깃 레시피 + `$(shell ...)`/`$$(...)` 실행.
##   (c) 정적 시드(항상 포함): ci/checker.mk, 본 도구, impact_closure_selector,
##       proof_reconcile_gate, all_gateway_runner, nimble.lock,
##       config.nims, config/effects.nims, src/gate/config.nims.
##
## 제3 도출 각 (ADR-0025 Amendment F, 2026-10-12): `--tree`는 merge-tree
## (`git merge-tree --write-tree B H`)가 내놓는 **후보 트리 OID**를 직접
## 대상으로 삼는다 — M은 트리일 뿐 커밋이 아니므로 `--ref`의 `^{commit}` 펠은
## 불가능하고, 워크플로가 commit-tree 래퍼 커밋을 만드는 대신(객체 저장소
## 변조·비결정 중간 OID) 트리 객체를 직접 읽는다. `git ls-tree -r
## --full-tree <tree-oid>`가 트리 OID를 받아 경로→blob OID를 해석하고,
## 그 OID들은 장수 `git cat-file --batch`가 객체 저장소에서 직독한다 —
## 산출은 트리의 순수 함수(결정론)이며 H·B 각과 바이트 동일 포맷이다.
##
## 도출 규칙 (결정론적):
##   - 리터럴 repo 경로 → 트리 존재 → 멤버. `nim c ... -o:<out> <src>.nim`의
##     out→src 매핑(product)으로 생성 바이너리(bin/*, build/* — gitignore 대상)와
##     artifact 다운로드 경로(verifier/…)를 정적으로 소거한다.
##   - `.nim` 소스 → 로컬 import/from/include 그래프 재귀(visited). `std/*`와
##     nimble 패키지(트리 미존재 모듈)는 nimble.lock 시드가 커버하므로 skip.
##   - make 타깃 → ci/checker.mk 레시피(연속행 결합, $@/$< 치환) + 변수 정의.
##
## fail-closed (구멍 12 — 코어): 정적으로 구체 repo 경로로 소거할 수 없는
## 모든 호출 형태(변수 경로, eval, 명령 치환 명령 위치, 생성 바이너리, PATH 미지
## 이름, 미해소 make 타깃/시드) → UNRESOLVED 수집 + stderr 출력 + exit≠0.
## "놓치면 거부" — 조용한 skip은 존재하지 않는다.

import core/trusted/layer_declaration
import core/trusted/axiom_pragmas_lite
axiomLayer "tools"

import std/[os, osproc, streams, strutils, sequtils, sets, tables, algorithm, parseopt, sugar]

{.push raises: [].}

const
  WorkflowPath = ".github/workflows/runner-pool-acceptance.yml"
  CheckerMkPath = "ci/checker.mk"
  SeedMembers = [
    CheckerMkPath,
    "tools/ci/derive_checker_closure.nim",
    "tools/ci/impact_closure_selector.nim",
    "tools/ci/proof_reconcile_gate.nim",
    "tests/gateway/all_gateway_runner.nim",
    "nimble.lock",
    "config.nims",
    "config/effects.nims",
    "src/gate/config.nims",
  ]
  ## PATH에 있다고 보장되는 외부 도구/셸 내장 (레포 코드가 아님 → args 미분석).
  ## 추가는 심사 대상 — 미지의 실행 이름은 UNRESOLVED로 거부된다.
  KnownTools = [
    # 외부 CLI (작업 명세: git/make/nim/jq/curl/gh/python3 …)
    "git", "gh", "make", "nim", "nimble", "choosenim", "jq", "curl", "wget",
    "python3", "lean", "lake", "elan",
    # POSIX 셸 내장/유틸
    "sh", "bash", "dash", "echo", "printf", "cat", "grep", "sed", "awk",
    "sort", "uniq", "wc", "cut", "tr", "seq", "head", "tail", "ls", "mkdir",
    "cp", "mv", "rm", "chmod", "chown", "ln", "find", "xargs", "comm", "diff",
    "cmp", "test", "[", "[[", "set", "export", "cd", "pwd", "trap", "exit",
    "return", "shift", "read", "true", "false", ":", "sleep", "touch", "date",
    "tee", "basename", "dirname", "realpath", "readlink", "which", "env",
    "timeout", "yes", "tar", "unzip", "zip", "gzip", "gunzip", "sha256sum",
    "sha1sum", "md5sum", "openssl", "stat", "du", "df", "file", "strings",
    "paste", "join", "nl", "pr", "split", "nproc", "mktemp", "install", "patch",
    "time", "getconf", "dd", "sync",
  ]
  ## 명령 위치에서 무시 후 나머지를 재분석하는 셸 키워드/구조어.
  ## (case/for는 구조 분석이 필요해 별도 처리 — 목록에서 제외)
  ShellKeywords = ["if", "then", "elif", "else", "fi", "do", "done", "esac",
                   "in", "{", "}", "!", "time", "function"]

type
  TreeEntry = object
    mode: string
    typ: string
    sha: string

  Unresolved = object
    origin: string     # file:line 또는 "seed"
    line: string       # 원문
    reason: string

  MakeTarget = object
    recipe: seq[string]      # 원본 레시피 라인(탭 제거, 연속행 결합 후)
    prereqs: seq[string]
    isFileTarget: bool

  Walker = object
    repoRoot: string
    repoRef: string
    tree: Table[string, TreeEntry]
    products: Table[string, string]            # 생성 바이너리/산출물 경로 → 소스
    artifactFiles: Table[string, seq[string]]  # upload name → 파일 경로
    makeVars: Table[string, string]            # checker.mk 변수 정의
    members: HashSet[string]
    unresolved: seq[Unresolved]
    targets: Table[string, MakeTarget]
    visitedTargets: HashSet[string]
    visitedNim: HashSet[string]
    expandDepth: int                    # make 변수 값 재토큰화 재귀 깊이 (상한 5)
    catProc: Process                    # 장수 `git cat-file --batch` (lazy 기동)

# 명령 분석 코어 포워드 선언 (make/셸 walk에서 서로 참조). 본 도구체인 퀴크:
# `{.forward.}` 프라그마 거부 + 파라미터명 불일치 시 중복 오버로드 생성 —
# 정의부와 동일한 파라미터명으로 무본문 선언해야 한다.
proc analyzeCommandTokens(w: var Walker, toksIn: seq[string], origin: string,
                          makeCtx, makeFirstPrereq: string)
proc analyzeSegment(w: var Walker, segIn: seq[string], origin: string,
                    makeCtx, makeFirstPrereq: string)
proc analyzeLine(w: var Walker, line: string, origin: string,
                 makeMode = false)

# ═══════════════════════════════════════════════════════════════════════════
# 텍스트/토큰 기본기 (순수)
# ═══════════════════════════════════════════════════════════════════════════

func findMatchingParen(line: string, openIdx: int): int =
  ## openIdx(문자열 내 '(' 위치)에 대응하는 닫는 ')' 인덱스.
  ## 인용부("') 내부의 괄호는 셸 파싱에서 괄호가 아니므로 무시한다 (결정론).
  ## 실패(미닫힘) 시 -1.
  var depth = 1
  var i = openIdx + 1
  var inS = false
  var inD = false
  while i < line.len and depth > 0:
    let c = line[i]
    if c == '\'' and not inD:
      inS = not inS
    elif c == '"' and not inS:
      inD = not inD
    elif not inS and not inD:
      if c == '(':
        depth.inc
      elif c == ')':
        depth.dec
    inc i
  if depth == 0:
    result = i - 1
  else:
    result = -1

func substMakeCtx(tok, makeCtx, makeFirstPrereq: string): string =
  ## 토큰 내부의 `$@`/`$<` 치환 (`-o:$@` 형태 포함).
  result = tok
  if makeCtx.len > 0:
    result = result.replace("$@", makeCtx)
    result = result.replace("$<", makeFirstPrereq)


func stripComment(line: string): string =
  ## 인용부 밖의 `#` 주석 제거 (`#`는 공백/행 시작 뒤에만 주석).
  var inS = false
  var inD = false
  for i, c in line:
    if c == '\'' and not inD:
      inS = not inS
    elif c == '"' and not inS:
      inD = not inD
    elif c == '#' and not inS and not inD:
      if i == 0 or line[i-1] in {' ', '\t'}:
        return line[0 ..< i]
  result = line

func tokenizeCommand(line: string): seq[string] =
  ## 셸/make 명령행을 토큰으로 분해. 인용부('")와 균형 잡힌 `$(...)`/`$$(...)`/
  ## `${{...}}`/백틱을 한 토큰으로 유지한다.
  result = @[]
  var cur = ""
  var i = 0
  while i < line.len:
    let c = line[i]
    if c == '\'' or c == '"':
      let q = c
      cur.add(q)
      inc i
      while i < line.len and line[i] != q:
        cur.add(line[i])
        inc i
      if i < line.len:
        cur.add(q)
        inc i
    elif c == '$' and i + 1 < line.len and line[i+1] == '(':
      let close = findMatchingParen(line, i + 1)
      if close >= 0:
        cur.add(line[i .. close])
        i = close + 1
      else:
        cur.add(c)
        inc i
    elif c == '$' and i + 2 < line.len and line[i+1] == '{' and line[i+2] == '{':
      cur.add("${{")
      i += 3
      var depth = 1
      while i < line.len and depth > 0:
        if line[i] == '{':
          depth.inc
        elif line[i] == '}':
          depth.dec
        if depth > 0:
          cur.add(line[i])
        inc i
      cur.add("}}")
    elif c == '<' and i + 1 < line.len and line[i+1] == '(':
      # 프로세스 치환 <( ... ) — 내부 | 가 세그먼트 분리자가 되지 않도록
      # 균형 잡힌 한 토큰으로 유지한다.
      cur.add("<(")
      i += 2
      var depth = 1
      while i < line.len and depth > 0:
        if line[i] == '(':
          depth.inc
        elif line[i] == ')':
          depth.dec
        if depth > 0:
          cur.add(line[i])
        inc i
      cur.add(')')
    elif c == '`':
      cur.add('`')
      inc i
      while i < line.len and line[i] != '`':
        cur.add(line[i])
        inc i
      if i < line.len:
        cur.add('`')
        inc i
    elif c in {' ', '\t'}:
      if cur.len > 0:
        result.add(cur)
        cur = ""
      inc i
    else:
      cur.add(c)
      inc i
  if cur.len > 0:
    result.add(cur)


func isEnvAssign(tok: string): bool =
  ## `NAME=value` (셸/make 변수 할당 토큰).
  if tok.len == 0 or not (tok[0] in {'A'..'Z', 'a'..'z', '_'}):
    return false
  var i = 1
  while i < tok.len and (tok[i] in {'A'..'Z', 'a'..'z', '_', '0'..'9'}):
    inc i
  result = i < tok.len and tok[i] == '='

func isCaseLabel(tok: string): bool =
  ## `0)`, `*)`, `name)` — case 분기 라벨.
  if tok.endsWith(")"):
    let body = tok[0 ..< tok.len - 1]
    if body == "*":
      return true
    if body.len > 0 and body.allIt(it in {'0'..'9'}):
      return true
    if body.len > 0 and body.allIt(it in {'A'..'Z', 'a'..'z', '_', '0'..'9', '-', '?'}):
      return true
  result = false

func isKnownTool(name: string): bool =
  name in KnownTools

func leadingIndent(s: string): int =
  ## 선행 공백 수 (YAML 들여쓰기 판정용).
  for c in s:
    if c == ' ':
      result.inc
    else:
      return

func quoteBalance(line: string): int =
  ## 인용 균형: 0=균형, 1=홑따옴표 열림, 2=겹따옴표 열림 (현재 상태 무시 규칙).
  var inS = false
  var inD = false
  for c in line:
    if c == '\'' and not inD:
      inS = not inS
    elif c == '"' and not inS:
      inD = not inD
  if inS:
    result = 1
  elif inD:
    result = 2

func endsWithContinuation(line: string): bool =
  ## 인용부 밖 백슬래시 종료(셸/make 연속행).
  for i in countdown(line.len - 1, 0):
    let c = line[i]
    if c == '\\':
      return true
    elif c != ' ' and c != '\t':
      return false
  result = false

const MakeExpandDepthCap = 5

func findTopLevelComma(s: string): int =
  ## 인용부/중첩 `(...)` 밖 첫 최상위 컴마 인덱스 (`$(call F,a,b)` 인자 분리용).
  ## 실패(없음) 시 -1.
  var depth = 0
  var inS = false
  var inD = false
  for i, c in s:
    if c == '\'' and not inD:
      inS = not inS
    elif c == '"' and not inS:
      inD = not inD
    elif not inS and not inD:
      if c == '(':
        depth.inc
      elif c == ')':
        if depth > 0:
          depth.dec
      elif c == ',' and depth == 0:
        return i
  result = -1

func splitCallArgs(s: string): seq[string] =
  ## `$(call F,a,b)` 인자 목록 — 최상위 컴마 분리 (인용/중첩 존중).
  ## 내부 빈 인자는 자리 보존, 끝 빈 인자는 생략.
  result = @[]
  var depth = 0
  var inS = false
  var inD = false
  var start = 0
  var i = 0
  while i < s.len:
    let c = s[i]
    if c == '\'' and not inD:
      inS = not inS
    elif c == '"' and not inS:
      inD = not inD
    elif not inS and not inD:
      if c == '(':
        depth.inc
      elif c == ')':
        if depth > 0:
          depth.dec
      elif c == ',' and depth == 0:
        result.add(s[start ..< i].strip())
        start = i + 1
    inc i
  if start < s.len:
    result.add(s[start .. ^1].strip())

# ═══════════════════════════════════════════════════════════════════════════
# 셸 치환 수집 (결정론적 — 실행되는 모든 치환을 전수 분석)
# ═══════════════════════════════════════════════════════════════════════════

func collectShellSubstitutions(line: string, isMakefile: bool): seq[string] =
  ##   - workflow 라인: `$(...)`/백틱 = 셸 치환 → 분석.
  ##   - makefile 라인: `$(shell ...)` = make 파싱 시 실행 → 분석 (중첩 포함:
  ##     make 함수 본문($(foreach …)/$(if …)) 속 `$(shell …)`도 파싱 시 실행).
  ##   - `$((...))` 산술 / `${{...}}` GitHub 식 / 기타 make 매크로 = 분석 금지.
  result = @[]
  var i = 0
  while i < line.len:
    if line[i] == '$' and i + 1 < line.len and line[i+1] == '(':
      if i + 2 < line.len and line[i+2] == '(':
        # $(( 산술 치환 — 명령 아님
        inc i
        continue
      let j = findMatchingParen(line, i + 1)
      if j >= 0:
        let body = line[i+2 ..< j]
        if not isMakefile:
          result.add(body)
        else:
          let t = body.strip()
          if t.startsWith("shell "):
            result.add(t["shell ".len .. ^1])
          else:
            # make 함수/매크로 본문 — 중첩 $(shell …)만 재귀 수집
            for sub in collectShellSubstitutions(body, isMakefile = true):
              result.add(sub)
        i = j
      else:
        inc i
    elif line[i] == '`':
      let j = line.find('`', i + 1)
      if j >= 0:
        result.add(line[i+1 ..< j])
        i = j + 1
      else:
        inc i
    else:
      inc i

proc collectMakeRuntimeSubstitutions(line: string): seq[string] =
  ## makefile 레시피의 `$$( ... )` — 런타임 셸 치환 (`$((…))` 산술은 제외).
  ## `$$(...)` 본문 속 `$(…)`는 make 파싱 시 이미 확장되므로 셸 치환 아님 —
  ## 수집하지 않는다 (결정론: 오로지 `$$(` 직접 본문만).
  var i = 0
  while i < line.len:
    if line[i] == '$' and i + 1 < line.len and line[i+1] == '$' and
       i + 2 < line.len and line[i+2] == '(':
      if i + 3 < line.len and line[i+3] == '(':
        inc i
        continue
      let j = findMatchingParen(line, i + 2)
      if j >= 0:
        result.add(line[i+3 ..< j])
        i = j
      else:
        inc i
    else:
      inc i

# ═══════════════════════════════════════════════════════════════════════════
# 협의: 미해소 보고 + 중복 제거
# ═══════════════════════════════════════════════════════════════════════════

proc unresolved(w: var Walker, origin, line, reason: string) =
  w.unresolved.add Unresolved(origin: origin, line: line, reason: reason)

proc errOut(msg: string) =
  ## stderr 출력 헬퍼 (raises: [] 하에서 IOError 흡수 — 출력 실패는 판정에
  ## 영향 없음. 실패 자체가 조용한 통과를 만들지 않는다: exit 코드가 판정).
  try:
    stderr.writeLine(msg)
  except IOError:
    discard

proc dedupUnresolved(w: var Walker) =
  var seen: HashSet[string]
  var deduped: seq[Unresolved]
  for u in w.unresolved:
    let key = u.origin & "\x1f" & u.reason & "\x1f" & u.line
    if key notin seen:
      seen.incl(key)
      deduped.add(u)
  w.unresolved = deduped

# ═══════════════════════════════════════════════════════════════════════════
# 트리/내용 접근 (I/O — git 전용, 워킹 트리 금지)
# ═══════════════════════════════════════════════════════════════════════════

proc git(root, args: string): tuple[outp: string, code: int] {.axiomEffect: IoEffect.} =
  try:
    let (o, c) = execCmdEx("git -C " & quoteShell(root) & " " & args)
    result = (o, c)
  except CatchableError:
    result = ("", 1)

proc treeEntryAt(w: Walker, path: string): TreeEntry =
  result = w.tree.getOrDefault(path)

proc fileExistsAt(w: Walker, path: string): bool =
  w.treeEntryAt(path).sha.len > 0

proc stopCatFile(w: var Walker) {.axiomEffect: IoEffect.} =
  ## 장수 cat-file 정리 — stdin EOF로 정상 종료를 기다리고 잔존 시 terminate.
  ## 정리 단계 실패는 판정 무관한 자원 정리 실패다: 부모 종료 시 OS가 파이프를
  ## 닫고 git도 EOF로 종료하므로, 닫기/종료 대기의 실패가 closure 유도 결과를
  ## 바꾸지 못한다. 실패 시 남은 정리를 포기하고 명시 복귀한다 — 삼킴이 아니라
  ## 제어 흐름 결정이다.
  if w.catProc.isNil:
    return
  let p = w.catProc
  w.catProc = nil
  try:
    p.inputStream.close()
  except CatchableError:
    return
  try:
    if p.waitForExit(2000) != 0 or p.running:
      p.terminate()
      discard p.waitForExit(1000)
  except CatchableError:
    return

proc startCatFile(w: var Walker): bool {.axiomEffect: IoEffect.} =
  ## `git cat-file --batch` 1회 기동 (plumbing — gitglossary 정의상 core Git).
  ## poStdErrToStdOut 금지: git 진단이 프레임 스트림을 오염시킨다 (stderr는 상속).
  try:
    w.catProc = startProcess("git", workingDir = w.repoRoot,
                             args = ["cat-file", "--batch"],
                             options = {poUsePath})
  except CatchableError:
    w.catProc = nil
    return false
  result = true

proc readCatExact(s: Stream, n: int): string {.axiomEffect: IoEffect.} =
  ## 정확히 n바이트 블록 읽기 (크기 기반 — 라인 추측 금지). EOF/부족 시 "".
  result = newString(n)
  var got = 0
  while got < n:
    var chunk = ""
    try:
      chunk = s.readStr(n - got)
    except CatchableError:
      return ""
    if chunk.len == 0:
      return ""
    result[got ..< got + chunk.len] = chunk
    got += chunk.len

proc readCatHeader(s: Stream): string {.axiomEffect: IoEffect.} =
  ## 요청 직후의 응답 헤더 1행. EOF/오류 = "" (git은 빈 헤더를 내지 않는다).
  try:
    result = s.readLine()
  except CatchableError:
    result = ""

proc catFileFatal(oid, why: string) =
  ## 프레임 프로토콜 불일치 — fail-closed. 조용한 "" 축소는 closure를
  ## 몰래 줄이는 극장이므로(§0.9) 비정상 exit로 종료한다.
  errOut("ERROR: git cat-file --batch 프로토콜 불일치 (" & why & "): " & oid)
  quit(2)

const CatFileAttempts = 2   # 초기 기동 + 사망 시 1회 재기동 재시도

proc fetchBlob(w: var Walker, oid: string): string {.axiomEffect: IoEffect.} =
  ## blob OID 1건을 장수 cat-file에서 크기 기반 프레임으로 직독.
  ## 응답 계약(git-cat-file(1)): `<oid> SP <type> SP <size> LF <contents> LF`,
  ## 미해소 시 `<object> SP missing LF`. 기본값(무 --buffer)은 객체당 flush이므로
  ## 요청-응답 대화형 프로토콜이 성립한다.
  ## 사망(EOF/쓰기 실패/프레임 단절) = 재기동 후 1회 재시도,
  ## 완결된 프레임의 비정합(OID/타입/size) = fail-closed quit(2).
  for _ in 1 .. CatFileAttempts:
    if w.catProc.isNil and not w.startCatFile():
      return ""   # git 기동 불가 — 기존 `git show` 실패("")와 동일 관측
    try:
      w.catProc.inputStream.writeLine(oid)
      w.catProc.inputStream.flush()
    except CatchableError:
      stopCatFile(w)
      continue
    var header = ""
    try:
      header = readCatHeader(w.catProc.outputStream)
    except CatchableError:
      stopCatFile(w)
      continue
    if header.len == 0:
      stopCatFile(w)
      continue
    let parts = header.split(' ')
    if parts.len == 2 and parts[1] == "missing":
      return ""   # ls-tree가 방금 나열한 blob의 부재 = 저장소 비정합 —
                  # 기존 `git show` 실패("")와 동일 관측으로 처리
    if parts.len != 3 or parts[0] != oid or parts[1] != "blob":
      catFileFatal(oid, "헤더 비정합: " & header)
    var size = -1
    try:
      size = parseInt(parts[2])
    except CatchableError:
      catFileFatal(oid, "size 비수치: " & header)
    if size < 0:
      catFileFatal(oid, "size 음수: " & header)
    var body = ""
    try:
      body = readCatExact(w.catProc.outputStream, size)
    except CatchableError:
      stopCatFile(w)
      continue
    if body.len != size:
      stopCatFile(w)
      continue
    var trailer = ""
    try:
      trailer = readCatExact(w.catProc.outputStream, 1)
    except CatchableError:
      stopCatFile(w)
      continue
    if trailer != "\n":
      stopCatFile(w)   # 프레임 트레일러 LF 단절/오염 — 사망 취급 후 재시도
      continue
    return body
  catFileFatal(oid, "재기동 후에도 응답 없음")
  result = ""

proc fileContent(w: var Walker, path: string): string {.axiomEffect: IoEffect.} =
  ## H 트리 내용 전용 (워킹 트리 절대 금지, ADR C2) — `git ls-tree`가 해석한
  ## blob OID를 단일 장수 `git cat-file --batch`로 직독한다 (spawn 1회).
  ## blob은 불변 객체이므로 `git show <ref>:<path>`와 바이트 동일하다.
  if not w.fileExistsAt(path):
    return ""
  result = w.fetchBlob(w.treeEntryAt(path).sha)

proc snapshotTree(w: var Walker): bool {.axiomEffect: IoEffect.} =
  ## `git ls-tree -r` 1회 스냅샷 — 멤버십/존재 판정의 유일 정본 (contents API 금지).
  let r = git(w.repoRoot, "ls-tree -r --full-tree " & w.repoRef)
  if r.code != 0:
    return false
  for line in r.outp.splitLines():
    if line.len == 0:
      continue
    let tab = line.find('\t')
    if tab < 0:
      continue
    let meta = line[0 ..< tab].split(' ')
    if meta.len != 3 or meta[1] != "blob":
      continue
    w.tree[line[tab+1 .. ^1]] = TreeEntry(mode: meta[0], typ: meta[1], sha: meta[2])
  result = true

# ═══════════════════════════════════════════════════════════════════════════
# 멤버 추가 + import 그래프 walk
# ═══════════════════════════════════════════════════════════════════════════

proc resolveImportPath(w: Walker, expr, importer: string): string =
  ## import 식 → repo 상대 경로. 후보 순서: 상대경로 → 루트 → src/ → 임포터 디렉.
  ## 트리에 존재하는 첫 후보만 인정; 미존재 = nimble/외부 모듈(skip).
  var e = expr.strip()
  if e.len == 0:
    return ""
  let asPos = e.find(" as ")
  if asPos >= 0:
    e = e[0 ..< asPos]
  var cands: seq[string]
  if e.startsWith("."):
    var base = importer.parentDir()
    var rel = e
    while rel.startsWith("../"):
      base = base.parentDir()
      rel = rel[3 .. ^1]
    if rel.startsWith("./"):
      rel = rel[2 .. ^1]
    cands.add(base / rel)
  else:
    cands.add(e)
    cands.add("src/" & e)
    cands.add(importer.parentDir() / e)
  for c in cands:
    var p = c.replace("\\", "/")
    while p.startsWith("./"):
      p = p[2 .. ^1]
    if p.startsWith("/"):
      continue
    if w.fileExistsAt(p & ".nim"):
      return p & ".nim"
  result = ""

proc parseImportItems(decl: string): seq[string] =
  ## `import a, b/c as d, e/[x, y]` → 분해된 모듈 식 목록.
  result = @[]
  let body = decl.strip()
  if body.len == 0:
    return
  var i = 0
  while i < body.len:
    var j = i
    while j < body.len and body[j] != ',':
      j = j + 1
    let item = body[i ..< j].strip()
    if item.len > 0:
      let br = item.find("/[")
      if br >= 0 and item.endsWith("]"):
        let prefix = item[0 ..< br]
        let inner = item[br+2 ..< item.len-1]
        for sub in inner.split(','):
          result.add(prefix & "/" & sub.strip())
      else:
        result.add(item)
    i = j + 1

proc walkNimImports(w: var Walker, path: string) {.axiomEffect: IoEffect.} =
  ## 소스의 로컬 import/from/include 그래프 재귀 walk (visited).
  if path in w.visitedNim:
    return
  w.visitedNim.incl(path)
  let content = w.fileContent(path)
  if content.len == 0:
    return
  var pending = ""
  for rawLine in content.splitLines():
    var line = stripComment(rawLine).strip()
    if pending.len > 0:
      line = pending & " " & line
      pending = ""
    if line.endsWith(",") and (line.startsWith("import ") or line.startsWith("include ")):
      pending = line
      continue
    if line.startsWith("import "):
      for item in parseImportItems(line["import ".len .. ^1]):
        let resolved = w.resolveImportPath(item.split(' ')[0], path)
        if resolved.len > 0 and resolved notin w.members:
          w.members.incl(resolved)
          w.walkNimImports(resolved)
        # 미해소 = std/* 또는 nimble 패키지 → nimble.lock 시드가 커버 (skip)
    elif line.startsWith("from "):
      let sp = line.find(" import")
      if sp > 0:
        let resolved = w.resolveImportPath(line["from ".len ..< sp], path)
        if resolved.len > 0 and resolved notin w.members:
          w.members.incl(resolved)
          w.walkNimImports(resolved)
    elif line.startsWith("include "):
      for item in parseImportItems(line["include ".len .. ^1]):
        let resolved = w.resolveImportPath(item.split(' ')[0], path)
        if resolved.len > 0 and resolved notin w.members:
          w.members.incl(resolved)
          w.walkNimImports(resolved)
        elif resolved.len == 0:
          # include는 반드시 로컬 — 미해소는 조용히 건너뛸 수 없다.
          w.unresolved(path, rawLine, "include가 ref 트리에 존재하지 않음")

proc addNimSource(w: var Walker, path: string) {.axiomEffect: IoEffect.} =
  ## `nim c <path>.nim` 소스 → 멤버 + import 그래프.
  var p = path
  while p.startsWith("./"):
    p = p[2 .. ^1]
  var src = p
  if src.endsWith(".nim"):
    src = src[0 ..< src.len - 4]
  if w.fileExistsAt(src & ".nim"):
    if src & ".nim" notin w.members:
      w.members.incl(src & ".nim")
      w.walkNimImports(src & ".nim")
  else:
    w.unresolved("nim c", path, "소스가 ref 트리에 존재하지 않음")

proc addScriptMember(w: var Walker, path: string) =
  ## sh/source로 실행되는 스크립트 경로 → 멤버 (내용 walk는 범위 밖 — Tier S 경계).
  var p = path
  while p.startsWith("./"):
    p = p[2 .. ^1]
  if p notin w.members and w.fileExistsAt(p):
    w.members.incl(p)

# ═══════════════════════════════════════════════════════════════════════════
# make 타깃/레시피 walk (진입점 (b) — ci/checker.mk @ref)
# ═══════════════════════════════════════════════════════════════════════════

proc scanMakeProducts(w: var Walker) =
  ## 모든 레시피의 `nim c ... -o:<out> <src>.nim` → 제품(생성 바이너리) 매핑
  ## 프리스캔. 레시피 walk 순서와 무관하게 out→src 소거를 보장한다.
  ## `$@`/`$<`는 각 타깃/프리레퀴 문맥으로 치환한다.
  for tgt, def in w.targets:
    var firstPrereq = if def.prereqs.len > 0: def.prereqs[0] else: ""
    for rawRecipe in def.recipe:
      var line = rawRecipe.strip()
      if line.startsWith("@"):
        line = line[1 .. ^1]
      var toks = tokenizeCommand(line)
      for ti in 0 ..< toks.len:
        toks[ti] = substMakeCtx(toks[ti], tgt, firstPrereq)
      if toks.len == 0:
        continue
      var cmd = toks[0]
      if cmd.startsWith("$("):
        cmd = w.makeVars.getOrDefault(cmd[2 ..< cmd.len - 1], cmd)
      if cmd == "nim":
        var outs: seq[string]
        for t in toks[1 .. ^1]:
          if t.startsWith("-o:"):
            var op = t[3 .. ^1]
            while op.startsWith("./"):
              op = op[2 .. ^1]
            outs.add(op)
        for t in toks[1 .. ^1]:
          if t.endsWith(".nim") and not t.startsWith("-") and not t.startsWith("$("):
            var sp = t
            while sp.startsWith("./"):
              sp = sp[2 .. ^1]
            if sp.endsWith(".nim"):
              sp = sp[0 ..< sp.len - 4]
            for op in outs:
              w.products[op] = sp & ".nim"

proc parseMakefile(w: var Walker) {.axiomEffect: IoEffect.} =
  ## ci/checker.mk @ref — 타깃 테이블 + 변수 정의 수집. makefile 자체는 시드 멤버.
  ## 레시피는 연속행(`\`)을 결합해 walk에 넘긴다. 타깃 블록 안의 컬럼 0 주석은
  ## 레시피 수집을 중단시키지 않는다 (ci-compile 형식).
  let content = w.fileContent(CheckerMkPath)
  if not w.fileExistsAt(CheckerMkPath):
    w.unresolved("entry", CheckerMkPath, "entry point 파일이 ref 트리에 없음")
    return
  let lines = content.splitLines()
  var i = 0
  while i < lines.len:
    let raw = lines[i]
    if raw.len == 0 or raw[0] != '\t':
      let noComment = stripComment(raw).strip()
      if noComment.len == 0:
        inc i
        continue
      # 변수 정의: NAME [?|:|+|!]= value. 연산자(`:=`/`?=`/`+=`/`!=`) 접미사를
      # 정규화해 등록하고, 백슬래시 연속 값도 전체를 결합한다 (다중 단어 값이
      # 명령 위치에서 재토큰화 분석될 수 있어야 함 — SHELL :=, GATEWAY_POLICY_PARSE
      # := 등). 정규화 실패 시 이 지점을 빠져나가면 `:` 콜론 분기가 `NAME := value`
      # 를 타깃/프리레퀴로 오인하므로, 반드시 여기서 소화하거나 명시적으로
      # 원문 유지 후 이동한다 (fail-closed 보존).
      let eq = noComment.find('=')
      if eq > 0:
        var name = noComment[0 ..< eq].strip()
        if name.len > 0 and name[^1] in {'?', ':', '+', '!'}:
          name = name[0 ..< name.len - 1].strip()
        if name.len > 0 and name.allIt(it in {'A'..'Z', 'a'..'z', '_', '0'..'9'}):
          var val = noComment[eq+1 .. ^1].strip()
          var j = i
          while endsWithContinuation(val) and j + 1 < lines.len:
            var nextLine = stripComment(lines[j+1]).strip()
            if nextLine.len > 0 and nextLine[0] == '\t':
              nextLine = nextLine[1 .. ^1]
            val = val[0 ..< val.len - 1].strip() & " " & nextLine
            inc j
          w.makeVars[name] = val
          i = j + 1
          continue
      let colon = noComment.find(':')
      if colon > 0:
        let head = noComment[0 ..< colon].strip()
        if head.len > 0 and not head.startsWith(".") and
           not head.contains(" ") and not head.contains("="):
          let prereqs = noComment[colon+1 .. ^1].splitWhitespace()
          var recipe: seq[string]
          var joined = ""
          var pendingCont = false   # 직전 조인 행이 `\` 연속이었는가 (조인 상태)
          inc i
          while i < lines.len:
            let rl = lines[i]
            # make 백슬래시 연속: 직전 행이 `\`로 끝나면 다음 행은 들여쓰기
            # (탭/공백)와 무관하게 레시피에 결합된다. 비연속 상태의 탭 행만
            # 새 레시피 행으로 취급한다 (test-gateway-policy-gate의 python
            # 본문은 공백 들여쓰기 연속 행이다).
            var body = ""
            var isRecipe = false
            if rl.len > 0 and rl[0] == '\t':
              body = rl[1 .. ^1]
              isRecipe = true
            elif pendingCont and rl.strip().len > 0:
              body = rl
              isRecipe = true
            if isRecipe:
              joined = (if joined.len == 0: body else: joined & " " & body)
              pendingCont = endsWithContinuation(joined)
              if pendingCont:
                joined = joined[0 ..< joined.len - 1]
                inc i
                continue
              recipe.add(joined)
              joined = ""
              inc i
            elif rl.strip().startsWith("#"):
              # 타깃 내 주석 — 레시피 수집 유지
              inc i
            else:
              break
          w.targets[head] = MakeTarget(recipe: recipe, prereqs: prereqs,
                                       isFileTarget: head.contains("/"))
          continue
      inc i
    else:
      inc i
  w.scanMakeProducts()

proc walkMakeTarget(w: var Walker, target: string) {.axiomEffect: IoEffect.} =
  ## 타깃 레시피 walk: nim c 소스/제품, $(MAKE) 서브타깃, 리터럴 경로.
  ## 프리레퀴 파일 타깃(생성 바이너리 규칙)을 먼저 walk한다 (결정적 순서).
  if target in w.visitedTargets:
    return
  w.visitedTargets.incl(target)
  let def = w.targets.getOrDefault(target)
  if def.recipe.len == 0 and def.prereqs.len == 0:
    w.unresolved("make target", target,
                 "ci/checker.mk에 타깃/레시피 없음 (정적 해석 불가)")
    return
  for p in def.prereqs:
    if p in w.targets:
      w.walkMakeTarget(p)
  var firstPrereq = if def.prereqs.len > 0: def.prereqs[0] else: ""
  for rawRecipe in def.recipe:
    var line = rawRecipe.strip()
    if line.len == 0:
      continue
    if line.startsWith("@"):
      line = line[1 .. ^1]
    for sub in collectMakeRuntimeSubstitutions(line):
      # 런타임 `$$(...)` 본문은 make 파싱 후 셸이 보는 텍스트 — 남은 `$(...)`는
      # make 파싱 시점 잔여물(매크로/함수)이므로 make 모드로 분석한다.
      # 셸 모드면 `$(call gate…)` 본문이 명령 `call`로 오인된다.
      w.analyzeLine(sub, "ci/checker.mk ($(..))", makeMode = true)
    w.analyzeCommandTokens(tokenizeCommand(line), "ci/checker.mk", target,
                           firstPrereq)

proc walkMakefileShellDirectives(w: var Walker) {.axiomEffect: IoEffect.} =
  ## checker.mk 전체 행의 `$(shell ...)` (파싱 시 실행 코드) 전수 walk.
  ## 주석 행은 실행 코드가 아니다 (백틱/$(…)이 있어도 분석 금지).
  let content = w.fileContent(CheckerMkPath)
  for rawLine in content.splitLines():
    if rawLine.strip().startsWith("#"):
      continue
    for sub in collectShellSubstitutions(rawLine, isMakefile = true):
      w.analyzeLine(sub, "ci/checker.mk [$(shell)]", makeMode = true)

# ═══════════════════════════════════════════════════════════════════════════
# 명령 분석 코어 (fail-closed 심장)
# ═══════════════════════════════════════════════════════════════════════════

proc resolveCommandPath(w: var Walker, tok: string, origin: string): bool =
  ## 명령 위치 토큰이 리터럴 경로면 정적 소거:
  ##   1) 트리 존재 → 멤버   2) -o:/다운로드 제품 매핑 → 소스   3) 미해소 → FAIL
  var p = tok
  if p.startsWith("\"") and p.endsWith("\"") and p.len >= 2:
    p = p[1 ..< p.len - 1]
  if p.startsWith("$") or p.contains("`"):
    if p.startsWith("$HOME/"):
      let base = p.split('/')[^1]
      if isKnownTool(base):
        return true
    w.unresolved(origin, tok, "변수/동적 경로 — 정적 소거 불가")
    return false
  while p.startsWith("./"):
    p = p[2 .. ^1]
  if p.len == 0:
    w.unresolved(origin, tok, "빈 경로")
    return false
  if w.fileExistsAt(p):
    if p.endsWith(".nim"):
      w.addNimSource(p)
    else:
      w.addScriptMember(p)
    return true
  let src = w.products.getOrDefault(p)
  if src.len > 0:
    w.addNimSource(src)
    return true
  w.unresolved(origin, tok,
               "리터럴 경로가 ref 트리도 아니고 제품 매핑도 없음 (생성/다운로드 바이너리?)")
  result = false

proc analyzeSegment(w: var Walker, segIn: seq[string], origin: string,
                    makeCtx, makeFirstPrereq: string) =
  var seg = segIn
  if makeCtx.len > 0:
    for i in 0 ..< seg.len:
      seg[i] = substMakeCtx(seg[i], makeCtx, makeFirstPrereq)
  if seg.len == 0:
    return
  var i = 0
  # case/for — 구조 분석 (키워드 일반 정리와 분리)
  if seg[0] == "case":
    var j = seg.len - 1
    while j >= 0 and seg[j] != "in":
      dec j
    if j < 1:
      w.unresolved(origin, seg.join(" "), "case 문 구조 미해소")
      return
    i = j + 1
  elif seg[0] == "for":
    var j = i + 1
    if j < seg.len:
      inc j  # 변수명
      if j < seg.len and seg[j] == "in":
        inc j
        while j < seg.len and seg[j] != "do":
          inc j
        if j < seg.len:
          i = j + 1
        else:
          w.unresolved(origin, seg.join(" "), "for 목록 구조 미해소")
          return
      else:
        w.unresolved(origin, seg.join(" "), "for 문 구조 미해소")
        return
    else:
      w.unresolved(origin, seg.join(" "), "for 문 구조 미해소")
      return
  # 선두 키워드/라벨/할당 정리
  while i < seg.len and (seg[i] in ShellKeywords or isCaseLabel(seg[i]) or
                         isEnvAssign(seg[i])):
    inc i
  if i >= seg.len:
    return  # 순수 구조/할당 — 실행 없음
  var cmd = seg[i]
  let rest = seg[i+1 .. ^1]
  # make 매크로 명령 토큰 처리
  if cmd.startsWith("$(foreach "):
    # $(foreach VAR,LIST,TEXT) — TEXT가 파싱 시 만드는 런타임 코드.
    # 두 번째 최상위 컴마 뒤를 본문으로 추출해 분석한다 (결정론적).
    var inner = cmd[2 ..< cmd.len - 1]  # "foreach VAR,LIST,TEXT"
    var depth = 0
    var inS = false
    var inD = false
    var commaCount = 0
    var bodyStart = -1
    for ci in 0 ..< inner.len:
      let cc = inner[ci]
      if cc == '\'' and not inD:
        inS = not inS
      elif cc == '"' and not inS:
        inD = not inD
      elif not inS and not inD:
        if cc == '(':
          depth.inc
        elif cc == ')':
          depth.dec
        elif cc == ',' and depth == 0:
          commaCount.inc
          if commaCount == 2:
            bodyStart = ci + 1
            break
    if bodyStart < 0:
      w.unresolved(origin, seg.join(" "), "foreach 구조 미해소")
      return
    w.analyzeCommandTokens(tokenizeCommand(inner[bodyStart .. ^1]), origin,
                           makeCtx, makeFirstPrereq)
    return
  if cmd.startsWith("$(") and cmd.endsWith(")"):
    let name = cmd[2 ..< cmd.len - 1]
    if name == "MAKE" or name == "NIM" or name == "NIMBLE":
      cmd = w.makeVars.getOrDefault(name, "")
      if cmd.len == 0:
        cmd = if name == "MAKE": "make" elif name == "NIM": "nim" else: "nimble"
    elif name.startsWith("call "):
      # $(call FN,args…) — FN 값에 $(1)..$(9) 결속 후 재토큰화 분석.
      let inner = name["call ".len .. ^1]
      let cpos = findTopLevelComma(inner)
      let fn = (if cpos < 0: inner.strip() else: inner[0 ..< cpos].strip())
      if w.makeVars.hasKey(fn) and w.expandDepth < MakeExpandDepthCap:
        var val = w.makeVars.getOrDefault(fn)
        let args = if cpos < 0: newSeq[string]() else:
          splitCallArgs(inner[cpos+1 .. ^1])
        for ai in countdown(args.len - 1, 0):
          if ai < 9:
            val = val.replace("$(" & $(ai + 1) & ")", args[ai])
            val = val.replace("${" & $(ai + 1) & "}", args[ai])
        inc w.expandDepth
        w.analyzeCommandTokens(tokenizeCommand(val), origin, makeCtx,
                               makeFirstPrereq)
        dec w.expandDepth
        return
      cmd = w.makeVars.getOrDefault(name, cmd)
    elif w.makeVars.hasKey(name):
      # 등록된 변수 값은 make 문자열 — 재토큰화해 명령으로 분석한다
      # (python3 -c '…' 같은 다중 단어 값: 단일 토큰 치환은 값을 명령명으로
      # 오인해 fail-closed 위양성을 만든다). 깊이 상한 초과/빈 값은 원문
      # 유지 — 미지 이름으로 거부된다 (fail-closed 보존).
      let val = w.makeVars.getOrDefault(name)
      if val.len == 0:
        return
      if w.expandDepth < MakeExpandDepthCap:
        inc w.expandDepth
        w.analyzeCommandTokens(tokenizeCommand(val), origin, makeCtx,
                               makeFirstPrereq)
        dec w.expandDepth
        return
      cmd = val
    else:
      cmd = w.makeVars.getOrDefault(name, cmd)
  if cmd in [">", ">>", "<", "2>", "2>>", "&>"]:
    return  # 리다이렉트만 있는 세그먼트
  if cmd.startsWith("<("):
    return  # 프로세스 치환 — 인자 취급 (명령 아님)
  if cmd in ["command", "exec"]:
    if rest.len == 0:
      w.unresolved(origin, seg.join(" "), "command/exec 인자 없음")
      return
    w.analyzeSegment(@rest, origin, makeCtx, makeFirstPrereq)
    return
  if cmd == "env":
    var j = 0
    while j < rest.len and isEnvAssign(rest[j]):
      inc j
    if j >= rest.len:
      return
    w.analyzeSegment(@rest[j .. ^1], origin, makeCtx, makeFirstPrereq)
    return
  if cmd == "eval":
    w.unresolved(origin, seg.join(" "), "eval 금지 — 정적 해석 불가")
    return
  if cmd == "make":
    var j = 0
    while j < rest.len and isEnvAssign(rest[j]):
      inc j
    if j < rest.len and rest[j] == "-f":
      # make -f <makefile> <target> — makefile은 ci/checker.mk만 허용
      inc j
      if j >= rest.len:
        w.unresolved(origin, seg.join(" "), "make -f makefile 미해소")
        return
      if rest[j] != "ci/checker.mk":
        w.unresolved(origin, seg.join(" "),
                     "make -f 대상이 ci/checker.mk 아님: " & rest[j])
        return
      inc j
    if j >= rest.len or rest[j].startsWith("-"):
      w.unresolved(origin, seg.join(" "), "make 타깃 미해소 (플래그/부재)")
      return
    w.walkMakeTarget(rest[j])
    return
  if cmd == "nim":
    for t in rest:
      if t.startsWith("-o:"):
        var op = t[3 .. ^1]
        while op.startsWith("./"):
          op = op[2 .. ^1]
        for t2 in rest:
          if t2.endsWith(".nim") and not t2.startsWith("-") and
             t2 != t and not t2.startsWith("-o:"):
            var sp = t2
            while sp.startsWith("./"):
              sp = sp[2 .. ^1]
            if sp.endsWith(".nim"):
              sp = sp[0 ..< sp.len - 4]
            w.products[op] = sp & ".nim"
      elif not t.startsWith("-"):
        if t.startsWith("$("):
          discard  # make 매크로 인자 — 값은 플래그/경로 치환 (정적 판정 불가 아님)
        elif t in ["c", "check", "install", "r", "compile", "dump", "js", "cc",
                 "e", "nep1", "doc"]:
          discard  # 서브커맨드
        elif t.endsWith(".nim"):
          w.addNimSource(t)
        else:
          w.unresolved(origin, seg.join(" "), "nim 비소스 위치인자: " & t)
    return
  if cmd in ["sh", "bash", "dash", "source", "."]:
    var j = 0
    var codeMode = false
    while j < rest.len:
      let a = rest[j]
      if codeMode:
        var code = a
        if code.startsWith("\"") and code.endsWith("\"") and code.len >= 2:
          code = code[1 ..< code.len - 1]
        if code.len > 0:
          w.analyzeCommandTokens(tokenizeCommand(code), origin, makeCtx,
                                 makeFirstPrereq)
        codeMode = false
      elif a == "-c" or (a.startsWith("-") and a.len > 2 and a[1] == 'c'):
        codeMode = true
      elif not a.startsWith("-") and not isEnvAssign(a) and not a.startsWith("$"):
        if a.contains("/") and not a.contains("`"):
          var sp = a
          while sp.startsWith("./"):
            sp = sp[2 .. ^1]
          if w.fileExistsAt(sp):
            w.addScriptMember(sp)
      inc j
    return
  if cmd.contains("/") or cmd.startsWith(".") or cmd.startsWith("\"") or
     cmd.startsWith("'"):
    discard w.resolveCommandPath(cmd, origin)
    return
  if isKnownTool(cmd):
    return
  w.unresolved(origin, seg.join(" "),
               "PATH 미지 실행 이름: '" & cmd & "' (허용 목록 외)")

proc analyzeCommandTokens(w: var Walker, toksIn: seq[string], origin: string,
                          makeCtx, makeFirstPrereq: string) =
  ## 토큰 시퀀스를 셸 세그먼트로 분리해 각각 명령 분석한다.
  ## 토큰에 붙은 `;`/`;;`(인용부 밖)도 분리자로 취급하고,
  ## `for … in …; do` 분리에서 `do`가 다음 세그먼트로 밀리면 재결합한다.
  if toksIn.len == 0:
    return
  var toks: seq[string]
  for t in toksIn:
    var body = t
    var inS = false
    var inD = false
    var start = 0
    var ci = 0
    while ci < body.len:
      let cc = body[ci]
      if cc == '\'' and not inD:
        inS = not inS
      elif cc == '"' and not inS:
        inD = not inD
      elif not inS and not inD:
        if cc == '(':
          # $(...)/<(…)/함수 괄호 내부의 ; 는 분리자가 아니다
          let close = findMatchingParen(body, ci)
          if close > ci:
            ci = close
        elif cc == ';':
          if ci > start:
            toks.add(body[start ..< ci].strip())
          toks.add(";")
          start = ci + 1
      inc ci
    if start < body.len:
      let tail = body[start .. ^1].strip()
      if tail.len > 0:
        toks.add(tail)
  if makeCtx.len > 0:
    for i in 0 ..< toks.len:
      toks[i] = substMakeCtx(toks[i], makeCtx, makeFirstPrereq)
  var segs: seq[seq[string]]
  var seg: seq[string]
  for t in toks:
    if t == ";" or t == "&&" or t == "||" or t == "|":
      segs.add(seg)
      seg = @[]
    else:
      seg.add(t)
  segs.add(seg)
  var i = 0
  while i < segs.len:
    let s = segs[i]
    if s.len == 0:
      inc i
      continue
    if s[0] == "for" and not s.contains("do") and i + 1 < segs.len and
       segs[i+1].len > 0 and segs[i+1][0] == "do":
      w.analyzeSegment(s & segs[i+1], origin, makeCtx, makeFirstPrereq)
      i += 2
    else:
      w.analyzeSegment(s, origin, makeCtx, makeFirstPrereq)
      inc i

proc analyzeLine(w: var Walker, line: string, origin: string,
                 makeMode = false) =
  ## 한 줄: 셸 치환 수집 + 세그먼트 명령 분석. heredoc 본문은 호출 측이 제외.
  ## makeMode: make 파싱 시 실행 문맥 — 중첩 `$(…)`는 make 매크로(분석 금지).
  let stripped = stripComment(line).strip()
  if stripped.len == 0 or stripped[0] == '#' or stripped[0] == ':':
    return
  for sub in collectShellSubstitutions(stripped, isMakefile = makeMode):
    w.analyzeLine(sub, origin & " ($(...))", makeMode)
  w.analyzeCommandTokens(tokenizeCommand(stripped), origin, "", "")

# ═══════════════════════════════════════════════════════════════════════════
# 워크플로 walk (진입점 (a) — .github/workflows/runner-pool-acceptance.yml)
# ═══════════════════════════════════════════════════════════════════════════

proc scanWorkflowProducts(w: var Walker, content: string) =
  ## 워크플로 전체의 `nim c ... -o:` → 제품 매핑 프리스캔 (잡 간 전달 순서 무관).
  for rawLine in content.splitLines():
    let toks = tokenizeCommand(stripComment(rawLine))
    if toks.len == 0 or toks[0] != "nim":
      continue
    var outs: seq[string]
    for t in toks[1 .. ^1]:
      if t.startsWith("-o:"):
        var op = t[3 .. ^1]
        while op.startsWith("./"):
          op = op[2 .. ^1]
        outs.add(op)
    for t in toks[1 .. ^1]:
      if t.endsWith(".nim") and not t.startsWith("-"):
        var sp = t
        while sp.startsWith("./"):
          sp = sp[2 .. ^1]
        if sp.endsWith(".nim"):
          sp = sp[0 ..< sp.len - 4]
        for op in outs:
          w.products[op] = sp & ".nim"

proc recordUploadArtifacts(w: var Walker, content: string) =
  ## upload-artifact 단계 전수 스캔 — artifact 이름 → 파일 경로 (전역 맵).
  var lines = content.splitLines()
  var i = 0
  while i < lines.len:
    let raw = lines[i]
    let t = stripComment(raw).strip()
    if t.startsWith("uses: actions/upload-artifact@") or
       t.startsWith("- uses: actions/upload-artifact@"):
      var name = ""
      var paths: seq[string]
      let usesIndent = raw.leadingIndent()
      inc i
      while i < lines.len:
        let r2 = lines[i]
        let ind = r2.leadingIndent()
        if ind < usesIndent or r2.strip().len == 0:
          break
        let v = r2.strip()
        if v.startsWith("name:"):
          name = v["name:".len .. ^1].strip()
        elif v.startsWith("path: |") or v.startsWith("path: >"):
          let pind = r2.len - r2.leadingIndent()
          inc i
          while i < lines.len and lines[i].len > 0 and
                lines[i].len - lines[i].leadingIndent() > pind:
            let item = lines[i].strip()
            if item.len > 0:
              paths.add(item)
            inc i
          continue
        elif v.startsWith("path:"):
          let pv = v["path:".len .. ^1].strip()
          if pv.len > 0:
            paths.add(pv)
        inc i
      if name.len > 0:
        w.artifactFiles[name] = paths
      continue
    inc i

proc recordDownloads(w: var Walker, content: string) =
  ## download-artifact 단계 — name/pattern + path. 이름 정합 시 다운로드 경로를
  ## 업로드 파일의 소스로 치환 (artifact 전달 = 같은 결정론적 바이너리).
  var lines = content.splitLines()
  var i = 0
  while i < lines.len:
    let raw = lines[i]
    let t = stripComment(raw).strip()
    if t.startsWith("uses: actions/download-artifact@") or
       t.startsWith("- uses: actions/download-artifact@"):
      var name = ""
      var dpath = ""
      let usesIndent = raw.leadingIndent()
      inc i
      while i < lines.len:
        let r2 = lines[i]
        let ind = r2.leadingIndent()
        if ind < usesIndent or r2.strip().len == 0:
          break
        let v = r2.strip()
        if v.startsWith("name:"):
          name = v["name:".len .. ^1].strip()
        elif v.startsWith("path:"):
          dpath = v["path:".len .. ^1].strip()
        inc i
      if name.len > 0 and dpath.len > 0 and name in w.artifactFiles:
        for f in w.artifactFiles.getOrDefault(name):
          let base = extractFilename(f)
          let dest = if dpath == ".": base else: dpath & "/" & base
          let src = w.products.getOrDefault(f)
          if src.len > 0:
            w.products[dest] = src
          elif w.fileExistsAt(f):
            w.members.incl(f)
          else:
            # 업로드 경로를 못 소거하면 다운로드 파일도 미해소 상태로 남겨
            # 명령 위치 등장 시 resolveCommandPath가 거부한다 (fail-closed).
            discard
      continue
    inc i

proc walkWorkflow(w: var Walker) {.axiomEffect: IoEffect.} =
  ## runner-pool-acceptance.yml @ref — run: 블록 전수 walk (heredoc 본문 제외).
  if not w.fileExistsAt(WorkflowPath):
    w.unresolved("entry", WorkflowPath, "entry point 파일이 ref 트리에 없음")
    return
  let content = w.fileContent(WorkflowPath)
  w.scanWorkflowProducts(content)
  w.recordUploadArtifacts(content)
  w.recordDownloads(content)
  var lines = content.splitLines()
  var i = 0
  var heredocs: seq[string]
  var runBlockCount = 0
  while i < lines.len:
    let raw = lines[i]
    if heredocs.len > 0:
      let stripped = raw.strip()
      if stripped == heredocs[^1]:
        discard heredocs.pop()
      inc i
      continue
    let t = raw.strip()
    let runPos = t.find("run:")
    if runPos == 0:
      let value = t["run:".len .. ^1].strip()
      if value.len == 0 or value in ["|", ">", "|-", ">-"]:
        let indent = raw.leadingIndent()
        inc i
        var carryOpen = 0
        while i < lines.len:
          let r2 = lines[i]
          if heredocs.len > 0:
            # heredoc 본문 — 실행 코드 아님. 구분자 도달까지 원문 skip.
            if r2.strip() == heredocs[^1]:
              discard heredocs.pop()
            inc i
            continue
          let ind = r2.leadingIndent()
          if r2.strip().len == 0:
            inc i
            continue
          if ind <= indent:
            break
          if carryOpen != 0:
            # 직전 명령의 열린 인용 문자열 잔여분 — 실행 코드 아님, 소비만.
            # 해당 인용부가 실제로 닫힐 때까지 유지한다.
            let closing = if carryOpen == 1: chr(39) else: chr(34)
            if closing in r2:
              if quoteBalance(r2.strip()) == 0:
                carryOpen = 0
            inc i
            continue
          let body = r2.strip()
          runBlockCount.inc
          if body.contains("<<"):
            for tok in tokenizeCommand(body):
              if tok.startsWith("<<") and tok.len > 2:
                var d = tok[2 .. ^1]
                if d.startsWith("'") or d.startsWith("\""):
                  d = d[1 ..< d.len - 1]
                elif d.startsWith("\\") or d.startsWith("-"):
                  d = d[1 .. ^1]
                heredocs.add(d)
          var joined = body
          while endsWithContinuation(joined):
            inc i
            if i >= lines.len:
              break
            joined = joined[0 ..< joined.len - 1] & " " & lines[i].strip()
          w.analyzeLine(joined, WorkflowPath & ":" & $(i+1))
          carryOpen = quoteBalance(joined)
          inc i
        # 블록 종료: while break — i는 다음 행
        continue
      else:
        runBlockCount.inc
        w.analyzeLine(value, WorkflowPath & ":" & $(i+1))
        inc i
        continue
    inc i
  if runBlockCount == 0:
    w.unresolved("entry", WorkflowPath,
                 "워크플로에 run 블록 0건 — 진입점 소멸 (정적 해석 불가)")

# ═══════════════════════════════════════════════════════════════════════════
# 스캔 후처리 + 출력
# ═══════════════════════════════════════════════════════════════════════════

proc addSeeds(w: var Walker) =
  for seed in SeedMembers:
    if not w.fileExistsAt(seed):
      w.unresolved("seed", seed, "정적 시드가 ref 트리에 없음 — closure 훼손")
    else:
      w.members.incl(seed)

proc emitClosure(w: Walker): string =
  ## 정렬된 `<mode> <type> <sha>\t<path>` 라인 (LC_ALL=C 정렬 == 바이트 정렬).
  var paths: seq[string]
  for p in w.members:
    paths.add(p)
  paths.sort()
  for p in paths:
    let e = w.treeEntryAt(p)
    result.add(e.mode & " " & e.typ & " " & e.sha & "\t" & p & "\n")

# ═══════════════════════════════════════════════════════════════════════════
# 러너
# ═══════════════════════════════════════════════════════════════════════════

proc printHelp() =
  echo "derive_checker_closure — H 실행 코드 closure 유도자 (ADR C2 derivation authority)"
  echo ""
  echo "Usage:"
  echo "  derive_checker_closure --ref <git-ref> [--repo <dir>]"
  echo "  derive_checker_closure --tree <git-tree-oid> [--repo <dir>]"
  echo ""
  echo "  --ref <git-ref>   분석 대상 H (커밋 SHA/브랜치). 필수 — 워킹 트리 무관."
  echo "  --tree <tree-oid> 분석 대상이 트리 객체 (merge-tree 후보 트리 M —"
  echo "                    ADR-0025 Amendment F 제3 도출 각). --ref와 상호 배타."
  echo "  --repo <dir>      git 저장소 루트 (기본: cwd에서 .git 탐색)"
  echo ""
  echo "stdout: 정렬된 `<mode> <type> <sha>\\t<path>` 멤버십 (git ls-tree 포맷)."
  echo "stderr: UNRESOLVED 진단 (미해소 1건 = exit 1 — fail-closed)."
  echo "exit: 0 = 성공, 1 = 미해소(fail closed), 2 = 사용법/ref 오류."

proc findRepoRoot(start: string): string {.axiomEffect: IoEffect.} =
  result = start
  for _ in 0 ..< 10:
    let g = result / ".git"
    if dirExists(g) or fileExists(g):
      return
    let parent = result.parentDir()
    if parent == result:
      return ""
    result = parent

proc main() {.axiomEffect: IoEffect.} =
  var repoRef = ""
  var repoTreeRef = ""   # --tree 모드: 대상이 커밋이 아니라 트리 객체 (Amendment F 제3각)
  var repoDir = ""
  try:
    repoDir = getCurrentDir()
  except OSError:
    repoDir = "."
  var p = initOptParser(commandLineParams())
  var pending = ""
  while true:
    p.next()
    case p.kind
    of cmdEnd:
      break
    of cmdLongOption, cmdShortOption:
      if p.val.len > 0:
        pending = ""
        case p.key
        of "ref":
          repoRef = p.val
        of "tree":
          repoTreeRef = p.val
        of "repo":
          repoDir = p.val
        else:
          printHelp()
          quit(2)
      else:
        if p.key notin ["ref", "tree", "repo"]:
          printHelp()
          quit(2)
        pending = p.key
    of cmdArgument:
      case pending
      of "ref":
        repoRef = p.key
      of "tree":
        repoTreeRef = p.key
      of "repo":
        repoDir = p.key
      else:
        printHelp()
        quit(2)
      pending = ""
  if repoRef.len == 0 and repoTreeRef.len == 0:
    printHelp()
    quit(2)
  if repoRef.len > 0 and repoTreeRef.len > 0:
    errOut("ERROR: --ref와 --tree는 상호 배타입니다 (대상은 하나뿐)")
    quit(2)
  if repoTreeRef.len > 0:
    repoRef = repoTreeRef

  var w = Walker(repoRoot: repoDir, repoRef: repoRef)
  let root = findRepoRoot(repoDir)
  if root.len == 0:
    errOut("ERROR: --repo에 git 저장소 없음: " & repoDir)
    quit(2)
  w.repoRoot = root

  if repoTreeRef.len > 0:
    # --tree 모드 (Amendment F 제3각): 트리 객체 직접 검증 — `^{commit}` 펠은
    # 트리에 대해 실패하므로 `^{tree}`로 검증한다. ls-tree는 이후 트리 OID를
    # 그대로 받고 blob 내용은 cat-file이 직독한다 (순수 트리 함수 — 결정론).
    let (tchk, tchkCode) = git(w.repoRoot,
      "rev-parse --verify --quiet " & quoteShell(repoRef & "^{tree}"))
    if tchkCode != 0 or tchk.strip().len == 0:
      errOut("ERROR: --tree 존재하지 않음 또는 트리 아님: " & repoRef)
      quit(2)
  else:
    let (chk, chkCode) = git(w.repoRoot,
      "rev-parse --verify --quiet " & quoteShell(repoRef & "^{commit}"))
    if chkCode != 0 or chk.strip().len == 0:
      errOut("ERROR: --ref 존재하지 않음 또는 커밋 아님: " & repoRef)
      quit(2)

  if not w.snapshotTree():
    errOut("ERROR: git ls-tree 실패 (ref=" & repoRef & ")")
    quit(2)

  w.parseMakefile()        # (b) ci/checker.mk 타깃/제품/변수 테이블
  w.walkMakefileShellDirectives()  # checker.mk $(shell ...) 파싱 시 실행
  w.addSeeds()             # (c) 정적 시드
  w.walkWorkflow()         # (a) run: 블록 전수
  w.dedupUnresolved()

  if w.unresolved.len > 0:
    errOut("")
    errOut("UNRESOLVED — 정적으로 소거 불가한 호출 (" & $w.unresolved.len & "건):")
    for u in w.unresolved:
      errOut("  [" & u.origin & "] " & u.reason)
      errOut("      " & u.line)
    errOut("")
    errOut("FAIL — closure 불완전 (fail-closed, 구멍 12). exit 1.")
    quit(1)

  try:
    stdout.write(emitClosure(w))
  except IOError:
    quit(1)

when isMainModule:
  main()