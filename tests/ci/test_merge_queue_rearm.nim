## test_merge_queue_rearm.nim — ADR-0027 Amendment F rearm contract
##
## `.github/workflows/merge-queue-rearm.yml` gained a second wake-up
## (`workflow_run[completed]` of the admission-gate kernel) and a rewritten
## arm path. This file pins the contract in two layers:
##
##   STRUCTURAL — the yaml is parsed and the properties that make the pipeline
##   safe are asserted directly: three wake-ups, event-name-keyed concurrency,
##   no repository checkout (the rearm job runs trusted code only), twelve
##   byte-identical `emit()` copies (the verdict projection is duplicated on
##   purpose — a shared definition would need a checkout or a composite
##   action, i.e. a new trust surface), no `exit 1`, no `${{ }}` inside any
##   `run:` scalar (Q4 expression-length quirk), and the intent label being
##   written BEFORE `gh pr merge` while `rearmed@` is written after.
##
##   EXECUTABLE — the production bash of conditions 0, 8 and 9 is executed
##   verbatim against a `gh` PATH stub. Those three steps decide the identity
##   of the subject, whether budget is available, and whether an arm happens;
##   a reimplementation in Nim would not prove the shipped script behaves as
##   claimed (ADR-0032 precedent: execute the run block, never a paraphrase).
##
## The stub models GitHub as a stateful label store (POST appends, GET
## returns) so "intent recorded before arm" is observed as an ordering of
## stub calls, not as a string index in the source.

import std/[unittest, os, osproc, strutils, strtabs, json, sequtils]

const
  WorkflowRel = ".github/workflows/merge-queue-rearm.yml"
  AdmissionPath = ".github/workflows/admission-gate-v2.yml"
  Sha = "1111111111111111111111111111111111111111"
  MG = "2222222222222222222222222222222222222222"
  OtherSha = "3333333333333333333333333333333333333333"
  QueueBranch = "gh-readonly-queue/main/pr-77-" & MG

const GhStub = """#!/usr/bin/env bash
set -euo pipefail
D="$REARM_STUB_DIR"
printf '%s\n' "$*" >> "$D/calls.log"
case "$1" in
  api)
    op=""
    for a in "$@"; do
      case "$a" in
        graphql)            op=graphql ;;
        *labels*per_page*)  op=labels ;;
        *issues/*/labels)   op=labels_post ;;
        *pulls/*)           op=pull ;;
        *) : ;;
      esac
    done
    case "$op" in
      graphql)     cat "$D/graphql.json" ;;
      labels)      cat "$D/labels.txt" ;;
      labels_post)
        lbl=""
        for a in "$@"; do
          case "$a" in labels[]=*) lbl="${a#labels[]=}" ;; esac
        done
        if [ -n "$lbl" ]; then printf '%s\n' "$lbl" >> "$D/labels.txt"; fi
        printf '[{"name":"%s"}]\n' "${lbl:-none}" ;;
      pull)        cat "$D/pull.json" ;;
      *) echo "stub gh: unhandled api $*" >&2; exit 1 ;;
    esac ;;
  pr)
    if [ "${2:-}" = "merge" ]; then
      if [ "${STUB_ARM_EXIT:-0}" != "0" ]; then
        echo "stub gh: auto-merge refused" >&2
        exit "${STUB_ARM_EXIT}"
      fi
      printf '%s\n' "$*" >> "$D/arms.log"
      exit 0
    fi
    echo "stub gh: unhandled pr $*" >&2; exit 1 ;;
  *) echo "stub gh: unhandled $*" >&2; exit 1 ;;
esac
"""

proc repoRoot(): string =
  result = absolutePath(currentSourcePath())
  for _ in 0 ..< 3:
    result = result.parentDir()

let root = repoRoot()
let wfPath = root / WorkflowRel

var pyCounter = 0

proc pyRun(scriptBody: string; args: varargs[string]): tuple[outp: string; code: int] =
  inc pyCounter
  let py = getTempDir() / ("rearm_py_" & $getCurrentProcessId() & "_" & $pyCounter & ".py")
  writeFile(py, scriptBody)
  var cmd = "python3 " & quoteShell(py)
  for a in args:
    cmd.add(" " & quoteShell(a))
  let (outp, code) = execCmdEx(cmd)
  removeFile(py)
  result = (outp: outp, code: code)

proc stepRun(path, job, namePrefix: string): string =
  ## The exact `run:` scalar of the single step whose name starts with prefix.
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
  if code != 0:
    raise newException(ValueError, "run extraction failed: " & outp)
  result = outp

type StepRow = tuple[idx: int, name, guard, uses: string]

proc stepsOfJob(path, job: string): seq[StepRow] =
  const Script = """
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
for i, s in enumerate(d['jobs'][sys.argv[2]].get('steps', [])):
    print('\t'.join([str(i), s.get('name',''), (s.get('if','') or '').replace('\n',' '), s.get('uses','') or '']))
"""
  let (outp, code) = pyRun(Script, path, job)
  if code != 0:
    raise newException(ValueError, "step extraction failed: " & outp)
  for line in outp.splitLines():
    if line.strip.len == 0: continue
    let c = line.split('\t')
    result.add((parseInt(c[0]), c[1], c[2], c[3]))

proc workflowShape(path: string): JsonNode =
  const Script = """
import sys, json, yaml
d = yaml.safe_load(open(sys.argv[1]))
print(json.dumps({
  'triggers': sorted(list((d.get(True) or d.get('on')).keys())),
  'concurrency': d.get('concurrency'),
  'steps': [s.get('name','') for s in d['jobs']['rearm']['steps']],
  'step_count': len(d['jobs']['rearm']['steps']),
  'run_bodies': [s.get('run','') for s in d['jobs']['rearm']['steps']],
  'uses': [s.get('uses','') for s in d['jobs']['rearm']['steps'] if s.get('uses')],
}))
"""
  let (outp, code) = pyRun(Script, path)
  if code != 0:
    raise newException(ValueError, "shape extraction failed: " & outp)
  result = parseJson(outp)

# ── executable fixture plumbing ─────────────────────────────────────────────

const Bin = getTempDir() / "axiom_rearm_contract_bin"
const Stub = getTempDir() / "axiom_rearm_contract_stub"

proc prepare() =
  if dirExists(Stub): removeDir(Stub)
  createDir(Stub)
  if not dirExists(Bin): createDir(Bin)
  writeFile(Bin / "gh", GhStub)
  setFilePermissions(Bin / "gh",
    {fpUserRead, fpUserWrite, fpUserExec, fpGroupRead, fpGroupExec,
     fpOthersRead, fpOthersExec})
  writeFile(Stub / "labels.txt", "")
  writeFile(Stub / "calls.log", "")
  writeFile(Stub / "arms.log", "")
  writeFile(Stub / "graphql.json", """{"data":{"repository":{"pullRequest":{
    "state":"OPEN","headRefOid":"$1","isInMergeQueue":false,
    "autoMergeRequest":null,"mergeQueueEntry":null}}}}""".replace("$1", Sha))
  writeFile(Stub / "pull.json", """{"number":77,"state":"open",
    "head":{"sha":"$1"}}""".replace("$1", Sha))

proc setGraphql(state = "OPEN"; head = Sha; inq = false; entry = "" ;
                armed = ""): void =
  var pr = %*{"state": state, "headRefOid": head, "isInMergeQueue": inq}
  pr["autoMergeRequest"] =
    if armed.len == 0: newJNull()
    else: %*{"enabledAt": armed}
  pr["mergeQueueEntry"] =
    if entry.len == 0: newJNull()
    else: %*{"state": entry}
  writeFile(Stub / "graphql.json", $(%*{"data": {"repository": {"pullRequest": pr}}}))

proc setLabels(labels: openArray[string]) =
  writeFile(Stub / "labels.txt", labels.join("\n") & (if labels.len > 0: "\n" else: ""))

proc labelsNow(): seq[string] =
  for line in readFile(Stub / "labels.txt").splitLines():
    if line.len > 0: result.add(line)

proc callsNow(): seq[string] =
  for line in readFile(Stub / "calls.log").splitLines():
    if line.len > 0: result.add(line)

proc armsNow(): seq[string] =
  for line in readFile(Stub / "arms.log").splitLines():
    if line.len > 0: result.add(line)

type StepResult = tuple[outp: string, code: int, env: string, summary: string]

proc runStep(body: string; envs: openArray[(string, string)]): StepResult =
  ## Execute the production bash verbatim. Only GITHUB_ENV / GITHUB_STEP_SUMMARY
  ## are redirected (they are runner-provided files, not semantics).
  let envFile = getTempDir() / "rearm_env_" & $getCurrentProcessId()
  let sumFile = getTempDir() / "rearm_sum_" & $getCurrentProcessId()
  let script = getTempDir() / "rearm_step_" & $getCurrentProcessId() & ".sh"
  writeFile(envFile, "")
  writeFile(sumFile, "")
  writeFile(script, body)
  var env = newStringTable(modeCaseSensitive)
  for k, v in envPairs():
    if k.startsWith("REARM_") or k.startsWith("GITHUB_"): continue
    env[k] = v
  env["REARM_STUB_DIR"] = Stub
  env["PATH"] = Bin & ":" & getEnv("PATH")
  env["GITHUB_ENV"] = envFile
  env["GITHUB_STEP_SUMMARY"] = sumFile
  env["REPO"] = "Archright/Axiom"
  # The runner always defines these (empty when the event carries no PR);
  # the production scripts use `set -u`, so an absent name is not equivalent.
  env["PR_NUMBER"] = ""
  env["HEAD_SHA"] = ""
  env["RUN_ID"] = ""
  for (k, v) in envs: env[k] = v
  let r = execCmdEx("bash " & quoteShell(script), env = env,
                    options = {poStdErrToStdOut})
  result.outp = r.output
  result.code = r.exitCode
  result.env = readFile(envFile)
  result.summary = readFile(sumFile)
  removeFile(script)
  removeFile(envFile)
  removeFile(sumFile)

proc withOver(base: seq[(string, string)]; k, v: string): seq[(string, string)] =
  result = base
  result.add((k, v))

proc envGet(env, key: string): string =
  for line in env.splitLines():
    if line.startsWith(key & "="): return line[key.len + 1 .. ^1]
  result = ""

proc lastVerdict(summary: string): JsonNode =
  ## emit() writes one JSON object per line; the last one is the verdict.
  for line in summary.splitLines():
    let t = line.strip()
    if t.startsWith("{"):
      result = parseJson(t)

proc actionOf(summary: string): string =
  let v = lastVerdict(summary)
  if v.isNil: "" else: v["rearm"]["action"].getStr("")

proc lineOf(summary: string): string =
  let v = lastVerdict(summary)
  if v.isNil: "" else: v["rearm"]["evidence"]["line"].getStr("")

proc budgetOf(summary: string): string =
  let v = lastVerdict(summary)
  if v.isNil: "" else: v["rearm"]["budget"].getStr("")

proc idx(calls: seq[string]; needle: string): int =
  for i, c in calls:
    if needle in c: return i
  result = -1

# ── structural contract ────────────────────────────────────────────────────

suite "structural — wake-ups, concurrency and execution surface":
  let shape = workflowShape(wfPath)

  test "three wake-ups share one pipeline":
    check shape["triggers"].getElems.mapIt(it.getStr) ==
      @["pull_request_target", "workflow_dispatch", "workflow_run"]

  test "workflow_run is scoped to the admission-gate kernel and completed only":
    let script = """
import sys, yaml, json
d = yaml.safe_load(open(sys.argv[1]))
on = d.get(True) or d.get('on')
print(json.dumps(on['workflow_run']))
"""
    let (outp, code) = pyRun(script, wfPath)
    check code == 0
    let wr = parseJson(outp)
    check wr["workflows"].getElems.mapIt(it.getStr) == @["admission-gate"]
    check wr["types"].getElems.mapIt(it.getStr) == @["completed"]

  test "concurrency keys on the event name so one wake-up cannot replace the other":
    let group = shape["concurrency"]["group"].getStr
    check "github.event_name" in group
    check shape["concurrency"]["cancel-in-progress"].getBool == false

  test "the rearm job never checks out the repository":
    check shape["uses"].getElems.allIt("checkout" notin it.getStr)

  test "no run: scalar contains a GitHub expression (Q4 quirk)":
    for body in shape["run_bodies"].getElems:
      check "${{" notin body.getStr

  test "no run: scalar terminates the job as a failure":
    for body in shape["run_bodies"].getElems:
      check "exit 1" notin body.getStr

  test "all twelve verdict projections are byte-identical":
    var bodies: seq[string]
    for body in shape["run_bodies"].getElems:
      let s = body.getStr
      let i = s.find("emit() {")
      if i < 0: continue
      let j = s.find("\n}\n", i)
      doAssert j > i, "emit() body is not closed by a column-0 brace"
      bodies.add(s[i .. j + 2])
    check bodies.len == 12
    check bodies.deduplicate.len == 1

suite "structural — failure classification keeps the closed enumerations":
  let c6c = stepRun(wfPath, "rearm", "condition 6c")
  let c7 = stepRun(wfPath, "rearm", "condition 7")
  let c6b = stepRun(wfPath, "rearm", "condition 6b")

  test "CANDIDATE_* is never a TRANSIENT title":
    check "ALLOWED=\"NOT_ADMIT_BINDING_MISMATCH NOT_ADMIT_STALE_BASE ADM_IDENTITY\"" in c6c
    check "CANDIDATE_MERGE_BASE_UNRESOLVED" in c6c          # enumerated as UNKNOWN
    check "REARM_CLASS=TRANSIENT\n  echo \"REARM_CODE=$CLASS" notin c6c
    check "CAND_RE='^CANDIDATE_'" in c6c

  test "CANDIDATE_* short-circuits before the log-anchor pass":
    let shortCircuit = c6c.find("CANDIDATE_* code(s)")
    let exitAfter = c6c.find("exit 0", shortCircuit)
    check shortCircuit > 0 and exitAfter > shortCircuit
    # condition 7 only runs when condition 6c produced no classification
    check "if [ -n \"${REARM_CLASS:-}\" ]; then" in c7

  test "the required check is selected by App id, not by name alone":
    check "select(.name == $ctx)" in c6b
    check "select((.app.id // -1) == $app)" in c6b
    check "REQ_APP=\"${REARM_REQUIRED_APP:-}\"" in c6b

  test "a green required check is a no-arm, never an arm":
    check "required-check=success" in c6b
    check "is SUCCESS on G=" in c6b

  test "a trust-surface rejection is PERMANENT":
    check "trust_surface=FAIL" in c6b
    check "emit PERMANENT" in c6b

suite "structural — budget contract (Amendment F)":
  let c8 = stepRun(wfPath, "rearm", "condition 8")
  let c9 = stepRun(wfPath, "rearm", "condition 9")

  test "condition 8 checks the intent label before the confirmed-spend label":
    let intent = c8.find("rearm-intent@$H12\"; then")
    let rearmed = c8.find("rearmed@$H12\"; then")
    check intent > 0
    check rearmed > intent

  test "budget exhaustion is a terminal no-op, not a red job":
    let exhaust = c8.find("BUDGET EXHAUSTED")
    let tail = c8[exhaust .. ^1]
    check "exit 1" notin tail
    check "rearm-exhausted" in tail

  test "the intent label is POSTed before the arm and verified present":
    let post = c9.find("labels[]=rearm-intent@$H12")
    let arm = c9.find("if ERR=$(gh pr merge")
    let verify = c9.find("intent-missing")
    check post > 0 and arm > post and verify > post
    check verify < arm

  test "the confirmed-spend label is written only after a successful arm":
    let arm = c9.find("if ERR=$(gh pr merge")
    let lastConfirmed = c9.rfind("labels[]=rearmed@$H12")
    check arm > 0 and lastConfirmed > arm

  test "a failed arm keeps the intent label and consumes budget":
    let failBranch = c9.find("arm outcome ambiguous")
    check failBranch > 0
    let tail = c9[failBranch .. ^1]
    check "rearm-intent@$H12 retained" in tail
    check "budget counts as spent" in tail
    # the exhaustion marker is written immediately before the verdict
    let marker = c9.rfind("labels[]=rearm-exhausted")
    let arm = c9.find("if ERR=$(gh pr merge")
    check marker > arm and marker < failBranch

  test "the arm is head-pinned and cannot fire from validation mode":
    check "--match-head-commit \"$HEAD_SHA\"" in c9
    check "if [ \"${REARM_LIVE:-0}\" != \"1\" ] || [ \"${DRY_RUN:-}\" = \"true\" ]" in c9

suite "condition 0 executes — workflow_run restores facts from the API":
  let c0 = stepRun(wfPath, "rearm", "condition 0")

  test "a single-PR queue branch resolves the PR and the expected merge-group sha":
    prepare()
    let r = runStep(c0, {
      "EVENT_NAME": "workflow_run", "REARM_DONE": "0",
      "WF_EVENT": "merge_group", "WF_STATUS": "completed",
      "WF_NAME": "admission-gate",
      "WF_PATH": AdmissionPath,
      "WF_HEAD_BRANCH": QueueBranch,
      "WF_HEAD_SHA": MG, "WF_RUN_ATTEMPT": "2"})
    check r.code == 0
    check envGet(r.env, "PR_NUMBER") == "77"
    check envGet(r.env, "HEAD_SHA") == Sha        # PR head, never the MG sha
    check envGet(r.env, "REARM_EXPECTED_G") == MG
    check envGet(r.env, "REARM_RUN_ATTEMPT") == "2"
    check envGet(r.env, "REARM_LIVE") == "1"
    check envGet(r.env, "EVENT_SOURCE") == "workflow_run_completed"

  test "a multi-PR merge group is refused (fail-closed UNKNOWN)":
    prepare()
    let r = runStep(c0, {
      "EVENT_NAME": "workflow_run", "REARM_DONE": "0",
      "WF_EVENT": "merge_group", "WF_STATUS": "completed",
      "WF_NAME": "admission-gate", "WF_PATH": AdmissionPath,
      "WF_HEAD_BRANCH": QueueBranch & "+pr-78-" & MG,
      "WF_HEAD_SHA": MG, "WF_RUN_ATTEMPT": "1"})
    check r.code == 0
    check envGet(r.env, "PR_NUMBER") == ""
    check actionOf(r.summary) == "no-arm"
    check lineOf(r.summary) == "head_branch=" & QueueBranch & "+pr-78-" & MG

  test "a non-merge_group workflow_run is never a verification subject":
    prepare()
    let r = runStep(c0, {
      "EVENT_NAME": "workflow_run", "REARM_DONE": "0",
      "WF_EVENT": "pull_request", "WF_STATUS": "completed",
      "WF_NAME": "admission-gate", "WF_PATH": AdmissionPath,
      "WF_HEAD_BRANCH": "feature/x", "WF_HEAD_SHA": MG})
    check r.code == 0
    check actionOf(r.summary) == "no-arm"
    check lineOf(r.summary) == "wf_event=pull_request"

  test "a wake-up that is not the admission-gate kernel is refused":
    prepare()
    let r = runStep(c0, {
      "EVENT_NAME": "workflow_run", "REARM_DONE": "0",
      "WF_EVENT": "merge_group", "WF_STATUS": "completed",
      "WF_NAME": "publication-integrity",
      "WF_PATH": ".github/workflows/publication-integrity.yml",
      "WF_HEAD_BRANCH": QueueBranch,
      "WF_HEAD_SHA": MG, "WF_RUN_ATTEMPT": "1"})
    check r.code == 0
    check actionOf(r.summary) == "no-arm"
    check r.summary.contains("wf_path=")

  test "dispatch is validation-only (REARM_LIVE=0)":
    prepare()
    let r = runStep(c0, {
      "EVENT_NAME": "workflow_dispatch", "REARM_DONE": "0",
      "PR_NUMBER": "77", "HEAD_SHA": Sha})
    check r.code == 0
    check envGet(r.env, "REARM_LIVE") == "0"

suite "condition 8 executes — the budget is spent before it can be re-spent":
  let c8 = stepRun(wfPath, "rearm", "condition 8")

  proc budgetEnv(): seq[(string, string)] =
    @[("REARM_CLASS", "TRANSIENT"), ("REARM_DONE", "0"),
      ("REARM_LIVE", "1"), ("DRY_RUN", "false"), ("HISTORICAL", "false"),
      ("PR_NUMBER", "77"), ("HEAD_SHA", Sha), ("EVENT_NAME", "workflow_run")]

  test "no label means budget available — nothing is written":
    prepare()
    let r = runStep(c8, budgetEnv())
    check r.code == 0
    check armsNow().len == 0
    check labelsNow().len == 0
    check r.summary.strip.len == 0     # no verdict: the pipeline continues

  test "an intent label without a confirmed arm consumes the budget":
    prepare()
    setLabels(["rearm-intent@" & Sha[0 .. 11]])
    let r = runStep(c8, budgetEnv())
    check r.code == 0
    check actionOf(r.summary) == "no-arm"
    check budgetOf(r.summary) == "spent"
    check lineOf(r.summary) == "intent-orphan"

  test "a confirmed spend is an operator marker, not a red job":
    prepare()
    setLabels(["rearmed@" & Sha[0 .. 11]])
    let r = runStep(c8, budgetEnv())
    check r.code == 0                    # regression guard: was exit 1
    check actionOf(r.summary) == "exhausted"
    check budgetOf(r.summary) == "spent"
    check "rearm-exhausted" in labelsNow()

  test "validation mode never writes the exhaustion marker":
    prepare()
    setLabels(["rearmed@" & Sha[0 .. 11]])
    let r = runStep(c8, withOver(budgetEnv(), "REARM_LIVE", "0"))
    check r.code == 0
    check "rearm-exhausted" notin labelsNow()

  test "a non-TRANSIENT classification never reaches the budget step":
    prepare()
    setLabels(["rearmed@" & Sha[0 .. 11]])
    let r = runStep(c8, withOver(budgetEnv(), "REARM_CLASS", "PERMANENT"))
    check r.code == 0
    check "rearm-exhausted" notin labelsNow()
    check r.summary.strip.len == 0

suite "condition 9 executes — one arm, claimed before it happens":
  let c9 = stepRun(wfPath, "rearm", "condition 9")

  proc armEnv(): seq[(string, string)] =
    @[("REARM_CLASS", "TRANSIENT"), ("REARM_G", MG), ("REARM_DONE", ""),
      ("REARM_LIVE", "1"), ("DRY_RUN", "false"), ("HISTORICAL", "false"),
      ("PR_NUMBER", "77"), ("HEAD_SHA", Sha), ("GH_TOKEN", "ghs_stub")]

  test "the happy path claims budget before arming and confirms it after":
    prepare()
    setGraphql()
    let r = runStep(c9, armEnv())
    check r.code == 0
    check actionOf(r.summary) == "armed"
    check armsNow().len == 1
    check "--match-head-commit " & Sha in armsNow()[0]
    let calls = callsNow()
    let intentPost = calls.idx("labels[]=rearm-intent@" & Sha[0 .. 11])
    let arm = calls.idx("pr merge")
    let spend = calls.idx("labels[]=rearmed@" & Sha[0 .. 11])
    check intentPost >= 0 and arm > intentPost and spend > arm
    check ("rearm-intent@" & Sha[0 .. 11]) in labelsNow()
    check ("rearmed@" & Sha[0 .. 11]) in labelsNow()

  test "a moved PR head invalidates the classification — no arm, no claim":
    prepare()
    setGraphql(head = OtherSha)
    let r = runStep(c9, armEnv())
    check r.code == 0
    check lineOf(r.summary) == "head-moved"
    check armsNow().len == 0
    check labelsNow().len == 0

  test "a PR already back in the queue is not armed again":
    prepare()
    setGraphql(inq = true, entry = "AWAITING_CHECKS")
    let r = runStep(c9, armEnv())
    check r.code == 0
    check lineOf(r.summary) == "queued-again"
    check armsNow().len == 0
    check labelsNow().len == 0

  test "an existing auto-merge request is reconciled, never re-armed":
    prepare()
    setGraphql(armed = "2026-11-22T00:00:00Z")
    let r = runStep(c9, armEnv())
    check r.code == 0
    check actionOf(r.summary) == "armed"
    check lineOf(r.summary) == "already-armed"
    check armsNow().len == 0
    check ("rearmed@" & Sha[0 .. 11]) in labelsNow()

  test "a concurrent budget consumption blocks the arm":
    prepare()
    setGraphql()
    setLabels(["rearmed@" & Sha[0 .. 11]])
    let r = runStep(c9, armEnv())
    check r.code == 0
    check lineOf(r.summary) == "budget-consumed"
    check armsNow().len == 0

  test "an ambiguous arm failure keeps the intent and marks the PR":
    prepare()
    setGraphql()
    let r = runStep(c9, withOver(armEnv(), "STUB_ARM_EXIT", "7"))
    check r.code == 0
    check actionOf(r.summary) == "no-arm"
    check lineOf(r.summary) == "arm-failed"
    check budgetOf(r.summary) == "spent"
    check ("rearm-intent@" & Sha[0 .. 11]) in labelsNow()
    check "rearm-exhausted" in labelsNow()

  test "a missing App credential is a fail-safe no-arm":
    prepare()
    setGraphql()
    let r = runStep(c9, withOver(armEnv(), "GH_TOKEN", ""))
    check r.code == 0
    check lineOf(r.summary) == "token-missing"
    check armsNow().len == 0

  test "validation mode never mutates":
    prepare()
    setGraphql()
    let r = runStep(c9, withOver(armEnv(), "REARM_LIVE", "0"))
    check r.code == 0
    check lineOf(r.summary) == "would-arm"
    check armsNow().len == 0
    check labelsNow().len == 0