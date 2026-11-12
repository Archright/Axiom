## test_landing_observe_acceptance.nim — L4 canonical-main observation contract
##
## The L4 observer (tools/ci/landing_observe.sh --main <sha>) is ADVISORY
## evidence, and its failure mode is silent: a state that cannot be established
## must never be reported as success. This file pins that property end-to-end by
## driving the real script against a stub `gh` on PATH and fixture artifacts —
## zero network, zero real GitHub state, no dependence on any live run.
##
## One group of cases also pins the L2 PR-mode queue phase (the 2026-10-25
## PR #1103 observation): an accepted merge-queue entry (GraphQL state
## QUEUED/AWAITING_CHECKS) observed with 0 merge_group runs yet is documented
## pre-dispatch progress — PROGRESSING (exit 3), never UNKNOWN. A failed runs
## query or an entry state without documented progress semantics stays
## fail-closed UNKNOWN.
## Contract pinned here (one exit code per state; L1/L2/L3 codes untouched):
##   0 OBSERVED_SUCCESS  1 OBSERVED_FAILURE  2 UNKNOWN
##   3 PENDING           4 STALE             5 NOT_RUN
## and the observation budget the accountancy rests on: a cold read is 3 API
## calls, a warm cache is 2, `--offline` is 0. A wrong count is not cosmetic —
## it is the number the cost claim would be reported from.

import std/[json, os, osproc, strutils, unittest]

let
  Root = block:
    var r = absolutePath(currentSourcePath())
    for _ in 0 ..< 3: r = r.parentDir()
    r
  Script = Root / "tools" / "ci" / "landing_observe.sh"
  Work = getTempDir() / "axiom_landing_observe_acceptance"
  Bin = Work / "bin"
  Stub = Work / "stub"
  Cache = Work / "cache"

const
  Sha = "0123456789abcdef0123456789abcdef01234567"
  OtherSha = "fedcba9876543210fedcba9876543210fedcba98"
  ArtifactName = "axiom-operational-slice-evidence"
  ArtifactId = 4242

const GhStub = """#!/usr/bin/env bash
set -euo pipefail
url="${2:-}"
case "$url" in
  */zip)       cat "$OBS_STUB_DIR/artifact.zip" ;;
  *artifacts*) cat "$OBS_STUB_DIR/artifacts.json" ;;
  *runs*)      cat "$OBS_STUB_DIR/runs.json" ;;
  *) echo "stub gh: unexpected url $url" >&2; exit 1 ;;
esac
"""

# L2 PR-mode stubs: answer the PR-path surface only (gh api graphql,
# /rulesets/<id>, /actions/runs?event=merge_group, gh pr view). gh passes the
# subcommand as $1 and its object as $2, so the case keys off $2.
const GhStubPr = """#!/usr/bin/env bash
set -euo pipefail
url="${2:-}"
case "$url" in
  graphql)      cat "$OBS_STUB_DIR/graphql.json" ;;
  */rulesets/*) cat "$OBS_STUB_DIR/ruleset.json" ;;
  *runs*)       cat "$OBS_STUB_DIR/runs.json" ;;
  view)         cat "$OBS_STUB_DIR/prview.json" ;;
  *) echo "stub gh(pr): unexpected url $url" >&2; exit 1 ;;
esac
"""

const GhStubPrRunsFail = """#!/usr/bin/env bash
set -euo pipefail
url="${2:-}"
case "$url" in
  graphql)      cat "$OBS_STUB_DIR/graphql.json" ;;
  */rulesets/*) cat "$OBS_STUB_DIR/ruleset.json" ;;
  *runs*)       echo "stub gh(pr): merge_group runs query refused" >&2; exit 1 ;;
  view)         cat "$OBS_STUB_DIR/prview.json" ;;
  *) echo "stub gh(pr): unexpected url $url" >&2; exit 1 ;;
esac
"""

proc manifestJson(gitHead: string): string =
  """{"schemaVersion":"axiom.run-manifest.v1","binary":{"sha256":"deadbeef"},|  "sourceTree":{"gitHead":"GITHEAD"},"toolchain":{"engineBuild":"unmeasured"},|  "certificate":{"verificationTier":"dual-verified"},"report":{"verdict":"PASS"}}""".replace("|", "").replace("GITHEAD", gitHead)

proc crc32(data: string): uint32 =
  ## ZIP's CRC-32 (IEEE 802.3). Written here because stdlib has no zip writer
  ## and a `zip` CLI dependency would make this check silently unexecutable on
  ## a runner image that happens to lack it — the exact "green because it never
  ## ran" failure this file exists to prevent.
  var crc = 0xFFFFFFFF'u32
  for ch in data:
    crc = crc xor uint32(ord(ch))
    for _ in 0 ..< 8:
      if (crc and 1'u32) != 0'u32: crc = (crc shr 1) xor 0xEDB8_8320'u32
      else: crc = crc shr 1
  crc xor 0xFFFFFFFF'u32

proc le16(v: int): string =
  result = newString(2)
  result[0] = char(v and 0xFF)
  result[1] = char((v shr 8) and 0xFF)

proc le32(v: int): string =
  result = newString(4)
  for i in 0 ..< 4: result[i] = char((v shr (8 * i)) and 0xFF)

proc storedZip(entries: seq[(string, string)]): string =
  ## A ZIP archive with method 0 (stored) — the only shape `unzip` needs here.
  ## Fixed timestamps keep the bytes deterministic.
  var body = ""
  var central = ""
  for (name, data) in entries:
    let offset = body.len
    let crc = int(crc32(data))
    body.add le32(0x0403_4b50)
    body.add le16(20) & le16(0) & le16(0) & le16(0) & le16(0)
    body.add le32(crc) & le32(data.len) & le32(data.len)
    body.add le16(name.len) & le16(0)
    body.add name
    body.add data
    central.add le32(0x0201_4b50)
    central.add le16(20) & le16(20) & le16(0) & le16(0) & le16(0) & le16(0)
    central.add le32(crc) & le32(data.len) & le32(data.len)
    central.add le16(name.len) & le16(0) & le16(0) & le16(0) & le16(0)
    central.add le32(0) & le32(offset)
    central.add name
  let cdOffset = body.len
  body.add central
  body.add le32(0x0605_4b50) & le16(0) & le16(0)
  body.add le16(entries.len) & le16(entries.len)
  body.add le32(central.len) & le32(cdOffset) & le16(0)
  body

proc prepare() =
  ## Fresh bin/, stub/, cache/ for one case; the working repo is never touched.
  if dirExists(Work): removeDir(Work)
  createDir(Bin)
  createDir(Stub)
  writeFile(Bin / "gh", GhStub)
  setFilePermissions(Bin / "gh", {fpUserRead, fpUserWrite, fpUserExec,
                                 fpGroupRead, fpGroupExec, fpOthersRead, fpOthersExec})

proc buildArtifact(gitHead: string) =
  ## An artifact shaped like the real upload: manifest + its declared digest.
  let mf = Stub / "run-manifest.json"
  writeFile(mf, manifestJson(gitHead))
  let digest = execProcess("sha256sum " & quoteShell(mf)).split[0]
  let declared = digest & "\n"
  writeFile(Stub / "run-manifest.sha256", declared)
  writeFile(Stub / "artifact.zip", storedZip(@[
    ("run-manifest.json", manifestJson(gitHead)),
    ("run-manifest.sha256", declared)]))

proc setRuns(total: int; id = 0; attempt = 1; status = "completed";
             conclusion = "success"; headSha = Sha) =
  var node = %*{"total_count": total, "workflow_runs": newJArray()}
  if total > 0:
    let conc: JsonNode = if conclusion.len == 0: newJNull() else: %conclusion
    node["workflow_runs"].add %*{
      "id": id, "run_number": 1, "run_attempt": attempt,
      "status": status, "conclusion": conc, "head_sha": headSha}
  writeFile(Stub / "runs.json", $node)

proc setArtifacts(kind: string) =
  ## kind: "none" | "expired" | "live"
  var node = %*{"total_count": 0, "artifacts": newJArray()}
  if kind != "none":
    node["artifacts"].add %*{"id": ArtifactId, "name": ArtifactName,
                             "expired": kind == "expired"}
    node["total_count"] = %1
  writeFile(Stub / "artifacts.json", $node)

proc observe(args: seq[string]): tuple[output: string, exit: int] =
  let cmd = "PATH=" & quoteShell(Bin) & ":$PATH " &
    "AXIOM_OBS_CACHE=" & quoteShell(Cache) & " " &
    "OBS_STUB_DIR=" & quoteShell(Stub) & " " &
    quoteShell(Script) & " " & args.join(" ")
  let r = execCmdEx(cmd, options = {poStdErrToStdOut})
  result = (output: r.output, exit: r.exitCode)

proc liveSuccess() =
  setRuns(1, id = 777, attempt = 1)
  setArtifacts("live")
  buildArtifact(Sha)

proc preparePr(stub: string = GhStubPr) =
  ## L2 PR mode: same fresh layout, but the stub answers the PR-path surface.
  prepare()
  writeFile(Bin / "gh", stub)
  setFilePermissions(Bin / "gh", {fpUserRead, fpUserWrite, fpUserExec,
                                 fpGroupRead, fpGroupExec, fpOthersRead, fpOthersExec})

proc setPrQueueFixture(state: string) =
  ## PR #1103 shape: OPEN, accepted merge-queue entry in `state`, no merge
  ## commit, 0 merge_group runs (the pre-dispatch phase itself). The ruleset's
  ## declared required context is MISSING on the pr head — surfaced, never
  ## promoted to FAILURE, so no terminal verdict can fire before verdict 3.
  writeFile(Stub / "graphql.json", $(%*{
    "data": {"repository": {"pullRequest": {
      "state": "OPEN", "mergedAt": newJNull(),
      "mergeStateStatus": "CLEAN", "mergeable": "MERGEABLE",
      "mergeCommit": newJNull(), "isInMergeQueue": true,
      "mergeQueueEntry": {"state": state, "position": 1,
        "headCommit": {"oid": "abcdef0123456789abcdef0123456789abcdef01"}},
      "statusCheckRollup": {"state": "PENDING", "contexts": {"nodes": []}}}}}}))
  writeFile(Stub / "ruleset.json",
    """{"name":"main","enforcement":"active","rules":[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"admission-gate"}]}}]}""")
  writeFile(Stub / "prview.json",
    """{"state":"OPEN","mergedAt":null,"mergeCommit":null}""")
  setRuns(0)

suite "landing_observe L4 — canonical-main acceptance":

  test "NOT_RUN (exit 5) when no push run exists for the commit":
    prepare()
    setRuns(0)
    let r = observe(@["--main", Sha])
    check r.exit == 5
    check "VERDICT: NOT_RUN" in r.output

  test "PENDING (exit 3) while the bound push run is still running":
    prepare()
    setRuns(1, id = 777, status = "in_progress", conclusion = "")
    let r = observe(@["--main", Sha])
    check r.exit == 3
    check "VERDICT: PENDING" in r.output

  test "OBSERVED_FAILURE (exit 1) when the bound push run failed":
    prepare()
    setRuns(1, id = 777, conclusion = "failure")
    let r = observe(@["--main", Sha])
    check r.exit == 1
    check "VERDICT: OBSERVED_FAILURE" in r.output

  test "STALE (exit 4) when the artifact has expired":
    prepare()
    setRuns(1, id = 777)
    setArtifacts("expired")
    let r = observe(@["--main", Sha])
    check r.exit == 4
    check "VERDICT: STALE" in r.output

  test "UNKNOWN (exit 2) when the run carries no such artifact":
    prepare()
    setRuns(1, id = 777)
    setArtifacts("none")
    let r = observe(@["--main", Sha])
    check r.exit == 2
    check "VERDICT: UNKNOWN" in r.output

  test "STALE (exit 4) when the manifest is bound to a different commit":
    prepare()
    setRuns(1, id = 777)
    setArtifacts("live")
    buildArtifact(OtherSha)
    let r = observe(@["--main", Sha])
    check r.exit == 4
    check "VERDICT: STALE" in r.output

  test "OBSERVED_SUCCESS (exit 0) on a cold cache, 3 API calls":
    prepare()
    liveSuccess()
    let r = observe(@["--main", Sha, "--stats"])
    check r.exit == 0
    check "VERDICT: OBSERVED_SUCCESS" in r.output
    check "gitHead=" & Sha in r.output
    check "API_CALLS: 3" in r.output

  test "warm cache reuses the immutable artifact, 2 API calls":
    prepare()
    liveSuccess()
    discard observe(@["--main", Sha])
    let r = observe(@["--main", Sha, "--stats"])
    check r.exit == 0
    check "reused" in r.output
    check "API_CALLS: 2" in r.output

  test "--offline reuses the cache with 0 API calls, never a freshness claim":
    prepare()
    liveSuccess()
    discard observe(@["--main", Sha])
    let r = observe(@["--main", Sha, "--offline", "--stats"])
    check r.exit == 0
    check "VERDICT: OBSERVED_SUCCESS" in r.output
    check "NOT a freshness claim" in r.output
    check "API_CALLS: 0" in r.output

  test "--offline without a cached observation is UNKNOWN, never success":
    prepare()
    let r = observe(@["--main", Sha, "--offline"])
    check r.exit == 2
    check "VERDICT: UNKNOWN" in r.output

  test "a malformed sha fails closed":
    prepare()
    let r = observe(@["--main", "not-a-sha"])
    check r.exit == 2
    check "VERDICT: UNKNOWN" in r.output

  test "--main and a PR number are mutually exclusive":
    prepare()
    let r = observe(@["--main", Sha, "1101"])
    check r.exit == 2
    check "VERDICT: UNKNOWN" in r.output

suite "landing_observe L2 — PR merge-queue phase (PR #1103 regression)":

  test "PROGRESSING (exit 3): QUEUED entry with 0 merge_group runs yet":
    preparePr()
    setPrQueueFixture("QUEUED")
    let r = observe(@["1103"])
    check r.exit == 3
    check "VERDICT: PROGRESSING" in r.output
    check "mergeQueueEntry.state=QUEUED position=1" in r.output
    check "0 merge_group runs exist yet" in r.output
    check "VERDICT: UNKNOWN" notin r.output

  test "PROGRESSING (exit 3): AWAITING_CHECKS entry with 0 merge_group runs yet":
    preparePr()
    setPrQueueFixture("AWAITING_CHECKS")
    let r = observe(@["1103"])
    check r.exit == 3
    check "VERDICT: PROGRESSING" in r.output
    check "mergeQueueEntry.state=AWAITING_CHECKS" in r.output

  test "UNKNOWN (exit 2): a FAILED merge_group runs query is never progress":
    preparePr(GhStubPrRunsFail)
    setPrQueueFixture("QUEUED")
    let r = observe(@["1103"])
    check r.exit == 2
    check "VERDICT: UNKNOWN" in r.output

  test "UNKNOWN (exit 2): entry states without documented progress semantics":
    preparePr()
    setPrQueueFixture("UNMERGEABLE")
    let r = observe(@["1103"])
    check r.exit == 2
    check "VERDICT: UNKNOWN" in r.output