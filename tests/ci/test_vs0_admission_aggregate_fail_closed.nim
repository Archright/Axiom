{.push raises: [CatchableError].}

## test_vs0_admission_aggregate_fail_closed.nim — VS-0 G2 계약 (admission aggregate fail-closed).
##
## `admission-gate-v2.yml`의 aggregate job(`admission-check`)은 required check
## context의 생산자다. 이 job의 실제 허용 집합은 "전부 success"가 아니다:
##
##   A1  7개 needed job 전부 `success` (event 무관)
##   A2  `anchor-resolve=skipped` + 나머지 6 `success` + `EVENT_NAME`이 set이고
##       `!= "pull_request"` (trigger set pin 덕분에 reachable event 중에서는
##       merge_group과 동치)
##
## A2 밖의 skip은 merge-group venue에서 조용한 green이 되고, A1만 고정하는
## 계약은 dead gate다. 이 파일은 (1) 구조 계약, (2) 실제 bash 실행 행동 matrix,
## (3) 15종 mutation 검출을 한 단언으로 묶는다.
##
## YAML 파서: Nim 2.2.10 stdlib에는 YAML parser가 없고, 이 저장소의 GitHub
## Actions YAML은 restricted subset 도구로 다룰 수 없다. required check
## `admission-check.yml`이 이미 쓰는 선례를 따른다 — 런타임 temp Python helper가
## PyYAML `StrictLoader`(duplicate key 거부, `on:`→`True` quirk 처리)로 파싱한다.
## 저장소에는 `.py` 파일을 추가하지 않는다.
##
## 행동 기대값은 predicate를 재구현해서 만들지 않는다. 56개 조합의 실제 통과
## 집합을 손으로 열거한 allow-list(A1/A2)와 집합 비교하고, 그 밖의 모든
## 조합·적대 토큰은 deny임을 단언한다.

import std/[algorithm, os, osproc, strtabs, strutils, unittest]

const
  WorkflowRel = ".github/workflows/admission-gate-v2.yml"
  SliceWorkflowRel = ".github/workflows/axiom-operational-slice.yml"
  TrustManifestRel = "config/policy/trust_surface_manifest.json"
  SelfRel = "tests/ci/test_vs0_admission_aggregate_fail_closed.nim"
  AggregateJob = "admission-check"
  AnchorJob = "anchor-resolve"

  NeededJobs = [
    "anchor-resolve", "closure-deriver", "attest", "mint-prepare",
    "mint-publish", "verdict", "gateway"
  ]

  ResultValues = ["success", "failure", "cancelled", "skipped"]
  Events = ["pull_request", "merge_group"]
  AdversarialTokens = ["", "Success", "neutral", "timed_out", "unknown"]

  # 구조 계약이 고정하는 production run body의 조각들.
  AnchorSuccessCheck = "[ \"$RESULT_ANCHOR_RESOLVE\" = \"success\" ]"
  AnchorSkippedCheck = "[ \"$RESULT_ANCHOR_RESOLVE\" = \"skipped\" ]"
  AnchorEventCheck = "[ \"$EVENT_NAME\" != \"pull_request\" ]"
  NeedsLine = "    needs: [anchor-resolve, closure-deriver, attest, mint-prepare, mint-publish, verdict, gateway]"
  AggregateIfLine = "    if: ${{ always() }}"
  AttestCheckLine = "          [ \"$RESULT_ATTEST\" = \"success\" ] \\"
  VerdictCheckLine = "          [ \"$RESULT_VERDICT\" = \"success\" ] \\"
  MintPublishCheckLine = "          [ \"$RESULT_MINT_PUBLISH\" = \"success\" ] \\"
  StepNameLine = "      - name: \"[verdict] Every needed job must be success (skipped -> FAILURE, never green)\""

# ── repo root / temp workspace ────────────────────────────────────────────

let
  TempDir = getTempDir() / ("axiom_vs0_contract_" & $getCurrentProcessId())
  HelperPath = TempDir / "parse_workflow.py"

proc findRepoRootDir(): string =
  var dir = getCurrentDir()
  for _ in 0 ..< 10:
    if fileExists(dir / ".axiom_root"):
      return dir
    dir = parentDir(dir)
  ""

# ── 런타임 temp Python helper (PyYAML StrictLoader) ──────────────────────
#
# 출력 protocol (탭 구분, UTF-8 bytes):
#   OK
#   TRIGGERS\t<sorted comma list>
#   MG_TYPES\t<comma list>
#   JOB_KEYS\t<sorted comma list>
#   NAME\t<value> / NEEDS\t<comma list> / IF\t<value>
#   JOB_COE\t<present|empty>
#   STEPS\t<n> / STEP_IF_COUNT\t<n> / STEP_COE_COUNT\t<n>
#   ENV_KEYS\t<sorted comma list>
#   ENV\t<KEY>\t<value>
#   RUN_BEGIN
#   <run body lines verbatim>
#   RUN_END
# 실패 시 PARSE_ERROR\t<message> 1줄 + exit 1.

const PyHelper = """import sys

try:
    import yaml
except Exception as exc:
    sys.stdout.buffer.write(("PARSE_ERROR\tPyYAML unavailable: %s\n" % exc).encode("utf-8"))
    sys.stdout.buffer.flush()
    sys.exit(1)

out = []


class DupKey(Exception):
    pass


def load_strict(raw):
    class StrictLoader(yaml.SafeLoader):
        pass

    def construct_mapping(loader, node, deep=False):
        loader.flatten_mapping(node)
        seen = set()
        for key_node, _ in node.value:
            key = loader.construct_object(key_node, deep=deep)
            try:
                hash(key)
                marker = (type(key).__name__, key)
            except TypeError:
                marker = ("unhashable", repr(key))
            if marker in seen:
                raise DupKey("duplicate mapping key %r" % (key,))
            seen.add(marker)
        return yaml.SafeLoader.construct_mapping(loader, node, deep=deep)

    StrictLoader.add_constructor(
        yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, construct_mapping)
    return yaml.load(raw, Loader=StrictLoader)


def ascii_only(text):
    return str(text).encode("ascii", "backslashreplace").decode("ascii")


def emit(key, value):
    out.append("%s\t%s\n" % (key, ascii_only(value).replace("\t", " ").replace("\n", " ")))


def scalar(value):
    if value is None:
        return ""
    if value is True:
        return "true"
    if value is False:
        return "false"
    return str(value)


def as_list(value):
    if value is None:
        return []
    if isinstance(value, (list, tuple)):
        return [scalar(item) for item in value]
    return [scalar(value)]


def flush():
    sys.stdout.buffer.write("".join(out).encode("utf-8"))
    sys.stdout.buffer.flush()
    del out[:]


def main():
    if len(sys.argv) != 2:
        emit("PARSE_ERROR", "usage: parse_workflow.py <workflow.yml>")
        flush()
        return 1
    path = sys.argv[1]
    try:
        with open(path, "r", encoding="utf-8") as handle:
            raw = handle.read()
    except Exception as exc:
        emit("PARSE_ERROR", "open failed: %s" % exc)
        flush()
        return 1
    try:
        doc = load_strict(raw)
    except Exception as exc:
        emit("PARSE_ERROR", "%s: %s" % (type(exc).__name__, exc))
        flush()
        return 1
    if not isinstance(doc, dict):
        emit("PARSE_ERROR", "document root is not a mapping")
        flush()
        return 1

    out.append("OK\n")

    triggers = doc.get("on", doc.get(True))
    trigger_keys = []
    merge_group_types = []
    if isinstance(triggers, dict):
        trigger_keys = sorted(str(key) for key in triggers.keys())
        merge_group = triggers.get("merge_group")
        if isinstance(merge_group, dict):
            merge_group_types = as_list(merge_group.get("types"))
    elif isinstance(triggers, list):
        trigger_keys = sorted(str(key) for key in triggers)
    elif isinstance(triggers, str):
        trigger_keys = [triggers]
    emit("TRIGGERS", ",".join(trigger_keys))
    emit("MG_TYPES", ",".join(merge_group_types))

    jobs = doc.get("jobs")
    if not isinstance(jobs, dict):
        emit("PARSE_ERROR", "jobs is not a mapping")
        flush()
        return 1
    emit("JOB_KEYS", ",".join(sorted(str(key) for key in jobs.keys())))

    job = jobs.get("admission-check")
    if not isinstance(job, dict):
        emit("PARSE_ERROR", "jobs.admission-check is not a mapping")
        flush()
        return 1
    emit("NAME", scalar(job.get("name")))
    emit("NEEDS", ",".join(as_list(job.get("needs"))))
    emit("IF", scalar(job.get("if")))
    emit("JOB_COE", "present" if "continue-on-error" in job else "")
    steps = job.get("steps")
    step_list = steps if isinstance(steps, list) else []
    emit("STEPS", str(len(step_list)))
    emit("STEP_IF_COUNT", str(sum(
        1 for step in step_list if isinstance(step, dict) and "if" in step)))
    emit("STEP_COE_COUNT", str(sum(
        1 for step in step_list
        if isinstance(step, dict) and "continue-on-error" in step)))
    if len(step_list) != 1 or not isinstance(step_list[0], dict):
        flush()
        return 0
    step = step_list[0]
    env = step.get("env")
    env_map = env if isinstance(env, dict) else {}
    emit("ENV_KEYS", ",".join(sorted(str(key) for key in env_map.keys())))
    for key in sorted(env_map.keys(), key=str):
        emit("ENV\t" + str(key), scalar(env_map[key]))
    run = step.get("run")
    if isinstance(run, str):
        out.append("RUN_BEGIN\n")
        out.append(run if run.endswith("\n") else run + "\n")
        out.append("RUN_END\n")
    flush()
    return 0


try:
    sys.exit(main())
except Exception as exc:
    emit("PARSE_ERROR", "unexpected: %s: %s" % (type(exc).__name__, exc))
    flush()
    sys.exit(1)
"""

# ── 파싱 ─────────────────────────────────────────────────────────────────

type
  WorkflowDoc = object
    ok: bool
    parseError: string
    fields: StringTableRef
    env: StringTableRef
    runBody: string

proc ensureHelper() =
  if not fileExists(HelperPath):
    createDir(TempDir)
    writeFile(HelperPath, PyHelper)

proc parseWorkflow(workflowPath: string): WorkflowDoc =
  result.fields = newStringTable(modeCaseSensitive)
  result.env = newStringTable(modeCaseSensitive)
  ensureHelper()
  let cmd = "python3 " & quoteShell(HelperPath) & " " & quoteShell(workflowPath)
  let r = execCmdEx(cmd)
  var sawOk = false
  var inRun = false
  for line in r.output.splitLines():
    if inRun:
      if line == "RUN_END":
        inRun = false
      else:
        result.runBody.add(line)
        result.runBody.add('\n')
      continue
    if line == "RUN_BEGIN":
      inRun = true
    elif line == "OK":
      sawOk = true
    elif line.startsWith("PARSE_ERROR\t"):
      result.parseError = line["PARSE_ERROR\t".len .. ^1]
    elif line.startsWith("ENV\t"):
      let rest = line["ENV\t".len .. ^1]
      let tab = rest.find('\t')
      if tab < 0:
        result.env[rest] = ""
      else:
        result.env[rest[0 ..< tab]] = rest[tab + 1 .. ^1]
    elif line.contains('\t'):
      let tab = line.find('\t')
      result.fields[line[0 ..< tab]] = line[tab + 1 .. ^1]
  if not sawOk and result.parseError.len == 0:
    result.parseError = "helper exit " & $r.exitCode &
      " (python3/PyYAML unavailable?): " & r.output.strip()
  result.ok = sawOk and result.parseError.len == 0

proc field(doc: WorkflowDoc; key: string): string =
  doc.fields.getOrDefault(key, "")

proc resultEnvName(job: string): string =
  "RESULT_" & job.replace("-", "_").toUpperAscii()

proc normalizeExpression(raw: string): string =
  ## `${{ always() }}` / `always()` / `"always()"` → `always()`.
  result = raw.strip()
  if result.len >= 2 and (result[0] == '"' or result[0] == '\'') and
     result[^1] == result[0]:
    result = result[1 ..< result.len - 1].strip()
  if result.startsWith("${{"):
    result = result[3 .. ^1]
  if result.endsWith("}}"):
    result = result[0 ..< result.len - 2]
  result = result.strip()

# ── 구조 계약 ────────────────────────────────────────────────────────────
#
# 반환값은 실패 사유 목록이다 — 빈 목록 = PASS. 사유는 안정된 prefix 코드로
# 시작해 mutation 기대값과 대조할 수 있다.

proc checkContract(workflowPath: string): seq[string] =
  result = @[]
  let doc = parseWorkflow(workflowPath)
  if not doc.ok:
    result.add("PARSE " & doc.parseError)
    return

  # trigger set 고정 — 이 pin이 `EVENT_NAME != "pull_request"`를 reachable
  # event 안에서 merge_group과 동치로 만든다.
  var triggerKeys = doc.field("TRIGGERS").split(',')
  var sortedTriggers = triggerKeys
  sortedTriggers.sort()
  if sortedTriggers != @["merge_group", "pull_request"]:
    result.add("TRIGGER_KEYS " & $triggerKeys)
  var mgTypes = doc.field("MG_TYPES").split(',')
  var sortedMg = mgTypes
  sortedMg.sort()
  if sortedMg != @["checks_requested"]:
    result.add("TRIGGER_MG_TYPES " & $mgTypes)

  # workflow job universe: 7 needed + aggregate, 그 외 없음.
  var jobKeys = doc.field("JOB_KEYS").split(',')
  var sortedJobs = jobKeys
  sortedJobs.sort()
  var expectedJobs = @NeededJobs & @[AggregateJob]
  expectedJobs.sort()
  if sortedJobs != expectedJobs:
    result.add("JOB_KEYS " & $jobKeys)

  if doc.field("NAME") != AggregateJob:
    result.add("NAME '" & doc.field("NAME") & "'")

  var needs = doc.field("NEEDS").split(',')
  var sortedNeeds = needs
  sortedNeeds.sort()
  var expectedNeeds = @NeededJobs
  expectedNeeds.sort()
  if needs.len != expectedNeeds.len or sortedNeeds != expectedNeeds:
    result.add("NEEDS " & $needs)

  if normalizeExpression(doc.field("IF")) != "always()":
    result.add("AGGREGATE_IF '" & doc.field("IF") & "'")

  if doc.field("STEPS") != "1":
    result.add("STEPS " & doc.field("STEPS"))
  if doc.field("STEP_IF_COUNT") != "0":
    result.add("STEP_IF " & doc.field("STEP_IF_COUNT"))
  if doc.field("JOB_COE").len > 0:
    result.add("CONTINUE_ON_ERROR job")
  if doc.field("STEP_COE_COUNT") != "0":
    result.add("CONTINUE_ON_ERROR step " & doc.field("STEP_COE_COUNT"))

  # env: 정확히 8키 (7 RESULT_* + EVENT_NAME), one-to-one mapping.
  var envKeys = doc.field("ENV_KEYS").split(',')
  var sortedEnv = envKeys
  sortedEnv.sort()
  var expectedEnv = @["EVENT_NAME"]
  for job in NeededJobs:
    expectedEnv.add(resultEnvName(job))
  expectedEnv.sort()
  if sortedEnv != expectedEnv:
    result.add("ENV_KEYS " & $envKeys)

  if not doc.env.hasKey("EVENT_NAME") or
     doc.env["EVENT_NAME"] != "${{ github.event_name }}":
    result.add("ENV_EVENT_NAME '" & doc.env.getOrDefault("EVENT_NAME", "<missing>") & "'")
  for job in NeededJobs:
    let key = resultEnvName(job)
    let expected = "${{ needs." & job & ".result }}"
    let actual = doc.env.getOrDefault(key, "<missing>")
    if actual != expected:
      result.add("ENV_RESULT " & key & "='" & actual & "' expected '" & expected & "'")

  # run body — shell 계약.
  let run = doc.runBody
  if "set -euo pipefail" notin run:
    result.add("RUN_SHELL set -euo pipefail missing")

  var failExitsOne = false
  for line in run.splitLines():
    if line.strip().startsWith("fail()") and "exit 1" in line:
      failExitsOne = true
  if not failExitsOne:
    result.add("RUN_FAIL fail() with 'exit 1' missing")

  let anchorStart = run.find("if " & AnchorSuccessCheck)
  let anchorEnd = if anchorStart >= 0: run.find("\nfi", anchorStart) else: -1
  if anchorStart < 0 or anchorEnd < 0:
    result.add("RUN_ANCHOR branch missing")
  else:
    let branch = run[anchorStart ..< anchorEnd]
    if AnchorSkippedCheck notin branch:
      result.add("RUN_ANCHOR 'skipped' arm missing")
    if AnchorEventCheck notin branch:
      result.add("RUN_ANCHOR EVENT_NAME condition missing")
  for job in NeededJobs:
    if job == AnchorJob:
      continue
    if "[ \"$" & resultEnvName(job) & "\" = \"success\" ]" notin run:
      result.add("RUN_CHECK " & job)

  for token in ["|| true", "exit 0", "set +e"]:
    if token in run:
      result.add("RUN_FORBIDDEN '" & token & "'")

# ── bash 실행 (행동 matrix) ──────────────────────────────────────────────

proc bashPath(): string =
  result = findExe("bash")
  if result.len == 0:
    result = "/bin/bash"

proc runAggregate(scriptPath: string; vars: openArray[(string, string)]): int =
  ## production `run` 본문을 그대로 bash로 실행한다. `env -i`로 깨끗한 환경을
  ## 쓰므로 전달하지 않은 변수는 진짜 unset이고, `set -u` 의미가 CI와 같다.
  var cmd = "env -i"
  for (key, value) in vars:
    cmd.add " " & key & "=" & quoteShell(value)
  cmd.add " " & quoteShell(bashPath()) & " " & quoteShell(scriptPath)
  execCmdEx(cmd).exitCode

proc successVars(): seq[(string, string)] =
  result = @[]
  for job in NeededJobs:
    result.add((resultEnvName(job), "success"))

proc withPosition(vars: seq[(string, string)];
                  job, value: string): seq[(string, string)] =
  result = @[]
  for (key, current) in vars:
    if key == resultEnvName(job):
      result.add((key, value))
    else:
      result.add((key, current))

proc caseKey(job, value, event: string): string =
  ## 전부 success인 조합은 위치마다 반복되므로 하나의 키로 접는다.
  if value == "success":
    "ALL-SUCCESS@" & event
  else:
    job & "=" & value & "@" & event

proc dedupeSorted(s: seq[string]): seq[string] =
  ## 정렬된 seq의 인접 중복 제거 (std/sequtils 의존 없이).
  result = @[]
  for item in s:
    if result.len == 0 or result[^1] != item:
      result.add(item)

# ── mutation primitives (전체 줄 단위 — 부분 문자열 오염 없음) ────────────

type
  Mutation = object
    id: string
    removes: seq[string]
    replaces: seq[tuple[oldLine, newLine: string]]
    insertsBefore: seq[tuple[anchor: string, lines: seq[string]]]
    insertsAfter: seq[tuple[anchor: string, lines: seq[string]]]
    expects: seq[string]

proc requireSingle(hits: int; what: string) =
  doAssert hits == 1, "mutation anchor must match exactly once: " & what &
    " (matched " & $hits & ")"

proc insertBlock(lines: var seq[string]; at: int; blockLines: seq[string]) =
  ## `seq.insert`는 단일 원소만 받는다 — 줄 블록 삽입은 뒤에서 앞으로.
  for offset in countdown(blockLines.len - 1, 0):
    lines.insert(blockLines[offset], at)

proc applyMutation(src: string; m: Mutation): string =
  var lines = src.splitLines()

  for target in m.removes:
    var kept: seq[string] = @[]
    var hits = 0
    for line in lines:
      if line == target:
        inc hits
      else:
        kept.add(line)
    requireSingle(hits, m.id & " remove: " & target)
    lines = kept

  for (oldLine, newLine) in m.replaces:
    var hits = 0
    for i in 0 ..< lines.len:
      if lines[i] == oldLine:
        inc hits
        lines[i] = newLine
    requireSingle(hits, m.id & " replace: " & oldLine)

  for (anchor, newLines) in m.insertsBefore:
    var at = -1
    var hits = 0
    for i in 0 ..< lines.len:
      if lines[i] == anchor:
        inc hits
        at = i
    requireSingle(hits, m.id & " insert-before anchor: " & anchor)
    insertBlock(lines, at, newLines)

  for (anchor, newLines) in m.insertsAfter:
    var at = -1
    var hits = 0
    for i in 0 ..< lines.len:
      if lines[i] == anchor:
        inc hits
        at = i
    requireSingle(hits, m.id & " insert-after anchor: " & anchor)
    insertBlock(lines, at + 1, newLines)

  # `splitLines`는 trailing newline을 마지막 "" 원소로 보존한다 — join이
  # 원본과 byte-identical하다 (이 저장소의 YAML은 LF-only).
  lines.join("\n")

# ── 테스트 픽스처 ────────────────────────────────────────────────────────

let
  RepoRoot = findRepoRootDir()

proc productionDoc(): WorkflowDoc =
  parseWorkflow(RepoRoot / WorkflowRel)

proc writeScript(name, body: string): string =
  result = TempDir / name
  writeFile(result, body)

proc writeMutant(name: string; mutation: Mutation): string =
  let src = readFile(RepoRoot / WorkflowRel)
  let path = TempDir / (name & ".yml")
  writeFile(path, applyMutation(src, mutation))
  path

proc textContains(haystack, needle: string): bool =
  ## `check a in hugeString`은 실패 시 문자열 전문을 출력한다 — boolean으로 접는다.
  needle in haystack

# ── mutation 15종 정의 (M01–M15, M01/M05는 두 형태) ─────────────────────

const
  NeedsWithoutVerdict = "    needs: [anchor-resolve, closure-deriver, attest, mint-prepare, mint-publish, gateway]"

  Mutations = [
    # M01a — aggregate `if`를 `!cancelled()`로 약화 (skipped need에서도 green).
    Mutation(
      id: "M01a-if-ncancelled",
      replaces: @[(oldLine: AggregateIfLine,
                   newLine: "    if: ${{ !cancelled() }}")],
      expects: @["AGGREGATE_IF"]),
    # M01b — aggregate `if` 제거: need 실패 시 aggregate 자체가 skip된다.
    Mutation(
      id: "M01b-if-removed",
      removes: @[AggregateIfLine],
      expects: @["AGGREGATE_IF"]),
    # M02 — needs 7→6 (env/check 동반 제거): verdict를 의존성에서 뺀다.
    Mutation(
      id: "M02-needs-shrink",
      removes: @[
        "          RESULT_VERDICT: ${{ needs.verdict.result }}",
        VerdictCheckLine
      ],
      replaces: @[(oldLine: NeedsLine, newLine: NeedsWithoutVerdict)],
      expects: @["NEEDS", "ENV_KEYS", "RUN_CHECK"]),
    # M03 — extra need: 계약 밖 job을 DAG에 끼워 넣는다.
    Mutation(
      id: "M03-extra-need",
      insertsBefore: @[(anchor: "  admission-check:",
                        lines: @[
                          "  rogue-audit:",
                          "    runs-on: ubuntu-latest",
                          "    steps:",
                          "      - run: echo rogue",
                          ""
                        ])],
      replaces: @[(oldLine: NeedsLine,
                   newLine: "    needs: [anchor-resolve, closure-deriver, attest, mint-prepare, mint-publish, verdict, gateway, rogue-audit]")],
      expects: @["JOB_KEYS", "NEEDS"]),
    # M04 — RESULT_GATEWAY를 verdict.result에 재바인딩: verdict가 gateway를 대신한다.
    Mutation(
      id: "M04-result-rebound",
      replaces: @[(oldLine: "          RESULT_GATEWAY: ${{ needs.gateway.result }}",
                   newLine: "          RESULT_GATEWAY: ${{ needs.verdict.result }}")],
      expects: @["ENV_RESULT"]),
    # M05a — guard를 `true`로 약화: 결과 검사 자체가 사라진다.
    Mutation(
      id: "M05a-guard-true",
      replaces: @[(oldLine: AttestCheckLine, newLine: "          true \\")],
      expects: @["RUN_CHECK"]),
    # M05b — `|| true`로 실패를 삼킨다.
    Mutation(
      id: "M05b-guard-or-true",
      replaces: @[(oldLine: AttestCheckLine,
                   newLine: "          [ \"$RESULT_ATTEST\" = \"success\" ] || true \\")],
      expects: @["RUN_FORBIDDEN"]),
    # M06 — anchor 분기의 EVENT_NAME 조건 제거: PR에서도 skip이 green이 된다.
    Mutation(
      id: "M06-anchor-event-removed",
      replaces: @[(oldLine: "          elif [ \"$RESULT_ANCHOR_RESOLVE\" = \"skipped\" ] && [ \"$EVENT_NAME\" != \"pull_request\" ]; then",
                   newLine: "          elif [ \"$RESULT_ANCHOR_RESOLVE\" = \"skipped\" ]; then")],
      expects: @["RUN_ANCHOR"]),
    # M07 — anchor가 아닌 job의 skip을 허용: 조용한 green 경로.
    Mutation(
      id: "M07-other-skip-allowed",
      replaces: @[(oldLine: AttestCheckLine,
                   newLine: "          [ \"$RESULT_ATTEST\" = \"skipped\" ] \\")],
      expects: @["RUN_CHECK"]),
    # M08 — continue-on-error: true (job level) — 실패가 success로 보고된다.
    Mutation(
      id: "M08-continue-on-error",
      insertsAfter: @[(anchor: "    name: admission-check",
                       lines: @["    continue-on-error: true"])],
      expects: @["CONTINUE_ON_ERROR"]),
    # M09 — step `if: false`: aggregate step이 실행되지 않는다.
    Mutation(
      id: "M09-step-if-false",
      insertsAfter: @[(anchor: StepNameLine, lines: @["        if: false"])],
      expects: @["STEP_IF"]),
    # M10 — EVENT_NAME 상수화: PR에서도 anchor skip이 green이 된다.
    Mutation(
      id: "M10-event-hardcoded",
      replaces: @[(oldLine: "          EVENT_NAME: ${{ github.event_name }}",
                   newLine: "          EVENT_NAME: merge_group")],
      expects: @["ENV_EVENT_NAME"]),
    # M11 — merge_group trigger 제거: queue venue가 계약에서 빠진다.
    Mutation(
      id: "M11-merge-group-trigger-removed",
      removes: @["  merge_group:", "    types:", "      - checks_requested"],
      expects: @["TRIGGER_KEYS"]),
    # M12 — required context 이름 변경.
    Mutation(
      id: "M12-name-changed",
      replaces: @[(oldLine: "    name: admission-check",
                   newLine: "    name: admission-check-v2")],
      expects: @["NAME"]),
    # M13 — duplicate `needs` key: last-wins 파서에서는 조용히 재정의된다.
    Mutation(
      id: "M13-duplicate-needs",
      insertsAfter: @[(anchor: NeedsLine, lines: @[NeedsLine])],
      expects: @["PARSE"]),
    # M14 — fail()이 exit 0: 모든 실패가 green으로 뒤집힌다.
    Mutation(
      id: "M14-fail-exit-zero",
      replaces: @[(oldLine: "          fail() { echo \"ADMISSION_GATE: FAIL — $1 (fail-closed)\" >&2; exit 1; }",
                   newLine: "          fail() { echo \"ADMISSION_GATE: FAIL\" >&2; exit 0; }")],
      expects: @["RUN_FAIL"]),
    # M15 — 결과 check 한 줄 삭제 (mint-publish).
    Mutation(
      id: "M15-check-line-deleted",
      removes: @[
        MintPublishCheckLine,
        "            || fail \"needed job 'mint-publish' result='$RESULT_MINT_PUBLISH' (expected 'success' — skipped/cancelled/failed must block, never green)\""
      ],
      expects: @["RUN_CHECK"])
  ]

proc mutationById(id: string): Mutation =
  for m in Mutations:
    if m.id == id:
      return m
  doAssert false, "unknown mutation id: " & id

proc mutatedRunScript(m: Mutation): string =
  let path = writeMutant(m.id & "-behavior", m)
  let doc = parseWorkflow(path)
  doAssert doc.ok, "mutant YAML did not parse: " & m.id
  writeScript(m.id & "-behavior.sh", doc.runBody)

proc missingCodes(reasons: seq[string]; expects: seq[string]): seq[string] =
  result = @[]
  for code in expects:
    var found = false
    for reason in reasons:
      if reason.startsWith(code):
        found = true
    if not found:
      result.add(code)

# ── suite ────────────────────────────────────────────────────────────────

try:

  suite "VS-0 G2 — admission aggregate 구조 계약":

    test "positive control: production workflow는 모든 조항을 통과한다":
      check RepoRoot.len > 0
      let reasons = checkContract(RepoRoot / WorkflowRel)
      if reasons.len > 0:
        checkpoint($reasons)
      check reasons.len == 0

    test "positive control: 무변조 copy도 통과한다 (경로 의존 없음)":
      let src = readFile(RepoRoot / WorkflowRel)
      let copyPath = TempDir / "copy.yml"
      writeFile(copyPath, src)
      check readFile(copyPath) == src
      let reasons = checkContract(copyPath)
      if reasons.len > 0:
        checkpoint($reasons)
      check reasons.len == 0

    test "negative control: invalid YAML은 crash 없이 PARSE로 FAIL":
      let badPath = TempDir / "invalid.yml"
      writeFile(badPath, "name: x\non: [\njobs: {\n")
      let reasons = checkContract(badPath)
      checkpoint($reasons)
      check reasons.len > 0
      check reasons[0].startsWith("PARSE")

    test "negative control: 없는 파일은 crash 없이 PARSE로 FAIL":
      let reasons = checkContract(TempDir / "does_not_exist.yml")
      checkpoint($reasons)
      check reasons.len > 0
      check reasons[0].startsWith("PARSE")

    test "mutation matrix: M01–M15 전부 기대 사유로 검출된다":
      let src = readFile(RepoRoot / WorkflowRel)
      for m in Mutations:
        checkpoint(m.id)
        let path = writeMutant(m.id, m)
        let reasons = checkContract(path)
        let missing = missingCodes(reasons, m.expects)
        if reasons.len == 0 or missing.len > 0:
          checkpoint("reasons=" & $reasons & " missing=" & $missing)
        check reasons.len > 0
        check missing.len == 0

    test "mutation primitives: 빈 mutation은 원본과 byte-identical하다":
      let src = readFile(RepoRoot / WorkflowRel)
      let identity = Mutation(id: "identity")
      check applyMutation(src, identity) == src
      check src.splitLines().join("\n") == src

  suite "VS-0 G2 — admission aggregate 행동 matrix":

    test "56개 조합(7×4×2)의 통과 집합 = 손으로 열거한 allow-list":
      let doc = productionDoc()
      check doc.ok
      let script = writeScript("aggregate_production.sh", doc.runBody)

      var passed: seq[string] = @[]
      var total = 0
      for job in NeededJobs:
        for value in ResultValues:
          for event in Events:
            inc total
            var vars = withPosition(successVars(), job, value)
            vars.add(("EVENT_NAME", event))
            if runAggregate(script, vars) == 0:
              passed.add(caseKey(job, value, event))

      check total == 56
      var distinctPassed = passed
      distinctPassed.sort()
      distinctPassed = dedupeSorted(distinctPassed)

      # 손으로 열거한 allow-list — predicate 재구현이 아니라 통과 "목록"이다.
      #   A1 전부 success (event 무관)
      #   A2 anchor-resolve=skipped + 나머지 6 success + EVENT_NAME set ∧ != pull_request
      let allowed = @[
        "ALL-SUCCESS@merge_group",
        "ALL-SUCCESS@pull_request",
        "anchor-resolve=skipped@merge_group"
      ]
      checkpoint("distinct pass set = " & $distinctPassed)
      check distinctPassed == allowed
      # 전부 success는 위치마다 반복되므로 14 + anchor-skipped MG 1 = 15.
      check passed.len == 15

    test "적대 토큰 20조합 (anchor + 비-anchor × 5토큰 × 2event)은 전부 deny":
      let doc = productionDoc()
      check doc.ok
      let script = writeScript("aggregate_adversarial.sh", doc.runBody)
      var denyCount = 0
      var total = 0
      for job in [AnchorJob, "verdict"]:
        for token in AdversarialTokens:
          for event in Events:
            inc total
            var vars = withPosition(successVars(), job, token)
            vars.add(("EVENT_NAME", event))
            let code = runAggregate(script, vars)
            if code != 0:
              inc denyCount
            else:
              checkpoint("unexpected PASS: " & job & "=" & token & "@" & event)
      check total == 20
      check denyCount == 20

    test "추가 fail-closed 경계: all-bad / all-unset / anchor-skip + EVENT_NAME unset·empty":
      let doc = productionDoc()
      check doc.ok
      let script = writeScript("aggregate_edges.sh", doc.runBody)

      # all-bad — 7개 전부 failure는 어느 event에서도 deny.
      for event in Events:
        var vars: seq[(string, string)] = @[]
        for job in NeededJobs:
          vars.add((resultEnvName(job), "failure"))
        vars.add(("EVENT_NAME", event))
        check runAggregate(script, vars) != 0

      # all-env-unset — set -u가 첫 참조에서 죽는다 (fail-closed).
      check runAggregate(script, @[]) != 0

      # anchor=skipped + EVENT_NAME unset — `set -u` unbound variable → deny.
      var anchorSkipped = withPosition(successVars(), AnchorJob, "skipped")
      check runAggregate(script, anchorSkipped) != 0

      # anchor=skipped + EVENT_NAME set-empty — `[ "" != "pull_request" ]`는
      # 참이다(실측 bash 5.2). 계약 문구 그대로 "set이고 != pull_request"이므로
      # allow이며, unset과 구분된다.
      anchorSkipped.add(("EVENT_NAME", ""))
      check runAggregate(script, anchorSkipped) == 0

      # 전부 success는 event와 무관하게 allow.
      for event in Events:
        var vars = successVars()
        vars.add(("EVENT_NAME", event))
        check runAggregate(script, vars) == 0

    test "행동 반증: M06/M07/M10/M14 변조 본문은 production이 deny하는 입력을 통과시킨다":
      # production 기준선: 모두 deny.
      let production = writeScript("aggregate_baseline.sh", productionDoc().runBody)

      # M06 — anchor skip + PR: production deny, mutant allow.
      var anchorSkipPr = withPosition(successVars(), AnchorJob, "skipped")
      anchorSkipPr.add(("EVENT_NAME", "pull_request"))
      check runAggregate(production, anchorSkipPr) != 0
      check runAggregate(mutatedRunScript(mutationById("M06-anchor-event-removed")), anchorSkipPr) == 0

      # M07 — 비-anchor(attest) skip + merge_group: production deny, mutant allow.
      var attestSkipMg = withPosition(successVars(), "attest", "skipped")
      attestSkipMg.add(("EVENT_NAME", "merge_group"))
      check runAggregate(production, attestSkipMg) != 0
      check runAggregate(mutatedRunScript(mutationById("M07-other-skip-allowed")), attestSkipMg) == 0

      # M10 — EVENT_NAME 상수화: run body 자체는 production과 동일하고 flip은
      # env mapping에 산다(구조 계약의 ENV_EVENT_NAME이 잡는다). 여기서는 그
      # 사실을 고정한다 — 행동 matrix는 env mapping을 평가하지 않는다.
      check readFile(mutatedRunScript(mutationById("M10-event-hardcoded"))) ==
        readFile(production)

      # M14 — fail() exit 0: attest failure + merge_group: production deny,
      # mutant allow (실패가 삼켜진다).
      var attestFailureMg = withPosition(successVars(), "attest", "failure")
      attestFailureMg.add(("EVENT_NAME", "merge_group"))
      check runAggregate(production, attestFailureMg) != 0
      check runAggregate(mutatedRunScript(mutationById("M14-fail-exit-zero")), attestFailureMg) == 0

  suite "VS-0 — 배선 보호":

    test "이 테스트 파일은 trust-surface manifest에 등록되어 있다":
      let manifest = readFile(RepoRoot / TrustManifestRel)
      check textContains(manifest, "\"" & SelfRel & "\"")

    test "required check axiom-operational-slice가 이 계약을 실행한다":
      let slice = readFile(RepoRoot / SliceWorkflowRel)
      check textContains(slice, "VS-0 admission aggregate fail-closed contract")
      check textContains(slice, SelfRel)
      check textContains(slice, "python3 -c 'import yaml'")

finally:
  if dirExists(TempDir):
    removeDir(TempDir)