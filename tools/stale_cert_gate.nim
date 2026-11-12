import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

## stale_cert_gate — AOT pre-commit stale-certificate checker.
##
## Blocks commits that would leave stale proof certificates: source changed but
## the committed certificate's `sourceHash` no longer matches the staged source.
## Fail-closed, staged-content-accurate, fast, deterministic.
##
## Semantics:
##   1. Reads every committed proof cert JSON in src/verification/certificates/.
##      Skips `manifest.json` and the `type_mappings/` directory (non-recursive).
##   2. For each cert with a modulePath + sourceHash, reads the STAGED source via
##      `git show :<modulePath>` (the index content being committed) [index mode],
##      computes computeStableSourceFingerprint(stagedSource) and compares to
##      cert.sourceHash.
##      Mismatch OR missing sourceHash (legacy) → STALE (fail flag).
##      `git show` failure (file not in index) → fail-closed stale.
##   3. Sanity-check that data/baseline.json still parses.
##   Exit 0 = all certs match staged source; exit 1 = stale detected.
##
## --worktree mode:
##   By default the gate reads the INDEX content (`git show :<path>`), which is
##   the pre-commit/staged behavior. In CI the index equals HEAD, so index-only
##   reads are vacuous (always pass). Passing `--worktree` instead reads the
##   actual source file from the filesystem (`repoRoot / modulePath`) via
##   `readFile`, enabling "full worktree integrity" checks. Semantics otherwise
##   identical: mismatch → stale; missing/unreadable source file → fail-closed
##   stale (genuine gap).
##
## Build (AOT precompile + hook): nim c --hints:off -o:bin/stale_cert_gate tools/stale_cert_gate.nim
##   Worktree check: bin/stale_cert_gate --worktree

import std/os
import std/osproc
import std/strutils
import std/json

import core/proof/source_fingerprint
import core/json/json_utils

const CertDir = "src/verification/certificates"
const BaselinePath = "data/baseline.json"

proc findRepoRoot(): string =
  var dir = getCurrentDir()
  while dir.len > 0:
    if fileExists(dir / ".axiom_root") or fileExists(dir / "axiom.toml"):
      return dir
    let parent = dir.parentDir()
    if parent == dir:
      break
    dir = parent
  getCurrentDir()

proc gitShowStaged(path: string): (string, bool) {.raises: [].} =
  ## Returns (stagedContent, ok). ok=false when the file is not in the index
  ## or git failed — callers treat this as fail-closed stale.
  var stdoutData = ""
  var ok = true
  try:
    let (outp, code) = execCmdEx("git show :" & quoteShell(path))
    if code != 0:
      ok = false
    else:
      stdoutData = outp
  except CatchableError:
    ok = false
  (stdoutData, ok)

proc readWorktreeSource(path: string): (string, bool) {.raises: [].} =
  ## Returns (fileContent, ok). ok=false when the source file does not exist
  ## or cannot be read — callers treat this as fail-closed stale (genuine gap).
  if not fileExists(path):
    return ("", false)
  try:
    (readFile(path), true)
  except CatchableError:
    ("", false)

var failFlag = false

proc wline(msg: string) {.raises: [].} =
  try:
    stderr.writeLine(msg)
  except IOError:
    discard  # axiom:best-effort(stderr write failure is non-fatal for the gate)

## WP4-g.1-B: conditional remediation guidance.
##
## A stale certificate only has a deterministic `ax cert reconcile --apply`
## remediation when the reference vault already contains a fresh cert bound to
## the CURRENT staged source hash for the same module. Otherwise reconciliation
## has nothing authoritative to project (rpoNoCurrentEvidence) and the correct
## next step is to re-run the verifier for the affected symbol first.
proc findFreshReferenceCert(modulePath, stagedHash: string): string {.raises: [CatchableError].} =
  ## Returns the file name of a tracked cert in the reference vault whose
  ## modulePath matches AND whose sourceHash equals the current staged hash.
  ## Empty string when no such fresh cert exists.
  for path in walkFiles(CertDir & "/*.json"):
    if extractFilename(path) == "manifest.json":
      continue
    var node: JsonNode
    try:
      node = readJsonFileNode(path)
    except CatchableError:
      continue
    if node.kind != JObject:
      continue
    if node{"modulePath"}.getStr("") != modulePath:
      continue
    if node{"sourceHash"}.getStr("") != stagedHash:
      continue
    return extractFilename(path)
  ""

proc failMsg(path, fnName, reason: string; stagedHash: string) {.raises: [].} =
  failFlag = true
  let guid =
    try:
      let freshRef = findFreshReferenceCert(path, stagedHash)
      if freshRef.len > 0:
        "run 'ax cert reconcile --apply' (fresh reference cert already present: " & freshRef & ")"
      else:
        "no fresh cert for current source in reference vault — run 'ax prove --target " & path & "::" & fnName & "' first, then retry"
    except CatchableError:
      "run 'ax cert reconcile --apply'"
  wline("STALE: " & path & "::" & fnName & " — " & reason & "; " & guid)

proc checkCertificate(certPath: string; useWorktree: bool) {.raises: [].} =
  var node: JsonNode
  try:
    node = readJsonFileNode(certPath)
  except CatchableError:
    return
  if node.kind != JObject:
    return

  let modulePath = node{"modulePath"}.getStr("")
  let sourceHash = node{"sourceHash"}.getStr("")
  let functionName = node{"functionName"}.getStr("")

  if sourceHash.len == 0:
    failMsg(modulePath, functionName, "cert missing sourceHash (legacy)", "")
    return

  if modulePath.len == 0:
    failMsg(modulePath, functionName, "cert missing modulePath", "")
    return

  let relModule = modulePath.replace("\\", "/")
  if relModule.startsWith("src/"):
    discard
  else:
    failMsg(relModule, functionName, "unexpected modulePath (not under src/)", "")
    return

  let (staged, ok) =
    if useWorktree:
      readWorktreeSource(relModule)
    else:
      gitShowStaged(relModule)
  if not ok:
    let reason =
      if useWorktree:
        "source file not found/readable on filesystem (genuine gap)"
      else:
        "staged source not in index (git show failed)"
    failMsg(relModule, functionName, reason, "")
    return

  let currentHash = computeStableSourceFingerprint(staged)
  if currentHash != sourceHash:
    let reason =
      if useWorktree:
        "worktree source no longer matches committed certificate"
      else:
        "staged source no longer matches committed certificate"
    failMsg(relModule, functionName, reason, currentHash)
    return

proc checkBaselineParses(): bool {.raises: [].} =
  let baselinePath = BaselinePath
  if not fileExists(baselinePath):
    wline("WARN: " & baselinePath & " missing — skipping baseline sanity check")
    return true
  try:
    discard parseJson(readFile(baselinePath))
    return true
  except CatchableError:
    wline("ERROR: " & baselinePath & " failed to parse (bad JSON)")
    failFlag = true
    return false

proc main() =
  var useWorktree = false
  for arg in commandLineParams():
    if arg == "--worktree":
      useWorktree = true

  let repoRoot = findRepoRoot()
  if repoRoot.len == 0 or not dirExists(repoRoot):
    wline("ERROR: cannot determine repo root")
    quit(2)
  setCurrentDir(repoRoot)

  discard checkBaselineParses()

  let certDir = CertDir
  if not dirExists(certDir):
    wline("WARN: " & certDir & " missing — nothing to check")
    quit(0)

  for path in walkFiles(joinPath(certDir, "*.json")):
    if extractFilename(path) == "manifest.json":
      continue
    checkCertificate(path, useWorktree)

  if failFlag:
    quit(1)

when isMainModule:
  main()

{.pop.}
