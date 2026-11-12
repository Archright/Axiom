import core/trusted/layer_declaration
axiomLayer "tools"

## check_inv9_forbidden_claims.nim — INV-9 forbidden-claim sentence scanner
## (I/O boundary runner for src/verification/forbidden_claim_scan.nim).
##
## Contract: docs/spec/certification_continuity_contract.md section 5 INV-9
## (forbidden claim sentences — "Nim semantics certified", "최종 TCB 폐쇄" 등 —
## static scan; violation = gate FAIL) + docs/adr/0030-rust-subject-semantic-
## authority.md U2/D3 (the scan must catch the Rust analogue "Rust semantics
## certified"; every artifact claim stays bounded to "verified w.r.t. the
## extracted representation under a Qualified extractor").
##
## Scan targets — the certificate payload surfaces the contract names:
##   default roots (repo-relative, scanned recursively):
##     data/trusted/certificates  data/trusted/subjects  data/trusted/evidence
##     data/trusted/journal       data/certification     data/attestations
##   `data/trusted/certificates` and `data/trusted/journal` are RUNTIME state
##   (untracked; minted by attest/journal runs) — a default root that is absent
##   is an empty surface (0 files), not an error. Explicitly passed paths are
##   assertions: a missing explicit path is fail-closed (exit 2).
##   .json files are parsed and every string value is scanned (structured:
##   the JSON field path becomes the allowlist symbol anchor); any other
##   extension is scanned as raw text (symbol anchor "text").
##
## Fail-closed: a missing/unreadable/malformed scan target is an ERROR and
## fails the run (exit 2) — never skipped. The default allowlist file is part
## of the scanner contract: absent or malformed allowlist = exit 2.
##
## Allowlist (docs/spec/theater_allowlist_stability.md — symbol-anchored,
## tamper-evident): tools/ci/inv9_forbidden_claim_allowlist.json; entry match
## requires file + symbol + ruleId + contentHash (sha256 of the offending
## string VALUE) to ALL match. File identity is the normalized scan path as
## given (pass repo-relative paths for stable anchors).
##
## Usage:
##   nim c -o:bin/check_inv9_forbidden_claims tools/ci/check_inv9_forbidden_claims.nim
##   bin/check_inv9_forbidden_claims                      # default roots
##   bin/check_inv9_forbidden_claims data/ path/to.json   # explicit targets
##   bin/check_inv9_forbidden_claims --allowlist <file> <path...>
##
## Exit codes: 0 = clean (all findings allowlisted) · 1 = forbidden claim
## finding(s) · 2 = fail-closed error (unreadable/malformed target or allowlist)

import std/[os, json, strutils, algorithm]
import verification/forbidden_claim_scan

const
  GateTag = "[inv9-claim-scan]"
  DefaultAllowlistPath = "tools/ci/inv9_forbidden_claim_allowlist.json"
  DefaultScanRoots: array[6, string] = [
    "data/trusted/certificates",
    "data/trusted/subjects",
    "data/trusted/evidence",
    "data/trusted/journal",
    "data/certification",
    "data/attestations",
  ]

type
  ScanError = object
    path: string
    reason: string

proc loadAllowlist(path: string): seq[ClaimAllowlistEntry] =
  ## Parse the allowlist file. Any structural deviation is fatal (caller
  ## exits 2): a silently-ignored allowlist could hide anchor drift.
  let raw = readFile(path)
  let root = parseJson(raw)
  if root.kind != JArray:
    raise newException(CatchableError, "allowlist root is not a JSON array")
  result = @[]
  for item in root.items:
    if item.kind != JObject:
      raise newException(CatchableError, "allowlist entry is not an object")
    result.add(ClaimAllowlistEntry(
      file: item["file"].getStr(),
      symbol: item["symbol"].getStr(),
      ruleId: item["ruleId"].getStr(),
      contentHash: item["contentHash"].getStr(),
      note: if item.hasKey("note"): item["note"].getStr() else: ""))

proc collectFiles(paths: seq[string]; explicit: bool):
    tuple[files: seq[string]; errors: seq[ScanError]] =
  ## Expand directories (recursive, sorted) and keep files as-is.
  ## explicit=true (user-passed paths): a missing path is a fail-closed error.
  ## explicit=false (default roots): a missing root is an empty surface —
  ## runtime state (certificates/journal) is legitimately absent pre-mint.
  result.files = @[]
  result.errors = @[]
  for p in paths:
    if fileExists(p):
      result.files.add(normalizedPath(p))
    elif dirExists(p):
      var members: seq[string] = @[]
      for f in walkDirRec(p):
        members.add(f)
      members.sort(system.cmp[string])
      for f in members:
        result.files.add(normalizedPath(f))
    else:
      if explicit:
        result.errors.add(ScanError(path: normalizedPath(p),
          reason: "scan target missing (fail-closed — never skip)"))
  result.files.sort(system.cmp[string])

proc scanFile(path: string): tuple[findings: seq[PayloadFinding]; errors: seq[ScanError]] =
  ## Scan one file. .json = structured payload scan (field-path symbols);
  ## everything else = raw-text scan (symbol "text"). Unreadable or
  ## unparseable targets are errors (fail-closed), never skipped.
  result.findings = @[]
  result.errors = @[]
  var content: string
  try:
    content = readFile(path)
  except CatchableError as e:
    result.errors.add(ScanError(path: path,
      reason: "unreadable (fail-closed): " & e.msg))
    return
  if path.splitFile.ext == ".json":
    try:
      let root = parseJson(content)
      result.findings = scanCertPayload(root)
    except CatchableError as e:
      result.errors.add(ScanError(path: path,
        reason: "malformed certificate JSON (fail-closed): " & e.msg))
  else:
    for f in findForbiddenClaims(content):
      result.findings.add(PayloadFinding(
        symbol: "text", ruleId: f.ruleId, phrase: f.phrase, value: content,
        offset: f.offset, line: f.line))

proc reportFindings(kind: string; file: string;
                    findings: seq[PayloadFinding];
                    allowlist: seq[ClaimAllowlistEntry]) =
  for f in findings:
    var allowed = false
    for e in allowlist:
      if isAllowlisted(f, file, e):
        allowed = true
        break
    if allowed:
      echo "[INV9-ALLOW] ", file, " ", f.symbol, " ", f.ruleId,
        " hash=", findingContentHash(f)
    else:
      echo "[INV9-", kind, "] ", file, " ", f.symbol, " ", f.ruleId,
        " \"", f.phrase, "\" hash=", findingContentHash(f),
        " line=", $f.line

proc main() =
  let args = commandLineParams()
  if args.len == 1 and (args[0] == "--help" or args[0] == "-h"):
    echo "usage: check_inv9_forbidden_claims [--allowlist <file>] [path...]"
    echo "  no path = scan the default certificate-payload roots"
    echo "  exit: 0 clean · 1 forbidden claim · 2 fail-closed error"
    quit(0)

  var allowlistPath = DefaultAllowlistPath
  var targets: seq[string] = @[]
  var i = 0
  while i < args.len:
    if args[i] == "--allowlist":
      if i + 1 >= args.len:
        echo GateTag, " FAIL — --allowlist requires a file path argument"
        quit(2)
      inc i
      allowlistPath = args[i]
    elif args[i].startsWith("--allowlist="):
      allowlistPath = args[i]["--allowlist=".len .. ^1]
    else:
      targets.add(args[i])
    inc i
  var usedDefaultRoots = false
  if targets.len == 0:
    usedDefaultRoots = true
    for root in DefaultScanRoots:
      targets.add(root)

  var allowlist: seq[ClaimAllowlistEntry] = @[]
  try:
    allowlist = loadAllowlist(allowlistPath)
  except CatchableError as e:
    echo GateTag, " FAIL — allowlist unusable (fail-closed): ", allowlistPath,
      " — ", e.msg
    quit(2)

  let collected = collectFiles(targets, not usedDefaultRoots)
  var totalFindings = 0
  var totalAllowed = 0
  var totalErrors = collected.errors.len
  var blockedByFile: seq[tuple[file: string;
      findings: seq[PayloadFinding]]] = @[]
  var allowedByFile: seq[tuple[file: string;
      findings: seq[PayloadFinding]]] = @[]

  for e in collected.errors:
    echo "[INV9-ERROR] ", e.path, ": ", e.reason

  for f in collected.files:
    let scanned = scanFile(f)
    for e in scanned.errors:
      echo "[INV9-ERROR] ", e.path, ": ", e.reason
      inc totalErrors
    var blocked: seq[PayloadFinding] = @[]
    var allowed: seq[PayloadFinding] = @[]
    for finding in scanned.findings:
      var isAllowed = false
      for entry in allowlist:
        if isAllowlisted(finding, f, entry):
          isAllowed = true
          break
      if isAllowed:
        allowed.add(finding)
      else:
        blocked.add(finding)
    if blocked.len > 0:
      blockedByFile.add((file: f, findings: blocked))
    if allowed.len > 0:
      allowedByFile.add((file: f, findings: allowed))
    inc totalFindings, scanned.findings.len
    inc totalAllowed, allowed.len

  # Deterministic report order: file, then symbol, then ruleId, then offset.
  blockedByFile.sort(proc(a, b: tuple[file: string; findings: seq[PayloadFinding]]): int =
    system.cmp[string](a.file, b.file))
  allowedByFile.sort(proc(a, b: tuple[file: string; findings: seq[PayloadFinding]]): int =
    system.cmp[string](a.file, b.file))
  for entry in blockedByFile:
    var sorted = entry.findings
    sorted.sort(proc(a, b: PayloadFinding): int =
      let s = system.cmp[string](a.symbol, b.symbol)
      if s != 0: return s
      let r = system.cmp[string](a.ruleId, b.ruleId)
      if r != 0: return r
      return system.cmp[int](a.offset, b.offset))
    reportFindings("FAIL", entry.file, sorted, @[])
  for entry in allowedByFile:
    var sorted = entry.findings
    sorted.sort(proc(a, b: PayloadFinding): int =
      let s = system.cmp[string](a.symbol, b.symbol)
      if s != 0: return s
      let r = system.cmp[string](a.ruleId, b.ruleId)
      if r != 0: return r
      return system.cmp[int](a.offset, b.offset))
    reportFindings("ALLOW", entry.file, sorted, allowlist)

  echo GateTag, " files=", collected.files.len,
    " findings=", $totalFindings,
    " allowlisted=", $totalAllowed,
    " errors=", $totalErrors

  if totalErrors > 0:
    echo GateTag, " FAIL — fail-closed scan errors present (exit 2)"
    quit(2)
  if totalFindings > totalAllowed:
    echo GateTag, " FAIL — forbidden claim sentence(s) present (INV-9; ",
      "bounded shape: \"verified w.r.t. the extracted representation under a ",
      "Qualified extractor\")"
    quit(1)
  echo GateTag, " PASS — no un-allowlisted forbidden claim sentences"
  quit(0)

main()
