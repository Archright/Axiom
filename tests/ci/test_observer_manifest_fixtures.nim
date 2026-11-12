## test_observer_manifest_fixtures.nim — 관측 오라클 음성 주입 fixture 3종
## (증거 클래스 E-B: 위반 클래스별 1회 — ADR-0033 승격 증거 계약).
##
## fixture SSOT = 커밋된 디렉터리 (tests/negative/observer_manifest_gate/):
##   pass_control/                  건강 트리 → rc 0 + verdict "PASS"
##   violation_unregistered_runner/ 위반 1종 (Check 6: 미등록 러너, V7류)
##                                  → rc != 0 + verdict "WOULD-BLOCK"
##   fault_probe/                   내부결함 1종 (F2: 스키마 파일 삭제 —
##                                  조기 quit 경로) → rc != 0 + verdict
##                                  "OBSERVER-FAULT" + fault_cause "gate"
##
## 실행 방식: tmpdir 격리 서브프로세스 (게이트 루트 주입 없음 — 게이트는
## CWD 상대 경로 하드코딩이므로 fixture 트리를 tmpdir에 만들고 workingDir을
## 거기로 설정한다). 선례: tests/ci/test_verify_b_artifact.nim(makeFixture/
## defer removeDir) + check-layer-negative의 "rc AND verdict 라인" 이중 단언.
##
## 계약: exit 코드는 플래그 유무 공통(0/1); OBSERVER-FAULT는 --json 실행의
## verdict 필드로만 구분된다(임의 exit 2 없음).
##
## 실행: nim c -r --hints:off tests/ci/test_observer_manifest_fixtures.nim
## Exit: 0 = 전 구간 PASS, 1 = 계약 위반.

import std/[os, osproc, strutils, json, streams]

const
  GateSource = "src/gate/runners/manifest_consistency_gate.nim"
  FixtureRoot = "tests/negative/observer_manifest_gate"

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
  let bin = getTempDir() / "obs_fix_gate_" & $getCurrentProcessId()
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

proc makeFixtureTree(name: string): string =
  ## 커밋된 fixture 디렉터리를 tmpdir로 복사 — 격리 실행 트리 생성.
  let dir = getTempDir() / "obs_fix_" & name & "_" & $getCurrentProcessId()
  removeDir(dir)
  copyDir(repoRoot() / FixtureRoot / name, dir)
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

proc checkFixture(name: string; wantVerdict: string; wantRcZero: bool;
                  wantFaultCause: string; violationNeedle: string) =
  sk name & " → rc " & (if wantRcZero: "0" else: "!= 0") & " + " & wantVerdict
  let tree = makeFixtureTree(name)
  defer: removeDir(tree)

  # --json 실행: verdict 필드 판정 (rc AND verdict 이중 단언)
  let (outp, _, code) = runGate(@["--json"], tree)
  if wantRcZero:
    ck name & ": rc == 0", code == 0
  else:
    ck name & ": rc != 0 (got " & $code & ")", code != 0
  if outp.len == 0:
    ck name & ": --json stdout 존재", false
    return
  let v = parseJson(outp)
  ck name & ": verdict == " & wantVerdict,
     v{"verdict"}.getStr("") == wantVerdict
  ck name & ": fault_cause == \"" & wantFaultCause & "\"",
     v{"fault_cause"}.getStr("x") == wantFaultCause
  if violationNeedle.len > 0:
    var found = false
    for item in v{"violations"}:
      if item.getStr("").contains(violationNeedle):
        found = true
    ck name & ": violations에 \"" & violationNeedle & "\" 포함", found

  # 무인자(legacy) 실행: exit 계약 공통 — verdict 필드 없이 rc만 소비
  let legacy = runGate(@[], tree)
  if wantRcZero:
    ck name & ": legacy rc == 0", legacy.code == 0
  else:
    ck name & ": legacy rc != 0 (got " & $legacy.code & ")", legacy.code != 0
  ck name & ": legacy stdout 공란 (바이트 불변 계약)", legacy.stdout.len == 0

proc main =
  gateBin = compileGate()

  checkFixture("pass_control", "PASS", true, "", "")
  checkFixture("violation_unregistered_runner", "WOULD-BLOCK", false, "",
               "missing manifest entry for runner")
  checkFixture("fault_probe", "OBSERVER-FAULT", false, "gate", "")

  echo ""
  echo "══════════════════════════════════════════════════════════"
  echo "Observer manifest fixtures: $# passed, $# failed" % [$passed, $failed]
  echo "══════════════════════════════════════════════════════════"
  if failed > 0:
    quit(1)
  quit(0)

main()
