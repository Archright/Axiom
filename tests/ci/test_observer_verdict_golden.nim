## test_observer_verdict_golden.nim — manifest-consistency-gate 구조화 verdict
## 골든 계약 (observer-verdict slice PR-β1, ADR-0033 관측 오라클).
##
## 고정 계약:
##   1. 무인자 경로 바이트 불변 — 같은 트리에서 플래그 없는 실행 2회:
##      stdout·stderr·exit code가 바이트 단위로 동일해야 한다. stdout은
##      공란(legacy 계약: 로그는 전부 stderr, Makefile check-manifest-consistency는
##      exit 코드만 소비).
##   2. --json 경로 — 실행 2회의 stdout 바이트 동일(재실행 결정론) + 고정키
##      순서(verdict → violations → judgmentKey → fault_cause; 패턴 선례:
##      layer_enforcement_gate.renderJson, check-layer-negative의 rc AND
##      verdict 라인 이중 단언) + 정확히 1줄.
##   3. 통과 트리에서 verdict == "PASS", fault_cause == "".
##
## 실행 환경: 커밋된 pass_control fixture를 tmpdir로 복사해 workingDir 격리
## 서브프로세스로 실행한다(게이트는 CWD 상대 경로 하드코딩 — 저장소 상태와
## 무관하게 결정론).
##
## 실행: nim c -r --hints:off tests/ci/test_observer_verdict_golden.nim
## Exit: 0 = 전 구간 PASS, 1 = 계약 위반.

import std/[os, osproc, strutils, json, streams]

const
  GateSource = "src/gate/runners/manifest_consistency_gate.nim"
  FixtureRel = "tests/negative/observer_manifest_gate/pass_control"
  JsonKeys = ["\"verdict\": ", "\"violations\": ", "\"judgmentKey\": ",
              "\"fault_cause\": "]

var
  gateBin = ""
  passed = 0
  failed = 0

template ck(label: string; cond: bool) =
  if cond:
    inc passed
    echo "  PASS: " & label
  else:
    inc failed
    echo "  FAIL: " & label

template sk(name: string) =
  echo ""
  echo "── " & name & " ──"

proc repoRoot(): string =
  result = absolutePath(currentSourcePath())
  for _ in 0 ..< 3:
    result = result.parentDir()

proc compileGate(): string =
  let bin = getTempDir() / "obs_golden_gate_" & $getCurrentProcessId()
  let root = repoRoot()
  # Makefile NIM_TOOL_FLAGS 미러: 게이트는 checksums/fusion nimble 패키지를
  # 임포트하므로 pkgs2 경로를 명시 주입한다 (wildcard → 런타임 열거).
  var pkgPaths = ""
  let pkgsDir = getHomeDir() / ".nimble" / "pkgs2"
  if dirExists(pkgsDir):
    for kind, path in walkDir(pkgsDir):
      if kind == pcDir:
        let name = path.extractFilename()
        if name.startsWith("checksums-") or name.startsWith("fusion-"):
          pkgPaths &= " --path:" & quoteShell(path)
  let (outp, code) = execCmdEx(
    "nim c --hints:off --skipParentCfg --skipProjCfg --path:" & quoteShell(root / "src") &
    " --path:" & quoteShell(root) & " --path:" & quoteShell(root / "tools") &
    pkgPaths &
    " -o:" & quoteShell(bin) & " " & quoteShell(root / GateSource))
  if code != 0:
    echo outp
  doAssert code == 0, "게이트 컴파일 실패: " & GateSource
  result = bin

proc makeFixtureDir(): string =
  ## 커밋된 pass_control fixture를 tmpdir로 복사 (SSOT = 커밋된 디렉터리).
  let dir = getTempDir() / "obs_golden_tree_" & $getCurrentProcessId()
  removeDir(dir)
  copyDir(repoRoot() / FixtureRel, dir)
  result = dir

proc runGate(args: seq[string]; workingDir: string):
    tuple[stdout, stderr: string, code: int] =
  ## workingDir 격리 서브프로세스 — stdout/stderr 개별 캡처.
  let p = startProcess(gateBin, workingDir = workingDir, args = args,
                       options = {poUsePath})
  let outp = readAll(p.outputStream)
  let errp = readAll(p.errorStream)
  let code = p.waitForExit()
  p.close()
  result = (outp, errp, code)

proc main =
  gateBin = compileGate()
  let tree = makeFixtureDir()
  defer: removeDir(tree)

  sk "무인자 경로 바이트 불변 (2회 실행 대조)"
  let r1 = runGate(@[], tree)
  let r2 = runGate(@[], tree)
  ck "no-arg exit 코드 재현 (" & $r1.code & ")", r1.code == r2.code
  ck "no-arg stdout 바이트 동일 (" & $r1.stdout.len & "B)", r1.stdout == r2.stdout
  ck "no-arg stderr 바이트 동일 (" & $r1.stderr.len & "B)", r1.stderr == r2.stderr
  ck "no-arg exit 0 (건강 트리)", r1.code == 0
  ck "no-arg stdout 공란 (legacy 계약 — 로그는 stderr)", r1.stdout.len == 0
  ck "no-arg stderr 로그 존재", r1.stderr.len > 0

  sk "--json 고정키 순서 + 재실행 결정론"
  let j1 = runGate(@["--json"], tree)
  let j2 = runGate(@["--json"], tree)
  ck "json exit 코드 재현", j1.code == j2.code
  ck "json stdout 바이트 동일", j1.stdout == j2.stdout
  ck "json exit 0 (건강 트리)", j1.code == 0
  let lines = j1.stdout.splitLines()
  ck "json stdout 정확히 1줄 (" & $(lines.len - 1) & "줄)",
     lines.len == 2 and lines[1] == ""

  var orderOk = true
  var lastPos = -1
  for k in JsonKeys:
    let pos = j1.stdout.find(k)
    if pos < 0 or pos <= lastPos:
      orderOk = false
    lastPos = pos
  ck "고정키 순서 verdict→violations→judgmentKey→fault_cause", orderOk

  let verdict = parseJson(j1.stdout)
  ck "verdict == PASS", verdict{"verdict"}.getStr("") == "PASS"
  ck "violations == []", verdict{"violations"}.kind == JArray and
     verdict{"violations"}.len == 0
  ck "judgmentKey == gate id + 입력 요약",
     verdict{"judgmentKey"}.getStr("").startsWith("manifest-consistency-gate|")
  ck "fault_cause == \"\" (PASS)", verdict{"fault_cause"}.getStr("x") == ""

  echo ""
  echo "══════════════════════════════════════════════════════════"
  echo "Observer-verdict golden: $# passed, $# failed" % [$passed, $failed]
  echo "══════════════════════════════════════════════════════════"
  if failed > 0:
    quit(1)
  quit(0)

main()
