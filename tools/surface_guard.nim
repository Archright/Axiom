## tools/surface_guard.nim — deterministic repository-surface classifier.
##
## Classifies `git diff --name-status` records against a repository surface
## policy and emits a single verdict JSON on stdout. The verdict is decided by
## pure functions — never by a human. Advisory classifier: it grants and denies
## no merge authority. Merge authority is GitHub (CODEOWNERS + ruleset required
## checks + merge queue); a FAIL verdict here does not by itself block a merge
## (layers 1-3, docs/spec/repository_surface_contract.md). The SL-20 admission
## wiring inside the required admission-check workflow is layer 4 — there a
## FAIL does block the merge, per the same contract.
## Mirrors the purity boundary of tools/readiness_evaluator.nim:
##
##   loadPolicy / readDiff   (IO only)
##     -> parseNameStatus    (pure, {.raises: [].})
##     -> resolveClass       (pure, {.raises: [].})
##     -> classify           (pure, {.raises: [].})
##     -> checkClosure       (pure, {.raises: [].})
##
## CLI:
##   surface_guard --policy <base_policy.json> [--head-policy <head.json>] [--diff <file>]
##   surface_guard --policy <policy.json> --check-closure <closure.json>
##   --diff omitted -> `git diff --name-status` text is read from stdin.
##   --head-policy pairs with the diff mode only; together with --check-closure
##   it is a usage error (exit 2) — the closure check judges the policy file
##   itself, not a change.
##
## Exit codes:
##   0 = PASS        (verdict JSON on stdout, exit 0)
##   1 = FAIL        (verdict JSON on stdout, exit 1)
##   2 = usage/load error (missing --policy, unknown flag, --diff together
##       with --check-closure, --head-policy together with --check-closure,
##       or a file cannot be opened/read). Nothing is written to stdout on
##       exit 2.
##
## Unparsable policy CONTENT or missing required policy fields is NOT a usage
## error: it produces a FAIL verdict with reasonCode POLICY_INVALID and exit 1
## (fail closed). File-not-found / unreadable files are usage/load errors
## (exit 2), because no evaluation happened at all. An unparsable
## --head-policy file is neither: the head policy only ARMS the
## selfAmendment exception, so an unparsable head policy leaves the exception
## unarmed (fail closed — the base verdict stands) and the run still emits a
## verdict (exit 0/1).
##
## Policy schema (schemaVersion 1):
##   { "schemaVersion": 1,
##     "policyVersion": <int>,
##     "classes":  { "PRODUCT": [glob...], "CONTROLLED": [glob...],
##                   "FROZEN":   [glob...] },
##     "defaultClass": "PRODUCT",
##     "rules": { <class>: { "ADD": "PASS"|"FAIL", "MODIFY": ..., "DELETE": ... } },
##     "resolutionOrder": ["PRODUCT", "CONTROLLED", "FROZEN"],   # optional
##     "selfAmendment": { "allowedPaths": [path...] } }           # optional
##
## Class resolution order: PRODUCT patterns -> CONTROLLED patterns -> FROZEN
## patterns -> defaultClass. First pattern match wins. The order is hardcoded
## in resolveClass. The optional `resolutionOrder` field is VALIDATED to
## declare exactly this order (a policy declaring a different order is
## POLICY_INVALID — declaration and semantics must agree); the legacy
## `classResolutionOrder` field (pre-v99 policies) is ignored without penalty.
##
## Structural validation (fail closed — every deviation is a verdict-level
## POLICY_INVALID, reported with an empty violations list):
##   * classes: exactly the three class keys (unknown key rejected), each an
##     array of strings;
##   * rules: exactly the three class keys (unknown key rejected), each an
##     object whose keys are a subset of {ADD, MODIFY, DELETE} (unknown op key
##     rejected). A MISSING op key is not a structural error — it surfaces as
##     a per-change POLICY_INVALID violation when a change needs that op;
##   * defaultClass must be one of the three class names;
##   * resolutionOrder (optional): exactly ["PRODUCT", "CONTROLLED", "FROZEN"];
##   * selfAmendment (optional): an object whose ONLY key is "allowedPaths",
##     an array of strings;
##   * exact double registration: a pattern with no wildcard ('*') listed in
##     two or more DIFFERENT classes is POLICY_INVALID — an exact path has
##     exactly one intended class (DEBT#538). Wildcard overlaps remain legal
##     and are resolved by the hardcoded precedence.
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
## Rename rule (two-sided, v2): a rename (R) is judged on BOTH paths — the
## NEW path with op ADD (a rename introduces a path that did not exist at
## that location, so a rename landing in CONTROLLED/FROZEN must go through a
## policy PR) and the OLD path with op DELETE of ITS OWN class (renaming a
## FROZEN path away is judged by rules.<class>.DELETE — closing v1's
## "old path is always PASS" blind spot, knownBlindSpots v51). A copy (C) is
## judged as ADD of the new path only (the source path stays intact).
##
## Rule application: "PASS" -> ok; "FAIL" -> violation
## {path,status,changeClass,op,reasonCode:"SURFACE_FORBIDDEN"}; any other or
## missing rule value -> violation reasonCode POLICY_INVALID (fail closed).
##
## selfAmendment exception (v2): SURFACE_FORBIDDEN violations on the FROZEN
## class are reclassified as `amendments` (verdict PASS, reasonCode AMENDED)
## only when ALL of the following hold — one miss leaves the FAIL standing:
##   (a) a head policy is supplied AND is structurally valid;
##   (b) the BASE policy declares selfAmendment.allowedPaths (non-empty);
##   (c) every FROZEN SURFACE_FORBIDDEN violation path is in allowedPaths;
##   (d) policyVersion(head) > policyVersion(base) (monotonic revision).
## This is the legal self-evolution path: the base policy names the exact
## paths its own amendment may touch, and the head policy must be a STRICTLY
## NEWER structurally-valid revision. It grants no authority over any other
## FROZEN path and never over non-FROZEN classes.
##
## Verdict reasonCode when multiple kinds of violation occur (all violations
## are always reported): POLICY_INVALID > UNPARSEABLE_DIFF > SURFACE_FORBIDDEN.
## When no violations remain but amendments exist: AMENDED.
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

proc jsonKeys(node: JsonNode): seq[string] {.raises: [].} =
  ## Deterministic key list of a JSON object (insertion order); empty for
  ## non-objects/nil.
  if node.isNil or node.kind != JObject:
    return @[]
  for k, _ in node:
    result.add(k)

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

proc selfAmendmentPaths*(policy: JsonNode): seq[string] {.raises: [].} =
  ## Pure: the selfAmendment.allowedPaths list of a policy (empty when the
  ## field is absent or malformed — validity itself is isValidPolicy's job).
  let sa = child(policy, "selfAmendment")
  if sa.isNil or sa.kind != JObject:
    return @[]
  let ap = child(sa, "allowedPaths")
  if ap.isNil or ap.kind != JArray:
    return @[]
  for p in ap.items:
    if p.kind == JString:
      result.add(p.getStr())

const FROZEN_EXCEPTION_SCHEMA* = "axiom.repository-surface-frozen-exceptions.v1"

proc frozenExceptionPaths*(policy: JsonNode): seq[string] {.raises: [].} =
  ## Pure: the exact paths registered as intentional FROZEN-glob overrides
  ## (frozenExceptions.paths), in declaration order. Empty when the block is
  ## absent or malformed — validity itself is isValidPolicy's job.
  let fe = child(policy, "frozenExceptions")
  if fe.isNil or fe.kind != JObject:
    return @[]
  let paths = child(fe, "paths")
  if paths.isNil or paths.kind != JObject:
    return @[]
  result = jsonKeys(paths)

proc exactPatternClasses(policy: JsonNode): seq[tuple[pattern: string,
                                                      classes: seq[string]]] {.raises: [].} =
  ## Pure: exact (no-wildcard) patterns listed in two or more DIFFERENT
  ## classes — the DEBT#538 double registration. Wildcard patterns are legal
  ## to overlap (they resolve by the hardcoded precedence).
  if policy.isNil or policy.kind != JObject:
    return @[]
  let classes = child(policy, "classes")
  if classes.isNil or classes.kind != JObject:
    return @[]
  var seen: seq[tuple[pattern: string, classes: seq[string]]] = @[]
  for cls, arr in classes:
    if arr.isNil or arr.kind != JArray:
      continue
    for pat in arr.items:
      if pat.isNil or pat.kind != JString:
        continue
      let p = pat.getStr()
      if '*' in p:
        continue
      var found = false
      for i in 0 ..< seen.len:
        if seen[i].pattern == p:
          if cls notin seen[i].classes:
            seen[i].classes.add(cls)
          found = true
          break
      if not found:
        seen.add((p, @[cls]))
  for e in seen:
    if e.classes.len >= 2:
      result.add(e)

proc isValidPolicy(policy: JsonNode): bool {.raises: [].} =
  ## Structural policy validation (fail closed): every deviation is
  ## POLICY_INVALID. All three classes must be present in `classes` and
  ## `rules` (possibly with empty pattern arrays). Unknown keys inside
  ## `classes`, `rules`, and `rules[<class>]` are rejected; `defaultClass`
  ## must be one of the three classes; `resolutionOrder` (optional) must
  ## declare exactly the hardcoded PRODUCT -> CONTROLLED -> FROZEN order;
  ## `selfAmendment` (optional) may carry only `allowedPaths` (string array);
  ## an exact (no-wildcard) pattern registered in two or more classes is
  ## rejected (DEBT#538); `frozenExceptions` (optional) must carry exactly
  ## `schema`/`groups`/`paths`, every group must state `rationale` and
  ## `approvedBy`, every exact PRODUCT/CONTROLLED pattern matching a FROZEN
  ## pattern must be registered there by exact path, and every registered path
  ## must be such a conflict (dead exceptions are rejected — DEBT#545).
  ## The legacy `classResolutionOrder` field is ignored without penalty.
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
  const classSet = ["PRODUCT", "CONTROLLED", "FROZEN"]
  const opSet = ["ADD", "MODIFY", "DELETE"]
  for k in jsonKeys(classes):
    if k notin classSet:
      return false
  for c in classSet:
    let ca = child(classes, c)
    if ca.isNil or ca.kind != JArray:
      return false
    for pat in ca.items:
      if pat.isNil or pat.kind != JString:
        return false
  for k in jsonKeys(rules):
    if k notin classSet:
      return false
  for c in classSet:
    let r = child(rules, c)
    if r.isNil or r.kind != JObject:
      return false
    for ok in jsonKeys(r):
      if ok notin opSet:
        return false
  if defaultClass.getStr() notin classSet:
    return false
  let ro = child(policy, "resolutionOrder")
  if not ro.isNil:
    if ro.kind != JArray or ro.len() != 3:
      return false
    for i, c in classSet:
      let item = ro.elems[i]
      if item.isNil or item.kind != JString or item.getStr() != c:
        return false
  let sa = child(policy, "selfAmendment")
  if not sa.isNil:
    if sa.kind != JObject:
      return false
    let saKeys = jsonKeys(sa)
    if saKeys.len != 1 or saKeys[0] != "allowedPaths":
      return false
    let ap = child(sa, "allowedPaths")
    if ap.isNil or ap.kind != JArray:
      return false
    for p in ap.items:
      if p.isNil or p.kind != JString:
        return false
  # v3 (DEBT#545): an exact PRODUCT/CONTROLLED registration that also matches
  # a FROZEN pattern resolves to PRODUCT/CONTROLLED under first-match, so the
  # declared FROZEN protection would be inert. Every such conflict must be
  # registered by exact path in frozenExceptions — wildcards are rejected,
  # because a broad exception would re-arm the same theater. Unregistered
  # conflicts and dead exceptions are POLICY_INVALID.
  let fe = child(policy, "frozenExceptions")
  var excPaths: seq[string] = @[]
  if not fe.isNil:
    if fe.kind != JObject:
      return false
    let feKeys = jsonKeys(fe)
    if feKeys.len != 3:
      return false
    for k in feKeys:
      if k notin ["schema", "groups", "paths"]:
        return false
    let sch = child(fe, "schema")
    if sch.isNil or sch.kind != JString or
        sch.getStr() != FROZEN_EXCEPTION_SCHEMA:
      return false
    let groups = child(fe, "groups")
    if groups.isNil or groups.kind != JObject:
      return false
    for gk in jsonKeys(groups):
      let g = child(groups, gk)
      if g.isNil or g.kind != JObject:
        return false
      let gKeys = jsonKeys(g)
      if gKeys.len != 2:
        return false
      for x in gKeys:
        if x notin ["rationale", "approvedBy"]:
          return false
      let ra = child(g, "rationale")
      let ab = child(g, "approvedBy")
      if ra.isNil or ra.kind != JString or ra.getStr().len == 0:
        return false
      if ab.isNil or ab.kind != JString or ab.getStr().len == 0:
        return false
    let paths = child(fe, "paths")
    if paths.isNil or paths.kind != JObject:
      return false
    for pk in jsonKeys(paths):
      let gid = child(paths, pk)
      if gid.isNil or gid.kind != JString:
        return false
      if child(groups, gid.getStr()).isNil:
        return false
      excPaths.add(pk)
  let frozenArr = child(classes, "FROZEN")
  var conflicts: seq[string] = @[]
  for cls in ["PRODUCT", "CONTROLLED"]:
    let arr = child(classes, cls)
    if arr.isNil or arr.kind != JArray:
      continue
    for pat in arr.items:
      if pat.isNil or pat.kind != JString:
        continue
      let p = pat.getStr()
      if '*' in p:
        continue
      for fp in frozenArr.items:
        if fp.kind == JString and globMatch(fp.getStr(), p):
          conflicts.add(p)
          break
  for c in conflicts:
    if c notin excPaths:
      return false
  for e in excPaths:
    if e notin conflicts:
      return false
  if exactPatternClasses(policy).len() > 0:
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

proc violationJson(path, status, cls, op, reason: string): JsonNode {.raises: [].} =
  ## One violation record. `op` is the judged op (ADD/MODIFY/DELETE, or ""
  ## for records that could not be parsed into an op at all).
  %* {"path": path, "status": status, "changeClass": cls, "op": op,
      "reasonCode": reason}

proc classify*(policy: JsonNode, changes: seq[ChangeRecord],
              headPolicy: JsonNode = nil): JsonNode {.raises: [].} =
  ## Pure: produce the verdict JSON from a policy and change records.
  ## `headPolicy` (optional) arms the selfAmendment exception — see the
  ## header. Deterministic: same inputs -> byte-identical JSON.
  var violations: seq[JsonNode] = @[]
  var amendments: seq[JsonNode] = @[]
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
    return %* {"schemaVersion": 1, "verdict": "FAIL",
               "reasonCode": "POLICY_INVALID", "policyVersion": nil,
               "binding": "base", "changeCount": changes.len,
               "violations": @[], "amendments": @[],
               "summary": {"add": add, "modify": modify, "delete": delete,
                           "rename": rename, "other": other}}

  proc applyChange(p: string, statusStr, op: string) =
    let cls = resolveClass(policy, p)
    let rule = ruleValue(policy, cls, op)
    if rule == "FAIL":
      violations.add(violationJson(p, statusStr, cls, op, "SURFACE_FORBIDDEN"))
    elif rule != "PASS":
      # missing or invalid rule value: fail closed.
      violations.add(violationJson(p, statusStr, cls, op, "POLICY_INVALID"))

  for rec in changes:
    case rec.status
    of 'A':
      applyChange(rec.path, "A", "ADD")
    of 'C':
      # copy -> judged as ADD of the new path (the source path stays intact).
      if rec.newPath.len == 0:
        violations.add(violationJson(rec.path, "C", "", "", "UNPARSEABLE_DIFF"))
      else:
        applyChange(rec.newPath, "C", "ADD")
    of 'M':
      applyChange(rec.path, "M", "MODIFY")
    of 'T':
      applyChange(rec.path, "T", "MODIFY")
    of 'D':
      applyChange(rec.path, "D", "DELETE")
    of 'R':
      # rename -> BOTH sides judged: the new path with op ADD, the old path
      # with op DELETE of its own class (two-sided, v2 — see header).
      if rec.newPath.len == 0:
        violations.add(violationJson(rec.path, "R", "", "", "UNPARSEABLE_DIFF"))
      else:
        applyChange(rec.newPath, "R", "ADD")
        applyChange(rec.path, "R", "DELETE")
    else:
      # unknown status letter or unparsable line record: fail closed.
      violations.add(violationJson(rec.path, $rec.status, "", "",
                                   "UNPARSEABLE_DIFF"))

  # selfAmendment exception — header conditions (a)-(d); one miss leaves the
  # FAIL standing (fail closed).
  if headPolicy != nil and isValidPolicy(headPolicy):
    let allowed = selfAmendmentPaths(policy)
    if allowed.len() > 0:
      let baseV = child(policy, "policyVersion").getInt()
      let headV = child(headPolicy, "policyVersion").getInt()
      if headV > baseV:
        var hasFrozen = false
        var allIn = true
        for v in violations:
          let rc = child(v, "reasonCode")
          let cc = child(v, "changeClass")
          if not rc.isNil and not cc.isNil and
              rc.getStr() == "SURFACE_FORBIDDEN" and cc.getStr() == "FROZEN":
            hasFrozen = true
            let pth = child(v, "path")
            if pth.isNil or pth.getStr() notin allowed:
              allIn = false
              break
        if hasFrozen and allIn:
          var remaining: seq[JsonNode] = @[]
          for v in violations:
            let rc = child(v, "reasonCode")
            let cc = child(v, "changeClass")
            if not rc.isNil and not cc.isNil and
                rc.getStr() == "SURFACE_FORBIDDEN" and cc.getStr() == "FROZEN":
              amendments.add(v)
            else:
              remaining.add(v)
          violations = remaining

  # verdict reasonCode = strongest kind present among REMAINING violations
  # (OK only when none; AMENDED when the exception cleared them all).
  var reasonCode = "OK"
  if violations.len() > 0:
    reasonCode = "SURFACE_FORBIDDEN"
    for v in violations:
      let rc = child(v, "reasonCode")
      if rc.isNil:
        continue
      let r = rc.getStr()
      if r == "POLICY_INVALID":
        reasonCode = "POLICY_INVALID"
        break
      elif r == "UNPARSEABLE_DIFF" and reasonCode != "POLICY_INVALID":
        reasonCode = "UNPARSEABLE_DIFF"
  elif amendments.len() > 0:
    reasonCode = "AMENDED"

  %* {"schemaVersion": 1,
      "verdict": (if violations.len() == 0: "PASS" else: "FAIL"),
      "reasonCode": reasonCode,
      "policyVersion": child(policy, "policyVersion").getInt(),
      "binding": "base",
      "changeCount": changes.len,
      "violations": violations,
      "amendments": amendments,
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
  ## IO: read + parse a policy file. ok=false + invalidContent=true means the
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
    stderr.writeLine("usage: surface_guard --policy <base_policy.json> [--head-policy <head_policy.json>] [--diff <file>]")
    stderr.writeLine("       surface_guard --policy <policy.json> --check-closure <closure.json>")
    quit(2)

  var policyPath = ""
  var diffPath = ""
  var closurePath = ""
  var headPolicyPath = ""
  let args = commandLineParams()
  var i = 0
  while i < args.len:
    if args[i] == "--policy" and i + 1 < args.len:
      policyPath = args[i + 1]
      inc i
    elif args[i] == "--diff" and i + 1 < args.len:
      diffPath = args[i + 1]
      inc i
    elif args[i] == "--head-policy" and i + 1 < args.len:
      headPolicyPath = args[i + 1]
      inc i
    elif args[i] == "--check-closure" and i + 1 < args.len:
      closurePath = args[i + 1]
      inc i
    else:
      usage()
    inc i
  # --diff omitted -> read `git diff --name-status` text from stdin.
  # --head-policy pairs with the diff mode only (closure judges the policy
  # file itself, not a change — pairing them is a usage error).
  if policyPath == "" or (diffPath != "" and closurePath != "") or
     (headPolicyPath != "" and closurePath != ""):
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

  var headPolicy: JsonNode = nil
  if headPolicyPath != "":
    let hl = loadPolicy(headPolicyPath)
    if not hl.ok and not hl.invalidContent:
      stderr.writeLine("surface_guard: cannot read head policy file: " & headPolicyPath)
      quit(2)
    if hl.ok:
      headPolicy = hl.node
    else:
      # unparsable head policy: the exception stays unarmed (fail closed) and
      # the base verdict still decides — see header.
      stderr.writeLine("surface_guard: unparsable head policy JSON: " &
                       headPolicyPath & " (selfAmendment exception NOT applied)")

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
  let verdict = classify(policy, records, headPolicy)
  echo verdict.pretty(2)
  quit(if verdict["verdict"].getStr() == "PASS": 0 else: 1)

when isMainModule:
  main()
