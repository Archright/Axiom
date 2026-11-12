## test_l3_guard_fail_closed.nim — L3 needs-result 가드 fail-closed 계약
## (사전등록 docs/evidence/l3_go_prereg_2026-11-03.md §2.4)
##
## 대상: .github/workflows/admission-check.yml의 L3 분할 — attest 스테이지의
## GO-독립 4스텝(core purity / admission identity / D9 / register)이 병렬 잡
## `admission-independents`로 이동한 뒤, 잔여 `admission-check` 잡의 [guard]
## 스텝이 direct needs 3종의 실행 결과를 명시 판정한다. 고정 계약:
##
##   * 양면 oracle — 플랫폼 의미론: 스킵된 잡은 Success로 보고되어 병합을
##     막지 않고, 기본 needs 전파는 실패한 need에 대해 이 잡 자체를 스킵
##     시킨다(가려진 green). 따라서 가드는 「needs 전부 success ⇒ GREEN,
##     그 외 모든 상태 ⇒ RED(판정 귀속 포함)」의 양면을 입증해야 한다 —
##     정상 입력까지 거부하면 죽은 게이트(§0.8), 잘못된 입력을 하나라도
##     통과시키면 극장(§0.9).
##   * 가드는 venue 스텝 직후(잡 내 최초 판정 스텝)·attest+landing 전용 —
##     preflight(레인 합법 스킵)·verdict(레인 무소비) 의미론 보존.
##   * 가드 env는 잡의 direct needs와 정확히 일대일 대응 — 커버 안 된
##     need는 가려진 green 구멍이다.
##   * 잡 if는 !cancelled() — 가드가 판정할 수 있는 생존 전제(취소 배치는
##     병합 불가 상태로 남는다, §2.4).
##   * 이동 4스텝은 cut-not-copy(잔여 잡 부재) + 본문 해시가 사전분할
##     세대(50d781e82, PR #1262 merge)에 핀 — 향후 의도적 수정은 해시
##     갱신을 요구한다(조용한 의미 드리프트 차단).
##   * 값 채널(잡 env 7종 ← needs outputs)·파일 채널(아티팩트명 후보
##     HEAD+run_attempt 결속, upload/download 원문 동일, 누락=에러,
##     continue-on-error 금지, 업로드 성공시에만, subject 저장소 포함
##     — §6.5 결함의 로컬 검출 핀)·witness `:?` 공실 red.
##
## 실행 시뮬레이션은 스텝 run 본문을 YAML에서 원문 추출해 실행한다
## (test_s5_build_skip.nim·test_sl02_consumer_binding.nim 선례 — production
## bash, 재구현 아님). 가드 본문은 무보간(값은 스텝 env가 실으며, 하니스가
## GitHub Actions와 동일하게 공급한다).

import std/[unittest, os, osproc, strutils, strtabs]

const
  AdmissionRel = ".github/workflows/admission-check.yml"
  CheckJob = "admission-check"
  IndependentsJob = "admission-independents"
  # 사전분할 세대 — 이동 4스텝 본문 해시의 원천(2026-11-04 L3 split 직전,
  # PR #1262 merge tip). 의도적 본문 수정 시 해시 상수를 갱신+사유 기록.
  PreSplitGen = "50d781e82f6a90058a610dc92db99453ea3fd676"
  GuardPrefix = "[guard] Every direct need must be success"
  VenuePrefix = "[venue] Resolve execution venue"
  ExportPrefix = "[independents] Export identity values"
  UploadPrefix = "[independents] Upload evidence chain"
  DownloadPrefix = "[check] Download admission-independents evidence"
  WitnessPrefix = "[check] Attest witness-only"
  GuardIf = "inputs.stage == 'attest' && steps.venue.outputs.venue == 'landing'"
  MovedSteps = [
    "[check] Core purity gate",
    "[check] Re-derive admission identity",
    "[check] Stage D9 evidence",
    "[check] Register subject",
  ]
  MovedHashes = [
    "c99c993ba78baaa78c0257c1aec7078b5daee6aaedd8e4457a3470147ee17974",
    "5627c901a314f5631c04a3b9fb00e56e22c35a8154e6722ced24be039d9bd411",
    "d158262c8a9740973c2f21eb1f2189b692517c7acc68f524d04a1f1fba50b309",
    "f422b2e25960196a97304195173ed3e315e15a23a6d070bbb2d60dd65d7c599f",
  ]
  ValueKeys = [
    "b", "h", "head_tree_oid", "merge_tree_oid", "subject_head",
    "subject_head_tree_oid", "subject_id",
  ]
  # 잡 env 이름(대문자 — witness가 소비하던 원래 GITHUB_ENV 이름)과
  # job outputs 키(소문자)의 병렬 대응 — 동일 값이 같은 이름 규칙으로 흐른다.
  EnvNames = [
    "B", "H", "HEAD_TREE_OID", "MERGE_TREE_OID", "SUBJECT_HEAD",
    "SUBJECT_HEAD_TREE_OID", "SUBJECT_ID",
  ]
  PassLine = "[guard] PASS"
  FailLine = "[guard] FAIL"

proc repoRoot(): string =
  ## tests/ci/ → 저장소 루트
  result = absolutePath(currentSourcePath())
  for _ in 0 ..< 3:
    result = result.parentDir()

var pyCounter = 0

proc pyRun(scriptBody: string; args: varargs[string]): tuple[outp: string; code: int] =
  inc pyCounter
  let py = getTempDir() / ("l3_py_" & $getCurrentProcessId() & "_" & $pyCounter & ".py")
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

proc stepIdxName(path, job, namePrefix: string): tuple[idx: int, name: string] =
  ## 스텝 색인+이름 — 정확히 하나여야 한다
  const Script = """
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
steps = d['jobs'][sys.argv[2]].get('steps', [])
hits = [(i, s.get('name', '')) for i, s in enumerate(steps)
        if s.get('name', '').startswith(sys.argv[3])]
if len(hits) != 1:
    sys.exit('expected exactly one step, got %d' % len(hits))
print('%d\t%s' % hits[0])
"""
  let (outp, code) = pyRun(Script, path, job, namePrefix)
  if code != 0: pyFail(outp)
  let cols = outp.strip().split('\t')
  doAssert cols.len == 2, "unexpected row: " & outp
  result = (parseInt(cols[0]), cols[1])

proc stepCount(path, job, namePrefix: string): int =
  ## 해당 접두 스텝의 출현 수
  const Script = """
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
steps = d['jobs'][sys.argv[2]].get('steps', [])
print(sum(1 for s in steps if s.get('name', '').startswith(sys.argv[3])))
"""
  let (outp, code) = pyRun(Script, path, job, namePrefix)
  if code != 0: pyFail(outp)
  result = parseInt(outp.strip())

proc stepField(path, job, namePrefix, field: string): string =
  ## 스텝의 임의 스칼라 필드(if / continue-on-error / …) — 공백 결합
  const Script = """
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
steps = d['jobs'][sys.argv[2]]['steps']
hits = [s for s in steps if s.get('name', '').startswith(sys.argv[3])]
if len(hits) != 1:
    sys.exit('expected exactly one step, got %d' % len(hits))
v = hits[0].get(sys.argv[4], '')
print(' '.join(str(v).split()), end='')
"""
  let (outp, code) = pyRun(Script, path, job, namePrefix, field)
  if code != 0: pyFail(outp)
  # execCmdEx는 출력을 줄 단위로 정규화한다 — end='' 출력에도 정확히
  # 1개의 trailing newline이 붙는다(docs/spec/nim_2_2_10_stdlib_quirks.md
  # Q-012: printf 'abc' → "abc\n"). ' '.join(split()) 결과에 의미 있는
  # 선행/후행 공백은 존재할 수 없으므로 strip이 안전하다.
  result = outp.strip()

proc jobField(path, job, field: string): string =
  ## 잡 레벨 스칼라 필드(needs는 공백 결합, if는 접힘 결합)
  const Script = """
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
j = d['jobs'][sys.argv[2]]
v = j.get(sys.argv[3], '')
if isinstance(v, list):
    print(' '.join(str(x) for x in v), end='')
else:
    print(' '.join(str(v).split()), end='')
"""
  let (outp, code) = pyRun(Script, path, job, field)
  if code != 0: pyFail(outp)
  # stepField와 동일한 execCmdEx 줄 정규화 quirk — strip으로 흡수.
  result = outp.strip()

proc mapLines(path, job, namePrefix, field: string): seq[tuple[k, v: string]] =
  ## 잡 레벨(outputs/env; namePrefix == "") 또는 스텝 레벨(env/with) 매핑을
  ## key\tvalue 행으로 — 정렬 순 (python yaml 원문 추출).
  const Script = """
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
if sys.argv[3] == '':
    m = d['jobs'][sys.argv[2]].get(sys.argv[4], {}) or {}
else:
    steps = d['jobs'][sys.argv[2]]['steps']
    hits = [s for s in steps if s.get('name', '').startswith(sys.argv[3])]
    if len(hits) != 1:
        sys.exit('expected exactly one step, got %d' % len(hits))
    m = hits[0].get(sys.argv[4], {}) or {}
for k in sorted(m):
    print(k + '\t' + ' '.join(str(m[k]).split()))
"""
  let (outp, code) = pyRun(Script, path, job, namePrefix, field)
  if code != 0: pyFail(outp)
  for line in outp.splitLines():
    if line.strip() == "": continue
    let cols = line.split('\t')
    doAssert cols.len == 2, "unexpected map row: " & line
    result.add((cols[0], cols[1]))

proc valueOf(m: seq[tuple[k, v: string]]; key: string): string =
  ## 매핑에서 키의 값 (부재 시 "")
  for kv in m:
    if kv.k == key: return kv.v

proc sha256Of(path: string): string =
  let (outp, code) = execCmdEx("sha256sum " & quoteShell(path))
  doAssert code == 0, "sha256sum 실패: " & outp
  result = outp.splitWhitespace()[0]

var shCounter = 0

proc runGuard(body: string; needs: tuple[bb, lanes, indep: string]): tuple[outp: string; code: int] =
  ## 가드 본문을 production 그대로 실행 — 값은 GitHub Actions가 실을
  ## 스텝 env를 하니스가 동일하게 공급한다(본문 무보간).
  inc shCounter
  let script = getTempDir() / ("l3_guard_" & $getCurrentProcessId() & "_" & $shCounter & ".sh")
  writeFile(script, body)
  let env = newStringTable(modeCaseInsensitive)
  for k, v in envPairs():
    env[k] = v
  env["NEED_BUILD_BASE"] = needs.bb
  env["NEED_GO_LANES"] = needs.lanes
  env["NEED_INDEPENDENTS"] = needs.indep
  let (outp, code) = execCmdEx("bash " & quoteShell(script), env = env)
  removeFile(script)
  result = (outp, code)

let root = repoRoot()
let admissionPath = root / AdmissionRel

suite "L3 — structure (가드 배치·배선·생존 전제)":

  test "가드는 [venue] 직후(잡 내 최초 판정 스텝)에 정확히 1회 존재":
    check stepCount(admissionPath, CheckJob, GuardPrefix) == 1
    let v = stepIdxName(admissionPath, CheckJob, VenuePrefix)
    let g = stepIdxName(admissionPath, CheckJob, GuardPrefix)
    check g.idx == v.idx + 1

  test "가드 if는 attest+landing 정확히 이 조합 — preflight/verdict 불발화":
    check stepField(admissionPath, CheckJob, GuardPrefix, "if") == GuardIf

  test "가드 env는 잡의 direct needs 3종과 정확히 일대일 (커버리지 닫힘)":
    let needs = jobField(admissionPath, CheckJob, "needs")
    check needs == "build-base-artifacts go-critical-lane admission-independents"
    let env = mapLines(admissionPath, CheckJob, GuardPrefix, "env")
    check env == @[
      ("NEED_BUILD_BASE", "${{ needs.build-base-artifacts.result }}"),
      ("NEED_GO_LANES", "${{ needs.go-critical-lane.result }}"),
      ("NEED_INDEPENDENTS", "${{ needs.admission-independents.result }}"),
    ]

  test "admission-check 잡 if는 !cancelled() — 가드가 판정할 생존 전제":
    let jif = jobField(admissionPath, CheckJob, "if")
    check "!cancelled()" in jif
    check "always()" notin jif

  test "job2a(admission-independents): needs build-base 단일·attest 전용·!cancelled()":
    check jobField(admissionPath, IndependentsJob, "needs") == "build-base-artifacts"
    let jif = jobField(admissionPath, IndependentsJob, "if")
    check "!cancelled()" in jif
    check "inputs.stage == 'attest'" in jif
    check "verdict" notin jif

  test "이동 4스텝은 job2a에 정확히 1회·잔여 잡에는 부재 (cut-not-copy)":
    for m in MovedSteps:
      check stepCount(admissionPath, IndependentsJob, m) == 1
      check stepCount(admissionPath, CheckJob, m) == 0

  test "이동 4스텝 본문 해시는 사전분할 세대에 핀 (의미 드리프트 차단)":
    ## 항 값: 2026-11-04 split 시점에 사전분할 세대 원문에서 계산됨.
    check PreSplitGen.len == 40
    for i, m in MovedSteps:
      let tmp = getTempDir() / ("l3_body_" & $getCurrentProcessId() & "_" & $i & ".yml.run")
      writeFile(tmp, stepRun(admissionPath, IndependentsJob, m))
      defer: removeFile(tmp)
      check sha256Of(tmp) == MovedHashes[i]

  test "값 채널: 잡 env 7종 ← needs outputs 매핑·export는 7값 승격":
    let jobEnv = mapLines(admissionPath, CheckJob, "", "env")
    let jobOut = mapLines(admissionPath, IndependentsJob, "", "outputs")
    check jobEnv.len == 7 and jobOut.len == 7
    for i, k in ValueKeys:
      check (EnvNames[i], "${{ needs.admission-independents.outputs." & k & " }}") in jobEnv
      check (k, "${{ steps.independents-export.outputs." & k & " }}") in jobOut
    let exp = stepRun(admissionPath, IndependentsJob, ExportPrefix)
    for k in ValueKeys:
      check (k & "=${" & k.toUpperAscii() & ":-}") in exp

  test "파일 채널: 업/다운로드명 원문 동일·run_attempt 결속·누락=에러·soft-fail 금지":
    ## 2026-11-04 subject-store 재핀 (docs/evidence/l3_go_split_impl_
    ## 2026-11-04.md §6.5): 파일 채널은 이동 Register-subject 스텝의 소비
    ## 입력 전부 — evidence 기록(--evidence)과 subject 저장소
    ## (findSubjectsByHeadSha) — 를 전달해야 한다. evidence만 전달하던
    ## 원 핀은 신세대 merge_group 전체를 witness red로 만들었다.
    ## 업로드는 다중 경로(LCA data/trusted 루팅), 다운로드는 data/trusted
    ## 복원 — 경로 핀이 이 결함 클래스를 로컬에서 잡는다.
    let up = mapLines(admissionPath, IndependentsJob, UploadPrefix, "with")
    let dl = mapLines(admissionPath, CheckJob, DownloadPrefix, "with")
    check up.len == 4 and dl.len == 2  # upload: name/path/if-no-files-found/retention
    let upName = valueOf(up, "name")
    let dlName = valueOf(dl, "name")
    check upName == dlName                      # 같은 run 안 같은 이름만 소비 가능
    check upName.startsWith("admission-independents-")
    check "github.run_attempt" in upName        # 재시도 세대 구분 (v4 불변명)
    check valueOf(dl, "path") == "data/trusted"
    check valueOf(up, "path") == "data/trusted/evidence/*.json data/trusted/subjects/*.json"
    check valueOf(up, "if-no-files-found") == "error"  # 증발 파일 = red
    check stepField(admissionPath, CheckJob, DownloadPrefix, "continue-on-error") == ""
    check stepField(admissionPath, IndependentsJob, UploadPrefix, "continue-on-error") == ""
    check "always()" notin stepField(admissionPath, IndependentsJob, UploadPrefix, "if")

  test "witness는 잔여 잡에 잔류 + 공실 SUBJECT_ID red 보존 (`:?`)":
    check stepCount(admissionPath, CheckJob, WitnessPrefix) == 1
    check stepCount(admissionPath, IndependentsJob, WitnessPrefix) == 0
    let wb = stepRun(admissionPath, CheckJob, WitnessPrefix)
    check ":?SUBJECT_ID not set" in wb

  test "Q4 — 가드 run 본문에 보간 토큰 없음":
    let gb = stepRun(admissionPath, CheckJob, GuardPrefix)
    check ("$" & "{{") notin gb

suite "L3 — guard 본문 양면 oracle (원문 실행)":

  proc guardBody(): string =
    stepRun(admissionPath, CheckJob, GuardPrefix)

  test "GREEN — needs 전부 success ⇒ 통과 (죽은 게이트 아님)":
    let r = runGuard(guardBody(), ("success", "success", "success"))
    check r.code == 0
    check PassLine in r.outp
    check FailLine notin r.outp

  test "RED 격자 — need 3종 × 비정상 5상태 전수 (귀속 포함)":
    const
      Vars = [
        ("NEED_BUILD_BASE", "build-base-artifacts"),
        ("NEED_GO_LANES", "go-critical-lane"),
        ("NEED_INDEPENDENTS", "admission-independents"),
      ]
      Bads = ["failure", "cancelled", "skipped", "", "Success"]
    for (envVar, wfName) in Vars:
      for bad in Bads:
        var n: tuple[bb, lanes, indep: string] = ("success", "success", "success")
        case envVar
        of "NEED_BUILD_BASE": n.bb = bad
        of "NEED_GO_LANES": n.lanes = bad
        else: n.indep = bad
        let r = runGuard(guardBody(), n)
        check r.code != 0
        check FailLine in r.outp
        check ("needs." & wfName & ".result") in r.outp
        check PassLine notin r.outp

  test "RED — 전 needs 동시 비정상도 red (최초 판정에서 즉시 차단)":
    let r = runGuard(guardBody(), ("failure", "cancelled", "skipped"))
    check r.code != 0
    check FailLine in r.outp

  test "RED — env 미공급(unbound)도 비종료 아님 (set -u 즉사 red)":
    ## GitHub는 result를 항상 4값 중 하나로 공급하지만, 공급 누락 자체가
    ## 조용한 통과로 이어져서는 안 된다 — set -u가 즉시 비정상 종료시킨다.
    inc shCounter
    let script = getTempDir() / ("l3_guard_unset_" & $getCurrentProcessId() & "_" & $shCounter & ".sh")
    writeFile(script, guardBody())
    let env = newStringTable(modeCaseInsensitive)
    for k, v in envPairs():
      env[k] = v
    env.del("NEED_BUILD_BASE")
    let (outp, code) = execCmdEx("bash " & quoteShell(script), env = env)
    removeFile(script)
    check code != 0
    check PassLine notin outp
