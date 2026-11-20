## trusted_writer_set_gate.nim — TrustedWriterSet equality gate with job-level
## effective-permission analysis (ADR-0022 §4 Nim port; DEBT#557 closure).
##
## Why this file exists
## --------------------
## The bash scanner (tools/ci/verify_trusted_writer_set.sh:111-116) only enters
## a `permissions:` block written at column-0, so a `contents: write` granted
## per JOB (`jobs.<id>.permissions.contents`) is invisible to it. Measured at
## 2026-11-18 on the landed tree: three effective writers exist —
##   .github/workflows/certificate-mint.yml#publish      (the declared writer)
##   .github/workflows/admission-gate-v2.yml#mint-prepare (transport)
##   .github/workflows/admission-gate-v2.yml#mint-publish (transport)
## — and only the first is observable by a top-level-only scan. DEBT#557 is the
## gap between "the declared writer set" and "the jobs that can actually push".
##
## What this gate enforces (all fail-closed)
## ----------------------------------------
## R1 top-level identity — the set of workflows whose column-0 `permissions:`
##    block grants `contents: write` must be exactly {declaredWriterWorkflow}.
##    (Same contract as the bash script; ported verbatim.)
## R2 job-level delta — with `--base <dir>` (a checkout of the merge base),
##    a job that is an effective writer at head but was not one at base is a
##    VIOLATION. This closes the attack the top-level scan cannot see: a PR
##    that adds `permissions: contents: write` to a job of its own choosing.
## R3 declared job set — when `config/trusted_writer_set.json` carries an
##    optional `trustedWriterJobs` array, the observed job-level writer set
##    must equal it exactly (⊆ ∧ ⊇). The field cannot be introduced by a PR:
##    the verifier rejects unknown TWS fields (`tws_new_field`) and the file is
##    blob-pinned in the trust-surface manifest, so R3 activating is itself an
##    audited break-glass event.
## R4 unconstrained workflows — a workflow with no `permissions:` block at all
##    inherits the repository default, which this gate cannot observe from the
##    tree. Such a workflow is therefore unprovable, not safe: known instances
##    are listed in `KnownUnconstrainedWorkflows`; any NEW instance FAILS.
## R5 admission identity — when `--admission-blob <sha>` is supplied the value
##    must equal `trustedAdmissionWorkflowSha` (the caller derives it with
##    `git rev-parse HEAD:.github/workflows/admission-check.yml`, keeping this
##    binary free of git dependencies).
##
## Effective-permission semantics (GitHub): a job-level `permissions:` block
## REPLACES the workflow-level block entirely; scopes it does not name are
## `none`. `read-all`/`write-all` are shorthands; `{}` grants nothing.
##
## Exit codes: 0 PASS · 1 VIOLATION · 2 configuration/environment error.
## Deterministic: same tree → same verdict. No network. No writes.

import std/[algorithm, json, os, sequtils, strutils]

# Effect-marker pragma, declared locally like every other tool in this tree
# (tools/hermetic_build.nim:59, tools/cas_promote.nim:28) — `axiomEffect` is a
# review-time marker, not a compiler builtin.
template axiomEffect*(e: untyped) {.pragma.}
type IoEffect* = object

const
  GateName* = "trusted_writer_set_gate"
  SetFileRel* = "config/trusted_writer_set.json"
  WorkflowsDirRel* = ".github/workflows"

  ## Workflows that carry no `permissions:` block today. They are reusable /
  ## selftest surfaces (`on: workflow_call` / `workflow_dispatch`, branch-push
  ## triggered), and their effective token scope is the repository default —
  ## unobservable from the tree. A NEW workflow in this class fails (R4).
  KnownUnconstrainedWorkflows* = ["byo-agent-selftest.yml", "byo-agent.yml"]

type
  ContentsPerm* = enum
    cpAbsent      ## no declaration anywhere — repository default (unobserved)
    cpNone
    cpRead
    cpWrite

  JobScope* = object
    name*: string
    declared*: bool        ## the job carries its own `permissions:` block
    contents*: ContentsPerm

  WorkflowScan* = object
    path*: string          ## repo-relative, `.github/workflows/<name>.yml`
    topDeclared*: bool
    topContents*: ContentsPerm
    jobs*: seq[JobScope]
    errors*: seq[string]

  DeclaredWriterSet* = object
    writerWorkflow*: string
    admissionSha*: string
    writerJobs*: seq[string]

  Verdict* = object
    ok*: bool
    reasons*: seq[string]
    notes*: seq[string]
    topWriters*: seq[string]
    jobWriters*: seq[string]

# ── line scanning ────────────────────────────────────────────────────────────

func indentOf(line: string): int {.raises: [].} =
  result = 0
  while result < line.len and line[result] == ' ':
    inc result

func stripComment(line: string): string {.raises: [].} =
  ## Strip a YAML comment that starts at line begin or after whitespace. Values
  ## in the scanned slots are plain scalars, so quote tracking is sufficient.
  var inSingle = false
  var inDouble = false
  var i = 0
  while i < line.len:
    let c = line[i]
    if c == '\'' and not inDouble:
      inSingle = not inSingle
    elif c == '"' and not inSingle:
      inDouble = not inDouble
    elif c == '#' and not inSingle and not inDouble:
      if i == 0 or line[i - 1] in {' ', '\t'}:
        return line[0 ..< i]
    inc i
  result = line

func splitKeyValue(s: string): tuple[hasKey: bool, key: string, value: string] {.raises: [].} =
  let t = s.strip()
  if t.len == 0:
    return
  let idx = t.find(':')
  if idx < 0:
    return
  result.hasKey = true
  result.key = t[0 ..< idx].strip()
  if idx == t.high:
    result.value = ""
  else:
    result.value = t[idx + 1 .. ^1].strip()

func permOfToken(v: string): ContentsPerm {.raises: [].} =
  case v.strip().toLowerAscii()
  of "write": cpWrite
  of "read": cpRead
  of "none": cpNone
  else: cpAbsent

func flowEntries(v: string): seq[tuple[key, value: string]] {.raises: [].} =
  var t = v.strip()
  if t.len >= 2 and t[0] == '{' and t[^1] == '}':
    t = t[1 .. ^2]
  for part in t.split(','):
    let kv = splitKeyValue(part)
    if kv.hasKey:
      result.add((kv.key, kv.value))

type PermBlock = object
  declared: bool
  contents: ContentsPerm
  consumed: int            ## lines consumed after the `permissions:` line
  errors: seq[string]

func parsePermBlock(lines: seq[string], start: int, indent: int): PermBlock {.raises: [].} =
  ## `lines[start]` is `permissions: …` at `indent`.
  let kv = splitKeyValue(lines[start])
  result.contents = cpNone
  if kv.value.len > 0:
    result.declared = true
    let v = kv.value
    if v == "{}":
      result.contents = cpNone
    elif v.startsWith("{"):
      if not v.endsWith("}"):
        result.errors.add("permissions flow map not closed: " & v)
        return
      for entry in flowEntries(v):
        if entry.key == "contents":
          result.contents = permOfToken(entry.value)
          if result.contents == cpAbsent:
            result.errors.add("unknown contents permission: " & entry.value)
    elif v in ["read-all", "write-all"]:
      result.contents = if v == "write-all": cpWrite else: cpRead
    else:
      result.errors.add("misplaced permissions scalar: " & v)
    return

  result.declared = true
  var childIndent = -1
  var i = start + 1
  while i < lines.len:
    let raw = lines[i]
    let line = stripComment(raw)
    if line.strip().len == 0:
      inc i
      continue
    let ind = indentOf(line)
    if ind <= indent:
      break
    if childIndent < 0:
      childIndent = ind
    if ind == childIndent:
      let entry = splitKeyValue(line)
      if not entry.hasKey:
        result.errors.add("unparsable permission entry: " & line.strip())
      elif entry.key == "contents":
        result.contents = permOfToken(entry.value)
        if result.contents == cpAbsent:
          result.errors.add("unknown contents permission: " & entry.value)
    elif ind < childIndent:
      result.errors.add("inconsistent permission indentation: " & line.strip())
    result.consumed = i - start
    inc i

func scanWorkflow*(relPath, src: string): WorkflowScan {.raises: [].} =
  ## Pure scanner over a workflow YAML source. Only the slots that can grant
  ## `contents: write` are interpreted; everything else is skipped by indent.
  result.path = relPath
  result.topContents = cpAbsent
  var lines: seq[string] = @[]
  for raw in src.splitLines():
    if raw.len > 0 and raw[0] == '\t':
      result.errors.add("tab indentation at line begin")
    lines.add(raw)

  var i = 0
  while i < lines.len:
    let line = stripComment(lines[i])
    if line.strip().len == 0:
      inc i
      continue
    let ind = indentOf(line)
    let kv = splitKeyValue(line)
    if ind == 0 and kv.hasKey and kv.key == "permissions":
      if result.topDeclared:
        result.errors.add("duplicate top-level permissions block")
      let b = parsePermBlock(lines, i, 0)
      result.topDeclared = true
      result.topContents = b.contents
      for e in b.errors:
        result.errors.add(e)
      i += b.consumed + 1
      continue
    if ind == 0 and kv.hasKey and kv.key == "jobs":
      var j = i + 1
      var current = -1
      while j < lines.len:
        let jline = stripComment(lines[j])
        if jline.strip().len == 0:
          inc j
          continue
        let jind = indentOf(jline)
        if jind == 0:
          break
        if jind == 2:
          let jobKv = splitKeyValue(jline)
          if jobKv.hasKey and jobKv.value.len == 0:
            result.jobs.add(JobScope(name: jobKv.key, declared: false,
                                     contents: cpAbsent))
            current = result.jobs.high
          inc j
          continue
        if current >= 0 and jind == 4:
          let jobKv = splitKeyValue(jline)
          if jobKv.hasKey and jobKv.key == "permissions":
            if result.jobs[current].declared:
              result.errors.add("duplicate job permissions block: " &
                                result.jobs[current].name)
            let b = parsePermBlock(lines, j, 4)
            result.jobs[current].declared = true
            result.jobs[current].contents = b.contents
            for e in b.errors:
              result.errors.add(e & " (job " & result.jobs[current].name & ")")
            j += b.consumed + 1
            continue
        inc j
      i = j
      continue
    inc i

func effectiveContents*(wf: WorkflowScan, job: JobScope): ContentsPerm {.raises: [].} =
  ## A job-level block replaces the workflow-level block; otherwise the job
  ## inherits the workflow block (absent declaration stays absent — unknown).
  if job.declared:
    job.contents
  else:
    wf.topContents

func isTopWriter*(wf: WorkflowScan): bool {.raises: [].} =
  wf.topDeclared and wf.topContents == cpWrite

func jobWriterId*(wf: WorkflowScan, job: JobScope): string {.raises: [].} =
  wf.path & "#" & job.name

# ── judgment ─────────────────────────────────────────────────────────────────

func jobWriters*(scans: seq[WorkflowScan]): seq[string] {.raises: [].} =
  for wf in scans:
    for job in wf.jobs:
      if effectiveContents(wf, job) == cpWrite:
        result.add(jobWriterId(wf, job))
  result.sort()

func topWriters*(scans: seq[WorkflowScan]): seq[string] {.raises: [].} =
  for wf in scans:
    if isTopWriter(wf):
      result.add(wf.path)
  result.sort()

func judge*(scans: seq[WorkflowScan], declared: DeclaredWriterSet,
            base: seq[WorkflowScan], baseProvided: bool): Verdict {.raises: [].} =
  ## Pure judgment. `base` is only consulted when `baseProvided`.
  result.topWriters = topWriters(scans)
  result.jobWriters = jobWriters(scans)
  let baseJobs = jobWriters(base)

  for wf in scans:
    for e in wf.errors:
      result.reasons.add("tws_parse_error:" & wf.path & ":" & e)

  # R4 — unprovable workflows (no permissions block anywhere).
  for wf in scans:
    if not wf.topDeclared and wf.jobs.allIt(not it.declared):
      let name = wf.path.split('/')[^1]
      if name notin KnownUnconstrainedWorkflows:
        result.reasons.add("tws_unconstrained_workflow:" & wf.path)
      else:
        result.notes.add("known unconstrained workflow (repository default): " & wf.path)

  # R1 — top-level identity.
  if result.topWriters.len == 0:
    result.reasons.add("tws_top_writer_missing")
  for p in result.topWriters:
    if p != declared.writerWorkflow:
      result.reasons.add("tws_top_writer_unexpected:" & p)
  if declared.writerWorkflow notin result.topWriters:
    result.reasons.add("tws_declared_writer_not_observed:" & declared.writerWorkflow)

  # R2/R3 — job-level writers.
  if declared.writerJobs.len > 0:
    for id in result.jobWriters:
      if id notin declared.writerJobs:
        result.reasons.add("tws_job_not_declared:" & id)
    for id in declared.writerJobs:
      if id notin result.jobWriters:
        result.reasons.add("tws_declared_job_not_observed:" & id)
  elif baseProvided:
    for id in result.jobWriters:
      if id notin baseJobs:
        result.reasons.add("tws_job_level_write_added:" & id)
  else:
    if result.jobWriters.len > 0:
      result.notes.add("job-level writers observed without a declared job set " &
                       "(absolute closure requires trustedWriterJobs; delta mode " &
                       "requires --base)")

  result.reasons.sort()
  result.ok = result.reasons.len == 0

# ── I/O boundary ─────────────────────────────────────────────────────────────

proc loadDeclaredSet(root: string): DeclaredWriterSet {.axiomEffect: IoEffect,
    raises: [CatchableError].} =
  let path = root / SetFileRel
  if not fileExists(path):
    raise newException(IOError, "set file missing: " & path)
  var stripped = ""
  for line in readFile(path).splitLines():
    if line.strip().startsWith("//"):
      continue
    stripped.add(line)
    stripped.add('\n')
  let node = parseJson(stripped)
  result.writerWorkflow = node{"trustedWriterWorkflow"}.getStr("")
  result.admissionSha = node{"trustedAdmissionWorkflowSha"}.getStr("")
  if node.hasKey("trustedWriterJobs"):
    for v in node["trustedWriterJobs"]:
      result.writerJobs.add(v.getStr(""))
  result.writerJobs.sort()

proc loadWorkflows(root: string): seq[WorkflowScan] {.axiomEffect: IoEffect,
    raises: [CatchableError].} =
  let dir = root / WorkflowsDirRel
  if not dirExists(dir):
    raise newException(IOError, "workflow directory missing: " & dir)
  var names: seq[string] = @[]
  for kind, path in walkDir(dir, relative = false):
    if kind == pcFile and path.endsWith(".yml"):
      names.add(path)
  names.sort()
  for p in names:
    let rel = WorkflowsDirRel & "/" & p.split('/')[^1]
    result.add(scanWorkflow(rel, readFile(p)))

proc emit(line: string) {.axiomEffect: IoEffect, raises: [].} =
  try:
    stdout.writeLine(GateName & ": " & line)
  except IOError: discard  # axiom:best-effort("stdout write failure is not actionable — the verdict is already computed; exit code carries it")

proc emitErr(line: string) {.axiomEffect: IoEffect, raises: [].} =
  try:
    stderr.writeLine(GateName & ": " & line)
  except IOError: discard  # axiom:best-effort("stderr write failure is not actionable — the verdict is already computed; exit code carries it")

proc usage() {.axiomEffect: IoEffect, raises: [].} =
  try:
    stderr.writeLine("usage: " & GateName & " [--root <dir>] [--base <dir>] " &
                     "[--admission-blob <sha>] [--json]")
  except IOError: discard  # axiom:best-effort("usage text is advisory — the exit code carries the failure")

proc main(): int {.axiomEffect: IoEffect, raises: [].} =
  var root = "."
  var baseDir = ""
  var admissionBlob = ""
  var asJson = false
  let args = commandLineParams()
  var i = 0
  while i < args.len:
    case args[i]
    of "--root":
      if i + 1 >= args.len:
        usage(); return 2
      root = args[i + 1]; i += 2
    of "--base":
      if i + 1 >= args.len:
        usage(); return 2
      baseDir = args[i + 1]; i += 2
    of "--admission-blob":
      if i + 1 >= args.len:
        usage(); return 2
      admissionBlob = args[i + 1]; i += 2
    of "--json":
      asJson = true; i += 1
    of "--help", "-h":
      usage(); return 0
    else:
      usage(); return 2

  var declared: DeclaredWriterSet
  var scans, baseScans: seq[WorkflowScan]
  try:
    declared = loadDeclaredSet(root)
    scans = loadWorkflows(root)
    if baseDir.len > 0:
      baseScans = loadWorkflows(baseDir)
  except CatchableError as e:
    emitErr("configuration error — " & e.msg & " (fail closed)")
    return 2

  if declared.writerWorkflow.len == 0 or not declared.writerWorkflow.startsWith(WorkflowsDirRel & "/"):
    emitErr("trustedWriterWorkflow missing or not a " & WorkflowsDirRel &
            "/*.yml path (configuration error — fail closed)")
    return 2
  if declared.admissionSha.len != 40 or declared.admissionSha.anyIt(it notin HexDigits):
    emitErr("trustedAdmissionWorkflowSha malformed (configuration error — fail closed)")
    return 2

  var verdict = judge(scans, declared, baseScans, baseProvided = baseDir.len > 0)
  if admissionBlob.len > 0 and admissionBlob != declared.admissionSha:
    verdict.ok = false
    verdict.reasons.add("tws_admission_sha_mismatch")
    verdict.reasons.sort()

  if asJson:
    var obj = %*{
      "ok": verdict.ok,
      "reasons": verdict.reasons,
      "notes": verdict.notes,
      "topWriters": verdict.topWriters,
      "jobWriters": verdict.jobWriters,
      "declaredWriterWorkflow": declared.writerWorkflow,
      "declaredWriterJobs": declared.writerJobs,
      "baseProvided": baseDir.len > 0,
      "admissionBlob": admissionBlob,
    }
    echo obj.pretty()
  else:
    emit("declared writer: " & declared.writerWorkflow & "@" & declared.admissionSha)
    emit("observed top-level contents:write workflows: " & $verdict.topWriters.len)
    for p in verdict.topWriters:
      emit("  " & p)
    emit("observed job-level contents:write holders: " & $verdict.jobWriters.len)
    for id in verdict.jobWriters:
      emit("  " & id)
    for n in verdict.notes:
      emit("NOTE — " & n)
    if verdict.ok:
      emit("PASS — writer set matches the declared TrustedWriterSet")
    else:
      for r in verdict.reasons:
        emitErr("VIOLATION — " & r)
      emitErr("FAIL — TrustedWriterSet contract violated (fail closed)")

  if verdict.ok: 0 else: 1

when isMainModule:
  quit(main())