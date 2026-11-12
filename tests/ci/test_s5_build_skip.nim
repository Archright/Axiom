## test_s5_build_skip.nim — S5 verified-supply build-skip contract (J3 §3.1)
##
## 대상: .github/workflows/admission-check.yml job1(build-base-artifacts)의
## S5 슬라이스 — landing venue에서 B-restore가 검증 OK(HIT)면 컴파일 블록을
## 생략하고 복원된 검증 payload를 공급으로 사용한다. 계약 고정점:
##
##   * s5-supply 판정 스텝이 정확히 1개, toolchain 액션 직후·probe 스텝 직전에
##     존재하고, 자신은 mode 중립(sl08 ∧ landing 게드만) — 판정자가 판정에
##     종속되면 순환이다;
##   * 컴파일 경로 3스텝(nimcache probe / Lake smoke / Build)만
##     mode == 'build' 컨정크트를 가진다 — manifest emit과 업로드 2종은
##     양 모두에서 실행(아티팩트 계약: job2·mint·publisher가 manifest.txt를
##     fail-closed 소비);
##   * 명시적 판정 라인 필수 — HIT는 "SUPPLY REUSE —", MISS/폐기는
##     "S5 COLD BUILD —" (플랫폼은 skipped 스텝을 success로 계수하므로
##     조용한 skip은 극장, §0.9);
##   * 판정 불변 — job2(attest/verdict)의 어떤 스텝도 mode 컨정크트를 갖지
##     않는다 (생략은 컴파일 공급뿐);
##   * Q4 — 새 run 본문(주석 포함)에 보간 토큰 없음 (workflow 파싱 사망 방지).
##
## 실행 시뮬레이션은 스텝 본문을 YAML에서 원문 추출해 실행한다
## (test_b_cache_anchor.nim·test_admission_venue_split.nim 선례):
##   (a) HIT — 전 payload 존재 → mode=skip + SUPPLY REUSE 라인 + emit 성공
##       (manifest가 supply 5종 + verdict-predicate 2종 = 7멤버를 digest 결속 —
##       업로드 payload 완결; 7멤버 확장 90085d96b 2026-10-12 toolchain-handoff)
##   (b) MISS — payload 부재(전체/부분: nimcache·ircheck 결손) → mode=build
##       + COLD 라인 (부분 결손도 콜드 — publisher 빈 캐리어 방어)
##   (c) verify FAIL 폐기 — 액션 discard_b가 남기는 상태(fingerprint 잔존,
##       바이너리·nimcache 삭제) → mode=build (콜드 폴백)
##   (d) 판정 스텝 불변 — mode 컨정크트 보유 스텝 집합이 컴파일 3종으로
##       정확히 닫힘 + job2 무접촉
##   (e) emit fail-closed — 빌드 없는 MISS 상태에서 emit은 실패(무증 아티팩트
##       조용히 생성 불가)
##
## freeze 태그는 로컬 전용이다(push-admissibility 게이트가 historical OID 태그
## push를 fail-closed — 2026-10-11 실측). 태그가 없는 클론에서는 freeze 대비
## 테스트가 [SKIPPED]로 결정적 강등된다 — 조용한 통과 아님(§0.9).
##
## fixture는 임시 디렉터리(/tmp)에서 만들며 작업 저장소를 건드리지 않는다.

import std/[unittest, os, osproc, strutils, strtabs]

const
  AdmissionRel = ".github/workflows/admission-check.yml"
  BuildJob = "build-base-artifacts"
  CheckJob = "admission-check"
  ## L3 split (2026-11-04): job2a 스코프 — mode 컨정크트 캐리어 스캔 확장용.
  ## job2a는 S5 공급(mode build)을 소비하지 않는다(핀된 사실: 캐리어 0건).
  ## 이 잡이 build-mode 컨정크트를 얻으면 아래 "집합 닫힘" 테스트가 red.
  IndependentsJob = "admission-independents"
  FreezeTag = "ci-frozen-2026-10-09-venue-split"
  Landing = "steps.venue.outputs.venue == 'landing'"
  ModeBuild = "steps.s5-supply.outputs.mode == 'build'"
  Sl08 = "steps.slice-engine.outputs.scope_sl08 == 'true'"
  SupplyLine = "SUPPLY REUSE — verified payload restored; compile skipped (ADR-0032/J3 §3.1)"
  ColdLine = "S5 COLD BUILD — verified supply absent"
  CompilePathSteps = [
    "[build] nimcache functional probe",
    "[build] Lake build smoke",
    "[build] Build bin/ax + harness from B",
  ]
  SupplyFiles = [
    "bin/ax", "bin/gate_hook", "bin/precompile_gates", "bin/install_ax_cas",
    "proofs/.lake/build/bin/ircheck",
  ]
  # emit 전용 멤버 — S5 판정기가 검사하지 않는다(판정 시점엔 부재). 양 모드에서
  # emit 직전에 무조건 새로 생산되는 verdict-predicate payload(90085d96b
  # 2026-10-12 toolchain-handoff; workflow 주석 "Manifest covers exactly the
  # 7 members")이므로 manifest 결속 검증은 이 둘을 포함한 7멤버가 정본이다.
  EmitOnlyFiles = [
    "bin/derive_checker_closure", "bin/jq",
  ]

proc repoRoot(): string =
  ## tests/ci/ → 저장소 루트
  result = absolutePath(currentSourcePath())
  for _ in 0 ..< 3:
    result = result.parentDir()

var pyCounter = 0

proc pyRun(scriptBody: string; args: varargs[string]): tuple[outp: string; code: int] =
  ## python3 한 스크립트 실행 — args는 sys.argv[1..]
  inc pyCounter
  let py = getTempDir() / ("s5_py_" & $getCurrentProcessId() & "_" & $pyCounter & ".py")
  writeFile(py, scriptBody)
  var cmd = "python3 " & quoteShell(py)
  for a in args:
    cmd.add(" " & quoteShell(a))
  let (outp, code) = execCmdEx(cmd)
  removeFile(py)
  result.outp = outp
  result.code = code

proc pyFail(outp: string) =
  doAssert false, "python extraction 실패: " & outp

type
  Step = tuple[idx: int, name, guard, uses: string]

proc stepsOfJob(path, job: string): seq[Step] =
  ## 단일 job의 스텝을 TSV로 추출: idx \t name \t if \t uses
  const Script = """
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
for i, s in enumerate(d['jobs'][sys.argv[2]].get('steps', [])):
    name = s.get('name', '')
    guard = s.get('if', '') or ''
    uses = s.get('uses', '') or ''
    row = [str(i), name, ' '.join(guard.split()), uses]
    print('\t'.join(row))
"""
  let (outp, code) = pyRun(Script, path, job)
  if code != 0: pyFail(outp)
  for line in outp.splitLines():
    if line.strip() == "": continue
    let cols = line.split('\t')
    doAssert cols.len == 4, "unexpected TSV row: " & line
    result.add((parseInt(cols[0]), cols[1], cols[2], cols[3]))

proc stepNamed(path, job, namePrefix: string): Step =
  ## 정확히 하나여야 한다 — 이름이 사라지거나 복제되면 모호해지므로 raise
  var found = 0
  for s in stepsOfJob(path, job):
    if s.name.startsWith(namePrefix):
      result = s
      inc found
  if found != 1:
    raise newException(ValueError,
      "step '" & namePrefix & "' occurs " & $found & " time(s) in " & path & "/" & job)

proc stepRun(path, job, namePrefix: string): string =
  ## 스텝 run 본문을 yaml로 추출 — 원문 그대로 (선례 테스트와 동일)
  const Script = """
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
steps = d['jobs'][sys.argv[2]]['steps']
hits = [s for s in steps if s.get('name', '').startswith(sys.argv[3])]
if len(hits) != 1:
    sys.exit('expected exactly one step, got %d' % len(hits))
print(hits[0].get('run', ''), end='')
"""
  let (outp, code) = pyRun(Script, path, job, namePrefix)
  if code != 0: pyFail(outp)
  result = outp

proc stepWithPath(path, job, namePrefix: string): string =
  ## 스텝 with.path 블록을 원문 추출 (업로드 payload 계약 고정용)
  const Script = """
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
steps = d['jobs'][sys.argv[2]]['steps']
hits = [s for s in steps if s.get('name', '').startswith(sys.argv[3])]
if len(hits) != 1:
    sys.exit('expected exactly one step, got %d' % len(hits))
w = hits[0].get('with', {}) or {}
print(str(w.get('path', '')), end='')
"""
  let (outp, code) = pyRun(Script, path, job, namePrefix)
  if code != 0: pyFail(outp)
  result = outp

proc runGit(args: string): string =
  let (outp, code) = execCmdEx("git -C " & quoteShell(repoRoot()) & " " & args)
  doAssert code == 0, "git " & args & " 실패: " & outp
  result = outp

proc freezeTagMissing(): bool =
  ## freeze 태그 부재 판정. freeze 태그는 로컬 전용 관례다 — historical OID
  ## 태그의 push는 push-admissibility 게이트가 fail-closed 심사한다(2026-10-11
  ## 실측: 6개 태그 전원 FAIL — docs/evidence/freeze_tag_reproducibility_2026-10-11.md).
  let (_, code) = execCmdEx("git -C " & quoteShell(repoRoot()) &
    " rev-parse -q --verify refs/tags/" & FreezeTag)
  result = code != 0

proc frozenFile(rel: string): string =
  ## freeze 대비 원문 조회. 부재 시 호출층은 unittest skip()으로 결정적 강등한다
  ## ([SKIPPED] — 조용한 통과 아님, §0.9). skip()은 실행을 중단하지 않으므로
  ## 호출층이 부재 경로를 먼저 닫아야 한다. 태그가 있으면 단정은 무변경 실행된다.
  result = runGit("show " & quoteShell(FreezeTag & ":" & rel))

var ghCounter = 0

proc runStep(body, workdir: string, extraEnv: seq[(string, string)]): tuple[outp: string, code: int, ghOut: string] =
  ## 스텝 본문을 workdir에서 실행 — GITHUB_OUTPUT은 임시 파일로 수집
  inc ghCounter
  let ghOutPath = getTempDir() / ("s5_gh_out_" & $getCurrentProcessId() & "_" & $ghCounter)
  writeFile(ghOutPath, "")
  let cmdEnv = newStringTable(modeCaseInsensitive)
  for k, v in envPairs():
    if k != "GITHUB_OUTPUT":
      cmdEnv[k] = v
  cmdEnv["GITHUB_OUTPUT"] = ghOutPath
  for (k, v) in extraEnv:
    cmdEnv[k] = v
  let script = getTempDir() / ("s5_step_" & $getCurrentProcessId() & "_" & $ghCounter & ".sh")
  writeFile(script, body)
  let (outp, code) = execCmdEx("cd " & quoteShell(workdir) & " && bash " & quoteShell(script),
                               env = cmdEnv)
  removeFile(script)
  result.outp = outp
  result.code = code
  result.ghOut = readFile(ghOutPath)
  removeFile(ghOutPath)

proc ghOutputValue(ghOut, key: string): string =
  for line in ghOut.splitLines():
    if line.startsWith(key & "="):
      return line[(key.len+1) .. ^1]

proc sha256Of(path: string): string =
  let (outp, code) = execCmdEx("sha256sum " & quoteShell(path))
  doAssert code == 0, "sha256sum 실패: " & outp
  result = outp.splitWhitespace()[0]

var fixtureCounter = 0

proc makeHitFixture(): string =
  ## 검증 HIT 세계의 fixture: 복원 payload 전체(4 바이너리 + ircheck +
  ## fingerprint manifest + nimcache 클래스) — 실행 비트 포함
  inc fixtureCounter
  let root = getTempDir() / "s5_hit_" & $getCurrentProcessId() & "_" & $fixtureCounter
  createDir(root / "bin")
  createDir(root / "build/nimcache/m")
  createDir(root / "proofs/.lake/build/bin")
  writeFile(root / "Makefile", "fixture-makefile\n")
  for rel in SupplyFiles:
    writeFile(root / rel, "fake verified binary " & rel & "\n")
    discard execCmdEx("chmod +x " & quoteShell(root / rel))
  writeFile(root / "build/nimcache/m/cached.nimcache.json", "{}\n")
  writeFile(root / "build/.axiom-b-fingerprint.json", "{\"schema\": \"axiom-b-fingerprint-v1\"}\n")
  result = root

proc removeAllContents(root: string) =
  ## 액션 discard_b와 동일한 삭제 집합을 시뮬레이트한다 — build/nimcache
  ## .axiom/cache proofs/.lake proofs/build + 4 바이너리. discard_b는
  ## build/.axiom-b-fingerprint.json을 삭제하지 않는다(원문 사실 — (c)의
  ## 트리거 상태를 이 사실과 정확히 일치시킨다).
  removeDir(root / "build/nimcache")
  if dirExists(root / ".axiom/cache"): removeDir(root / ".axiom/cache")
  removeDir(root / "proofs/.lake")
  if dirExists(root / "proofs/build"): removeDir(root / "proofs/build")
  for b in ["ax", "gate_hook", "precompile_gates", "install_ax_cas"]:
    removeFile(root / ("bin/" & b))

let root = repoRoot()
let admissionPath = root / AdmissionRel

suite "S5 — s5-supply judgment step structure (판정자는 mode 중립)":

  test "s5-supply step exists exactly once, after the toolchain action, before the probe":
    let steps = stepsOfJob(admissionPath, BuildJob)
    let s5 = stepNamed(admissionPath, BuildJob, "[s5] Supply-mode judgment")
    check s5.uses == ""  # plain run step
    var idxAction = -1
    var idxProbe = -1
    for i, s in steps:
      if s.uses.endsWith("setup-axiom-toolchain"): idxAction = i
      if s.name.startsWith("[build] nimcache functional probe"): idxProbe = i
    check idxAction >= 0 and idxProbe >= 0
    check s5.idx == idxAction + 1  # 액션(복원/검증/폐기) 직후 — 판정 입력은 디스크 상태
    check s5.idx < idxProbe

  test "s5-supply guard is sl08 ∧ landing only — the judge never depends on its own verdict":
    let s5 = stepNamed(admissionPath, BuildJob, "[s5] Supply-mode judgment")
    check s5.guard == Sl08 & " && " & Landing
    check ModeBuild notin s5.guard

  test "exactly the 3 compile-path steps carry the build-mode conjunct (집합 닫힘)":
    var carriers: seq[string] = @[]
    for s in stepsOfJob(admissionPath, BuildJob) & stepsOfJob(admissionPath, CheckJob) &
        stepsOfJob(admissionPath, IndependentsJob):
      if s.guard.contains(ModeBuild):
        carriers.add(s.name)
    check carriers.len == 3
    for want in CompilePathSteps:
      var hit = 0
      for c in carriers:
        if c.startsWith(want): inc hit
      check hit == 1

  test "manifest emit + both uploads run in BOTH modes (아티팩트 계약 — 컨정크트 없음)":
    for name in ["[build] Emit fail-closed artifact manifest",
                 "[build] Upload base-built artifacts",
                 "[build] Upload base-tree nimcache"]:
      let s = stepNamed(admissionPath, BuildJob, name)
      check s.guard.contains(Landing)
      check ModeBuild notin s.guard

  test "compile-path guards keep the exact pre-S5 prefix (게드 의미 불변 — venue split 계약 연속)":
    for name in CompilePathSteps:
      let s = stepNamed(admissionPath, BuildJob, name)
      check s.guard == Sl08 & " && " & Landing & " && " & ModeBuild

  test "upload payload contract unchanged vs freeze (이름·경로 — publisher/mint 소비 표면)":
    if freezeTagMissing():
      echo "[freeze-tag-missing] ", FreezeTag,
        " — freeze 대비 검증 SKIPPED. 복구: git fetch origin tag ", FreezeTag
      skip()
    else:
      let frozenContent = frozenFile(AdmissionRel)
      let frozenPath = getTempDir() / ("s5_frozen_" & $getCurrentProcessId() & "_admission.yml")
      writeFile(frozenPath, frozenContent)
      for step in @["[build] Upload base-built artifacts",
                    "[build] Upload base-tree nimcache"]:
        let cur = stepWithPath(admissionPath, BuildJob, step)
        let fro = stepWithPath(frozenPath, BuildJob, step)
        check cur == fro
      check "manifest.txt" in stepWithPath(admissionPath, BuildJob, "[build] Upload base-built artifacts")
      check "build/nimcache" in stepWithPath(admissionPath, BuildJob, "[build] Upload base-tree nimcache")
      removeFile(frozenPath)

suite "S5 — judgment lines + fail-closed directions (본문 원문 고정)":

  test "both explicit judgment lines exist in the s5 body (조용한 skip 금지 — §0.9)":
    let body = stepRun(admissionPath, BuildJob, "[s5] Supply-mode judgment")
    check SupplyLine in body
    check ColdLine in body
    check "mode=skip" in body and "mode=build" in body

  test "the s5 body checks presence AND executability of every supply member":
    let body = stepRun(admissionPath, BuildJob, "[s5] Supply-mode judgment")
    for rel in SupplyFiles:
      check rel in body
    check "build/nimcache" in body
    check "build/.axiom-b-fingerprint.json" in body
    # -f(존재)와 -x(실행비트) 양방향 루프 + nimcache 디렉터리 검사 — 부분 복원·
    # 비트 소실 모두 콜드로
    check "[ -f " in body
    check "[ -x " in body
    check "[ -d build/nimcache ]" in body

  test "Q4 — no interpolation token in the S-touched compile-path run bodies (주석 포함)":
    ## 보간 토큰은 셸 전에 치환된다 — 주석에만 있어도 워크플로 파싱이 죽는다
    ## (quirk Q4). 본 슬라이스가 만진 run 본문을 스캔한다. emit 스텝은 예외다 —
    ## build_sha 이벤트 보간은 의도된 원문 계약이므로 (freeze 대비 불변).
    let q4token = "$" & "{{"
    for name in @CompilePathSteps & @["[s5] Supply-mode judgment"]:
      let body = stepRun(admissionPath, BuildJob, name)
      check q4token notin body

  test "emit step's build_sha interpolation is the only event expression in job1 supply steps":
    let body = stepRun(admissionPath, BuildJob, "[build] Emit fail-closed artifact manifest")
    check body.count("$" & "{{") == 1  # build_sha 단일 — 우발적 이중 보간 방지

suite "S5 — execution simulation (스텝 본문 원문 실행)":

  proc s5Body(): string =
    stepRun(admissionPath, BuildJob, "[s5] Supply-mode judgment")

  proc emitBody(): string =
    ## emit 스텝 본문 — build_sha 이벤트 식만 env 치환 (venue 선례와 동일 방식).
    ## 치환 원문은 workflow의 build_sha 표현식과 정확히 일치해야 한다 — 현재 식은
    ## inputs.baseSha 최우선 소비 형태(728096965 2026-10-13, Stage 2 단일 앵커
    ## B*). baseSha는 workflow_call input(required:false, 기본값 '')이므로
    ## 미전달 run에서는 빈 문자열=falsy로 payload 표현식에 폴백한다(GitHub 공식
    ## 문서: inputs context는 reusable workflow에서만 존재, 공실은 falsy).
    stepRun(admissionPath, BuildJob, "[build] Emit fail-closed artifact manifest").replace(
      "${{ inputs.baseSha || github.event.pull_request.base.sha || github.event.merge_group.base_sha || github.sha }}",
      "${AXIOM_TEST_B}")

  test "(a) HIT — 전 payload 존재 → mode=skip + SUPPLY REUSE 라인":
    let root = makeHitFixture()
    defer: removeDir(root)
    let r = runStep(s5Body(), root, @[])
    check r.code == 0
    check ghOutputValue(r.ghOut, "mode") == "skip"
    check SupplyLine in r.outp
    check "S5 COLD BUILD" notin r.outp

  test "(a2) HIT 이어받기 — emit이 supply 5종 + verdict-predicate 2종을 digest 결속 (업로드 payload 완결)":
    let root = makeHitFixture()
    defer: removeDir(root)
    discard runStep(s5Body(), root, @[])
    # emit 시점 상태 재현 — verdict-predicate 2종은 S5 판정 이후·emit 이전에
    # 양 모드에서 무조건 생산된다(deriver compile + pinned jq fetch 스텝) —
    # 판정 시점 fixture(SupplyFiles 5종)에는 없고 emit 시점에는 존재한다.
    for rel in EmitOnlyFiles:
      writeFile(root / rel, "fresh verdict-predicate member " & rel & "\n")
      discard execCmdEx("chmod +x " & quoteShell(root / rel))
    let r = runStep(emitBody(), root, @[("AXIOM_TEST_B", "b" & repeat('0', 39))])
    check r.code == 0
    let manifest = readFile(root / "manifest.txt")
    check ("build_sha = b" & repeat('0', 39)) in manifest
    for rel in @SupplyFiles & @EmitOnlyFiles:
      let line = sha256Of(root / rel) & "  " & rel
      check line in manifest  # 7멤버 전원의 실제 digest 결속 (업로드 payload 완결)

  test "(b) MISS — payload 전체 부재 → mode=build + COLD 라인":
    let root = getTempDir() / ("s5_miss_" & $getCurrentProcessId())
    createDir(root)
    writeFile(root / "Makefile", "fixture-makefile\n")
    defer: removeDir(root)
    let r = runStep(s5Body(), root, @[])
    check r.code == 0
    check ghOutputValue(r.ghOut, "mode") == "build"
    check ColdLine in r.outp
    check "SUPPLY REUSE" notin r.outp

  test "(b2) MISS 부분 결손 — 바이너리·fingerprint는 있어도 nimcache 부재 → mode=build (빈 캐리어 방어)":
    let root = makeHitFixture()
    defer: removeDir(root)
    removeDir(root / "build/nimcache")
    let r = runStep(s5Body(), root, @[])
    check ghOutputValue(r.ghOut, "mode") == "build"
    check ColdLine in r.outp

  test "(b3) MISS 부분 결손 — ircheck 부재 → mode=build (attest 커널 무공급 방어)":
    let root = makeHitFixture()
    defer: removeDir(root)
    removeFile(root / "proofs/.lake/build/bin/ircheck")
    let r = runStep(s5Body(), root, @[])
    check ghOutputValue(r.ghOut, "mode") == "build"

  test "(b4) 실행비트 소실 — 존재하지만 non-exec → mode=build (캐시 비트 보존 스냅샷 오류 방어)":
    let root = makeHitFixture()
    defer: removeDir(root)
    discard execCmdEx("chmod -x " & quoteShell(root / "bin/gate_hook"))
    let r = runStep(s5Body(), root, @[])
    check ghOutputValue(r.ghOut, "mode") == "build"
    check "not executable: bin/gate_hook" in r.outp

  test "(c) verify FAIL 폐기 상태 — discard_b 잔존물(fingerprint만 남음) → mode=build (콜드 폴백)":
    ## 액션 b-verify/probe의 discard_b는 4 바이너리·nimcache·lake를 지우고
    ## build/.axiom-b-fingerprint.json은 남긴다(원문 사실) — 그 정확한 상태에서
    ## 판정이 콜드로 떨어지는 것을 고정한다 (조용한 skip 없음).
    let root = makeHitFixture()
    defer: removeDir(root)
    removeAllContents(root)
    check not fileExists(root / "bin/ax")
    check fileExists(root / "build/.axiom-b-fingerprint.json")  # discard_b 원문 사실
    let r = runStep(s5Body(), root, @[])
    check r.code == 0
    check ghOutputValue(r.ghOut, "mode") == "build"
    check ColdLine in r.outp

  test "(e) emit fail-closed — 빌드 없는 MISS 상태에서 emit은 실패한다 (무증 아티팩트 차단)":
    let root = getTempDir() / ("s5_emitfc_" & $getCurrentProcessId())
    createDir(root)
    writeFile(root / "Makefile", "fixture-makefile\n")
    defer: removeDir(root)
    let r = runStep(emitBody(), root, @[("AXIOM_TEST_B", "c" & repeat('0', 39))])
    check r.code != 0
    check "missing or not executable" in r.outp
