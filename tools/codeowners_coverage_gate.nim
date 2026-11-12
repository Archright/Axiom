## tools/codeowners_coverage_gate.nim — mechanical CODEOWNERS coverage gate
## for the auto-merge trust surface.
##
## PASS/FAIL decisions are computed by pure functions — never by manual
## comparison. The gate answers, for every trust-surface path:
##   1. does some .github/CODEOWNERS pattern cover it?
##   2. does EVERY covering rule's owner column include @Archright/architect?
##   3. is .github/CODEOWNERS itself part of the target set (self-protection)?
##
## Target set (union, deduplicated, fixed order):
##   (a) config/policy/merge_admission.json `trustSurface` array (JSON) —
##       the runtime SSOT since the trust-surface single-sourcing
##       (docs/evidence/trustsurface_ssot_alignment_2026-10-14.md): the CLI
##       evaluates classification from this file at evaluation time, so the
##       gate audits exactly what the runtime consumes.
##   (b) the `TrustSurfaceTombstones` const in src/cli/merge_cli.nim — parsed
##       TEXTUALLY (regex over the source; the module is deliberately NOT
##       imported, so this gate stays compile-decoupled from a
##       concurrently-edited file). These protection-retention entries
##       (e.g. .github/workflows/auto_merge.yml) are unioned into the runtime
##       surface by loadTrustSurface, so the gate includes them by
##       construction. The former compiled LIVE-surface const was removed
##       with the single-sourcing (it had drifted from the policy — 2026-10-14
##       06:47 arbitrary deny, run 38524327637); this gate fail-closes on the
##       tombstone declaration so a resurrected live-surface copy is caught.
##   (c) fixed additions: AGENTS.md, .github/CODEOWNERS.
##
## STATUS (2026-09-30): advisory coverage audit — defense-in-depth
## INFORMATION, not a merge gate. Platform code-owner review enforcement
## (ruleset require_code_owner_review) was REJECTED for this org: it has
## exactly one human (author = sole architect), so any required review
## would be a self-approval deadlock. Trust-surface PRs require a human
## manual merge (adopted policy 2026-09-30, "Axiom-controlled auto-land
## exclusion"; the in-CLI arm-auto lane was removed — GitHub ruleset +
## required status check is the sole enforcement authority).
## This gate therefore remains to verify, for information, that every
## trust-surface path is covered by an @Archright/architect-owned
## CODEOWNERS rule — code ownership of the trust surface stays explicit
## even though platform review enforcement does not exist.
##
## CODEOWNERS semantics implemented:
##   - patterns are anchored at the repo root (a leading '/' is the anchor);
##   - a trailing '/' is a directory prefix (covers the dir and everything
##     beneath it);
##   - '/**' covers the prefix directory and everything beneath it (mirrors
##     pathMatchesGlob in src/cli/merge_cli.nim:313-324);
##   - a '*' matches an arbitrary run of characters within a single path
##     segment — it never crosses '/' (segment DP, mirrors
##     tools/surface_guard.nim segMatch);
##   - a plain pattern matches the exact path and anything beneath it.
##
## Fail-closed: any source file that cannot be read, any missing trust-surface
## field/declaration, or an empty target set produces FAIL (exit 1). A PASS is
## only ever the result of every target passing both judgments.
##
## CLI:
##   nim c -r tools/codeowners_coverage_gate.nim [--root <repo-root>]
## Output: one [PASS]/[FAIL] line per target, then the verdict line.
## Exit codes: 0 = PASS, 1 = FAIL (uncoverable/wrong-owner/load error).

import std/[json, os, re, sequtils, strutils]
import api/tools_facade

# ---------------------------------------------------------------------------
# Pure core
# ---------------------------------------------------------------------------

type
  OwnerRule* = object
    ## One parsed CODEOWNERS rule: normalized pattern + owner tokens.
    pattern*: string
    owners*: seq[string]

  CoverageVerdict* = object
    pass*: bool
    checked*: int
    problems*: seq[string]  ## one entry per failing target, deterministic order
    details*: seq[string]   ## per-target [PASS]/[FAIL] lines, deterministic order

const
  ## Fixed additions to the trust surface: the repo-wide governance
  ## instructions and the CODEOWNERS file itself (self-protection).
  FixedTargets* = ["AGENTS.md", ".github/CODEOWNERS"]
  ## Owner column requirement: every covering rule must list the architect
  ## team (case-insensitive; GitHub folds team refs in practice).
  RequiredOwner* = "@Archright/architect"

let
  ## Compiled once at module load (re() raises RegexError; a raising
  ## constructor would violate the {.raises: [].} contract of the pure funcs).
  ## Locates `TrustSurfaceTombstones*: seq[string] = @[` in src/cli/merge_cli.nim.
  TrustSurfaceDeclRe = re(r"TrustSurfaceTombstones\*?\s*:\s*seq\[string\]\s*=\s*@\[")
  ## One double-quoted string literal, with backslash escapes tolerated.
  QuotedStringRe = re(""""((?:[^"\\]|\\.)*)"""")

func parseCodeowners*(text: string): seq[OwnerRule] {.raises: [].} =
  ## Pure: parse CODEOWNERS text into rules. Blank lines and full-line `#`
  ## comments are skipped; an inline `#` token terminates the owner list.
  ## Lines with a pattern but no owner token are ignored (GitHub treats such
  ## invalid rules as nonexistent, so coverage over them is UNCOVERED —
  ## fail-closed either way). Owners are kept verbatim (trimmed).
  for rawLine in text.splitLines():
    let line = rawLine.strip()
    if line.len == 0 or line[0] == '#':
      continue
    let tokens = line.splitWhitespace()
    if tokens.len < 2:
      continue
    var owners: seq[string] = @[]
    for t in tokens[1 .. ^1]:
      if t.startsWith("#"):
        break
      owners.add(t)
    result.add(OwnerRule(pattern: tokens[0], owners: owners))

func segMatchStar(pat, seg: string): bool {.raises: [].} =
  ## '*' matches an arbitrary run of characters within one segment
  ## (classic wildcard DP; mirrors tools/surface_guard.nim segMatch).
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

func codeownersPatternMatches*(pattern, path: string): bool {.raises: [].} =
  ## Pure: CODEOWNERS pattern vs path, mirroring pathMatchesGlob
  ## (src/cli/merge_cli.nim:313-324) plus the trailing-'/' directory-prefix
  ## semantics. A leading '/' is the root anchor and is stripped.
  let p = path.replace("\\", "/")
  var pat = pattern.replace("\\", "/")
  if pat.startsWith("/"):
    pat = pat[1 .. ^1]
  if pat.endsWith("/"):
    let dir = pat[0 .. ^2]
    return p == dir or p.startsWith(dir & "/")
  if pat.endsWith("/**"):
    let prefix = pat[0 .. ^4]
    return p == prefix or p.startsWith(prefix & "/")
  if pat.contains('*'):
    # '*' matches within a single path segment — it never crosses '/'
    # (segment-wise DP; '**' was already handled above). Segment counts
    # must agree; a star segment cannot match a slash.
    let ps = pat.split('/')
    let xs = path.split('/')
    if ps.len != xs.len:
      return false
    for i in 0 ..< ps.len:
      if not segMatchStar(ps[i], xs[i]):
        return false
    return true
  p == pat or p.startsWith(pat & "/")

func coveringRules*(rules: seq[OwnerRule]; path: string): seq[OwnerRule] {.raises: [].} =
  ## Pure: every rule whose pattern covers `path`.
  for r in rules:
    if codeownersPatternMatches(r.pattern, path):
      result.add(r)

func ownersInclude*(rule: OwnerRule; owner: string): bool {.raises: [].} =
  ## Pure: is `owner` listed in the rule's owner column? Case-insensitive
  ## trimmed token comparison.
  let want = owner.toLowerAscii()
  for o in rule.owners:
    if o.strip().toLowerAscii() == want:
      return true
  false

proc extractTrustSurfaceTombstones*(source: string): seq[string] {.raises: [].} =
  ## Textually extract the string literals of the
  ## `TrustSurfaceTombstones*: seq[string] = @[...]` array literal from
  ## src/cli/merge_cli.nim. The module is never imported (compile-decoupled);
  ## the declaration is located by regex and the array body is scanned for
  ## quoted strings. Missing declaration or unbalanced array -> empty
  ## (caller fails closed). The LIVE trust-surface paths are NOT extracted —
  ## since the policy-SSOT single-sourcing they exist only in
  ## config/policy/merge_admission.json (source (a) in main()); a compiled
  ## live-surface copy here would re-create the 2026-10-14 drift incident.
  ## NOTE: declared as proc (not func) because the PCRE-backed std/re
  ##   find/findAll bindings are flagged side-effecting by the compiler;
  ##   the function is logically pure (no observable state change).
  let start = source.find(TrustSurfaceDeclRe)
  if start < 0:
    return @[]
  let arrStart = source.find("@[", start)
  if arrStart < 0:
    return @[]
  var depth = 0
  var arrEnd = -1
  var i = arrStart + 1
  while i < source.len:
    let c = source[i]
    if c == '[':
      inc depth
    elif c == ']':
      dec depth
      if depth == 0:
        arrEnd = i
        break
    inc i
  if arrEnd < 0:
    return @[]
  try:
    for m in findAll(source[arrStart + 1 ..< arrEnd], QuotedStringRe):
      if m.len >= 2:
        # strip the surrounding quotes and process backslash escapes
        # (unescape's default prefix/suffix are quotes — the quotes are
        # already stripped by the slice, so pass empty delimiters)
        result.add(unescape(m[1 .. ^2], "", ""))
  except ValueError:
    # a malformed escape in the const: fail closed (caller reports FAIL)
    return @[]

func jsonTrustSurface*(node: JsonNode): tuple[entries: seq[string]; ok: bool] {.raises: [].} =
  ## Pure: read the `trustSurface` array from config/policy/
  ## merge_admission.json. Missing field, non-array, or non-string entries
  ## -> ok=false (fail closed).
  if node.isNil or node.kind != JObject:
    return (@[], false)
  for k, v in node:
    if k == "trustSurface":
      if v.kind != JArray:
        return (@[], false)
      var entries: seq[string] = @[]
      for e in v.items:
        if e.kind != JString:
          return (@[], false)
        entries.add(e.getStr())
      return (entries, true)
  (@[], false)

func buildTargetSet*(jsonEntries, constEntries: seq[string]): seq[string] {.raises: [].} =
  ## Pure: union of both trust-surface sources plus the fixed additions,
  ## deduplicated, order-preserving (JSON entries first, then const entries,
  ## then the fixed additions).
  for e in jsonEntries:
    if e notin result:
      result.add(e)
  for e in constEntries:
    if e notin result:
      result.add(e)
  for e in FixedTargets:
    if e notin result:
      result.add(e)

func assessCoverage*(rules: seq[OwnerRule]; targets: seq[string];
                     requiredOwner = RequiredOwner): CoverageVerdict {.raises: [].} =
  ## Pure: PASS iff every target is covered by >=1 rule AND every covering
  ## rule's owner column includes requiredOwner. Deterministic: targets are
  ## judged in the order given; problems/details are appended in that order.
  result.pass = true
  result.checked = targets.len
  for t in targets:
    let covering = coveringRules(rules, t)
    if covering.len == 0:
      result.pass = false
      result.problems.add("UNCOVERED " & t)
      result.details.add("[FAIL] " & t & ": UNCOVERED — no CODEOWNERS pattern matches")
      continue
    var bad: seq[string] = @[]
    for r in covering:
      if not ownersInclude(r, requiredOwner):
        bad.add(r.pattern & " -> {" & r.owners.join(", ") & "}")
    if bad.len > 0:
      result.pass = false
      result.problems.add("WRONG_OWNER " & t & " (" & bad.join("; ") & ")")
      result.details.add("[FAIL] " & t & ": WRONG_OWNER — covering rule(s) " &
        bad.join("; ") & " miss " & requiredOwner)
    else:
      let pats = covering.mapIt(it.pattern).join(", ")
      result.details.add("[PASS] " & t & ": covered by " & pats)

# ---------------------------------------------------------------------------
# IO boundary
# ---------------------------------------------------------------------------

proc readRootFile*(root, rel: string): tuple[ok: bool; exists: bool; text: string] {.axiomEffect: IoEffect.} =
  ## IO: read a file relative to the .axiom_root-identified root.
  ## ok=false + exists=false -> file missing; ok=false + exists=true -> read
  ## error. Both fail closed in main().
  let path = root / rel
  if not fileExists(path):
    return (false, false, "")
  try:
    (true, true, readFile(path))
  except CatchableError:
    (false, true, "")

proc findRepoRoot(startDir: string): string {.axiomEffect: IoEffect.} =
  ## IO: walk up from `startDir` until `.axiom_root` is found (max 10 levels).
  var dir = startDir
  for _ in 0 ..< 10:
    if fileExists(dir / ".axiom_root"):
      return dir
    let parent = dir.parentDir()
    if parent == dir:
      break
    dir = parent
  ""

proc main() {.axiomEffect: IoEffect.} =
  var root = findRepoRoot(currentSourcePath().parentDir())
  let args = commandLineParams()
  var i = 0
  while i < args.len:
    if args[i] == "--root" and i + 1 < args.len:
      root = args[i + 1]
      inc i
    else:
      stderr.writeLine("codeowners_coverage_gate: unknown argument: " & args[i])
      stderr.writeLine("usage: codeowners_coverage_gate [--root <repo-root>]")
      quit(1)
    inc i
  if root.len == 0:
    stderr.writeLine("codeowners_coverage_gate: FAIL — cannot locate the .axiom_root anchor")
    quit(1)

  let co = readRootFile(root, ".github/CODEOWNERS")
  let mp = readRootFile(root, "config/policy/merge_admission.json")
  let mc = readRootFile(root, "src/cli/merge_cli.nim")
  if not co.ok:
    stderr.writeLine("codeowners_coverage_gate: FAIL — .github/CODEOWNERS " &
      (if co.exists: "unreadable" else: "missing") & " under " & root)
    quit(1)
  if not mp.ok:
    stderr.writeLine("codeowners_coverage_gate: FAIL — config/policy/merge_admission.json " &
      (if mp.exists: "unreadable" else: "missing") & " under " & root)
    quit(1)
  if not mc.ok:
    stderr.writeLine("codeowners_coverage_gate: FAIL — src/cli/merge_cli.nim " &
      (if mc.exists: "unreadable" else: "missing") & " under " & root)
    quit(1)

  var policyOk = true
  var jsonEntries: seq[string] = @[]
  try:
    let (entries, ok) = jsonTrustSurface(parseJson(mp.text))
    policyOk = ok
    jsonEntries = entries
  except JsonParsingError:
    policyOk = false
  if not policyOk:
    stderr.writeLine("codeowners_coverage_gate: FAIL — merge_admission.json has no valid trustSurface array")
    quit(1)

  let constEntries = extractTrustSurfaceTombstones(mc.text)
  if constEntries.len == 0:
    stderr.writeLine("codeowners_coverage_gate: FAIL — TrustSurfaceTombstones const not found in src/cli/merge_cli.nim")
    quit(1)

  let rules = parseCodeowners(co.text)
  let targets = buildTargetSet(jsonEntries, constEntries)
  if targets.len == 0:
    stderr.writeLine("codeowners_coverage_gate: FAIL — empty target set (vacuous pass forbidden)")
    quit(1)

  echo "codeowners_coverage_gate: " & $targets.len & " target path(s) vs " &
    $rules.len & " CODEOWNERS rule(s), required owner " & RequiredOwner
  let verdict = assessCoverage(rules, targets)
  for d in verdict.details:
    echo "  " & d
  if verdict.pass:
    echo "verdict: PASS — " & $verdict.checked & "/" & $verdict.checked &
      " targets covered; every covering rule includes " & RequiredOwner
    quit(0)
  else:
    echo "verdict: FAIL — " & $verdict.problems.len & " problem(s):"
    for p in verdict.problems:
      echo "  " & p
    quit(1)

when isMainModule:
  main()