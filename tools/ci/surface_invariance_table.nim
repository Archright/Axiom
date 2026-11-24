## tools/ci/surface_invariance_table.nim — differential class table between two
## repository-surface policies.
##
## Prints, for a list of representative paths, the class each path resolves to
## under an OLD policy and a NEW policy, and labels every transition:
##
##   SAME        the resolved class did not change, OR it moved between
##               PRODUCT and CONTROLLED (those two classes carry an identical
##               rule row — ADD/MODIFY/DELETE all PASS — so the verdict is
##               unchanged and the movement is a declaration change only)
##   LOOSENED    the path moved FROM FROZEN to a non-FROZEN class
##   TIGHTENED   the path moved TO FROZEN from a non-FROZEN class
##
## The tool is an assertion, not a report: it exits non-zero when a transition
## violates the caller's declared intent.
##
##   --intent no-regression   FAIL on any LOOSENED transition.
##   --intent self-amendment  FAIL on any LOOSENED transition whose path the
##                            caller did not name with --allow-loosened, and
##                            FAIL when a named path did not actually loosen
##                            (a stale allowance is a lie about the change).
##
## TIGHTENED transitions are always reported and never fail: tightening cannot
## be a security regression, but it must stay visible.
##
## App trust-surface manifest (`--manifest`): reports, for every member of
## `config/policy/trust_surface_manifest.json`, the class it resolves to under
## the NEW policy. Drift is reported unconditionally and only FAILS the run
## with `--require-manifest-frozen`. The reason it is opt-in: the shipped
## policy already resolves 8 of the 18 members to CONTROLLED (v105–v108
## narrowed those exact paths, on the recorded ground that the App blob-
## equality lock is the binding control and the surface FROZEN entry was a
## redundant second lock). Making FROZEN-agreement a default assertion would
## therefore mean asserting something the committed policy deliberately does
## not hold — a claim, not a check.
##
## Usage:
##   surface_invariance_table --old <old.json> --new <new.json> \
##     --paths <path-list.txt> [--manifest <manifest.json>] \
##     [--intent no-regression|self-amendment] \
##     [--allow-loosened <path>]... [--require-manifest-frozen]
##
## `--paths` takes one path per line; blank lines and lines whose first
## non-space character is '#' are skipped. Use the same list for the before and
## after runs so the tables are comparable.
##
## Exit codes: 0 = every asserted invariant held · 1 = an invariant failed ·
## 2 = usage/load error (no evaluation happened).
##
## Determinism: the output is a pure function of the input files plus the set of
## --allow-loosened values (argument order normalised away). No timestamps, no
## environment, no network, no writes.

import std/[json, os, strutils]

# Effect-marker pragma, declared locally like every other tool in this tree
# (tools/ci/trusted_writer_set_gate.nim:50, tools/hermetic_build.nim:59) —
# `axiomEffect` is a review-time marker, not a compiler builtin.
template axiomEffect*(e: untyped) {.pragma.}
type IoEffect* = object

import ../../tools/surface_guard

const
  ToolName* = "surface_invariance_table"
  ## Class ladder, weakest first: a path moving to a later entry is tightened,
  ## a path moving to an earlier entry is loosened.
  ClassLadder*: array[3, string] = ["PRODUCT", "CONTROLLED", "FROZEN"]

type
  TransitionKind* = enum
    tkSame = "SAME"
    tkLoosened = "LOOSENED"
    tkTightened = "TIGHTENED"

  Row* = object
    path*: string
    oldClass*: string
    newClass*: string
    kind*: TransitionKind

func rankOf*(cls: string): int {.raises: [].} =
  ## Position on the class ladder, -1 when `cls` is outside the vocabulary.
  for i, c in ClassLadder:
    if c == cls:
      return i
  -1

func classifyTransition*(oldClass, newClass: string): TransitionKind {.raises: [].} =
  ## Pure: direction of movement on the PRODUCT < CONTROLLED < FROZEN ladder.
  ## Only FROZEN participates in the security judgment — PRODUCT and CONTROLLED
  ## carry an identical rule row in the shipped rule table, so a move between
  ## them leaves every verdict unchanged.
  if oldClass == newClass:
    return tkSame
  if oldClass == "FROZEN":
    return tkLoosened
  if newClass == "FROZEN":
    return tkTightened
  tkSame

func padRight(s: string, n: int): string {.raises: [].} =
  if s.len >= n: s else: s & repeat(' ', n - s.len)

proc parsePathList*(text: string): seq[string] {.raises: [].} =
  ## Pure: one path per line; blank lines and '#' comments skipped.
  for raw in text.splitLines():
    let line = raw.strip()
    if line.len == 0 or line[0] == '#':
      continue
    result.add(line)

proc rowsFor*(oldP, newP: JsonNode, paths: seq[string]): seq[Row] {.raises: [].} =
  ## Pure: the differential table.
  for p in paths:
    let a = resolveClass(oldP, p)
    let b = resolveClass(newP, p)
    result.add(Row(path: p, oldClass: a, newClass: b,
                   kind: classifyTransition(a, b)))

proc structuralError*(policy: JsonNode, label, path: string): string {.raises: [CatchableError].} =
  ## isValidPolicy is not exported by the guard, so validity is observed through
  ## its public surface: a structurally invalid policy makes classify() report
  ## POLICY_INVALID. Re-implementing the validator here would create a second
  ## copy of the same semantic state.
  let verdict = classify(policy, @[])
  let rc = verdict{"reasonCode"}
  if not rc.isNil and rc.kind == JString and rc.getStr() == "POLICY_INVALID":
    return label & " policy is structurally invalid (POLICY_INVALID): " & path
  ""

proc readTextFile(path: string, label: string): tuple[ok: bool, text: string] {.
    axiomEffect: IoEffect, raises: [].} =
  if not fileExists(path):
    return (false, "")
  try:
    (true, readFile(path))
  except CatchableError:
    (false, "")

proc loadPolicyOrQuit(path, label: string): JsonNode {.
    axiomEffect: IoEffect, raises: [CatchableError].} =
  let loaded = loadPolicy(path)
  if not loaded.ok:
    stderr.writeLine(ToolName & ": cannot read " & label & " policy file: " & path)
    quit(2)
  if loaded.invalidContent:
    stderr.writeLine(ToolName & ": unparsable " & label & " policy JSON: " & path)
    quit(2)
  loaded.node

proc main() {.axiomEffect: IoEffect, raises: [CatchableError].} =
  proc usage() {.raises: [CatchableError].} =
    stderr.writeLine(ToolName & " --old <old.json> --new <new.json> --paths <list.txt>")
    stderr.writeLine("  [--manifest <trust_surface_manifest.json>] [--require-manifest-frozen]")
    stderr.writeLine("  [--intent no-regression|self-amendment] [--allow-loosened <path>]...")
    quit(2)

  var oldPath = ""
  var newPath = ""
  var listPath = ""
  var manifestPath = ""
  var intent = "no-regression"
  var requireManifestFrozen = false
  var allowLoosened: seq[string] = @[]
  let args = commandLineParams()
  var i = 0
  while i < args.len:
    case args[i]
    of "--old":
      if i + 1 >= args.len: usage()
      oldPath = args[i + 1]
      inc i
    of "--new":
      if i + 1 >= args.len: usage()
      newPath = args[i + 1]
      inc i
    of "--paths":
      if i + 1 >= args.len: usage()
      listPath = args[i + 1]
      inc i
    of "--manifest":
      if i + 1 >= args.len: usage()
      manifestPath = args[i + 1]
      inc i
    of "--intent":
      if i + 1 >= args.len: usage()
      intent = args[i + 1]
      inc i
    of "--allow-loosened":
      if i + 1 >= args.len: usage()
      allowLoosened.add(args[i + 1])
      inc i
    of "--require-manifest-frozen":
      requireManifestFrozen = true
    else:
      usage()
    inc i
  if oldPath == "" or newPath == "" or listPath == "":
    usage()
  if intent notin ["no-regression", "self-amendment"]:
    stderr.writeLine(ToolName & ": unknown --intent: " & intent)
    quit(2)

  let oldP = loadPolicyOrQuit(oldPath, "old")
  let newP = loadPolicyOrQuit(newPath, "new")
  let bad = structuralError(oldP, "old", oldPath) &
            structuralError(newP, "new", newPath)
  if bad.len > 0:
    stderr.writeLine(ToolName & ": " & bad)
    quit(1)

  let listText = readTextFile(listPath, "path list")
  if not listText.ok:
    stderr.writeLine(ToolName & ": cannot read path list: " & listPath)
    quit(2)
  let paths = parsePathList(listText.text)
  if paths.len == 0:
    stderr.writeLine(ToolName & ": path list is empty: " & listPath)
    quit(2)

  let rows = rowsFor(oldP, newP, paths)

  echo padRight("path", 64) & padRight("old", 12) & padRight("new", 12) & "transition"
  echo repeat('-', 64) & repeat('-', 12) & repeat('-', 12) & "----------"
  for r in rows:
    echo padRight(r.path, 64) & padRight(r.oldClass, 12) &
         padRight(r.newClass, 12) & $r.kind
  echo ""

  var failures: seq[string] = @[]
  var loosened: seq[string] = @[]
  var tightened: seq[string] = @[]
  for r in rows:
    case r.kind
    of tkLoosened: loosened.add(r.path)
    of tkTightened: tightened.add(r.path)
    of tkSame: discard

  echo "old policyVersion = " & $oldP["policyVersion"].getInt()
  echo "new policyVersion = " & $newP["policyVersion"].getInt()
  echo "paths evaluated   = " & $rows.len
  echo "same              = " & $(rows.len - loosened.len - tightened.len)
  echo "tightened         = " & $tightened.len
  for p in tightened:
    echo "  + " & p
  echo "loosened          = " & $loosened.len
  for p in loosened:
    echo "  - " & p

  case intent
  of "no-regression":
    for p in loosened:
      failures.add("LOOSENED transition is a security regression: " & p)
  of "self-amendment":
    for p in loosened:
      if p notin allowLoosened:
        failures.add("LOOSENED transition outside the declared amendment scope: " & p)
    for p in allowLoosened:
      if p notin loosened:
        failures.add("declared amendment path did not loosen: " & p)
  else:
    discard

  echo ""
  if manifestPath == "":
    echo "manifest members checked = UNKNOWN (--manifest not supplied)"
  else:
    let mt = readTextFile(manifestPath, "manifest")
    if not mt.ok:
      stderr.writeLine(ToolName & ": cannot read manifest: " & manifestPath)
      quit(2)
    var manifest: JsonNode = nil
    try:
      manifest = parseJson(mt.text)
    except JsonParsingError:
      stderr.writeLine(ToolName & ": unparsable manifest JSON: " & manifestPath)
      quit(2)
    let listed = manifest{"paths"}
    if listed.isNil or listed.kind != JArray:
      stderr.writeLine(ToolName & ": manifest has no array 'paths': " & manifestPath)
      quit(2)
    var members = 0
    var drifted: seq[string] = @[]
    for item in listed.items:
      if item.kind != JString:
        stderr.writeLine(ToolName & ": manifest 'paths' carries a non-string entry")
        quit(2)
      inc members
      let p = item.getStr()
      let cls = resolveClass(newP, p)
      if cls != "FROZEN":
        drifted.add(p & " -> " & cls)
    echo "manifest members checked = " & $members
    if drifted.len == 0:
      echo "manifest drift           = none (every member resolves FROZEN)"
    else:
      echo "manifest drift           = " & $drifted.len & " member(s) resolve non-FROZEN"
      for d in drifted:
        echo "  ! " & d
      if requireManifestFrozen:
        for d in drifted:
          failures.add("App trust-surface member is not FROZEN: " & d)
      else:
        echo "  (reported only — pass --require-manifest-frozen to assert)"

  echo ""
  if failures.len == 0:
    echo "verdict = PASS (intent: " & intent & ")"
    quit(0)
  echo "verdict = FAIL (intent: " & intent & ")"
  for f in failures:
    echo "  - " & f
  quit(1)

when isMainModule:
  main()
