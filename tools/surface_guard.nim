## tools/surface_guard.nim — deterministic repository-surface classifier.
##
## Classifies `git diff --name-status` records against a repository surface
## policy and emits a single verdict JSON on stdout. The verdict is decided by
## pure functions — never by a human. Advisory classifier: it grants and denies
## no merge authority. Merge authority is GitHub (CODEOWNERS + ruleset required
## checks + merge queue); a FAIL verdict here does not by itself block a merge.
## Mirrors the purity boundary of tools/readiness_evaluator.nim:
##
##   loadPolicy / readDiff   (IO only)
##     -> parseNameStatus    (pure, {.raises: [].})
##     -> resolveClass       (pure, {.raises: [].})
##     -> classify           (pure, {.raises: [].})
##     -> checkClosure       (pure, {.raises: [].})
##
## CLI:
##   surface_guard --policy <policy.json> [--diff <file>]
##   surface_guard --policy <policy.json> --check-closure <closure.json>
##   --diff omitted -> `git diff --name-status` text is read from stdin.
##
## Exit codes:
##   0 = PASS        (verdict JSON on stdout, exit 0)
##   1 = FAIL        (verdict JSON on stdout, exit 1)
##   2 = usage/load error (missing --policy, unknown flag, both --diff and
##       --check-closure given, or a file cannot be opened/read). Nothing is
##       written to stdout on exit 2.
##
## Unparsable policy CONTENT or missing required policy fields is NOT a usage
## error: it produces a FAIL verdict with reasonCode POLICY_INVALID and exit 1
## (fail closed). File-not-found / unreadable files are usage/load errors
## (exit 2), because no evaluation happened at all.
##
## Policy schema (schemaVersion 1):
##   { "schemaVersion": 1,
##     "policyVersion": <int>,
##     "classes":  { "PRODUCT": [glob...], "CONTROLLED": [glob...],
##                   "FROZEN":   [glob...] },
##     "defaultClass": "PRODUCT",
##     "rules": { <class>: { "ADD": "PASS"|"FAIL", "MODIFY": ..., "DELETE": ... } } }
## Class resolution order: PRODUCT patterns -> CONTROLLED patterns -> FROZEN
## patterns -> defaultClass. First pattern match wins. The order is hardcoded in
## resolveClass — the policy's `classResolutionOrder` field is NOT read.
##
## Glob semantics: pattern segments are split by "/". "**" matches any number
## of whole segments (including zero); "*" matches an arbitrary run of
## characters within a single segment; no wildcard = exact segment.
##   src/core/**  matches src/core/a.nim and src/core/x/b.nim (and src/core)
##   Makefile     matches only Makefile
##   tools/*.nim  matches tools/a.nim but not tools/x/b.nim
##
## Diff input: lines of `git diff --name-status`: `<STATUS>\t<path>` or
## R<score>\t<old>\t<new> / C<score>\t<old>\t<new>. Status classes by first
## char: A=ADD, M=MODIFY, D=DELETE, R=rename, C=copy, T=typechange (MODIFY).
## Any other first char, or a line that cannot be parsed (no tab, empty
## status, empty path, or R/C without both old and new path) -> violation with
## reasonCode UNPARSEABLE_DIFF (fail closed). Blank lines are skipped.
##
## Rename rule (frozen): a rename (R) is judged on the NEW path with op ADD —
## a rename introduces a path that did not exist at that location, so a rename
## landing in CONTROLLED/FROZEN must go through a policy PR. The OLD path is
## an implicit DELETE and is always PASS. A copy (C) is judged as ADD of the
## new path.
##
## Rule application: "PASS" -> ok; "FAIL" -> violation
## {path,status,changeClass,reasonCode:"SURFACE_FORBIDDEN"}; any other or
## missing rule value -> violation reasonCode POLICY_INVALID (fail closed).
##
## Verdict reasonCode when multiple kinds of violation occur (all violations
## are always reported): POLICY_INVALID > UNPARSEABLE_DIFF > SURFACE_FORBIDDEN.
##
## Determinism: classify/checkClosure are pure functions of their inputs;
## identical inputs -> byte-identical verdict JSON (keys and values built in a
## fixed order).

import std/[json, strutils, sequtils, os]

# ---------------------------------------------------------------------------
# Pure core
# ---------------------------------------------------------------------------

type
  ChangeRecord* = object
    ## One parsed `git diff --name-status` record.
    status*: char    ## 'A','M','D','R','C','T'; '?' for an unparsable line
    path*: string    ## primary path (for R/C the old path; for '?' the raw line)
    newPath*: string ## non-empty only for R/C (the new path)

proc parseNameStatus*(text: string): (seq[ChangeRecord], seq[string]) =
  ## Pure: parse `git diff --name-status` text into records plus the raw
  ## unparsable lines (diagnostics). Unparsable lines are ALSO returned as
  ## records with status '?' so the pure classify() sees them and fails
  ## closed — the second return value exists for reporting only.
  var records: seq[ChangeRecord] = @[]
  var bad: seq[string] = @[]
  for rawLine in text.splitLines():
    let line = rawLine.strip(leading = false, trailing = true, chars = {'\r'})
    if line.len == 0:
      continue
    let fields = line.split('\t')
    if fields.len < 2 or fields[0].len == 0 or fields[1].len == 0:
      bad.add(line)
      records.add(ChangeRecord(status: '?', path: line))
      continue
    let st = fields[0][0]
    case st
    of 'A', 'M', 'D', 'T':
      records.add(ChangeRecord(status: st, path: fields[1]))
    of 'R', 'C':
      if fields.len < 3 or fields[2].len == 0:
        # rename/copy requires an old and a new path: unparsable.
        bad.add(line)
        records.add(ChangeRecord(status: st, path: fields[1]))
      else:
        records.add(ChangeRecord(status: st, path: fields[1], newPath: fields[2]))
    else:
      # Unknown status letter: keep the record so classify() fails closed.
      records.add(ChangeRecord(status: st, path: fields[1]))
  (records, bad)

proc segMatch(pat, seg: string): bool {.raises: [].} =
  ## '*' matches an arbitrary run of characters within one segment.
  ## Classic wildcard DP over (pattern chars x segment chars).
  var prev = newSeq[bool](pat.len + 1)
  prev[0] = true
  for i in 1..pat.len:
    prev[i] = prev[i - 1] and pat[i - 1] == '*'
  for j in 1..seg.len:
    var cur = newSeq[bool](pat.len + 1)
    for i in 1..pat.len:
      if pat[i - 1] == '*':
        cur[i] = cur[i - 1] or prev[i]
      elif pat[i - 1] == seg[j - 1]:
        cur[i] = prev[i - 1]
    prev = cur
  prev[pat.len]

proc globMatch(pat, path: string): bool {.raises: [].} =
  ## Segment-wise glob: "**" swallows any number of whole segments (incl. zero).
  var ps = pat.split('/').filterIt(it.len > 0)
  var xs = path.split('/').filterIt(it.len > 0)
  var pi = 0
  var si = 0
  var starPi = -1
  var starSi = 0
  while si < xs.len:
    if pi < ps.len and ps[pi] == "**":
      starPi = pi
      starSi = si
      inc pi
    elif pi < ps.len and segMatch(ps[pi], xs[si]):
      inc pi
      inc si
    elif starPi >= 0:
      pi = starPi + 1
      inc starSi
      si = starSi
    else:
      return false
  while pi < ps.len and ps[pi] == "**":
    inc pi
  pi == ps.len

proc child(node: JsonNode, key: string): JsonNode {.raises: [].} =
  ## Non-raising field access: nil when `node` is not an object or `key` is
  ## absent. std/json `[]`(name) raises KeyError, which the {.raises: [].}
  ## contract forbids, so the object's own pairs iterator is used.
  if node.isNil or node.kind != JObject:
    return nil
  for k, v in node:
    if k == key:
      return v
  nil

proc matchesClass(policy: JsonNode, cls: string, path: string): bool {.raises: [].} =
  if policy.isNil or policy.kind != JObject:
    return false
  let classes = child(policy, "classes")
  if classes.isNil or classes.kind != JObject:
    return false
  let arr = child(classes, cls)
  if arr.isNil or arr.kind != JArray:
    return false
  for pat in arr.items:
    if pat.kind == JString and globMatch(pat.getStr(), path):
      return true
  false

proc resolveClass*(policy: JsonNode, path: string): string {.raises: [].} =
  ## Pure: first matching class wins — PRODUCT -> CONTROLLED -> FROZEN — else
  ## defaultClass. Returns "" when the policy is malformed or no class matches
  ## and no default exists.
  for c in ["PRODUCT", "CONTROLLED", "FROZEN"]:
    if matchesClass(policy, c, path):
      return c
  if not policy.isNil and policy.kind == JObject:
    let d = child(policy, "defaultClass")
    if not d.isNil and d.kind == JString:
      return d.getStr()
  ""

proc isValidPolicy(policy: JsonNode): bool {.raises: [].} =
  ## Structural policy validation (fail closed): every deviation is
  ## POLICY_INVALID. All three classes must be present in `classes` and
  ## `rules` (possibly with empty pattern arrays).
  if policy.isNil or policy.kind != JObject:
    return false
  let sv = child(policy, "schemaVersion")
  if sv.isNil or sv.kind != JInt or sv.getInt() != 1:
    return false
  let pv = child(policy, "policyVersion")
  if pv.isNil or pv.kind != JInt:
    return false
  let classes = child(policy, "classes")
  if classes.isNil or classes.kind != JObject:
    return false
  let rules = child(policy, "rules")
  if rules.isNil or rules.kind != JObject:
    return false
  let defaultClass = child(policy, "defaultClass")
  if defaultClass.isNil or defaultClass.kind != JString:
    return false
  for c in ["PRODUCT", "CONTROLLED", "FROZEN"]:
    let ca = child(classes, c)
    if ca.isNil or ca.kind != JArray:
      return false
    for pat in ca.items:
      if pat.kind != JString:
        return false
    let r = child(rules, c)
    if r.isNil or r.kind != JObject:
      return false
  true

proc ruleValue(policy: JsonNode, cls, op: string): string {.raises: [].} =
  ## Returns "PASS" or "FAIL", or "" when the rule is missing/invalid.
  let rules = child(policy, "rules")
  if rules.isNil or rules.kind != JObject:
    return ""
  let rc = child(rules, cls)
  if rc.isNil or rc.kind != JObject:
    return ""
  let rv = child(rc, op)
  if rv.isNil or rv.kind != JString:
    return ""
  let v = rv.getStr()
  if v == "PASS" or v == "FAIL": v else: ""

proc noteViolation(violations: var seq[JsonNode], reasonCode: var string,
                   path, status, cls, reason: string) {.raises: [].} =
  violations.add(%* {"path": path, "status": status, "changeClass": cls,
                     "reasonCode": reason})
  # verdict reasonCode = strongest kind present (PASS only when none).
  if reason == "POLICY_INVALID":
    reasonCode = "POLICY_INVALID"
  elif reason == "UNPARSEABLE_DIFF" and reasonCode != "POLICY_INVALID":
    reasonCode = "UNPARSEABLE_DIFF"
  elif reasonCode notin ["POLICY_INVALID", "UNPARSEABLE_DIFF"]:
    reasonCode = "SURFACE_FORBIDDEN"

proc classify*(policy: JsonNode, changes: seq[ChangeRecord]): JsonNode {.raises: [].} =
  ## Pure: produce the verdict JSON from a policy and change records.
  ## Deterministic: same inputs -> byte-identical JSON.
  var violations: seq[JsonNode] = @[]
  var reasonCode = "OK"
  var add = 0
  var modify = 0
  var delete = 0
  var rename = 0
  var other = 0
  for rec in changes:
    case rec.status
    of 'A', 'C': inc add
    of 'M', 'T': inc modify
    of 'D': inc delete
    of 'R': inc rename
    else: inc other
  if not isValidPolicy(policy):
    return %* {"schemaVersion": 1, "verdict": "FAIL", "reasonCode": "POLICY_INVALID",
               "policyVersion": nil, "binding": "base", "changeCount": changes.len,
               "violations": @[], "summary": {"add": add, "modify": modify,
               "delete": delete, "rename": rename, "other": other}}

  proc applyChange(p: string, statusStr, op: string) =
    let cls = resolveClass(policy, p)
    let rule = ruleValue(policy, cls, op)
    if rule == "FAIL":
      noteViolation(violations, reasonCode, p, statusStr, cls, "SURFACE_FORBIDDEN")
    elif rule != "PASS":
      # missing or invalid rule value: fail closed.
      noteViolation(violations, reasonCode, p, statusStr, cls, "POLICY_INVALID")

  for rec in changes:
    case rec.status
    of 'A':
      applyChange(rec.path, "A", "ADD")
    of 'C':
      # copy -> judged as ADD of the new path.
      if rec.newPath.len == 0:
        noteViolation(violations, reasonCode, rec.path, "C", "", "UNPARSEABLE_DIFF")
      else:
        applyChange(rec.newPath, "C", "ADD")
    of 'M':
      applyChange(rec.path, "M", "MODIFY")
    of 'T':
      applyChange(rec.path, "T", "MODIFY")
    of 'D':
      applyChange(rec.path, "D", "DELETE")
    of 'R':
      # rename -> new path judged with op ADD; old path is an implicit
      # DELETE and is always PASS (frozen rule, see header).
      if rec.newPath.len == 0:
        noteViolation(violations, reasonCode, rec.path, "R", "", "UNPARSEABLE_DIFF")
      else:
        applyChange(rec.newPath, "R", "ADD")
    else:
      # unknown status letter or unparsable line record: fail closed.
      noteViolation(violations, reasonCode, rec.path, $rec.status, "", "UNPARSEABLE_DIFF")

  %* {"schemaVersion": 1,
      "verdict": (if violations.len == 0: "PASS" else: "FAIL"),
      "reasonCode": reasonCode,
      "policyVersion": child(policy, "policyVersion").getInt(),
      "binding": "base",
      "changeCount": changes.len,
      "violations": violations,
      "summary": {"add": add, "modify": modify, "delete": delete,
                  "rename": rename, "other": other}}

proc coveredBySurface(policy: JsonNode, path: string): bool {.raises: [].} =
  ## Closure coverage: PRODUCT or CONTROLLED patterns only. Pattern matching
  ## only — defaultClass and FROZEN matches never count as covered.
  for c in ["PRODUCT", "CONTROLLED"]:
    if matchesClass(policy, c, path):
      return true
  false

proc checkClosure*(policy: JsonNode, closure: JsonNode): JsonNode {.raises: [].} =
  ## Pure: closure mode verdict — every reachable file must match a PRODUCT or
  ## CONTROLLED pattern. Deterministic; fail closed on malformed inputs.
  let policyOk = isValidPolicy(policy)
  var closureOk = true
  var uncovered: seq[string] = @[]
  if closure.isNil or closure.kind != JObject:
    closureOk = false
  else:
    let rf = child(closure, "reachableFiles")
    if rf.isNil or rf.kind != JArray:
      closureOk = false
    else:
      for f in rf.items:
        if f.kind == JString:
          if not coveredBySurface(policy, f.getStr()):
            uncovered.add(f.getStr())
        else:
          # non-string reachable entry: fail closed and surface it.
          closureOk = false
          uncovered.add($f)
  var res = newJObject()
  res["schemaVersion"] = %1
  res["check"] = %"closure"
  res["verdict"] = %(if policyOk and closureOk and uncovered.len == 0: "PASS" else: "FAIL")
  var ua = newJArray()
  for p in uncovered:
    ua.add(%p)
  res["uncovered"] = ua
  if policyOk:
    res["policyVersion"] = %(child(policy, "policyVersion").getInt())
  else:
    res["policyVersion"] = newJNull()
  res

# ---------------------------------------------------------------------------
# IO boundary
# ---------------------------------------------------------------------------

proc loadPolicy*(path: string): tuple[ok: bool, invalidContent: bool, node: JsonNode] =
  ## IO: read + parse the policy file. ok=false + invalidContent=true means the
  ## file exists but is not valid JSON (caller emits a POLICY_INVALID verdict,
  ## exit 1); ok=false + invalidContent=false means it could not be read at
  ## all (usage/load error, exit 2).
  if not fileExists(path):
    return (false, false, nil)
  try:
    (true, false, parseFile(path))
  except JsonParsingError:
    (false, true, nil)
  except CatchableError:
    (false, false, nil)

proc readDiff*(path: string): tuple[ok: bool, text: string] =
  ## IO: read the diff file. path == "" means read `git diff --name-status`
  ## text from stdin.
  if path == "":
    return (true, stdin.readAll())
  try:
    (true, readFile(path))
  except CatchableError:
    (false, "")

proc main() =
  proc usage() =
    stderr.writeLine("usage: surface_guard --policy <policy.json> [--diff <file>]")
    stderr.writeLine("       surface_guard --policy <policy.json> --check-closure <closure.json>")
    quit(2)

  var policyPath = ""
  var diffPath = ""
  var closurePath = ""
  let args = commandLineParams()
  var i = 0
  while i < args.len:
    if args[i] == "--policy" and i + 1 < args.len:
      policyPath = args[i + 1]
      inc i
    elif args[i] == "--diff" and i + 1 < args.len:
      diffPath = args[i + 1]
      inc i
    elif args[i] == "--check-closure" and i + 1 < args.len:
      closurePath = args[i + 1]
      inc i
    else:
      usage()
    inc i
  # --diff omitted -> read `git diff --name-status` text from stdin.
  if policyPath == "" or (diffPath != "" and closurePath != ""):
    usage()

  let loaded = loadPolicy(policyPath)
  if not loaded.ok and not loaded.invalidContent:
    stderr.writeLine("surface_guard: cannot read policy file: " & policyPath)
    quit(2)

  if closurePath != "":
    # --check-closure mode.
    let diff = readDiff(closurePath)
    if not diff.ok:
      stderr.writeLine("surface_guard: cannot read closure file: " & closurePath)
      quit(2)
    var closure: JsonNode = nil
    try:
      closure = parseJson(diff.text)
    except JsonParsingError:
      stderr.writeLine("surface_guard: unparsable closure JSON: " & closurePath)
      quit(2)
    let policy = if loaded.ok: loaded.node else: nil
    let verdict = checkClosure(policy, closure)
    echo verdict.pretty(2)
    quit(if verdict["verdict"].getStr() == "PASS": 0 else: 1)

  let diff = readDiff(diffPath)
  if not diff.ok:
    stderr.writeLine("surface_guard: cannot read diff file: " & diffPath)
    quit(2)
  let (records, badLines) = parseNameStatus(diff.text)
  if badLines.len > 0:
    # diagnostic only; the violations appear in the verdict.
    stderr.writeLine("surface_guard: " & $badLines.len &
      " unparsable diff line(s) (see verdict)")
  let policy = if loaded.ok: loaded.node else: nil
  let verdict = classify(policy, records)
  echo verdict.pretty(2)
  quit(if verdict["verdict"].getStr() == "PASS": 0 else: 1)

when isMainModule:
  main()
