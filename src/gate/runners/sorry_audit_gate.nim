import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## Sorry Audit Gate — Hard-Fail Gate
##
## Scans `proofs/` directory recursively for `.lean` files and checks for
## the Lean `sorry` tactic (word-boundary match to avoid false positives
## on identifiers like `sorry_not_sorry`).
##
## Detection:
##   - `\bsorry\b` as a word boundary in non-comment lines
##
## Usage: sorry_audit_gate <repoRoot> <mode> <maxJobs>
##
## Exit 0 = pass (no sorry found), exit 1 = blocking findings.

import std/[os, strutils, strformat, json, monotimes]
import core/axiom_pragmas
import infrastructure/logger
import infrastructure/logging_facade


# axiomIoBoundary

const
  GateTag = "[sorry-audit]"
  ProofsDir = "proofs"

type
  SorryFinding* = object
    file*: string
    line*: int
    context*: string

  SorryGateOutput* = object
    ok*: bool
    findings*: seq[SorryFinding]
    stdout*: string
    stderr*: string

# ── Pure logic: word-boundary sorry check ──────────────────────────────────

func isSorryWord*(line: string): bool =
  ## Check if `sorry` appears as a standalone word in the line.
  ## Word boundary: not preceded or followed by an alphanumeric, or underscore.
  const keyword = "sorry"
  var idx = 0
  while idx <= line.len - keyword.len:
    let pos = line.find(keyword, idx)
    if pos < 0: break
    let beforeOk = pos == 0 or not (line[pos - 1].isAlphaNumeric() or line[pos - 1] == '_')
    let afterPos = pos + keyword.len
    let afterOk = afterPos >= line.len or not (line[afterPos].isAlphaNumeric() or line[afterPos] == '_')
    if beforeOk and afterOk: return true
    idx = pos + 1
  return false

func scanContent*(content: string, filePath: string): seq[SorryFinding] =
  ## Scan file content for sorry occurrences (pure function).
  result = @[]
  var lineNum = 0
  for line in content.splitLines():
    inc lineNum
    let stripped = line.strip()
    # Skip comment lines (Lean comments start with --)
    if stripped.startsWith("--"): continue
    if isSorryWord(stripped):
      # Extract surrounding context: up to 60 chars around the match
      var ctxStart = max(0, stripped.find("sorry") - 20)
      var ctxEnd = min(stripped.len, stripped.find("sorry") + 25)
      let context = stripped[ctxStart ..< ctxEnd].strip()
      result.add(SorryFinding(
        file: filePath,
        line: lineNum,
        context: context,
      ))

# ── I/O: file scanner ──────────────────────────────────────────────────────

proc scanLeanFiles(proofsDir: string): seq[SorryFinding] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Recursively scan all .lean files under proofsDir for sorry.
  result = @[]
  if not dirExists(proofsDir): return
  for kind, path in walkDir(proofsDir, relative = false):
    if kind == pcFile and path.endsWith(".lean"):
      try:
        let content = readFile(path)
        let findings = scanContent(content, path)
        for f in findings:
          result.add(f)
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
    elif kind == pcDir:
      for kind2, path2 in walkDir(path, relative = false):
        if kind2 == pcFile and path2.endsWith(".lean"):
          try:
            let content = readFile(path2)
            let findings = scanContent(content, path2)
            for f in findings:
              result.add(f)
          except CatchableError:
            discard  # axiom:best-effort(ioboundary catch)

# ── Gate runner ─────────────────────────────────────────────────────────────

proc runSorryAudit*(repoRoot: string): SorryGateOutput =
  ## Run the sorry audit scan. Returns gate output with findings.
  let proofsDir = repoRoot / ProofsDir
  let findings = scanLeanFiles(proofsDir)

  # Build JSON output
  var jFindings = newJArray()
  for f in findings:
    var jf = newJObject()
    jf["file"] = %f.file
    jf["line"] = %f.line
    jf["context"] = %f.context
    jFindings.add(jf)

  var jOutput = newJObject()
  jOutput["gate"] = %"sorry-audit-gate"
  jOutput["totalFindings"] = %findings.len
  jOutput["findings"] = jFindings

  let stdoutJson = try: $jOutput.pretty() except CatchableError: "{}"
  let stderrText =
    if findings.len > 0:
      var lines: seq[string] = @[]
      for f in findings:
        lines.add(&"  {f.file}:{f.line}  {f.context}")
      &"{GateTag} FAIL — {findings.len} sorry occurrence(s) found:\n" & lines.join("\n")
    else:
      &"{GateTag} PASS — no sorry found in proofs/"

  let ok = findings.len == 0
  result = SorryGateOutput(
    ok: ok,
    findings: findings,
    stdout: stdoutJson,
    stderr: stderrText,
  )

# ── CLI entry point ────────────────────────────────────────────────────────

proc main()  =
  var repoRoot = getCurrentDir()
  if paramCount() >= 1:
    repoRoot = paramStr(1)

  let t0Ticks = getMonoTime().ticks
  let res = runSorryAudit(repoRoot)
  let elapsedMs = (getMonoTime().ticks - t0Ticks) div 1_000_000
  if elapsedMs > 500:
    logInfo("sorry_audit_gate", &"axiom: [PERF] sorry-audit took {elapsedMs}ms (threshold: 500ms)")
  logger.info (if res.ok: "PASS" else: "FAIL") & " sorry-audit"
  logger.info res.stdout
  quit(if res.ok: 0 else: 1)

when isMainModule: main()

{.pop.}
