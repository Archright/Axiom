import core/trusted/layer_declaration
axiomLayer "tools"

import std/[algorithm, json, os, strutils]

## trust_surface_divergence.nim — VS-A: trust-surface divergence detector.
##
## THE MEASURED PROBLEM
## --------------------
## Axiom carries two independent definitions of "trust surface", and they
## disagree. That disagreement is the structural cause of "a PR touches the
## trust surface and CI deadlocks".
##
##   1. config/policy/trust_surface_manifest.json — 17 exact paths,
##      "comparison": "blob-based", "readFrom": "B_mg". Enforced OUT OF REPO by
##      App 5795152 as a preflight. Any byte change to a listed path ⇒ the App
##      publishes admission-check = failure with reasons=mismatch:<path>, and
##      the PR cannot merge without break-glass.
##   2. config/repository_surface.json — a 3-class path policy
##      (PRODUCT/CONTROLLED/FROZEN, first match in resolutionOrder order, else
##      defaultClass), enforced IN REPO by tools/surface_guard.nim.
##
## Measured at HEAD: of the 17 manifest paths only 2 resolve to FROZEN. The
## other 8 resolve CONTROLLED or default-PRODUCT — so on those 8 the in-repo
## gates PASS while the App FAILs.
##
## WHAT THIS TOOL IS
## -----------------
## A deterministic, pure, READ-ONLY detector plus a ratchet ledger.
##
##   A manifest path is CONVERGENT iff it resolves to FROZEN under the
##   repository-surface semantics; anything else is a DIVERGENCE.
##
## Divergences that already exist are registered in
## data/ci_optimization/trust_surface_divergence/ledger.json. Any divergence
## NOT registered, and any ledger entry that no longer corresponds to a real
## divergence (a dead entry), fails the run. The ledger is exact-path only:
## a wildcard would pre-forgive divergence that has not happened yet.
##
## THIS IS A DETECTOR, NOT AN ADMISSION GATE. It does not prevent the App
## preflight deadlock and it does not decide mergeability. It makes FUTURE
## divergence impossible to introduce silently, by failing before the PR opens.
##
## Resolution semantics are deliberately re-stated here rather than imported
## from tools/surface_guard.nim: this detector must keep working if the guard
## is refactored, and a shared helper would make the two definitions converge
## by construction, which would hide exactly the drift this file exists to
## report. Fidelity is pinned instead by a test that runs this resolver over
## the real policy and asserts 2 FROZEN / 15 divergent — a divergence between
## the two resolvers fails that test loudly.
##
## Exit codes (fail-closed; a read/parse failure is NEVER "no divergence"):
##   0  every divergence is registered in the ledger (or there is none)
##   1  at least one unregistered divergence, or a dead ledger entry
##   2  input error — file missing/unparsable, non-string manifest path, empty
##      manifest path list, repo policy missing classes/resolutionOrder/
##      defaultClass, wildcard or duplicate ledger entry, malformed ledger value
##
## Determinism: paths are sorted, no timestamps, no locale dependence.
## Same input ⇒ byte-identical stdout.

const
  ManifestPath* = "config/policy/trust_surface_manifest.json"
  PolicyPath* = "config/repository_surface.json"
  LedgerPath* = "data/ci_optimization/trust_surface_divergence/ledger.json"
  ## The only class that makes a manifest path convergent: the in-repo policy
  ## and the out-of-repo App agree that the path is immovable.
  ConvergentClass* = "FROZEN"
  ## Reported as `pattern=` when the path matched no pattern at all.
  DefaultPattern* = "<default>"

type
  Verdict* = object
    ## exitCode is 0/1/2; lines is the exact stdout, one string per line.
    exitCode*: int
    lines*: seq[string]

  Classification* = object
    cls*: string
    pattern*: string

# ── resolver (mirrors tools/surface_guard.nim:169-256 semantics) ───────────────

func segMatch(pat, seg: string): bool =
  ## '*' matches an arbitrary run of characters within one path segment.
  var prev = newSeq[bool](pat.len + 1)
  prev[0] = true
  for i in 1 .. pat.len:
    prev[i] = prev[i - 1] and pat[i - 1] == '*'
  for j in 1 .. seg.len:
    var cur = newSeq[bool](pat.len + 1)
    for i in 1 .. pat.len:
      if pat[i - 1] == '*':
        cur[i] = cur[i - 1] or prev[i]
      elif pat[i - 1] == seg[j - 1]:
        cur[i] = prev[i - 1]
    prev = cur
  prev[pat.len]

func splitSegs(s: string): seq[string] =
  for part in s.split('/'):
    if part.len > 0:
      result.add(part)

func globMatch(pat, path: string): bool =
  ## Segment-wise glob: "**" swallows any number of whole segments (incl. zero).
  let ps = splitSegs(pat)
  let xs = splitSegs(path)
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

func field(node: JsonNode, key: string): JsonNode =
  ## Non-raising field access: nil when `node` is not an object or `key` is
  ## absent. std/json `[]`(name) raises KeyError, which {.raises: [].} forbids.
  if node.isNil or node.kind != JObject:
    return nil
  for k, v in node:
    if k == key:
      return v
  nil

func firstPattern(classes: JsonNode, cls, path: string): string =
  ## The first pattern registered under `cls` that matches `path`; "" if none.
  if classes.isNil or classes.kind != JObject:
    return ""
  var arr: JsonNode = nil
  for k, v in classes:
    if k == cls:
      arr = v
      break
  if arr.isNil or arr.kind != JArray:
    return ""
  for p in arr.items:
    if p.kind == JString and globMatch(p.getStr(), path):
      return p.getStr()
  ""

func classifyPath*(policy: JsonNode, path: string): Classification =
  ## First match in `resolutionOrder` order, `defaultClass` when nothing
  ## matches. resolutionOrder is read from the policy, never assumed — the
  ## declared order and the semantics are the same contract.
  let classes = field(policy, "classes")
  let order = field(policy, "resolutionOrder")
  if not order.isNil and order.kind == JArray:
    for item in order.items:
      if item.kind != JString:
        continue
      let cls = item.getStr()
      let pat = firstPattern(classes, cls, path)
      if pat.len > 0:
        return Classification(cls: cls, pattern: pat)
  let dflt = field(policy, "defaultClass")
  let dc = if dflt.isNil or dflt.kind != JString: "" else: dflt.getStr()
  Classification(cls: dc, pattern: DefaultPattern)

# ── validation (every failure is exit 2 — fail closed on unknown input) ────���───

func validateManifest(manifest: JsonNode): string =
  ## "" = valid, else the reason.
  if manifest.isNil or manifest.kind != JObject:
    return "trust-surface manifest is not a JSON object"
  let paths = field(manifest, "paths")
  if paths.isNil or paths.kind != JArray:
    return "trust-surface manifest has no `paths` array"
  if paths.len == 0:
    return "trust-surface manifest `paths` array is empty"
  for item in paths.items:
    if item.kind != JString:
      return "trust-surface manifest `paths` contains a non-string entry"
  ""

func validatePolicy(policy: JsonNode): string =
  if policy.isNil or policy.kind != JObject:
    return "repository-surface policy is not a JSON object"
  let classes = field(policy, "classes")
  if classes.isNil or classes.kind != JObject:
    return "repository-surface policy missing `classes` object"
  let order = field(policy, "resolutionOrder")
  if order.isNil or order.kind != JArray:
    return "repository-surface policy missing `resolutionOrder` array"
  if order.len == 0:
    return "repository-surface policy `resolutionOrder` array is empty"
  for item in order.items:
    if item.kind != JString:
      return "repository-surface policy `resolutionOrder` contains a non-string"
  let dflt = field(policy, "defaultClass")
  if dflt.isNil or dflt.kind != JString:
    return "repository-surface policy missing `defaultClass` string"
  ""

func isLedgerValueValid(v: JsonNode): bool =
  if v.isNil or v.kind != JObject:
    return false
  let reason = field(v, "rationale")
  let tracked = field(v, "trackedAs")
  if reason.isNil or reason.kind != JString or reason.getStr().strip().len == 0:
    return false
  if tracked.isNil or tracked.kind != JString or tracked.getStr().strip().len == 0:
    return false
  true

func countObjectKeys(raw, key: string): int =
  ## Occurrences of `"key"` followed (after optional whitespace) by ':' in the
  ## raw JSON text. std/json collapses duplicate object keys silently, so the
  ## parsed node cannot answer "was this key written twice?" — the raw text is
  ## the only place a duplicate entry is still observable.
  let needle = "\"" & key & "\""
  var at = 0
  while true:
    let found = raw.find(needle, at)
    if found < 0:
      break
    var j = found + needle.len
    while j < raw.len and raw[j] in {' ', '\t', '\r', '\n'}:
      inc j
    if j < raw.len and raw[j] == ':':
      inc result
    at = found + needle.len

func ledgerPaths*(ledger: JsonNode): seq[string] =
  ## Deterministic key list of the ledger `paths` map.
  let paths = field(ledger, "paths")
  if paths.isNil or paths.kind != JObject:
    return @[]
  for k, _ in paths:
    result.add(k)

func validateLedger(ledger: JsonNode, raw: string): string =
  if ledger.isNil or ledger.kind != JObject:
    return "divergence ledger is not a JSON object"
  let paths = field(ledger, "paths")
  if paths.isNil or paths.kind != JObject:
    return "divergence ledger has no `paths` object"
  for key, value in paths:
    if key.contains('*') or key.contains('?'):
      return "divergence ledger entry is a wildcard, exact paths only: " & key
    if countObjectKeys(raw, key) > 1:
      return "divergence ledger entry is duplicated: " & key
    if not isLedgerValueValid(value):
      return "divergence ledger value needs non-empty `rationale` and " &
        "`trackedAs` strings: " & key
  ""

# ── verdict ───────────────────────────────────────────────────────────────────

proc evaluate*(manifestText, policyText, ledgerText: string): Verdict =
  ## Pure string→verdict evaluation. No filesystem access, so the tests can
  ## drive every branch with fixtures instead of editing config/**.
  var manifest: JsonNode
  var policy: JsonNode
  var ledger: JsonNode
  try:
    manifest = parseJson(manifestText)
  except CatchableError:
    return Verdict(exitCode: 2, lines: @["INPUT-ERROR unparsable trust-surface manifest"])
  try:
    policy = parseJson(policyText)
  except CatchableError:
    return Verdict(exitCode: 2, lines: @["INPUT-ERROR unparsable repository-surface policy"])
  try:
    ledger = parseJson(ledgerText)
  except CatchableError:
    return Verdict(exitCode: 2, lines: @["INPUT-ERROR unparsable divergence ledger"])

  for reason in [validateManifest(manifest), validatePolicy(policy)]:
    if reason.len > 0:
      return Verdict(exitCode: 2, lines: @["INPUT-ERROR " & reason])
  let ledgerReason = validateLedger(ledger, ledgerText)
  if ledgerReason.len > 0:
    return Verdict(exitCode: 2, lines: @["INPUT-ERROR " & ledgerReason])

  let registered = ledgerPaths(ledger)
  var manifestPaths: seq[string]
  for item in field(manifest, "paths").items:
    manifestPaths.add(item.getStr())
  manifestPaths.sort()

  var divergent: seq[string]
  var classifications: seq[Classification]
  var convergent = 0
  for path in manifestPaths:
    let c = classifyPath(policy, path)
    if c.cls == ConvergentClass:
      inc convergent
    else:
      divergent.add(path)
      classifications.add(c)

  var unregistered = 0
  var dead = 0
  for path in divergent:
    if path notin registered:
      inc unregistered
  for path in registered:
    if path notin divergent:
      inc dead

  for i in 0 ..< divergent.len:
    result.lines.add("DIVERGENCE " & divergent[i] & " class=" &
      classifications[i].cls & " pattern=" & classifications[i].pattern)
  var sortedRegistered = registered
  sortedRegistered.sort()
  for path in sortedRegistered:
    if path notin divergent:
      result.lines.add("DEAD " & path)
  result.lines.add("SUMMARY manifest=" & $manifestPaths.len &
    " convergent=" & $convergent &
    " divergent=" & $divergent.len &
    " registered=" & $(divergent.len - unregistered) &
    " unregistered=" & $unregistered &
    " dead=" & $dead)

  result.exitCode = if unregistered > 0 or dead > 0: 1 else: 0

proc readText(path: string): tuple[ok: bool, text: string] =
  if not fileExists(path):
    return (false, "")
  try:
    (true, readFile(path))
  except CatchableError:
    (false, "")

proc runPaths*(manifestPath, policyPath, ledgerPath: string): Verdict =
  ## Filesystem boundary: read the three inputs, then evaluate. A missing or
  ## unreadable file is exit 2 — never "no divergence".
  let m = readText(manifestPath)
  if not m.ok:
    return Verdict(exitCode: 2, lines: @["INPUT-ERROR trust-surface manifest missing or unreadable: " & manifestPath])
  let p = readText(policyPath)
  if not p.ok:
    return Verdict(exitCode: 2, lines: @["INPUT-ERROR repository-surface policy missing or unreadable: " & policyPath])
  let l = readText(ledgerPath)
  if not l.ok:
    return Verdict(exitCode: 2, lines: @["INPUT-ERROR divergence ledger missing or unreadable: " & ledgerPath])
  evaluate(m.text, p.text, l.text)

proc usage() =
  echo "usage: trust_surface_divergence [--manifest=<path>] [--policy=<path>] [--ledger=<path>]"
  echo ""
  echo "  --manifest  trust-surface manifest (default " & ManifestPath & ")"
  echo "  --policy    repository-surface policy (default " & PolicyPath & ")"
  echo "  --ledger    ratchet ledger (default " & LedgerPath & ")"
  echo ""
  echo "exit 0 = every divergence registered; 1 = unregistered divergence or dead"
  echo "ledger entry; 2 = input error (fail closed). A DETECTOR, not a gate."

proc main() =
  var manifestPath = ManifestPath
  var policyPath = PolicyPath
  var ledgerPath = LedgerPath
  let args = commandLineParams()
  var idx = 0
  while idx < args.len:
    let a = args[idx]
    var consumed = 1
    if a == "--help" or a == "-h":
      usage()
      quit(0)
    elif a == "--manifest":
      if idx + 1 >= args.len:
        echo "INPUT-ERROR --manifest requires a value"
        quit(2)
      manifestPath = args[idx + 1]
      consumed = 2
    elif a.startsWith("--manifest="):
      manifestPath = a["--manifest=".len .. ^1]
    elif a == "--policy":
      if idx + 1 >= args.len:
        echo "INPUT-ERROR --policy requires a value"
        quit(2)
      policyPath = args[idx + 1]
      consumed = 2
    elif a.startsWith("--policy="):
      policyPath = a["--policy=".len .. ^1]
    elif a == "--ledger":
      if idx + 1 >= args.len:
        echo "INPUT-ERROR --ledger requires a value"
        quit(2)
      ledgerPath = args[idx + 1]
      consumed = 2
    elif a.startsWith("--ledger="):
      ledgerPath = a["--ledger=".len .. ^1]
    else:
      echo "INPUT-ERROR unknown argument: " & a
      quit(2)
    idx += consumed

  let verdict = runPaths(manifestPath, policyPath, ledgerPath)
  for line in verdict.lines:
    echo line
  quit(verdict.exitCode)

when isMainModule:
  main()
