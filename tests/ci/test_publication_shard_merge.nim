## test_publication_shard_merge.nim — publication-integrity license-scan shard
## merge contract: the production `[merge]` step body, executed.
##
## WHY (§0.8/§0.9 — dead gates and theater): the shard merge step is the only
## place that decides whether the license dimension adjudicates over a COMPLETE
## scan surface. A happy-path landing proves the merge can pass; it proves
## nothing about whether the merge can FAIL. This suite pins every fail-closed
## path as a negative fixture, plus the dead-gate guard that the same body
## PASSES on a valid, complete, duplicate-directory-bearing shard set:
##
##   1. one shard report missing            -> FAIL "expected N shard reports"
##   2. zero shard reports (empty dir)      -> FAIL with the same diagnostic
##      (before the 2026-11-27 `|| true` fix the step died inside the
##      command substitution and printed NO diagnostic at all)
##   3. a file emitted by two shards        -> FAIL "duplicate file paths"
##      (before 2026-11-27 this fixture PASSED: the merge jq dedups by path
##      before the old check ran, so the old check was unreachable — §0.9)
##   4. a tracked file in no shard report   -> FAIL "completeness FAIL"
##   5. valid JSON, one file entry dropped  -> FAIL "completeness FAIL"
##   6. directory entries shared by several shards -> PASS (the per-path dedup
##      is legitimate for directories; the duplicate guard must not reject it)
##
## The body under test is EXTRACTED FROM THE WORKFLOW YAML at run time (not a
## copy) and executed with a synthetic $RUNNER_TEMP/$GITHUB_WORKSPACE pair, so
## an edit to the workflow that weakens the merge changes these results.
##
## The static coupling test pins matrix length == awk n == SHARD_COUNT and is
## itself mutation-checked: a mutated copy of the workflow (n=4) must be
## reported as a mismatch, so the coupling test cannot pass by construction.

import std/[json, strutils, os, osproc, strtabs, unittest]

const
  WorkflowRel = ".github/workflows/publication-integrity.yml"
  ShardJob = "license-scan-shards"
  MergeJob = "license-scan"
  ScanStepPrefix = "[scan] license"
  MergeStepPrefix = "[merge]"
  ## Files tracked in every fixture repo, spread over the shard reports. None
  ## matches ScanCode's ignores_VCS basenames, so the expected set is exactly
  ## these paths.
  FixtureFiles = ["a.txt", "b.txt", "c.txt", "d.txt", "e.txt", "nested/f.txt"]

proc repoRoot(): string =
  result = absolutePath(currentSourcePath())
  for _ in 0 ..< 3:
    result = result.parentDir()

var pyCounter = 0

proc pyRun(scriptBody: string; args: varargs[string]): tuple[outp: string; code: int] =
  ## Run one python3 script; args become sys.argv[1..] (test_admission_venue_split precedent)
  inc pyCounter
  let py = getTempDir() / ("pi_shard_py_" & $getCurrentProcessId() & "_" &
    $pyCounter & ".py")
  writeFile(py, scriptBody)
  var cmd = "python3 " & quoteShell(py)
  for a in args:
    cmd.add(" " & quoteShell(a))
  let (outp, code) = execCmdEx(cmd)
  removeFile(py)
  result.outp = outp
  result.code = code

proc stepRun(path, job, namePrefix: string): string =
  ## Extract a step's run body through yaml — the workflow text itself, not a copy.
  const Script = """
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
hits = [s for s in d['jobs'][sys.argv[2]]['steps']
        if s.get('name', '').startswith(sys.argv[3])]
if len(hits) != 1:
    sys.exit('expected exactly one step, got %d' % len(hits))
print(hits[0].get('run', ''), end='')
"""
  let (outp, code) = pyRun(Script, path, job, namePrefix)
  if code != 0:
    raise newException(ValueError,
      "workflow step extraction failed for " & job & "/" & namePrefix & ": " & outp)
  result = outp

proc shardCoupling(path: string): tuple[matrixLen, awkN, countN: int] =
  ## The three sites that pin the shard count: matrix length / awk `-v n=` / SHARD_COUNT assert.
  const Script = """
import sys, re, yaml
d = yaml.safe_load(open(sys.argv[1]))
matrix = d['jobs']['license-scan-shards']['strategy']['matrix']['shard']
scan = [s['run'] for s in d['jobs']['license-scan-shards']['steps']
        if s.get('name', '').startswith('[scan] license')][0]
merge = [s['run'] for s in d['jobs']['license-scan']['steps']
         if s.get('name', '').startswith('[merge]')][0]
awk_n = re.findall(r'-v n=(\d+)', scan)
count_n = re.findall(r'SHARD_COUNT" -eq (\d+)', merge)
if len(awk_n) != 1 or len(count_n) != 1:
    sys.exit('expected one n= and one -eq site, got %r / %r' % (awk_n, count_n))
print(len(matrix), awk_n[0], count_n[0])
"""
  let (outp, code) = pyRun(Script, path)
  if code != 0:
    raise newException(ValueError, "shard coupling extraction failed: " & outp)
  let cols = outp.strip().splitWhitespace()
  doAssert cols.len == 3, "unexpected coupling row: " & outp
  result = (parseInt(cols[0]), parseInt(cols[1]), parseInt(cols[2]))

proc initRepo(dir: string) =
  createDir(dir)
  for rel in FixtureFiles:
    let p = dir / rel
    createDir(p.parentDir)
    writeFile(p, rel & "\n")
  for args in [@["init", "-q"], @["add", "-A"],
               @["-c", "user.email=t@t", "-c", "user.name=t",
                "commit", "-q", "-m", "fixture"]]:
    let (outp, code) = execCmdEx("git -C " & quoteShell(dir) & " " & args.join(" "))
    doAssert code == 0, "git " & args.join(" ") & " failed: " & outp

proc reportJson(prefix: string; shardFiles: seq[string];
                extraDirs: seq[string] = @[]): string =
  ## scancode_shard.json shape: headers + files[] (file and directory entries)
  ## + license_detections[]. Paths carry the '<root>/' prefix ScanCode emits.
  var files = newJArray()
  for d in extraDirs:
    files.add(%*{"path": prefix & "/" & d, "type": "directory"})
  for f in shardFiles:
    files.add(%*{"path": prefix & "/" & f, "type": "file"})
  result = $(%*{
    "headers": {"fixture": "pi_shard_merge"},
    "files": files,
    "license_detections": [],
  }) & "\n"

type
  Harness = object
    root, repo, runnerTemp, prefix, body: string

proc writeShards(h: Harness; shardSets: seq[seq[string]];
                 sharedDirs: seq[string] = @[]) =
  ## license-scan-shard-N/scancode_shard.json per set (the download-artifact
  ## pattern layout), each report carrying the shared directory entries.
  let shards = h.runnerTemp / "shards"
  createDir(shards)
  for i, files in shardSets:
    let d = shards / ("license-scan-shard-" & $i)
    createDir(d)
    writeFile(d / "scancode_shard.json",
      reportJson(h.prefix, files, sharedDirs))

proc runMerge(body, repo, runnerTemp: string): tuple[outp: string, code: int] =
  ## Run the merge run body verbatim; only RUNNER_TEMP/GITHUB_WORKSPACE are injected
  ## (the body carries no ${{ }} expression: verified when extracting the yaml).
  let script = runnerTemp / "merge_step.sh"
  writeFile(script, body)
  let env = newStringTable(modeCaseInsensitive)
  for k, v in envPairs():
    env[k] = v
  env["RUNNER_TEMP"] = runnerTemp
  env["GITHUB_WORKSPACE"] = repo
  let (outp, code) = execCmdEx("bash " & quoteShell(script), env = env,
    workingDir = repo)
  removeFile(script)
  result.outp = outp
  result.code = code

## Mutation hook for the anti-theater proof (AGENTS.md §0.9b): pointing this at
## a mutated copy of the workflow makes the merge tests execute THAT body, so
## 'red when mutated' is measured against the old tree rather than asserted.
## Unset (the normal case, incl. CI) = the committed workflow.
let workflowPath = getEnv("AXIOM_PI_WORKFLOW_FILE",
  repoRoot() / WorkflowRel)

proc newHarness(name: string): Harness =
  let root = getTempDir() / ("pi_shard_" & $getCurrentProcessId() & "_" & name)
  removeDir(root)
  result.root = root
  result.repo = root / "Axiom"
  result.runnerTemp = root / "rt"
  createDir(result.runnerTemp)
  initRepo(result.repo)
  result.prefix = "Axiom"
  result.body = stepRun(workflowPath, MergeJob, MergeStepPrefix)

proc cleanup(h: Harness) =
  removeDir(h.root)

suite "license-scan shard merge — the production step body, executed":

  test "valid five-shard set PASSES (dead-gate guard)":
    let h = newHarness("pass")
    # 6 files across 5 shards, every shard also emitting the SAME directory
    # entries: the per-path dedup is designed for exactly this shape.
    writeShards(h,
      @[@["a.txt"], @["b.txt"], @["c.txt", "d.txt"], @["e.txt"],
        @["nested/f.txt"]], @["nested"])
    let r = runMerge(h.body, h.repo, h.runnerTemp)
    if r.code != 0:
      echo "expected PASS, got " & $r.code & ":\n" & r.outp
    check r.code == 0
    check fileExists(h.runnerTemp / "scancode.json")
    cleanup(h)

  test "one shard report missing FAILS with the count diagnostic":
    let h = newHarness("count")
    writeShards(h,
      @[@["a.txt"], @["b.txt"], @["c.txt", "d.txt"], @["e.txt"]])
    let r = runMerge(h.body, h.repo, h.runnerTemp)
    check r.code != 0
    check "expected 5 shard reports, found 4" in r.outp
    cleanup(h)

  test "zero shard reports FAILS with a diagnostic (no silent die)":
    # The 2026-11-27 fix: `grep -c .` exits 1 on empty input, and under
    # `set -e` the assignment died BEFORE the echo, so the step ended with a
    # bare exit 1 and no message. The assertion must be the one place that
    # reports.
    let h = newHarness("zero")
    createDir(h.runnerTemp / "shards")
    let r = runMerge(h.body, h.repo, h.runnerTemp)
    check r.code != 0
    check "expected 5 shard reports, found 0" in r.outp
    cleanup(h)

  test "the same file in two shard reports FAILS (duplicate guard fires)":
    # The pre-2026-11-27 workflow PASSED this fixture: the merge jq collapsed
    # the two identical file entries into one (group_by(.path) | map(.[0]))
    # before the duplicate check ran, so the check was unreachable theater.
    let h = newHarness("dup")
    writeShards(h,
      @[@["a.txt", "b.txt"], @["b.txt", "c.txt"], @["d.txt"], @["e.txt"],
        @["nested/f.txt"]])
    let r = runMerge(h.body, h.repo, h.runnerTemp)
    check r.code != 0
    check "duplicate file paths across shard reports" in r.outp
    cleanup(h)

  test "a tracked file in no shard report FAILS the set comparison":
    let h = newHarness("holeset")
    # 'e.txt' exists in HEAD but no shard scanned it (a lost shard leg whose
    # count still matches, e.g. an empty report).
    writeShards(h,
      @[@["a.txt"], @["b.txt"], @["c.txt"], @["d.txt"], @["nested/f.txt"]])
    let r = runMerge(h.body, h.repo, h.runnerTemp)
    check r.code != 0
    check "completeness FAIL" in r.outp
    check "e.txt" in r.outp
    cleanup(h)

  test "valid JSON with one file entry dropped FAILS (set, not count)":
    let h = newHarness("dropped")
    # Five reports, five shard directories, zero duplicates — only the
    # per-file set reveals that d.txt was never emitted.
    writeShards(h,
      @[@["a.txt"], @["b.txt"], @["c.txt"], @["e.txt"],
        @["nested/f.txt"]])
    let r = runMerge(h.body, h.repo, h.runnerTemp)
    check r.code != 0
    check "completeness FAIL" in r.outp
    check "d.txt" in r.outp
    cleanup(h)

  test "directory entries shared by every shard PASS (dedup is legitimate)":
    let h = newHarness("dirs")
    # Every shard emits the same 'nested' directory entry; only the duplicate
    # FILE guard may fail, so this pins that the directory dedup stays legal.
    let sets = @[@[FixtureFiles[0], FixtureFiles[5]], @[FixtureFiles[1]],
                 @[FixtureFiles[2]], @[FixtureFiles[3]], @[FixtureFiles[4]]]
    writeShards(h, sets, @["nested"])
    let r = runMerge(h.body, h.repo, h.runnerTemp)
    if r.code != 0:
      echo "expected PASS on shared directories, got " & $r.code & ":\n" & r.outp
    check r.code == 0
    cleanup(h)

suite "license-scan shard count — static coupling matrix == awk n == count":

  test "the three shard-count sites agree (currently 5)":
    let c = shardCoupling(workflowPath)
    if not (c.matrixLen == c.awkN and c.awkN == c.countN):
      echo "shard-count drift: matrix=" & $c.matrixLen & " awk n=" & $c.awkN &
        " count=" & $c.countN
    check c.matrixLen == c.awkN
    check c.awkN == c.countN
    check c.matrixLen == 5

  test "a mutated copy (awk n=4) is reported as drift":
    # Mutation check on the checker itself: if the coupling detector could
    # not see a real divergence it would be theater.
    let src = readFile(workflowPath)
    doAssert "-v n=5 " in src, "unexpected workflow shape: n= site not found"
    let mutated = src.replace("-v n=5 ", "-v n=4 ")
    check mutated != src
    let tmp = getTempDir() / ("pi_shard_mut_" & $getCurrentProcessId() & ".yml")
    writeFile(tmp, mutated)
    let c = shardCoupling(tmp)
    removeFile(tmp)
    check c.matrixLen == 5
    check c.awkN == 4
    check c.countN == 5
    check not (c.matrixLen == c.awkN and c.awkN == c.countN)

  test "a mutated copy (count assertion -eq 4) is reported as drift":
    let src = readFile(workflowPath)
    doAssert "SHARD_COUNT\" -eq 5" in src,
      "unexpected workflow shape: -eq site not found"
    let mutated = src.replace("SHARD_COUNT\" -eq 5", "SHARD_COUNT\" -eq 4")
    check mutated != src
    let tmp = getTempDir() / ("pi_shard_mut2_" & $getCurrentProcessId() & ".yml")
    writeFile(tmp, mutated)
    let c = shardCoupling(tmp)
    removeFile(tmp)
    check c.countN == 4
    check not (c.matrixLen == c.awkN and c.awkN == c.countN)