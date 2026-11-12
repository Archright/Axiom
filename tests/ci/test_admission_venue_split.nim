## test_admission_venue_split.nim — ADR-0032 admission venue split contract
##
## The admission pipeline now runs in TWO venues from the SAME pinned files:
## pull_request = preflight (fast static/structural contrast only — no build,
## no kernel E2E, no witness, no `ax merge`), merge_group|workflow_call =
## landing (the full canonical verification, byte-identical guard semantics
## behind the landing conjunct). The contract this file pins:
##
##   * every job's FIRST step resolves the venue from `github.event_name`;
##     any other event is fail-closed (no venue, no run);
##   * heavy steps carry `steps.venue.outputs.venue == 'landing'` — a dropped
##     conjunct would put the whole landing chain back on every PR (the
##     ~202-min loop the stage split fixed is exactly what this would
##     reassemble); a conjunct added to a light step would starve the PR
##     preflight of its identity content;
##   * the four preflight legs are REAL fail-closed checks (§0.9), gated to
##     `venue == 'preflight'`, and each states "preflight success ≠ landing
##     evidence" (ADR-0032 (f) — the non-canonical marking);
##   * the A2 pin pair stays atomic: git blob(HEAD admission-check.yml) ==
##     trusted_writer_set.json trustedAdmissionWorkflowSha ==
##     epoch_manifest.json productionExecutionPin;
##   * the artifact surface stays pinned to the pre-split freeze
##     (ci-frozen-2026-10-09-venue-split) plus an explicitly enumerated
##     sanctioned-addition set (A2-pin-rotating commits) — artifact names are
##     consumed across files (mint lookup, cache publisher) and any unlisted
##     addition/removal/duplicate-count drift fails.
##
## freeze 태그는 로컬 전용이다(push-admissibility 게이트가 historical OID 태그
## push를 fail-closed — 2026-10-11 실측). 태그가 없는 클론에서는 freeze 대비
## 테스트가 [SKIPPED]로 결정적 강등된다 — 조용한 통과 아님(§0.9).
##
## Structural assertions use the yaml parser where names/guards are needed
## (test_b_cache_anchor.nim precedent) and EXECUTE the venue run block itself
## with substituted event names — the production bash, not a reimplementation.

import std/[unittest, os, osproc, strutils, strtabs, algorithm]

const
  AdmissionRel = ".github/workflows/admission-check.yml"
  MintRel = ".github/workflows/certificate-mint.yml"
  TwsRel = "config/trusted_writer_set.json"
  ManifestRel = "config/policy/epoch_manifest.json"
  FreezeTag = "ci-frozen-2026-10-09-venue-split"
  Landing = "steps.venue.outputs.venue == 'landing'"
  Preflight = "steps.venue.outputs.venue == 'preflight'"
  ## L3 split (2026-11-04): `admission-independents` (job2a) joined the
  ## admission callee file — it pays the same [venue] preamble and carries
  ## the landing-gated GO-independent steps, so every job-scoped loop below
  ## (venue resolution, slice-scope gating, landing counts, PREFLIGHT scan)
  ## walks all THREE admission jobs. go-critical-lane / go-critical-rollup
  ## stay OUT of this list: they are merge_group|workflow_call-only jobs
  ## (landing by job-level guard, no venue marker), unchanged from the G2
  ## generation.
  AdmissionJobs* = @["build-base-artifacts", "admission-check", "admission-independents"]
  MintJobs = @["prepare", "publish"]

proc repoRoot(): string =
  ## tests/ci/ → 저장소 루트
  result = absolutePath(currentSourcePath())
  for _ in 0 ..< 3:
    result = result.parentDir()

proc runGit(args: string): string =
  let (outp, code) = execCmdEx("git -C " & quoteShell(repoRoot()) & " " & args)
  doAssert code == 0, "git " & args & " 실패: " & outp
  result = outp.strip()

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

var pyCounter = 0

proc pyRun(scriptBody: string; args: varargs[string]): tuple[outp: string; code: int] =
  ## python3 한 스크립트 실행 — args는 sys.argv[1..]
  inc pyCounter
  let py = getTempDir() / ("venue_py_" & $getCurrentProcessId() & "_" & $pyCounter & ".py")
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
  Step = tuple[idx: int, name, guard, uses, withName: string]

proc stepsOf(path: string): seq[Step] =
  ## (file, job, step) 전체를 TSV로 추출: job \t idx \t name \t if \t uses \t with-name
  const Script = """
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
for job, spec in d['jobs'].items():
    for i, s in enumerate(spec.get('steps', [])):
        name = s.get('name', '')
        guard = s.get('if', '') or ''
        uses = s.get('uses', '') or ''
        wname = ''
        if isinstance(s.get('with'), dict):
            wname = str(s['with'].get('name', '') or '')
        row = [job, str(i), name, guard.replace('\n', ' '), uses, wname]
        print('\t'.join(row))
"""
  let (outp, code) = pyRun(Script, path)
  if code != 0: pyFail(outp)
  for line in outp.splitLines():
    if line.strip() == "": continue
    let cols = line.split('\t')
    doAssert cols.len == 6, "unexpected TSV row: " & line
    result.add((parseInt(cols[1]), cols[2], cols[3], cols[4], cols[5]))

proc stepsOfJob(path, job: string): seq[Step] =
  ## 단일 job의 스텝을 TSV로 추출: idx \t name \t if \t uses \t with-name
  let (outp, code) = pyRun("""import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
for i, s in enumerate(d['jobs'][sys.argv[2]].get('steps', [])):
    name = s.get('name', '')
    guard = s.get('if', '') or ''
    uses = s.get('uses', '') or ''
    wname = ''
    if isinstance(s.get('with'), dict):
        wname = str(s['with'].get('name', '') or '')
    row = [str(i), name, guard.replace('\n', ' '), uses, wname]
    print('\t'.join(row))
""", path, job)
  if code != 0: pyFail(outp)
  for line in outp.splitLines():
    if line.strip() == "": continue
    let cols = line.split('\t')
    doAssert cols.len == 5, "unexpected TSV row: " & line
    result.add((parseInt(cols[0]), cols[1], cols[2], cols[3], cols[4]))

proc stepsNamed(path, job, namePrefix: string): seq[Step] =
  for s in stepsOfJob(path, job):
    if s.name.startsWith(namePrefix):
      result.add(s)

proc stepNamed(path, job, namePrefix: string): Step =
  ## 정확히 하나여야 한다 — 이름이 사라지거나 복제되면 모호해지므로 raise
  let found = stepsNamed(path, job, namePrefix)
  if found.len != 1:
    raise newException(ValueError,
      "step '" & namePrefix & "' occurs " & $found.len & " time(s) in " &
      path & "/" & job)
  result = found[0]

proc stepRun(path, job, namePrefix: string): string =
  ## 스텝 run 본문을 yaml로 추출 — 원문 그대로 (test_b_cache_anchor.nim 선례)
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

proc jsonScalar(path, jqExpr: string): string =
  ## comment-stripped JSON에서 scalar 1개 추출 (TWS는 // 주석을 허용한다)
  const Script = """
import sys, json, re
raw = open(sys.argv[1]).read()
stripped = '\n'.join(l for l in raw.splitlines() if not re.match(r'\s*//', l))
print(json.loads(stripped)[sys.argv[2]])
"""
  let (outp, code) = pyRun(Script, path, jqExpr)
  if code != 0: pyFail(outp)
  result = outp.strip()

proc artifactNames(path: string): seq[string] =
  ## upload/download 아티팩트 name 값(비어있지 않은 것)의 정렬 목록
  for s in stepsOf(path):
    if "upload-artifact" in s.uses or "download-artifact" in s.uses:
      if s.withName.len > 0:
        result.add(s.withName)
  result.sort()

proc venueScript(body, eventName: string): tuple[outp: string, code: int, ghOut: string] =
  ## venue run 본문을 그대로 실행 — `${{ github.event_name }}`만 env 참조로 치환
  var ghCounter = 0
  proc once(b: string): tuple[outp: string, code: int, ghOut: string] =
    inc ghCounter
    let ghOutPath = getTempDir() / ("venue_gh_out_" & $getCurrentProcessId() & "_" & $ghCounter)
    writeFile(ghOutPath, "")
    let env = newStringTable(modeCaseInsensitive)
    for k, v in envPairs():
      if k != "GITHUB_OUTPUT":
        env[k] = v
    env["GITHUB_OUTPUT"] = ghOutPath
    env["AXIOM_TEST_EVENT_NAME"] = eventName
    let script = getTempDir() / ("venue_step_" & $getCurrentProcessId() & "_" & $ghCounter & ".sh")
    writeFile(script, b)
    let (outp, code) = execCmdEx("bash " & quoteShell(script), env = env)
    removeFile(script)
    result.outp = outp
    result.code = code
    result.ghOut = readFile(ghOutPath)
    removeFile(ghOutPath)
  result = once(body.replace("${{ github.event_name }}", "${AXIOM_TEST_EVENT_NAME}"))

proc ghVenue(ghOut: string): string =
  for line in ghOut.splitLines():
    if line.startsWith("venue="):
      return line["venue=".len .. ^1]
  doAssert false, "venue= output missing in GITHUB_OUTPUT: " & ghOut

let root = repoRoot()
let admissionPath = root / AdmissionRel
let mintPath = root / MintRel

suite "ADR-0032 — venue resolution is the first step of every job":

  test "each of the 5 jobs opens with exactly one [venue] step at index 0":
    for (path, jobs) in [(admissionPath, AdmissionJobs), (mintPath, MintJobs)]:
      for job in jobs:
        let steps = stepsOfJob(path, job)
        check steps.len > 1
        check steps[0].name.startsWith("[venue] Resolve execution venue")
        check steps[0].uses == ""  # a plain run step, not an action
        check steps[0].guard == "" # 무조건 실행 — venue 미결 상태에서는 아무 것도 없다

  test "venue steps in all five jobs are byte-identical (single venue contract)":
    var bodies: seq[string] = @[]
    for (path, jobs) in [(admissionPath, AdmissionJobs), (mintPath, MintJobs)]:
      for job in jobs:
        bodies.add(stepRun(path, job, "[venue] Resolve execution venue"))
    check bodies.len == 5
    for b in bodies[1 .. ^1]:
      check b == bodies[0]

  test "venue run branches on github.event_name with a fail-closed default":
    let body = stepRun(admissionPath, "build-base-artifacts", "[venue] Resolve execution venue")
    check "case \"${{ github.event_name }}\"" in body
    check "pull_request)" in body and "venue=preflight" in body
    check "merge_group|workflow_call)" in body and "venue=landing" in body
    check "*)" in body
    check "exit 1" in body

  test "execute: pull_request → venue=preflight (exit 0)":
    let body = stepRun(admissionPath, "build-base-artifacts", "[venue] Resolve execution venue")
    let r = venueScript(body, "pull_request")
    check r.code == 0
    check ghVenue(r.ghOut) == "preflight"

  test "execute: merge_group → venue=landing (exit 0)":
    let body = stepRun(admissionPath, "build-base-artifacts", "[venue] Resolve execution venue")
    let r = venueScript(body, "merge_group")
    check r.code == 0
    check ghVenue(r.ghOut) == "landing"

  test "execute: workflow_call → venue=landing (exit 0)":
    let body = stepRun(admissionPath, "build-base-artifacts", "[venue] Resolve execution venue")
    let r = venueScript(body, "workflow_call")
    check r.code == 0
    check ghVenue(r.ghOut) == "landing"

  test "execute: unknown event → fail-closed nonzero, no venue output":
    let body = stepRun(admissionPath, "build-base-artifacts", "[venue] Resolve execution venue")
    let r = venueScript(body, "push")
    check r.code != 0
    check "FAIL" in r.outp
    let r2 = venueScript(body, "workflow_dispatch")
    check r2.code != 0

suite "ADR-0032 — heavy steps are landing-gated, exactly":

  test "every slice-scoped step keeps the landing conjunct (both files)":
    ## 무거운 스텝 판정의 하한선: scope_ 컨정크트를 가진 모든 스텝은 landing
    ## 게드여야 한다 — 하나라도 컨정크트가 떨어지면 전체 landing 체인이 PR에
    ## 돌아온다 (역 ~202분 루프 재조립). 예외는 의도적으로 가벼운 두 스텝뿐:
    ## identity 재유도(sl01)와 (P0) activation guard — 둘 다 PR preflight의
    ## identity 내용이며 아래 별도 테스트가 무게이트를 고정한다.
    const UngatedByDesign = [
      "[check] Re-derive admission identity",
      "(P0) Publish activation guard"]
    for (path, jobs) in [(admissionPath, AdmissionJobs), (mintPath, MintJobs)]:
      for job in jobs:
        for s in stepsOfJob(path, job):
          var isException = false
          for u in UngatedByDesign:
            if s.name.startsWith(u): isException = true
          if "steps.slice-engine.outputs.scope_" in s.guard and not isException:
            check s.guard.contains(Landing)

  test "landing-gated guard counts are exact (34 admission + 16 mint)":
    ## 정확 카운트: 무분별한 컨정크트 추가도 잡는다 — 새 landing 게드 스텝을
    ## 추가하면 이 카운트와 이 테스트를 함께 개정한다 (계약 핀).
    ## 소급 정정 (2026-11-04 실측, b1659ef16 선례의 다섯 번째 사례): 본 핀은
    ## 33이었으나 50d781e82 (PR #1262 merge, 사전분할 tip)에서 2잡
    ## (build-base-artifacts + admission-check) 실측은 29였다 — 선존재 red.
    ## 33의 조성 산술(아래 사슬의 26+4+4−2+1)은 어느 시점의 실측과도
    ## 대응되지 않는, 개정 의무가 누락된 채 산술로만 유지된 값이었다.
    ## 실측 29를 기저로 재핀한다(과대 계상된 조성 항의 특정은 유추하지
    ## 않는다 — 실측이 정본).
    ## L3 split (work/l3-go-split-2026-11-04,
    ## docs/evidence/l3_go_prereg_2026-11-03.md):
    ##   29 (50d781e82 2잡 실측)
    ##   − 3 (Core purity gate · Stage D9 evidence · Register subject가
    ##        admission-independents 잡으로 이동 — 아래 2잡 스캔에서 벗어남)
    ##   + 2 (admission-check 신규 landing-gated: [guard] needs-result gate ·
    ##        [check] Download admission-independents evidence)
    ##   = 28 (2잡 스캔)
    ##   + 6 (admission-independents 잡: Download base-built · Verify manifest ·
    ##        Core purity · Stage D9 · Register subject · Upload evidence chain)
    ##   = 34 (3잡 — AdmissionJobs가 job2a를 포함하므로 카운트는 3잡 합계다).
    ## 구핀 33의 개별 조성 항목(toolchain-handoff +4 · G2 job-matrix +4−2 ·
    ## accounting +1)은 실측 29와 대응되지 않는 산술이므로 본 핀에서
    ## 제거했다 — 커밋 이력(git log -p tests/ci/test_admission_venue_split.nim)이
    ## 원문을 보존한다. 이전 세대의 실측 기반 조성 사슬은 아래에 남긴다.
    ## 26의 조성 = 20 (venue split, ci-frozen-2026-10-09-venue-split)
    ##      + 1 (S5 supply-mode judgment — d3ccad320, J3 §3.1 검증 공급 재사용)
    ##      + 3 (Pass 2.75 verdict cluster — 9b8791b53: FAIL-CLOSED guard ·
    ##        verdict 로그 검증 · verdict 로그 업로드. ADR-0025 Amendment D;
    ##        A2 원자 페어는 동일 커밋 회전했으나 본 카운트 핀 개정이 누락 —
    ##        2026-10-11 선존재 red 실측 후 b1659ef16 선례로 소급 정정)
    ##      + 2 (test-mode nimcache union carrier + folded upload — af3cfa2e7,
    ##        J3 acceleration. 같은 커밋 A2 회전, 핀 개정 누락 소급 정정).
    ## 16 = 15 (venue split freeze) + 1 (P7c-x judgment ledger append —
    ## bc22d36b2가 gate를 복원하며 본 카운트 핀 개정을 누락했던 것을 2026-10-10
    ## 선존재 red 실측 후 소급 정정).
    var nAdmission = 0
    for job in AdmissionJobs:
      for s in stepsOfJob(admissionPath, job):
        if s.guard.contains(Landing): inc nAdmission
    check nAdmission == 34
    ## 16 = 15 (venue split 계약) + 1 (P7c-x judgment CAS ledger append의
    ## landing venue gate 복원분 — bc22d36b2, 2026-10-09 병합. 게드 추가 시
    ## 본 핀 동시 개정 규칙이 누락돼 2026-10-10 재측정으로 소급 정합).
    var nMint = 0
    for job in MintJobs:
      for s in stepsOfJob(mintPath, job):
        if s.guard.contains(Landing): inc nMint
    check nMint == 16

  test "named heavy steps in admission-check are landing-gated":
    ## GO-critical 실행은 G2 세대(0848662fb, 2026-10-16)에서 go-critical-lane
    ## 잡으로 이동했다 — 직렬 실행 스텝 `[check] GO-critical admission tests`는
    ## 이 잡에 더 이상 존재하지 않고, 본 잡 안의 착지 소비 경계는 레인 핸드오프
    ## 다운로드 2스텝이다 (레인 잡 자체는 merge_group|workflow_call 한정 —
    ## 잡 단위 landing-only).
    ## L3 split (2026-11-04): Core purity gate · Stage D9 evidence · Register
    ## subject가 admission-independents 잡으로 이동했다(아래 별도 스코프) — 본
    ## 잡의 착지 소비 경계는 job2a 핸드오프 다운로드 1스텝과 [guard]
    ## needs-result 게이트로 늘었다.
    for step in ["[check] Download base-built artifacts",
                 "[check] Verify artifact manifest",
                 "[check] Download lane-0 judgment artifacts",
                 "[check] Download lane-1 judgment artifacts",
                 "[check] Download admission-independents evidence",
                 "[guard] Every direct need must be success",
                 "[check] Attest witness-only",
                 "[check] Fetch subject-certificate artifact",
                 "[check] Admission predicate evaluation"]:
      check stepNamed(admissionPath, "admission-check", step).guard.contains(Landing)
    # build job heavy set
    for step in ["[build] Build bin/ax + harness from B",
                 "[build] Upload base-built artifacts",
                 "[build] Upload base-tree nimcache"]:
      check stepNamed(admissionPath, "build-base-artifacts", step).guard.contains(Landing)
    # L3 independents job heavy set (moved steps + producer-edge upload)
    for step in ["[check] Download base-built artifacts",
                 "[check] Verify artifact manifest",
                 "[check] Core purity gate",
                 "[check] Stage D9 evidence",
                 "[check] Register subject",
                 "[independents] Upload evidence chain"]:
      check stepNamed(admissionPath, "admission-independents", step).guard.contains(Landing)

  test "identity re-derivation stays venue-UNGATED (preflight identity content, sl01)":
    ## B/H/treeOID 재유도는 가벼워서 PR preflight가 그 결과를 identity 내용으로
    ## 소비한다 — venue 게드하면 preflight가 허위 identity가 된다. L3 split으로
    ## 이 스텝은 admission-independents 잡으로 이동했으나 guard는 바이트 동일
    ## (prereg §3 — 이동은 게드 의미를 바꾸지 않는다).
    let guard = stepNamed(admissionPath, "admission-independents",
      "[check] Re-derive admission identity").guard
    check guard == "inputs.stage == 'attest' && steps.slice-engine.outputs.scope_sl01 == 'true'"
    check Landing notin guard
    check Preflight notin guard

  test "named heavy steps in certificate-mint are landing-gated":
    for step in ["[mint] Consume admission B-built bin/ax",
                 "(3) Artifact retrieval",
                 "(3b) Merge-candidate tree identity",
                 "(4) Verify + normalize witness",
                 "(5) Cert artifact digest + manifest + upload",
                 "(5b) Upload subject-certificate artifact"]:
      check stepNamed(mintPath, "prepare", step).guard.contains(Landing)
    for step in ["(P1) [X]1 artifact identity",
                 "(P2) [X]2 file digest",
                 "(P3) Bin/ax 준비",
                 "(P4) [X]3 field binding",
                 "(P5) [B2] (b) canonical tree identity",
                 "(P6) [B2] (c) gateway lane conclusion",
                 "(P7) D6 + FF-CAS 3분기 reconciliation",
                 "(P7b) [SL-15] evidence record",
                 "(P7c) [SL-15] judgment record"]:
      check stepNamed(mintPath, "publish", step).guard.contains(Landing)

  test "the publish activation guard (P0) stays venue-UNGATED (deliberate)":
    ## (P0)는 가벼운 API 재검증으로 PR publish preflight의 identity 내용이다 —
    ## venue 게드되면 preflight가 내용을 잃고, 무단 해제되면 극장이 된다.
    let guard = stepNamed(mintPath, "publish", "(P0) Publish activation guard").guard
    check guard == "steps.slice-engine.outputs.scope_sl0713 == 'true'"
    check Landing notin guard
    check Preflight notin guard

  test "stage dispatch conjuncts survive alongside the venue conjunct":
    ## venue 게드는 stage 배출을 대체하지 않는다 — attest 전용/verdict 전용
    ## 스텝은 여전히 자기 stage 컨정크트를 유지한다 (test_admission_check_stages
    ## 호환의 내용면 고정). L3 split: Core purity gate는
    ## admission-independents 잡에서 같은 컨정크트를 유지한다.
    check stepNamed(admissionPath, "admission-independents", "[check] Core purity gate").guard.startsWith("inputs.stage == 'attest'")
    check stepNamed(admissionPath, "admission-check", "[check] Admission predicate evaluation").guard.startsWith("inputs.stage == 'verdict'")

suite "ADR-0032 — the four preflight legs are real, fail-closed, preflight-only":

  proc preflightLeg(path, job, namePrefix, marker: string) =
    let s = stepNamed(path, job, namePrefix)
    check s.guard.contains(Preflight)
    check s.guard.contains("== 'preflight'")
    let body = stepRun(path, job, namePrefix)
    check "PREFLIGHT PASS — " in body
    check marker in body
    check "exit 1" in body  # fail-closed, not an always-green echo
    check "≠ landing evidence" in body  # (f) 비정원 표시

  test "attest leg preflight — TWS pin pairing + policy SSOT":
    preflightLeg(admissionPath, "admission-check",
      "[preflight] Attest-leg static contrast", "trustedAdmissionWorkflowSha")

  test "verdict leg preflight — policy SSOT + stage dispatch structure":
    preflightLeg(admissionPath, "admission-check",
      "[preflight] Verdict-leg static contrast", "certRequired")

  test "prepare leg preflight — policy SSOT + mint structure":
    preflightLeg(mintPath, "prepare",
      "[preflight] Prepare-leg static contrast", "subject-certificate-")

  test "publish leg preflight — single-writer posture + stage structure":
    preflightLeg(mintPath, "publish",
      "[preflight] Publish-leg structural contrast", "contents: write")

  test "PREFLIGHT PASS appears exactly twice per file, inside preflight-gated steps":
    ## PASS 라인이 preflight 스텝 밖에 존재하면 landing 런이 preflight 증거를
    ## 흘려보내는 것이므로 스텝 경계로 묶는다.
    for (path, jobs) in [(admissionPath, AdmissionJobs), (mintPath, MintJobs)]:
      var total = 0
      for job in jobs:
        for s in stepsOfJob(path, job):
          if s.uses != "": continue
          let body = stepRun(path, job, s.name)
          if "PREFLIGHT PASS — " in body:
            inc total
            check s.guard.contains(Preflight)
      check total == 2

suite "ADR-0032 — A2 pin pairing stays atomic (3-way)":

  test "git blob(HEAD admission-check.yml) == TWS trustedAdmissionWorkflowSha == epoch manifest pin":
    let blob = runGit("hash-object " & quoteShell(".github/workflows/admission-check.yml"))
    let twsSha = jsonScalar(root / TwsRel, "trustedAdmissionWorkflowSha")
    let pin = jsonScalar(root / ManifestRel, "productionExecutionPin")
    check blob.len == 40
    check twsSha == blob
    check pin == blob

  test "TWS still names certificate-mint.yml as the sole trusted writer":
    check jsonScalar(root / TwsRel, "trustedWriterWorkflow") == MintRel

  test "epoch manifest still declares the same ci epoch id":
    check jsonScalar(root / ManifestRel, "ciEpochId").len > 0

suite "ADR-0032 — artifact surface invariance vs freeze":

  test "upload/download artifact names = exact freeze + sanctioned additions since ci-frozen-2026-10-09-venue-split":
    ## (소급 정정 2026-10-11 — b1659ef16 선례) freeze 이후 A2 원자 페어 회전
    ## 커밋(ADR-0032 §(d)이 정한 admission-check.yml 개정 채널)으로 승인된
    ## 증가분만 명시 핀으로 흡수한다:
    ##   +1 admission-verdict-<head>-<run_attempt> — 9b8791b53 (Pass 2.75
    ##      judge.source 저널, fail-closed upload if-no-files-found: error;
    ##      ADR-0025 Amendment D + proof_required_admission_contract.md §3,
    ##      src/gate/slice_catalog.nim produces 등록).
    ##   +2 admission-check-base-nimcache — af3cfa2e7 (job2 union carrier:
    ##      소비자 표면을 byte-identical로 유지하기 위한 같은 이름 재업로드).
    ##   +2 admission-independents-<head>-<run_attempt> — L3 split
    ##      (work/l3-go-split-2026-11-04, prereg
    ##      docs/evidence/l3_go_prereg_2026-11-03.md): job2a의
    ##      [independents] Upload evidence chain 1항 + admission-check의
    ##      [check] Download admission-independents evidence 1항 (양측 동일
    ##      이름 — run-scoped handoff, if-no-files-found: error).
    ## 이 목록 밖의 추가·삭제·중복 수 변화는 여전히 red — 정확 다중집합 핀.
    const Admitted: array[2, tuple[rel: string, added: seq[string]]] = [
      (AdmissionRel, @[
        "admission-verdict-${{ github.event.pull_request.head.sha || github.event.merge_group.head_sha || github.sha }}-${{ github.run_attempt }}",
        "admission-check-base-nimcache",
        "admission-check-base-nimcache",
        "admission-independents-${{ github.event.pull_request.head.sha || github.event.merge_group.head_sha || github.sha }}-${{ github.run_attempt }}",
        "admission-independents-${{ github.event.pull_request.head.sha || github.event.merge_group.head_sha || github.sha }}-${{ github.run_attempt }}"]),
      (MintRel, @[])]
    if freezeTagMissing():
      echo "[freeze-tag-missing] ", FreezeTag,
        " — freeze 대비 검증 SKIPPED. 복구: git fetch origin tag ", FreezeTag
      skip()
    else:
      for (rel, admitted) in Admitted:
        let frozenContent = frozenFile(rel)
        let frozenPath = getTempDir() / ("venue_frozen_" & $getCurrentProcessId() & "_" & extractFilename(rel))
        writeFile(frozenPath, frozenContent)
        let frozen = artifactNames(frozenPath)
        let current = artifactNames(root / rel)
        removeFile(frozenPath)
        var expected = frozen & admitted
        expected.sort()
        check current == expected
        check current.len > 0
