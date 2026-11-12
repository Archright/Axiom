## test_sl02_consumer_binding.nim — SL-02 derived-closure consumer binding (ADR-0033)
##
## The verdict stage's `[check] Admission predicate evaluation` step is the
## SL-02 consumer: it all-or-nones the FIVE derived-closure files (derived-H.txt,
## derived-B.txt, derived-M.txt — the ADR-0025 Amendment F candidate-delta leg —
## pin-H.json, identity.json), verifies L1 identifier binding
## (identity.json ↔ event-frozen H/B/pin-blob/run-attempt) and L2 set
## completeness (in-run deriver re-run digest equality at H and B + per-member
## `git ls-tree -r H` cross-check) + the candidate-delta leg (in-run M
## re-derivation via the deterministic history-fetch contract, equality
## against the tested candidate tree, derived(M) supply) before exporting the
## rotation env for the predicate. Contracts: ADR-0033 + ADR-0025 Amendment F.
## Negative matrix measured HERE by executing the PRODUCTION bash
## (T2/T3/T5/T6 + positive path); T1/T4 (merge_cli invariants) live in
## tests/cli/test_merge_cli.nim — merge_cli stays immutable.
##
## Method: "production bash, not a reimplementation"
## (tests/ci/test_admission_venue_split.nim) — the step's run block is
## extracted verbatim via yaml, ONLY the GitHub Actions expression tokens are
## rewritten to env-var references, and the block is executed with bash. The
## negative verdicts (run-level err) fire inside the closure section, before
## the step's `gh api` PR-context leg, so no network/token is needed.

import std/[unittest, os, osproc, strutils, strtabs]

const
  AdmissionRel = ".github/workflows/admission-check.yml"
  PredStepPrefix = "[check] Admission predicate evaluation"
  # Deterministic sandbox identities (40-hex; never resolved by the failing
  # paths — L1/L2 fire before any object access on these vectors).
  HOther = "0123456789abcdef0123456789abcdef01234567"
  # Nonexistent sandbox repo for the PR-context leg — the API 404s (or fails
  # offline) and the step fail-closes at its own PR-context guard.
  SandboxRepo = "SL02-TEST-NONEXISTENT/sandbox"
  RunAttempt = "7"

proc repoRoot(): string =
  result = absolutePath(currentSourcePath())
  for _ in 0 ..< 3:
    result = result.parentDir()

var
  pyCounter = 0
  shCounter = 0

proc pyRun(scriptBody: string; args: varargs[string]): tuple[outp: string; code: int] =
  inc pyCounter
  let py = getTempDir() / ("sl02_py_" & $getCurrentProcessId() & "_" & $pyCounter & ".py")
  writeFile(py, scriptBody)
  var cmd = "python3 " & quoteShell(py)
  for a in args:
    cmd.add(" " & quoteShell(a))
  let (outp, code) = execCmdEx(cmd)
  removeFile(py)
  result = (outp, code)

proc stepRun(path, job, namePrefix: string): string =
  ## 스텝 run 본문을 yaml로 추출 — 원문 그대로 (venue_split 선례)
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
  doAssert code == 0, "run-block extraction 실패: " & outp
  result = outp

proc substituteTokens(body: string): string =
  ## GitHub Actions expression tokens → env 참조 (production bash 그대로 유지).
  ## 기존 토큰은 PR-context leg 전용 — 부정 경로는 도달하지 않고, 도달해도
  ## 존재하지 않는 sandbox repo로 fail-closed 실패한다 (네트워크 의존 아님).
  result = body
  result = result.replace("${{ github.event.pull_request.head.sha || github.event.merge_group.head_sha }}", "${SL02_TEST_EVENT_HEAD}")
  result = result.replace("${{ github.event.pull_request.base.sha || github.event.merge_group.base_sha }}", "${SL02_TEST_EVENT_BASE}")
  result = result.replace("${{ github.run_attempt }}", "${SL02_TEST_RUN_ATTEMPT}")
  result = result.replace("${{ github.event.pull_request.number }}", "${SL02_TEST_PR_NUM:-}")
  result = result.replace("${{ github.event.merge_group.head_sha }}", "${SL02_TEST_EVENT_HEAD}")
  # Candidate-delta leg (Amendment F): the tested landing candidate commit —
  # the sandbox models it as the local head (tree(head) == merge-tree(base,
  # head) whenever base is head's ancestor, which the real-repo fixtures use).
  result = result.replace("${{ github.sha }}", "${SL02_TEST_GITHUB_SHA}")
  result = result.replace("${{ github.repository }}", SandboxRepo)
  result = result.replace("${{ github.event_name }}", "${SL02_TEST_EVENT_NAME}")
  result = result.replace("${{ secrets.GITHUB_TOKEN }}", "${SL02_TEST_TOKEN}")
  doAssert "${{" notin result, "unsubstituted GitHub Actions token in extracted block"

proc runStepSandbox(body: string; ws: string; head, base: string): tuple[outp: string; code: int] =
  ## 추출+치환된 스텝 본문을 production 패리티로 실행 (CWD == GITHUB_WORKSPACE).
  let env = newStringTable(modeCaseInsensitive)
  for k, v in envPairs():
    if k notin ["GITHUB_OUTPUT", "GITHUB_ENV", "GITHUB_WORKSPACE"]:
      env[k] = v
  env["GITHUB_WORKSPACE"] = ws
  # The step's env block (workflow, `admission-predicate` step env:) is NOT
  # part of the extracted run body — the harness supplies exactly what
  # GitHub Actions would. Since 1ce590484 (run-body 무보간화) the body has
  # ZERO interpolation tokens: every event-sourced value is carried by the
  # step env mapping (below) or the runner default env (GITHUB_SHA), and
  # the SL02_TEST_* names remain only as legacy-token carriers for
  # substituteTokens (no-ops on the current body).
  env["AXIOM_MAIN_SHA"] = base
  env["SL02_EVENT_HEAD"] = head
  # #667 merge: the subject head is env-supplied at the event boundary —
  # sandbox models the PR-context leg (subject == event head). The
  # merge_group parent2 re-derivation leg (gh api) is the only network
  # path and is not exercised here.
  env["SL02_PR_HEAD"] = head
  env["SL02_RUN_ATTEMPT"] = RunAttempt
  # Step env carries the run body reads on the merge_group venue (the
  # event these vectors model): event name, merge-group head (= the event
  # head), an EMPTY PR number (merge_group carries none → the PR-context
  # leg must re-derive it and fail-closed), and the unresolvable sandbox
  # repo (gh api parent2 re-derivation fails → "PR context unresolvable").
  env["SL02_EVENT_NAME"] = "merge_group"
  env["SL02_MG_HEAD"] = head
  env["SL02_PR_NUMBER"] = ""
  env["SL02_REPOSITORY"] = SandboxRepo
  env["SL02_TEST_EVENT_HEAD"] = head
  env["SL02_TEST_EVENT_BASE"] = base
  env["SL02_TEST_RUN_ATTEMPT"] = RunAttempt
  env["SL02_TEST_EVENT_NAME"] = "merge_group"
  env["SL02_TEST_TOKEN"] = ""
  # Candidate-delta leg (Amendment F): the tested candidate commit is the
  # runner default env GITHUB_SHA (== github.sha on both admitted events,
  # per the step env's contract note; 1ce590484) — the sandbox models it
  # as the local head (tree(head) == merge-tree(base, head) whenever base
  # is head's ancestor, which the real-repo fixtures use).
  env["GITHUB_SHA"] = head
  inc shCounter
  let script = getTempDir() / ("sl02_step_" & $getCurrentProcessId() & "_" & $shCounter & ".sh")
  writeFile(script, body)
  # poStdErrToStdOut is REQUIRED: every fail() in the step echoes to stderr —
  # the negative assertions below match that vocabulary.
  let (outp, code) = execCmdEx("bash " & quoteShell(script), env = env,
                               options = {poUsePath, poStdErrToStdOut},
                               workingDir = ws)
  removeFile(script)
  result = (outp, code)

proc gitOut(args: string): string =
  let (outp, code) = execCmdEx("git -C " & quoteShell(repoRoot()) & " " & args)
  doAssert code == 0, "git " & args & " 실패: " & outp
  result = outp.strip()

proc dropLastLine(content: string): string =
  ## derived-H.txt에서 1행 삭제 (T6 누락 멤버 조작) — trailing newline 보존.
  var lines = content.split('\n')
  if lines.len > 0 and lines[^1] == "":
    discard lines.pop()          # trailing empty from the final newline
  doAssert lines.len > 1, "fixture set too small to drop a member"
  discard lines.pop()            # the member under test
  result = lines.join("\n") & "\n"

suite "SL-02 consumer binding — step contract structure (ADR-0033)":

  test "the predicate step carries the all-or-none 5-file + L1 + L2 + candidate-delta sections":
    let body = stepRun(repoRoot() / AdmissionRel, "admission-check", PredStepPrefix)
    # all-or-none: exactly the 5-file contract (Amendment F adds derived-M.txt),
    # partial = run-level err
    check "derived-H.txt derived-B.txt derived-M.txt pin-H.json identity.json" in body
    check "partial derived-closure artifact" in body
    check "exit 1" in body
    # empty-file forgery guard (빈 아티팩트 위장 금지)
    check "0-byte member" in body
    # L1 — identifier binding, run-level err vocabulary
    check "identity.candidateHeadSha" in body
    check "identity.baseSha" in body
    check "pinHeadBlobSha" in body
    check "git -C \"$GITHUB_WORKSPACE\" rev-parse \"$H_EVT:config/trusted_writer_set.json\"" in body
    check "github.run_attempt" in body
    # L2 — deriver re-run digest equality (H and B) + ls-tree membership
    check body.count("derive_checker_closure --ref") >= 2
    check "L2①: derived-H digest mismatch" in body
    check "L2③: derived-B digest mismatch" in body
    check "git -C \"$GITHUB_WORKSPACE\" ls-tree -r \"$H_EVT\"" in body
    # the excess-member limitation is stated by contract (ADR-0033 §D)
    check "detectable only by" in body
    # candidate-delta leg (Amendment F): in-run M re-derivation with the
    # deterministic history-fetch contract + tested-tree equality + the
    # derived-M supply/export
    check "merge-tree --write-tree" in body
    check "CANDIDATE_TREE_MISMATCH" in body
    check "CANDIDATE_TREE_CONFLICT" in body
    check "CANDIDATE_MERGE_BASE_UNRESOLVED" in body
    check "fetch --deepen=64" in body
    check "derive_checker_closure --tree" in body
    check "export AXIOM_DERIVED_M_PATH=" in body
    check "CANDIDATE_M_DIGEST_MISMATCH" in body
    # no NEW ${{ tokens inside run: (quirk Q4) — the event shas come via env:
    check "${{ github.event.pull_request.head.sha" notin body
    # in-place H source is the EVENT head, not workspace HEAD (ADR-0033 §C
    # correction of e54de52e4: HEAD == B in the verdict checkout)
    check "H_SHA=\"$(git -C \"$GITHUB_WORKSPACE\" rev-parse HEAD)\"" notin body
    check "SL02_EVENT_HEAD" in body

suite "SL-02 consumer binding — negative matrix (production bash executed, sandbox repos)":

  proc sandboxRepo(ws: string) =
    ## 최소 git repo — 부정 경로는 객체 해석 전에 실패한다 (fetch 불필요).
    removeDir(ws)
    createDir(ws)
    let (outp, code) = execCmdEx(
      "git init -q " & quoteShell(ws) &
      " && git -C " & quoteShell(ws) & " config user.email t@t" &
      " && git -C " & quoteShell(ws) & " config user.name t" &
      " && git -C " & quoteShell(ws) & " commit -q --allow-empty -m seed")
    doAssert code == 0, "sandbox repo init 실패: " & outp

  proc writeArtifact(ws: string; files: seq[tuple[name, content: string]]) =
    let dir = ws / ".derived-closure"
    createDir(dir)
    for f in files:
      writeFile(dir / f.name, f.content)

  const
    validSet = "100644 blob a1b2\tci/checker.mk\n"
    identityFmt = "{\"candidateHeadSha\":\"$1\",\"baseSha\":\"$2\",\"pinHeadBlobSha\":\"$3\",\"runAttempt\":$4}"
    # Another VALID 40-hex, distinct from the event head — the T3 forgery
    # vector must trip the L1② event-equality gate, not the ① format gate.
    HForged = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let fiveFiles = [
    ("derived-H.txt", validSet),
    ("derived-B.txt", validSet),
    ("derived-M.txt", validSet),
    ("pin-H.json", "{}"),
    ("identity.json", identityFmt % [HOther, HOther, HOther, RunAttempt])]

  test "T2 incomplete artifact (4/5 files — identity.json missing) → run-level err":
    let body = substituteTokens(
      stepRun(repoRoot() / AdmissionRel, "admission-check", PredStepPrefix))
    let ws = getTempDir() / ("sl02_t2_" & $getCurrentProcessId())
    sandboxRepo(ws)
    writeArtifact(ws, @fiveFiles[0 .. 3])
    let (outp, code) = runStepSandbox(body, ws, HOther, HOther)
    check code != 0
    check "partial derived-closure artifact (4/5" in outp
    removeDir(ws)

  test "T2b empty member file (5 files, one 0-byte) → run-level err (빈 아티팩트 위장 금지)":
    let body = substituteTokens(
      stepRun(repoRoot() / AdmissionRel, "admission-check", PredStepPrefix))
    let ws = getTempDir() / ("sl02_t2b_" & $getCurrentProcessId())
    sandboxRepo(ws)
    writeArtifact(ws, @fiveFiles)
    writeFile(ws / ".derived-closure" / "derived-H.txt", "")
    let (outp, code) = runStepSandbox(body, ws, HOther, HOther)
    check code != 0
    check "0-byte member" in outp
    removeDir(ws)

  test "T3 wrong-H identity injection (candidateHeadSha = other H0) → L1 deny":
    let body = substituteTokens(
      stepRun(repoRoot() / AdmissionRel, "admission-check", PredStepPrefix))
    let ws = getTempDir() / ("sl02_t3_" & $getCurrentProcessId())
    sandboxRepo(ws)
    writeArtifact(ws, @[
      ("derived-H.txt", validSet),
      ("derived-B.txt", validSet),
      ("derived-M.txt", validSet),
      ("pin-H.json", "{}"),
      # identity binds a DIFFERENT (but valid) head than the event's (HOther
      # is the event head below) → L1 ② mismatch, before any object access
      ("identity.json", identityFmt % [HForged, HOther, HOther, RunAttempt])])
    let (outp, code) = runStepSandbox(body, ws, HOther, HOther)
    check code != 0
    check "L1: identity.candidateHeadSha" in outp
    check "wrong-run closure injection" in outp
    removeDir(ws)

  test "T3b wrong runAttempt (cross-attempt reuse) → L1 deny":
    let body = substituteTokens(
      stepRun(repoRoot() / AdmissionRel, "admission-check", PredStepPrefix))
    let ws = getTempDir() / ("sl02_t3b_" & $getCurrentProcessId())
    sandboxRepo(ws)
    writeArtifact(ws, @[
      ("derived-H.txt", validSet),
      ("derived-B.txt", validSet),
      ("derived-M.txt", validSet),
      ("pin-H.json", "{}"),
      ("identity.json", identityFmt % [HOther, HOther, HOther, "999"])])
    let (outp, code) = runStepSandbox(body, ws, HOther, HOther)
    check code != 0
    check "L1: identity.runAttempt" in outp
    removeDir(ws)

  test "T5 common-loss posture (derived-H + pin-H missing → 3/5) → run-level err, not rqRotation":
    ## 계획 T5: 생산자가 derived-H와 pin-H를 함께 결손시키는 공결손 벡터 —
    ## 5파일 all-or-none이 run-level err로 봉합해 rqRotation(회전 승인)에
    ## 도달하지 못한다. 이것이 "완전성 입증" 선언의 기계적 트리거다.
    let body = substituteTokens(
      stepRun(repoRoot() / AdmissionRel, "admission-check", PredStepPrefix))
    let ws = getTempDir() / ("sl02_t5_" & $getCurrentProcessId())
    sandboxRepo(ws)
    writeArtifact(ws, @[
      ("derived-B.txt", validSet),
      ("derived-M.txt", validSet),
      ("identity.json", identityFmt % [HOther, HOther, HOther, RunAttempt])])
    let (outp, code) = runStepSandbox(body, ws, HOther, HOther)
    check code != 0
    check "partial derived-closure artifact (3/5" in outp
    check "rqRotation" notin outp
    check "mergeGo" notin outp
    removeDir(ws)

suite "SL-02 consumer binding — T6 + positive path (real repo, real deriver)":

  # These two execute the production block against THIS repository: the fixture
  # derived sets are the real deriver output at HEAD (T6: minus one member —
  # L2① must deny; positive: exact — L1/L2 must pass and the step must reach
  # its PR-context leg). One deriver compile serves both (the block's
  # `[ -x bin/derive_checker_closure ]` guard reuses it).

  let head = gitOut("rev-parse HEAD")
  var base = head
  let (parentOut, parentCode) = execCmdEx(
    "git -C " & quoteShell(repoRoot()) & " rev-parse --verify --quiet HEAD~1")
  if parentCode == 0 and parentOut.strip().len == 40:
    base = parentOut.strip()

  proc realDerivedSet(): string =
    ## 같은 커맨드로 deriver를 컴파일/실행해 실제 집합을 확보한다 (블록과
    ## 동일한 hermetic 레시피 — production bash와 동일 결정 경로).
    let root = repoRoot()
    let (coutp, ccode) = execCmdEx(
      "nim c --hints:off --skipParentCfg --skipProjCfg --path:src " &
      "-o:bin/derive_checker_closure tools/ci/derive_checker_closure.nim",
      workingDir = root)
    doAssert ccode == 0, "deriver compile 실패: " & coutp
    let (outp, code) = execCmdEx(
      quoteShell(root / "bin" / "derive_checker_closure") & " --ref " &
      quoteShell(head) & " --repo " & quoteShell(root), workingDir = root)
    doAssert code == 0, "deriver --ref HEAD 실패 (UNRESOLVED — 트리 자체 fail-closed): " & outp
    doAssert outp.strip().len > 0, "deriver empty output — 0 미선언 위반"
    result = outp

  proc cleanArtifacts() =
    removeDir(repoRoot() / ".derived-closure")
    for f in [".sl02-rederive-H.txt", ".sl02-rederive-B.txt", ".sl02-rederive-M.txt",
              ".sl02-lstree-H.txt"]:
      try:
        removeFile(repoRoot() / f)
      except OSError:
        discard

  proc realDerivedSetAt(rev: string): string =
    let root = repoRoot()
    let (outp, code) = execCmdEx(
      quoteShell(root / "bin" / "derive_checker_closure") & " --ref " &
      quoteShell(rev) & " --repo " & quoteShell(root), workingDir = root)
    doAssert code == 0, "deriver --ref " & rev & " 실패: " & outp
    result = outp

  proc realCandidateTree(): string =
    ## 실제 후보 트리 — 프로덕션 블록과 동일 명령 (merge-tree --write-tree).
    ## base가 head의 조상(HEAD~1 fixture)이므로 M == tree(head).
    let root = repoRoot()
    let (outp, code) = execCmdEx(
      "git -C " & quoteShell(root) & " merge-tree --write-tree " &
      quoteShell(base) & " " & quoteShell(head))
    doAssert code == 0, "merge-tree --write-tree 실패: " & outp
    result = outp.strip()

  proc realDerivedM(): string =
    ## derived(M) — deriver 제3각을 프로덕션과 동일하게 실행 (--tree 모드).
    let root = repoRoot()
    let (outp, code) = execCmdEx(
      quoteShell(root / "bin" / "derive_checker_closure") & " --tree " &
      quoteShell(realCandidateTree()) & " --repo " & quoteShell(root), workingDir = root)
    doAssert code == 0, "deriver --tree 실패: " & outp
    result = outp

  proc writeRealArtifact(derivedH: string) =
    let dir = repoRoot() / ".derived-closure"
    createDir(dir)
    writeFile(dir / "derived-H.txt", derivedH)
    writeFile(dir / "derived-B.txt", realDerivedSetAt(base))
    writeFile(dir / "derived-M.txt", realDerivedM())
    writeFile(dir / "pin-H.json", gitOut("show HEAD:config/trusted_writer_set.json"))
    let pinBlob = gitOut("rev-parse " & quoteShell(head & ":config/trusted_writer_set.json"))
    writeFile(dir / "identity.json",
      "{\"candidateHeadSha\":\"" & head & "\",\"baseSha\":\"" & base &
      "\",\"pinHeadBlobSha\":\"" & pinBlob & "\",\"runAttempt\":" & RunAttempt & "}")

  test "T6 missing member (derived-H 1행 삭제) → L2① digest mismatch → run-level err":
    cleanArtifacts()
    let full = realDerivedSet()
    writeRealArtifact(dropLastLine(full))
    defer: cleanArtifacts()
    let body = substituteTokens(
      stepRun(repoRoot() / AdmissionRel, "admission-check", PredStepPrefix))
    let (outp, code) = runStepSandbox(body, repoRoot(), head, base)
    check code != 0
    check "L2①: derived-H digest mismatch" in outp
    check "member loss/excess" in outp

  test "positive path (정확한 5파일 공급) → L1 OK + L2 OK + candidate-delta OK, PR-context에서만 종료":
    cleanArtifacts()
    writeRealArtifact(realDerivedSet())
    defer: cleanArtifacts()
    let body = substituteTokens(
      stepRun(repoRoot() / AdmissionRel, "admission-check", PredStepPrefix))
    let (outp, code) = runStepSandbox(body, repoRoot(), head, base)
    # L1/L2/candidate-delta must PASS; the step then fail-closes at its own
    # PR-context leg (sandbox repo is unresolvable) — the expected sandbox
    # boundary.
    check code != 0
    check "SL-02 L1 OK" in outp
    check "SL-02 L2 OK" in outp
    check "candidate-delta leg OK" in outp
    check "rotation closure inputs supplied + L1/L2 verified" in outp
    check "PR context unresolvable" in outp
    check "[check] FAIL: L1" notin outp
    check "[check] FAIL: L2" notin outp
