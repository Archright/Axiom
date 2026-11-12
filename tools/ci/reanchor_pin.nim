import core/trusted/layer_declaration
axiomLayer "tools"

## reanchor_pin.nim — rotation pin 재앵커 writer + 로컬 H2 preflight.
##
## 판정은 여기서 재구현하지 않는다. 파싱·비교 술어의 SSOT는 공유 leaf 모듈
## core/policy/rotation_closure_facts (parseDerivedSet / pinClosureLineSet /
## newAnchorVerdict)이며, merge_cli(landing Pass 2.75)와
## rotation_pin_anchor_check(preflight)가 소비하는 **동일 컴파일 구현**이다.
## 이 도구는 CLI 표면 + 트리 I/O + 텍스트 재작성만 소유한다
## (rotation_pin_anchor_check.nim / derive_checker_closure.nim과 같은 venue
## split: seconds-class build, cli/merge_cli import 금지).
##
## 두 venue에서 같은 사실을 쓴다:
##   - preflight(fail-fast): remote CI가 보기 전에 pin@ref != derived(ref)를
##     로컬에서 차단한다. `.githooks/pre-push`가 OID별로 호출한다.
##   - writer: drift가 값 변화뿐일 때 pin 문서를 제자리에서 재앵커한다.
##
## Usage:
##   reanchor_pin --ref <git-ref> [--repo <dir>] [--derived <file>] [--write]
##
##     --ref <git-ref>   H. pin은 **그 ref의 트리**에서 읽는다
##                       (`git show <ref>:config/trusted_writer_set.json`) —
##                       워킹 트리를 읽으면 커밋되지 않은 편집이 판정에 섞인다.
##     --repo <dir>      git 저장소 루트 (기본: cwd에서 .git 탐색)
##     --derived <file>  이미 유도된 closure linetext (CI 아티팩트 재사용).
##                       생략 시 bin/derive_checker_closure를 같은 ref로 실행.
##     --write           drift를 pin 문서에 반영한다. **기본은 dry-run**.
##                       값(mode/type/sha) 갱신만 한다 — 멤버 추가/삭제는
##                       사람의 결정이므로 exit 3으로 거부하고 아무것도 쓰지 않는다.
##
## stdout: drift 1건당 한 줄 + 요약 1줄 (경로 정렬, 결정론).
##   changed <path> <old-sha> -> <new-sha>
##   missing-from-pin <path> <sha>      (pin에 없는 derived 멤버)
##   pin-only <path> <sha>              (derived에 없는 pin 멤버)
##   OK no-drift
## stderr: 입력 계약 진단.
## exit: 0 = pin@ref가 derived(ref)를 앵커함 (또는 --write 성공)
##       1 = dry-run에서 drift 검출 (판정 — fail-closed 아님)
##       2 = 입력 계약 위반 (ref/파일/JSON(C) 파싱 — fail-closed, 판정 없음)
##       3 = 멤버십 변경 (자동 재앵커 거부, 파일 무변경)
##
## 재작성은 전체 재직렬화가 아니라 **표적 치환**이다: pin 문서는 수백 줄의
## JSONC 주석을 담고 있어 재직렬화는 리뷰 불가능한 diff를 만든다. 치환 후
## 결과를 다시 파싱해 line-set == derived를 자기검증하고, 불일치면 쓰지 않는다.

import std/[algorithm, json, options, os, osproc, parseopt, sets, strutils]
import core/results
import core/policy/rotation_closure_facts
import core/trusted/stdlib_shield  # safeMoveFile: moveFile 예외 격리의 기존 shim 재사용

const
  ToolName* = "reanchor_pin"
  ## rotation pin 문서의 트리 상대 경로 (B/H 공통 identity).
  PinPath* = RotationPinBPath
  ## H closure 유도자 — 단일 derivation authority (ADR C2).
  DeriverBin* = "bin/derive_checker_closure"

  ExitOk* = 0               ## pin@ref anchors derived(ref) (또는 --write 성공)
  ExitDrift* = 1            ## dry-run: drift 검출
  ExitInputViolation* = 2   ## 입력 계약 위반 — fail-closed, 판정 없음
  ExitMembershipChange* = 3 ## 멤버 추가/삭제 — 자동 재앵커 거부

type
  DriftKind* = enum
    dkValueChanged     ## 같은 경로, 다른 라인 (mode/type/sha 중 무엇이든)
    dkMissingFromPin   ## derived에 있고 pin에 없음 — 핀에 멤버 추가 필요
    dkOnlyInPin        ## pin에 있고 derived에 없음 — 핀에서 멤버 삭제 필요

  DriftEntry* = object
    kind*: DriftKind
    path*: string
    oldLine*: string   ## pin 라인 (dkMissingFromPin이면 "")
    newLine*: string   ## derived 라인 (dkOnlyInPin이면 "")

  Outcome* = object
    exitCode*: int
    ## stdout 본문 (exit 0/1/3) 또는 stderr 진단 (exit 2).
    text*: string
    drift*: seq[DriftEntry]
    ## --write 성공 시 재작성된 pin 전문 (I/O 계층이 원자적으로 교체한다).
    newPinText*: Option[string]

# ---------------------------------------------------------------------------
# Pure core — drift 계산 (공유 모듈 술어 위에서만 동작)
# ---------------------------------------------------------------------------

func shaOf*(line: string): string {.raises: [].} =
  ## `<mode> <type> <sha>\t<path>` → sha (진단 출력 전용).
  let t = line.find('\t')
  if t < 0:
    return ""
  let head = line[0 ..< t]
  let s = head.rfind(' ')
  if s < 0: "" else: head[s + 1 .. ^1]

func headField*(line: string; idx: int): string {.raises: [].} =
  ## `<mode> <type> <sha>\t<path>`의 tab 앞 3필드 중 idx번째.
  let t = line.find('\t')
  let head = if t < 0: line else: line[0 ..< t]
  var
    i = 0
    start = 0
    n = 0
  while i <= head.len:
    if i == head.len or head[i] == ' ':
      if n == idx:
        return head[start ..< i]
      inc n
      start = i + 1
    inc i
  ""

type PathLine = tuple[path, line: string]

func sortedPathLines(lines: HashSet[string]): seq[PathLine] {.raises: [].} =
  ## 경로 오름차순 정렬 — Hash 집합의 열거 순서를 출력 순서로 쓰지 않는다.
  for ln in lines:
    result.add((path: closurePathFromLine(ln), line: ln))
  result.sort(proc(a, b: PathLine): int = cmp(a.path, b.path))

func computeDrift*(derivedH: HashSet[string]; pinH: Option[HashSet[string]]):
    seq[DriftEntry] {.raises: [].} =
  ## derived(H)와 pin@H의 line-set 차이를 경로 단위로 분류한다. 정렬된 두
  ## 시퀀스의 병합 비교이므로 출력은 구조적으로 경로 순서이고, 키 조회
  ## 예외(KeyError) 경로가 없다.
  ## pin 키 부재(genesis)는 "모든 멤버가 pin에 없음"으로 나타난다 — 즉
  ## genesis는 멤버십 변경(exit 3)이며 자동 재앵커로 통과되지 않는다
  ## (ADR-0025 §7 one-time genesis exception은 사람이 세운다).
  let pin = if pinH.isSome: pinH.get else: initHashSet[string]()
  let
    d = sortedPathLines(derivedH)
    p = sortedPathLines(pin)
  var
    i = 0
    j = 0
  while i < d.len or j < p.len:
    if j >= p.len or (i < d.len and d[i].path < p[j].path):
      result.add DriftEntry(kind: dkMissingFromPin, path: d[i].path,
                            newLine: d[i].line)
      inc i
    elif i >= d.len or p[j].path < d[i].path:
      result.add DriftEntry(kind: dkOnlyInPin, path: p[j].path,
                            oldLine: p[j].line)
      inc j
    else:
      if d[i].line != p[j].line:
        result.add DriftEntry(kind: dkValueChanged, path: d[i].path,
                              oldLine: p[j].line, newLine: d[i].line)
      inc i
      inc j

# ---------------------------------------------------------------------------
# Pure core — pin 문서의 표적 재작성 (JSONC 주석/포맷 바이트 보존)
# ---------------------------------------------------------------------------

func replaceValue(line, key, newVal: string): string {.raises: [].} =
  ## `      "sha": "abc",` → 같은 라인의 값만 교체 (들여쓰기/쉼표 보존).
  ## 형태가 예상과 다르면 "" (호출자가 fail-closed로 처리).
  let ki = line.find("\"" & key & "\"")
  if ki < 0:
    return ""
  let colon = line.find(':', ki + key.len + 2)
  if colon < 0:
    return ""
  let q1 = line.find('"', colon + 1)
  if q1 < 0:
    return ""
  let q2 = line.find('"', q1 + 1)
  if q2 < 0:
    return ""
  line[0 .. q1] & newVal & line[q2 .. ^1]

func rewriteEntry*(text: string; entry: DriftEntry): Result[string, string] {.
    raises: [].} =
  ## changed 1건의 mode/type/sha를 텍스트에서 표적으로 교체한다.
  ## 키 경로의 출현이 정확히 1회가 아니면 거부한다 — 주석 안의 동일 문자열에
  ## 쓰는 사고를 막는 fail-closed 가드다.
  let keyPat = "\"" & entry.path & "\":"
  var
    start = -1
    hits = 0
  let lines = text.splitLines()
  for i, ln in lines:
    if ln.strip().startsWith(keyPat):
      start = i
      inc hits
  if hits != 1:
    return err("pin entry '" & entry.path & "' key occurrences=" & $hits &
      " (expected exactly 1 — refusing to guess)")
  let
    newMode = headField(entry.newLine, 0)
    newType = headField(entry.newLine, 1)
    newSha = shaOf(entry.newLine)
  if newMode.len == 0 or newType.len == 0 or newSha.len == 0:
    return err("malformed derived line for '" & entry.path & "'")
  var outLines = lines
  if outLines.len > 0 and outLines[^1].len == 0:
    # splitLines는 종료 개행 뒤에 빈 원소를 하나 남긴다 — 개행은 아래에서
    # 한 번만 복원한다 (그대로 두면 join이 개행을 하나 더 만든다).
    outLines.setLen(outLines.len - 1)
  var
    found = 0
    i = start + 1
  let limit = min(start + 6, lines.high)
  while i <= limit:
    let s = outLines[i].strip()
    if s.startsWith("}"):
      break  # 항목 블록 끝 — 다음 항목의 필드를 삼키지 않는다
    if s.startsWith("\"mode\":"):
      let v = replaceValue(outLines[i], "mode", newMode)
      if v.len == 0:
        return err("cannot rewrite mode of '" & entry.path & "'")
      outLines[i] = v
      inc found
    elif s.startsWith("\"type\":"):
      let v = replaceValue(outLines[i], "type", newType)
      if v.len == 0:
        return err("cannot rewrite type of '" & entry.path & "'")
      outLines[i] = v
      inc found
    elif s.startsWith("\"sha\":"):
      let v = replaceValue(outLines[i], "sha", newSha)
      if v.len == 0:
        return err("cannot rewrite sha of '" & entry.path & "'")
      outLines[i] = v
      inc found
    inc i
  if found != 3:
    return err("pin entry '" & entry.path & "' block has " & $found &
      "/3 fields (mode/type/sha) — unexpected document shape")
  var joined = outLines.join("\n")
  if text.endsWith("\n"):
    joined.add("\n")
  ok(joined)

proc parsePinNode*(text: string): Result[JsonNode, string] {.raises: [].} =
  ## trusted_writer_set 문서는 JSONC 주석을 담는다 — strip 후 파싱한다.
  ## 파싱 실패는 입력 계약 위반(err)이며, closure 키 부재(genesis)와 다르다.
  ## (ok/err 템플릿은 호출자의 result 타입에 결속되므로 전용 func이 필요하다.)
  try:
    ok(parseJson(stripJsoncComments(text)))
  except CatchableError as e:
    err("malformed JSON(C): " & e.msg)

proc applyWrite*(pinText: string; derivedH: HashSet[string];
                 drift: seq[DriftEntry]): Result[string, string] {.raises: [].} =
  ## changed 전건을 치환한 새 텍스트를 만들고, **다시 파싱해**
  ## line-set == derived(H)를 자기검증한다. 검증 실패 = 아무것도 쓰지 않는다.
  var outText = pinText
  for e in drift:
    if e.kind != dkValueChanged:
      return err("applyWrite called with a membership change for '" & e.path & "'")
    let r = rewriteEntry(outText, e)
    if r.isErr:
      return err(r.err)
    outText = r.get
  let reparsed = parsePinNode(outText)
  if reparsed.isErr:
    return err(reparsed.err)
  let verified = pinClosureLineSet(reparsed.get)
  if verified.isErr:
    return err("rewritten pin failed the shared pin predicate: " & verified.err)
  if verified.get.isNone or verified.get.get != derivedH:
    return err("self-check failed: rewritten pin line-set != derived(H) — refusing to write")
  ok(outText)

# ---------------------------------------------------------------------------
# Pure core — 판정 (텍스트 → Outcome). I/O 없음.
# ---------------------------------------------------------------------------

proc evaluateTexts*(derivedText, pinText, refName: string; write: bool):
    Outcome {.raises: [].} =
  ## 세 텍스트 → 종료코드 + 본문. 입력 계약 위반은 판정 **이전에** exit 2로
  ## 끝난다 (malformed 입력은 run-level 실패이지 H2 verdict가 아니다).
  let derived = parseDerivedSet(derivedText)
  if derived.isErr:
    return Outcome(exitCode: ExitInputViolation,
                   text: "input contract violation: derived: " & derived.err)
  let pinNode = parsePinNode(pinText)
  if pinNode.isErr:
    return Outcome(exitCode: ExitInputViolation,
                   text: "input contract violation: pin: " & pinNode.err)
  let pinSet = pinClosureLineSet(pinNode.get)
  if pinSet.isErr:
    return Outcome(exitCode: ExitInputViolation,
                   text: "input contract violation: pin: " & pinSet.err)
  let drift = computeDrift(derived.get, pinSet.get)
  if drift.len == 0:
    return Outcome(exitCode: ExitOk,
                   text: "OK no-drift — pin@" & refName & " anchors derived(" & refName & ")")

  var body = ""
  var
    valueChanged = 0
    missing = 0
    only = 0
  for e in drift:
    case e.kind
    of dkValueChanged:
      inc valueChanged
      body.add "changed " & e.path & " " & shaOf(e.oldLine) & " -> " & shaOf(e.newLine) & "\n"
    of dkMissingFromPin:
      inc missing
      body.add "missing-from-pin " & e.path & " " & shaOf(e.newLine) & "\n"
    of dkOnlyInPin:
      inc only
      body.add "pin-only " & e.path & " " & shaOf(e.oldLine) & "\n"
  let summary = "DRIFT changed=" & $valueChanged & " missing-from-pin=" & $missing &
                " pin-only=" & $only

  if missing > 0 or only > 0:
    return Outcome(exitCode: ExitMembershipChange,
                   text: body & summary &
                     "\nREFUSED: closure membership changed — the pin's member set is a human" &
                     " decision (ADR-0025 §7), not a value update. No file written.",
                   drift: drift)

  if write:
    let rewritten = applyWrite(pinText, derived.get, drift)
    if rewritten.isErr:
      return Outcome(exitCode: ExitInputViolation,
                     text: "write refused: " & rewritten.err, drift: drift)
    return Outcome(exitCode: ExitOk,
                   text: body & summary & "\nWROTE " & PinPath &
                     " — commit the updated pin, then re-run without --write.",
                   drift: drift, newPinText: some(rewritten.get))

  Outcome(exitCode: ExitDrift,
          text: body & summary & "\nrun: reanchor_pin --ref " & refName & " --write",
          drift: drift)

# ---------------------------------------------------------------------------
# I/O boundary — git(트리 전용) / deriver / 파일
# ---------------------------------------------------------------------------

proc runGit*(repoRoot, args: string): tuple[outp: string, code: int] {.raises: [].} =
  try:
    let r = execCmdEx("git -C " & quoteShell(repoRoot) & " " & args)
    (outp: r.output, code: r.exitCode)
  except CatchableError:
    (outp: "", code: 1)

proc findRepoRoot*(start: string): string {.raises: [].} =
  ## `.git`(디렉터리 또는 worktree 파일)을 만나는 첫 상위 디렉터리.
  result = start
  for _ in 0 ..< 10:
    let g = result / ".git"
    if dirExists(g) or fileExists(g):
      return
    let parent = result.parentDir()
    if parent == result:
      return ""
    result = parent

proc readDerived*(repoRoot, refName, derivedPath: string): Result[string, string] {.
    raises: [].} =
  ## --derived가 있으면 그 파일, 없으면 bin/derive_checker_closure를 같은 ref로
  ## 실행한다. 둘 다 실패하면 입력 계약 위반 (판정 없음).
  if derivedPath.len > 0:
    try:
      return ok(readFile(derivedPath))
    except CatchableError as e:
      return err("cannot read --derived '" & derivedPath & "': " & e.msg)
  let deriver = repoRoot / DeriverBin
  if not fileExists(deriver):
    return err("deriver missing: " & deriver &
      " (build: nim c -d:danger --hints:off -d:axiomNoLto -o:" & DeriverBin &
      " tools/ci/derive_checker_closure.nim)")
  let cmd = quoteShell(deriver) & " --ref " & quoteShell(refName) &
            " --repo " & quoteShell(repoRoot)
  var run: tuple[output: string, exitCode: int]
  try:
    run = execCmdEx(cmd)
  except CatchableError as e:
    return err("deriver invocation failed: " & e.msg)
  if run.exitCode != 0:
    return err("derive_checker_closure exited " & $run.exitCode & " for ref '" &
      refName & "' (UNRESOLVED/usage — fail-closed): " & run.output.strip())
  ok(run.output)

proc readPinAt*(repoRoot, refName: string): Result[string, string] {.raises: [].} =
  ## pin@ref — **그 ref의 트리**에서 읽는다. 워킹 트리를 읽으면 커밋되지 않은
  ## 편집이 판정에 섞여 preflight와 CI가 갈라진다.
  let r = runGit(repoRoot, "show " & quoteShell(refName & ":" & PinPath))
  if r.code != 0:
    return err("cannot read " & PinPath & " at '" & refName & "' (git show exit " &
      $r.code & "): " & r.outp.strip())
  ok(r.outp)

proc writePinAtomically*(repoRoot, text: string): Result[string, string] {.
    raises: [].} =
  let target = repoRoot / PinPath
  let tmp = target & ".reanchor.tmp"
  try:
    writeFile(tmp, text)
  except CatchableError as e:
    return err("cannot write '" & tmp & "': " & e.msg)
  try:
    safeMoveFile(tmp, target)
  except CatchableError as e:
    try:
      safeRemoveFile(tmp)
    except CatchableError: # bestEffort("""temp-file cleanup — the primary failure is the move""")
      discard
    return err("cannot replace '" & target & "': " & e.msg)
  ok(target)

# ---------------------------------------------------------------------------
# CLI surface
# ---------------------------------------------------------------------------

type
  ReanchorArgs* = object
    refName*: string
    repoDir*: string
    derivedPath*: string
    write*: bool

proc parseReanchorArgs*(args: seq[string]): Result[ReanchorArgs, string] {.
    raises: [].} =
  ## `--ref`(필수), `--repo`, `--derived`, `--write`(플래그). 그 외는 거부.
  var
    refName, repoDir, derivedPath: string
    write = false
  var p = initOptParser(args)
  while true:
    p.next()
    case p.kind
    of cmdEnd:
      break
    of cmdLongOption, cmdShortOption:
      let key = p.key
      if key == "write":
        write = true
        continue
      if key notin ["ref", "repo", "derived"]:
        return err("unknown option '--" & key & "'")
      var val = p.val
      if val.len == 0:
        p.next()
        if p.kind != cmdArgument:
          return err("option '--" & key & "' requires a value")
        val = p.key
      case key
      of "ref":
        refName = val
      of "repo":
        repoDir = val
      of "derived":
        derivedPath = val
      else:
        return err("unknown option '--" & key & "'")
    of cmdArgument:
      return err("unexpected argument '" & p.key & "'")
  if refName.len == 0:
    return err("missing required --ref <git-ref>")
  ok(ReanchorArgs(refName: refName, repoDir: repoDir,
                  derivedPath: derivedPath, write: write))

func usage*(): string {.raises: [].} =
  ToolName & " — rotation pin 재앵커 writer + 로컬 H2 preflight\n" &
  "  " & ToolName & " --ref <git-ref> [--repo <dir>] [--derived <file>] [--write]\n" &
  "  --ref <git-ref>   대상 H (pin은 그 ref의 트리에서 읽는다)\n" &
  "  --repo <dir>      git 저장소 루트 (기본: cwd에서 .git 탐색)\n" &
  "  --derived <file>  이미 유도된 closure linetext (기본: bin/derive_checker_closure --ref)\n" &
  "  --write           drift를 pin에 반영 (기본 dry-run)\n" &
  "exit: 0=anchored, 1=drift(dry-run), 2=input contract violation, 3=membership change"

proc emitDiagnostic(line: string) {.raises: [].} =
  try:
    stderr.writeLine(ToolName & ": " & line)
  except CatchableError: # bestEffort("""diagnostic stream unavailable — the exit code is the contract""")
    discard

proc runReanchor*(args: seq[string]): int {.raises: [].} =
  ## CLI 진입: 인자 → 유도 → 판정 → (--write) 원자적 교체.
  ## exit 2는 stderr, 그 외 판정 본문은 stdout.
  if args.len == 0:
    try:
      stderr.writeLine(usage())
    except CatchableError: # bestEffort("""diagnostic stream unavailable — the exit code is the contract""")
      discard
    return ExitInputViolation
  let parsed = parseReanchorArgs(args)
  if parsed.isErr:
    emitDiagnostic(parsed.err)
    return ExitInputViolation
  let a = parsed.get
  var repoRoot = a.repoDir
  if repoRoot.len == 0:
    let cwd = try: getCurrentDir() except OSError: "."
    repoRoot = findRepoRoot(cwd)
  if repoRoot.len == 0 or not dirExists(repoRoot):
    emitDiagnostic("not a git repository (--repo '" & a.repoDir &
      "' / cwd walk found no .git)")
    return ExitInputViolation
  if runGit(repoRoot, "rev-parse --git-dir").code != 0:
    emitDiagnostic("not a git repository: '" & repoRoot & "' (git rev-parse --git-dir failed)")
    return ExitInputViolation
  let derived = readDerived(repoRoot, a.refName, a.derivedPath)
  if derived.isErr:
    emitDiagnostic("input contract violation: " & derived.err)
    return ExitInputViolation
  let pinText = readPinAt(repoRoot, a.refName)
  if pinText.isErr:
    emitDiagnostic("input contract violation: " & pinText.err)
    return ExitInputViolation
  let outcome = evaluateTexts(derived.get, pinText.get, a.refName, a.write)
  if outcome.newPinText.isSome:
    let w = writePinAtomically(repoRoot, outcome.newPinText.get)
    if w.isErr:
      emitDiagnostic(w.err)
      return ExitInputViolation
  try:
    if outcome.exitCode == ExitInputViolation:
      stderr.writeLine(ToolName & ": " & outcome.text)
    else:
      stdout.writeLine(outcome.text)
  except CatchableError: # bestEffort("""output stream unavailable — the exit code is the contract, the text is advisory""")
    discard
  outcome.exitCode

when isMainModule:
  quit(runReanchor(commandLineParams()))