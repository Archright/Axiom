## preflight_script_scan.nim — local preflight for the publication-integrity
## `script-scan` dimension (issue #422).
##
## WHY THIS EXISTS
## `tools/ci/publication_script_eval.nim` judges ADDED LINES only, but a line
## that merely CONTAINS pre-existing non-ASCII text becomes an "added line" the
## moment it is touched. Editing an unrelated part of such a line (even one
## trailing space) re-judges all of its text and turns baseline prose into a
## fresh violation. The failure is only visible in the merge_group run, i.e.
## after a full merge-group cycle. This tool runs the same judgement locally,
## against the same base, in seconds.
##
## FAITHFULNESS CONTRACT
## The verdict is meant to be the evaluator's verdict, not an approximation:
##   - same base resolution and ancestry/merge-base equality checks;
##   - same `git diff` invocation (byte-identical diff text);
##   - same diff parser (added lines only; removed lines are discarded);
##   - same path exemptions, binary/submodule/rename/quoted-path judgements;
##   - same ripgrep invocation and pin, same code-point classification;
##   - same violation dedupe key (path:line:codePoint);
##   - same fail-closed UNKNOWN set (UNKNOWN blocks, it is never a pass).
##
## KNOWN DIVERGENCES (all deliberate, none can turn a CI FAIL into a PASS):
##   1. The base comes from the caller. CI passes merge_group.base_sha (or
##      HEAD~1 off the merge queue); this tool defaults to
##      merge-base(origin/main, HEAD), which is the diff the merge-queue base
##      produces for a single-PR group, and validates an explicit --base with
##      the evaluator's own ancestry + merge-base-equality rules.
##   2. --head accepts any rev; the evaluator requires a 40-hex sha. The ref is
##      resolved to a commit first, so the diffed object is the same.
##   3. --assume-tools-ok is opt-in and relaxes only the ripgrep/git pins, to
##      warnings. It cannot relax the data UNKNOWNs (invalid UTF-8, quoted
##      paths, submodules, binary documents, bad base).
##   4. Display only: the excerpt around a violation shows the first occurrence
##      of that code point on the line, not necessarily the matched offset, and
##      the "pre-existing on base" hint is computed by looking for the same
##      code point in the base blob of that path.
##
## Verdicts: PASS / FAIL / UNKNOWN. Exit: 0 / 1 / 2.
##
## Read-only with respect to the repository: it shells out to git and ripgrep
## and writes nothing except an optional --json report.

import std/[json, options, os, osproc, parseopt, sets, strutils, tables, unicode]
import core/trusted/layer_declaration
import core/crypto/hash_kernel
import core/results
import tools/ci/publication_yaml

axiomLayer "tools"

const
  ToolName = "preflight_script_scan"
  ExitPass = 0
  ExitFail = 1
  ExitUnknown = 2
  DefaultPolicy = "compliance/policy/script-scan-policy.yml"
  AllowedScriptNames = ["Latin", "Greek", "Common", "Inherited"]
  MaxDetailChars = 400
  ExcerptRadius = 28

# ---------------------------------------------------------------------------
# Inputs
# ---------------------------------------------------------------------------

type
  Inputs = object
    policyPath: string
    rgPath: string
    headRev: string
    baseRev: string
    mainRef: string
    repoRoot: string
    jsonPath: string
    assumeToolsOk: bool

proc parseArgs(): Inputs =
  result = Inputs(policyPath: DefaultPolicy, repoRoot: ".", mainRef: "origin/main",
                  headRev: "HEAD", rgPath: "")
  var p = initOptParser(commandLineParams())
  while true:
    p.next()
    case p.kind
    of cmdEnd:
      break
    of cmdLongOption, cmdShortOption:
      let key = p.key
      case key
      of "assume-tools-ok":
        result.assumeToolsOk = true
      of "help", "h":
        echo """preflight_script_scan — predict the publication-integrity script-scan verdict

Usage:
  preflight_script_scan [--base <rev>] [--head <rev>] [--policy <path>]
                        [--rg <path>] [--repo-root <dir>] [--json <path>]
                        [--main-ref <ref>] [--assume-tools-ok]

  --base <rev>      Base for <base>..<head>. Validated exactly like the gate:
                    must resolve to a commit, be an ancestor of --head, and be
                    its own merge-base with --head (else UNKNOWN, as in CI).
  --head <rev>      Default HEAD. Anything git rev-parse can resolve.
  --main-ref <ref>  Used only when --base is absent: the base becomes
                    merge-base(<main-ref>, <head>). Default origin/main.
  --policy <path>   Default compliance/policy/script-scan-policy.yml.
  --rg <path>       Default: first ripgrep found (PATH, ~/.local/bin, /usr/bin).
  --json <path>     Optional machine-readable report.
  --assume-tools-ok Relax tool-contract UNKNOWNs (ripgrep version, git floor)
                    to warnings. DIVERGENT MODE: the CI verdict may differ.

Verdicts: PASS / FAIL / UNKNOWN. Exit: 0 / 1 / 2.

The gate's own base (what CI passes):
  merge_group      -> github.event.merge_group.base_sha
                      (.github/workflows/publication-integrity.yml:650,690)
  other venues     -> git rev-parse HEAD~1 (same file, 691-693)
  evaluator default (--base omitted, never used by CI):
                      policy.baselineCommit
                      (tools/ci/publication_script_eval.nim:333-334)
The diff itself is always `git diff <base>..<head>` with the evaluator's exact
flags (tools/ci/publication_script_eval.nim:589-595).
"""
        quit(ExitPass)
      else:
        var val = p.val
        if val.len == 0:
          p.next()
          if p.kind != cmdArgument:
            echo ToolName & " INPUT ERROR: option '--" & key & "' requires a value"
            quit(ExitUnknown)
          val = p.key
        case key
        of "policy": result.policyPath = val
        of "rg": result.rgPath = val
        of "head": result.headRev = val
        of "base": result.baseRev = val
        of "main-ref": result.mainRef = val
        of "repo-root": result.repoRoot = val
        of "json": result.jsonPath = val
        else:
          echo ToolName & " INPUT ERROR: unknown option '--" & key & "'"
          quit(ExitUnknown)
    of cmdArgument:
      echo ToolName & " INPUT ERROR: unexpected argument '" & p.key & "'"
      quit(ExitUnknown)

proc detectRg(): string =
  let exe = findExe("rg")
  if exe.len > 0: return exe
  let home = getEnv("HOME")
  for cand in [home / ".local" / "bin" / "rg", "/usr/bin/rg", "/usr/local/bin/rg"]:
    if cand.len > 3 and fileExists(cand): return cand
  ""

# ---------------------------------------------------------------------------
# Small helpers (mirrors the evaluator)
# ---------------------------------------------------------------------------

type
  RunResult = tuple[output: string, exitCode: int]

proc runShell(cmd: string): RunResult =
  try:
    let outp = execCmdEx(cmd)
    (outp.output, outp.exitCode)
  except CatchableError:
    ("", 129)

proc isHexSha*(s: string): bool =
  if s.len != 40: return false
  for c in s:
    if c notin {'0'..'9', 'a'..'f', 'A'..'F'}: return false
  true

proc detail(s: string): string =
  if s.len <= MaxDetailChars: s
  else: s[0 ..< MaxDetailChars] & "…"

proc parseSemver(s: string): tuple[major, minor, patch: int] =
  var parts: seq[int] = @[]
  var cur = ""
  for ch in s:
    if ch in {'0'..'9'}:
      cur.add(ch)
    elif ch == '.':
      if cur.len > 0:
        try: parts.add(parseInt(cur))
        except ValueError: return (-1, -1, -1)
        cur = ""
      if parts.len == 3: break
    elif parts.len > 0:
      break
  if cur.len > 0 and parts.len < 3:
    try: parts.add(parseInt(cur))
    except ValueError: return (-1, -1, -1)
  if parts.len >= 3: (parts[0], parts[1], parts[2])
  else: (-1, -1, -1)

proc semverAtLeast*(actual, minimum: string): bool =
  let a = parseSemver(actual)
  let m = parseSemver(minimum)
  if a.major < 0 or m.major < 0: return false
  if a.major != m.major: return a.major > m.major
  if a.minor != m.minor: return a.minor > m.minor
  a.patch >= m.patch

proc isValidUtf8*(s: string): bool =
  ## Strict UTF-8 validator, identical to the evaluator's (overlong, surrogate
  ## and >U+10FFFF rejected).
  var i = 0
  while i < s.len:
    let b = uint8(s[i])
    if b < 0x80'u8:
      inc i
    elif b >= 0xC2'u8 and b <= 0xDF'u8:
      if i + 1 >= s.len: return false
      if (uint8(s[i+1]) and 0xC0'u8) != 0x80'u8: return false
      i += 2
    elif b == 0xE0'u8:
      if i + 2 >= s.len: return false
      if uint8(s[i+1]) < 0xA0'u8 or uint8(s[i+1]) > 0xBF'u8: return false
      if (uint8(s[i+2]) and 0xC0'u8) != 0x80'u8: return false
      i += 3
    elif b >= 0xE1'u8 and b <= 0xEC'u8:
      if i + 2 >= s.len: return false
      if (uint8(s[i+1]) and 0xC0'u8) != 0x80'u8: return false
      if (uint8(s[i+2]) and 0xC0'u8) != 0x80'u8: return false
      i += 3
    elif b == 0xED'u8:
      if i + 2 >= s.len: return false
      if uint8(s[i+1]) < 0x80'u8 or uint8(s[i+1]) > 0x9F'u8: return false
      if (uint8(s[i+2]) and 0xC0'u8) != 0x80'u8: return false
      i += 3
    elif b >= 0xEE'u8 and b <= 0xEF'u8:
      if i + 2 >= s.len: return false
      if (uint8(s[i+1]) and 0xC0'u8) != 0x80'u8: return false
      if (uint8(s[i+2]) and 0xC0'u8) != 0x80'u8: return false
      i += 3
    elif b == 0xF0'u8:
      if i + 3 >= s.len: return false
      if uint8(s[i+1]) < 0x90'u8 or uint8(s[i+1]) > 0xBF'u8: return false
      if (uint8(s[i+2]) and 0xC0'u8) != 0x80'u8: return false
      if (uint8(s[i+3]) and 0xC0'u8) != 0x80'u8: return false
      i += 4
    elif b >= 0xF1'u8 and b <= 0xF3'u8:
      if i + 3 >= s.len: return false
      if (uint8(s[i+1]) and 0xC0'u8) != 0x80'u8: return false
      if (uint8(s[i+2]) and 0xC0'u8) != 0x80'u8: return false
      if (uint8(s[i+3]) and 0xC0'u8) != 0x80'u8: return false
      i += 4
    elif b == 0xF4'u8:
      if i + 3 >= s.len: return false
      if uint8(s[i+1]) < 0x80'u8 or uint8(s[i+1]) > 0x8F'u8: return false
      if (uint8(s[i+2]) and 0xC0'u8) != 0x80'u8: return false
      if (uint8(s[i+3]) and 0xC0'u8) != 0x80'u8: return false
      i += 4
    else:
      return false
  true

proc isQuotedOrAmbiguous*(p: string): bool =
  if p.len == 0: return false
  if p[0] == '"' or p.contains('"') or p.contains('\\'): return true
  if p.contains(' ') or p.contains('\t'): return true
  false

proc extensionOf(path: string): string =
  let ext = splitFile(path).ext
  if ext.len > 0 and ext[0] == '.': ext[1 .. ^1].toLowerAscii()
  else: ext.toLowerAscii()

proc excerptAround(line: string, r: Rune): string =
  var runes: seq[Rune] = @[]
  try: runes = toRunes(line)
  except CatchableError: return detail(line)
  var idx = -1
  for i in 0 ..< runes.len:
    if runes[i] == r:
      idx = i
      break
  if idx < 0: return detail(line)
  let a = max(0, idx - ExcerptRadius)
  let b = min(runes.len - 1, idx + ExcerptRadius)
  var s = ""
  if a > 0: s.add("…")
  for i in a .. b: s.add($runes[i])
  if b < runes.len - 1: s.add("…")
  s

# ---------------------------------------------------------------------------
# Policy (same restricted-YAML SSOT and same validation as the evaluator)
# ---------------------------------------------------------------------------

type
  Policy* = object
    path*: string
    sha256*: string
    baselineCommit*: string
    allowedScripts*: seq[string]
    exemptPaths*: seq[string]
    documentExtensions*: seq[string]
    ripgrepVersion*: string
    gitMinVersion*: string
    claim*: string

proc loadPolicy*(path: string): Result[Policy, string] =
  var text: string
  try:
    text = readFile(path)
  except CatchableError as e:
    return err("cannot read policy " & path & ": " & e.msg)
  let parsed = parseRestrictedYaml(text)
  if parsed.isErr:
    return err("policy parse error: " & parsed.error)
  let root = parsed.get
  if root.kind != yMap:
    return err("policy root is not a mapping")
  if yHasDuplicateKeys(root).len > 0:
    return err("policy has duplicate keys")

  var p = Policy(path: path)
  p.sha256 = sha256Hex(text)
  if yStr(root, "schemaVersion") != "1":
    return err("policy schemaVersion must be \"1\"")
  if yStr(root, "dimension") != "script-scan":
    return err("policy dimension must be \"script-scan\"")
  if yStr(root, "scope") != "added-lines":
    return err("policy scope must be \"added-lines\"")
  p.baselineCommit = yStr(root, "baselineCommit")
  if not isHexSha(p.baselineCommit):
    return err("policy baselineCommit must be a 40-hex commit sha")
  p.claim = yStr(root, "claim")

  p.allowedScripts = yListStrs(root, "allowedScripts")
  for s in p.allowedScripts:
    if s notin AllowedScriptNames:
      return err("policy allowedScripts contains an unknown script: " & s)
  for s in AllowedScriptNames:
    if s notin p.allowedScripts:
      return err("policy allowedScripts must list exactly: " &
        AllowedScriptNames.join(","))

  for n in yListMaps(root, "exemptPaths"):
    let ep = yStr(n, "path")
    let reason = yStr(n, "reason")
    if ep.len == 0 or reason.len == 0:
      return err("policy exemptPaths entries need path and reason")
    if ep.contains('*') or ep.contains('?'):
      return err("policy exemptPaths must be exact paths, no wildcards: " & ep)
    p.exemptPaths.add(ep)

  p.documentExtensions = yListStrs(root, "documentExtensions")
  for i in 0 ..< p.documentExtensions.len:
    p.documentExtensions[i] = p.documentExtensions[i].toLowerAscii()
    if p.documentExtensions[i].startsWith("."):
      p.documentExtensions[i] = p.documentExtensions[i][1 .. ^1]

  let tc = yGet(root, "toolContract")
  if tc.isNone:
    return err("policy toolContract is required")
  p.ripgrepVersion = yStr(tc.get, "ripgrepVersion")
  p.gitMinVersion = yStr(tc.get, "gitMinVersion")
  if p.ripgrepVersion.len == 0 or p.gitMinVersion.len == 0:
    return err("policy toolContract needs ripgrepVersion and gitMinVersion")

  ok(p)

# ---------------------------------------------------------------------------
# Git (same environment isolation as the evaluator)
# ---------------------------------------------------------------------------

proc gitCmd(repoRoot: string, args: seq[string]): string =
  result = "env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null " &
    "GIT_CONFIG_NOSYSTEM=1 LC_ALL=C git -C " & quoteShell(repoRoot)
  for a in args:
    result.add(" " & quoteShell(a))

proc gitRun(repoRoot: string, args: seq[string]): RunResult =
  let errPath = getTempDir() / ("preflight_scan_git_" & $getCurrentProcessId() & ".err")
  let cmd = gitCmd(repoRoot, args) & " 2>" & quoteShell(errPath)
  let r = runShell(cmd)
  var errText = ""
  try:
    if fileExists(errPath):
      errText = readFile(errPath)
      removeFile(errPath)
  except CatchableError as exc:
    errText = "stderr unreadable: " & exc.msg
  if r.exitCode != 0 and errText.len > 0:
    (detail(r.output & errText), r.exitCode)
  else:
    (r.output, r.exitCode)

proc revParse(repoRoot, rev: string): Result[string, string] =
  if rev.len == 0: return err("empty revision")
  let r = gitRun(repoRoot, @["rev-parse", "--verify", "--quiet", rev & "^{commit}"])
  if r.exitCode != 0:
    return err("cannot resolve '" & rev & "' to a commit: " & detail(r.output))
  let sha = r.output.strip()
  if not isHexSha(sha):
    return err("resolved revision is not a commit sha: " & detail(sha))
  ok(sha)

proc gitShowBlob(repoRoot, rev, path: string): Result[string, string] =
  let r = gitRun(repoRoot, @["show", rev & ":" & path])
  if r.exitCode != 0:
    return err("cannot read blob " & path & " at " & rev & ": " & detail(r.output))
  ok(r.output)

# ---------------------------------------------------------------------------
# Diff parser (verbatim port of publication_script_eval.nim)
# ---------------------------------------------------------------------------

type
  Addition* = object
    path*: string
    lineNo*: int
    content*: string

  FileSection* = object
    oldPath*: string
    newPath*: string
    isNew*: bool
    isDeleted*: bool
    isRename*: bool
    isCopy*: bool
    isBinary*: bool
    submoduleLog*: bool
    oldMode*: string
    newMode*: string
    renameFrom*: string
    renameTo*: string
    additions*: seq[Addition]

proc parseHunkNewStart(line: string): int =
  let plus = line.find('+')
  if plus < 0: return -1
  var i = plus + 1
  var num = ""
  while i < line.len and line[i] in {'0'..'9'}:
    num.add(line[i])
    inc i
  if num.len == 0: return -1
  try: parseInt(num)
  except ValueError: -1

proc parseDiff*(text: string): seq[FileSection] =
  var sections: seq[FileSection] = @[]
  var cur: FileSection
  var haveCur = false
  var inHunk = false
  var newLineNo = 0

  proc flush() =
    if haveCur:
      sections.add(cur)

  for line in text.splitLines():
    if line.startsWith("diff --git "):
      flush()
      cur = FileSection()
      haveCur = true
      inHunk = false
      newLineNo = 0
      let rest = line["diff --git ".len .. ^1]
      let sp = rest.find(' ')
      if sp < 0:
        cur.oldPath = rest
        cur.newPath = rest
      else:
        cur.oldPath = rest[0 ..< sp]
        cur.newPath = rest[sp+1 .. ^1]
    elif not haveCur:
      continue
    elif line.startsWith("new file mode "):
      cur.isNew = true
      cur.newMode = line["new file mode ".len .. ^1].strip()
    elif line.startsWith("deleted file mode "):
      cur.isDeleted = true
      cur.oldMode = line["deleted file mode ".len .. ^1].strip()
    elif line.startsWith("old mode "):
      cur.oldMode = line["old mode ".len .. ^1].strip()
    elif line.startsWith("new mode "):
      cur.newMode = line["new mode ".len .. ^1].strip()
    elif line.startsWith("index "):
      let parts = strutils.splitWhitespace(line)
      if parts.len >= 3:
        if cur.oldMode.len == 0: cur.oldMode = parts[2]
        if cur.newMode.len == 0: cur.newMode = parts[2]
    elif line.startsWith("similarity index "):
      discard
    elif line.startsWith("rename from "):
      cur.isRename = true
      cur.renameFrom = line["rename from ".len .. ^1]
    elif line.startsWith("rename to "):
      cur.isRename = true
      cur.renameTo = line["rename to ".len .. ^1]
    elif line.startsWith("copy from ") or line.startsWith("copy to "):
      cur.isCopy = true
    elif line.startsWith("--- ") and not inHunk:
      let p = line[4 .. ^1]
      if p != "/dev/null": cur.oldPath = p
    elif line.startsWith("+++ ") and not inHunk:
      let p = line[4 .. ^1]
      if p != "/dev/null": cur.newPath = p
    elif line.startsWith("@@ "):
      inHunk = true
      newLineNo = parseHunkNewStart(line)
    elif inHunk:
      if line.len == 0:
        continue
      case line[0]
      of '+':
        cur.additions.add(Addition(path: cur.newPath, lineNo: newLineNo,
          content: line[1 .. ^1]))
        inc newLineNo
      of '-':
        discard
      of ' ':
        inc newLineNo
      of '\\':
        discard
      else:
        discard
    elif line.startsWith("Binary files ") or line.startsWith("GIT binary patch"):
      cur.isBinary = true
    elif line.startsWith("Submodule "):
      cur.submoduleLog = true
  flush()
  sections

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

type
  Violation = object
    path: string
    lineNo: int
    codePoint: string
    rune: Rune
    content: string
    excerpt: string
    presentOnBase: bool
    touchRearmed: bool

proc buildDiff(repoRoot, base, head: string): RunResult =
  ## Byte-identical to the evaluator's diff invocation (eval lines 589-595).
  let errPath = getTempDir() / ("preflight_scan_diff_" & $getCurrentProcessId() & ".err")
  let cmd = "env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null " &
    "GIT_CONFIG_NOSYSTEM=1 LC_ALL=C git -C " & quoteShell(repoRoot) &
    " -c core.quotePath=false -c diff.renames=true" &
    " diff -U0 --no-prefix --no-color --no-ext-diff --no-textconv" &
    " --find-renames=50% --diff-algorithm=myers --submodule=short" &
    " --ignore-submodules=none " & quoteShell(base & ".." & head) &
    " 2>" & quoteShell(errPath)
  let r = runShell(cmd)
  if r.exitCode != 0:
    var errText = ""
    try:
      if fileExists(errPath):
        errText = readFile(errPath)
        removeFile(errPath)
    except CatchableError as exc:
      errText = "stderr unreadable: " & exc.msg
    return (detail(errText), r.exitCode)
  (r.output, 0)

proc main() =
  let inputs = parseArgs()
  var rgPath = inputs.rgPath
  if rgPath.len == 0:
    rgPath = detectRg()

  let policyRes = loadPolicy(inputs.policyPath)
  if policyRes.isErr:
    echo ToolName & " POLICY ERROR: " & policyRes.error
    quit(ExitUnknown)
  let policy = policyRes.get

  var unknowns: seq[string] = @[]
  var toolUnknowns: seq[string] = @[]
  var warnings: seq[string] = @[]
  var additions: seq[Addition] = @[]
  var exempted: seq[string] = @[]
  var binarySkipped: seq[string] = @[]
  var submoduleChanged: seq[string] = @[]
  var renamedPaths: seq[string] = @[]

  # ── tool contract ───────────────────────────────────────────────────────
  # Kept separate from the data UNKNOWNs so --assume-tools-ok can relax only
  # the toolchain pins and never mask an invalid-UTF-8 / quoted-path UNKNOWN.
  var rgVersion = ""
  if rgPath.len == 0 or not fileExists(rgPath):
    toolUnknowns.add("ripgrep binary not found: " & (if rgPath.len == 0: "<none>" else: rgPath))
  else:
    let v = runShell(quoteShell(rgPath) & " --version")
    if v.exitCode != 0:
      toolUnknowns.add("ripgrep --version failed: " & detail(v.output))
    else:
      let first = v.output.splitLines()[0]
      if first.startsWith("ripgrep "):
        let tokens = strutils.splitWhitespace(first["ripgrep ".len .. ^1].strip())
        if tokens.len > 0:
          rgVersion = tokens[0]
      if rgVersion != policy.ripgrepVersion:
        toolUnknowns.add("ripgrep version mismatch: policy=" & policy.ripgrepVersion &
          " actual=" & rgVersion)

  var gitVersion = ""
  let gv = gitRun(inputs.repoRoot, @["--version"])
  if gv.exitCode != 0:
    toolUnknowns.add("git --version failed: " & detail(gv.output))
  else:
    let first = gv.output.splitLines()[0]
    if first.startsWith("git version "):
      gitVersion = first["git version ".len .. ^1].strip()
    if not semverAtLeast(gitVersion, policy.gitMinVersion):
      toolUnknowns.add("git version below policy floor: policy>=" & policy.gitMinVersion &
        " actual=" & gitVersion)

  if inputs.assumeToolsOk:
    for u in toolUnknowns:
      warnings.add("relaxed tool-contract check (DIVERGENT): " & u)
  else:
    for u in toolUnknowns:
      unknowns.add(u)

  # ── exempt path liveness ────────────────────────────────────────────────
  for ep in policy.exemptPaths:
    let tracked = gitRun(inputs.repoRoot, @["ls-files", "--error-unmatch", ep])
    if tracked.exitCode != 0:
      unknowns.add("exempt path is not tracked: " & ep)

  # ── base and head ───────────────────────────────────────────────────────
  var baseMode = ""
  var base = ""
  var head = ""
  let headRes = revParse(inputs.repoRoot, inputs.headRev)
  if headRes.isErr:
    unknowns.add(headRes.error)
  else:
    head = headRes.get

  if head.len > 0:
    if inputs.baseRev.len > 0:
      baseMode = "explicit --base"
      let b = revParse(inputs.repoRoot, inputs.baseRev)
      if b.isErr:
        unknowns.add(b.error)
      else:
        base = b.get
      if base.len > 0:
        # resolveBase() semantics, in the evaluator's order (eval 340-358):
        # cat-file, ancestry, then merge-base == base. A failure is terminal
        # there, so base is cleared and the diff never runs.
        let anc = gitRun(inputs.repoRoot, @["merge-base", "--is-ancestor", base, head])
        if anc.exitCode == 1:
          unknowns.add("base is not an ancestor of head: " & base & ".." & head &
            " (update the branch, or omit --base to use merge-base)")
          base = ""
        elif anc.exitCode != 0:
          unknowns.add("ancestry check failed: " & detail(anc.output))
          base = ""
        else:
          let mb = gitRun(inputs.repoRoot, @["merge-base", base, head])
          if mb.exitCode != 0:
            unknowns.add("merge-base failed: " & detail(mb.output))
            base = ""
          elif mb.output.strip() != base:
            unknowns.add("merge-base differs from the declared base (" &
              mb.output.strip() & " != " & base & ")")
            base = ""
    else:
      baseMode = "merge-base(" & inputs.mainRef & ", head)"
      let mb = gitRun(inputs.repoRoot, @["merge-base", inputs.mainRef, head])
      if mb.exitCode != 0:
        unknowns.add("cannot compute merge-base(" & inputs.mainRef & ", " & head &
          "): " & detail(mb.output) & " (fetch the base ref, or pass --base)")
      else:
        base = mb.output.strip()
        if not isHexSha(base):
          unknowns.add("merge-base is not a commit sha: " & detail(base))
          base = ""

  # ── diff ────────────────────────────────────────────────────────────────
  var diffText = ""
  var mergeBase = ""
  if base.len > 0 and head.len > 0:
    let mb = gitRun(inputs.repoRoot, @["merge-base", base, head])
    if mb.exitCode == 0: mergeBase = mb.output.strip()
    let d = buildDiff(inputs.repoRoot, base, head)
    if d.exitCode != 0:
      unknowns.add("git diff failed (" & $d.exitCode & "): " & detail(d.output))
    else:
      diffText = d.output

  let diffDigest = sha256Hex(diffText)
  let sections = parseDiff(diffText)

  for s in sections:
    let dst = if s.newPath.len > 0: s.newPath else: s.oldPath
    if isQuotedOrAmbiguous(s.oldPath) or isQuotedOrAmbiguous(s.newPath) or
       isQuotedOrAmbiguous(s.renameFrom) or isQuotedOrAmbiguous(s.renameTo):
      unknowns.add("quoted or ambiguous path: " & dst)
      continue
    if s.isCopy:
      unknowns.add("copy header present for " & dst &
        " (copy detection must stay disabled)")
      continue
    if s.submoduleLog:
      unknowns.add("submodule output in non-short format: " & dst)
      continue
    if s.oldMode == "160000" or s.newMode == "160000":
      submoduleChanged.add(dst)
      unknowns.add("submodule change: " & dst)
      continue
    if s.isBinary:
      if extensionOf(dst) in policy.documentExtensions:
        unknowns.add("binary document extension: " & dst)
      else:
        binarySkipped.add(dst)
      continue
    if s.isRename:
      let src = s.renameFrom
      let dstp = s.renameTo
      if src.len == 0 or dstp.len == 0:
        unknowns.add("rename without from/to: " & dst)
        continue
      let srcExempt = src in policy.exemptPaths
      let dstExempt = dstp in policy.exemptPaths
      if srcExempt and not dstExempt:
        let blob = gitShowBlob(inputs.repoRoot, head, dstp)
        if blob.isErr:
          unknowns.add("rename out of exempt path cannot be scanned: " & blob.error)
        else:
          let content = blob.get
          if not isValidUtf8(content):
            unknowns.add("invalid UTF-8 in renamed destination: " & dstp)
          else:
            var ln = 1
            for l in content.splitLines():
              additions.add(Addition(path: dstp, lineNo: ln, content: l))
              inc ln
            renamedPaths.add(src & " -> " & dstp & " (full destination scan)")
      elif not srcExempt and dstExempt:
        if dstp.endsWith(".json"):
          let blob = gitShowBlob(inputs.repoRoot, head, dstp)
          if blob.isErr:
            unknowns.add("renamed exempt JSON unreadable: " & blob.error)
          else:
            try:
              discard parseJson(blob.get)
            except CatchableError:
              unknowns.add("renamed exempt JSON does not parse: " & dstp)
        renamedPaths.add(src & " -> " & dstp & " (exempt destination)")
      else:
        renamedPaths.add(src & " -> " & dstp)
      continue
    if dst in policy.exemptPaths:
      exempted.add(dst)
      continue
    for a in s.additions:
      if not isValidUtf8(a.content):
        unknowns.add("invalid UTF-8: " & dst & ":" & $a.lineNo)
        continue
      additions.add(Addition(path: dst, lineNo: a.lineNo, content: a.content))

  # ── scan with the pinned detector ───────────────────────────────────────
  var violations: seq[Violation] = @[]
  var violationKeys = initHashSet[string]()
  if additions.len > 0 and unknowns.len == 0:
    let scanPath = getTempDir() / ("preflight_scan_" & $getCurrentProcessId() & ".txt")
    var wrote = true
    try:
      var f = open(scanPath, fmWrite)
      for a in additions:
        f.write(a.content)
        f.write("\n")
      f.close()
    except CatchableError as e:
      unknowns.add("cannot write scan file: " & e.msg)
      wrote = false
    if wrote:
      var pattern = "[^\\x00-\\x7F"
      for s in policy.allowedScripts:
        pattern.add("\\p{" & s & "}")
      pattern.add("]")
      let cmd = quoteShell(rgPath) & " --no-config -o -n --text -e " &
        quoteShell(pattern) & " -- " & quoteShell(scanPath)
      let r = runShell(cmd)
      if r.exitCode == 0:
        for line in r.output.splitLines():
          if line.len == 0: continue
          let idx = line.find(':')
          if idx < 0:
            unknowns.add("unparseable ripgrep output: " & detail(line))
            continue
          var recNo = 0
          try: recNo = parseInt(line[0 ..< idx])
          except ValueError:
            unknowns.add("unparseable ripgrep line number: " & detail(line))
            continue
          if recNo < 1 or recNo > additions.len:
            unknowns.add("ripgrep line number out of range: " & $recNo)
            continue
          let m = line[idx+1 .. ^1]
          if m.len == 0:
            unknowns.add("empty ripgrep match on line " & $recNo)
            continue
          let rec = additions[recNo-1]
          var cp = ""
          var rune: Rune
          try:
            rune = runeAt(m, 0)
            cp = "U+" & toHex(ord(rune), 4)
          except CatchableError:
            unknowns.add("cannot decode matched code point at " & rec.path & ":" & $rec.lineNo)
            continue
          let key = rec.path & ":" & $rec.lineNo & ":" & cp
          if key notin violationKeys:
            violationKeys.incl(key)
            violations.add(Violation(path: rec.path, lineNo: rec.lineNo,
              codePoint: cp, rune: rune, content: rec.content,
              excerpt: excerptAround(rec.content, rune)))
      elif r.exitCode == 1:
        discard
      else:
        unknowns.add("ripgrep exited " & $r.exitCode & ": " & detail(r.output))
      try:
        removeFile(scanPath)
      except CatchableError as e:
        warnings.add("temp scan file cleanup failed (" & scanPath & "): " & e.msg)

  # ── touched-not-authored diagnosis ──────────────────────────────────────
  var baseBlobs = initTable[string, seq[string]]()
  for i in 0 ..< violations.len:
    let path = violations[i].path
    if path notin baseBlobs:
      let blob = gitShowBlob(inputs.repoRoot, base, path)
      if blob.isOk:
        baseBlobs[path] = blob.get.splitLines()
      else:
        baseBlobs[path] = @[]
    let lines = baseBlobs[path]
    let needle = $violations[i].rune
    let stripped = violations[i].content.strip()
    var present = false
    var rearmed = false
    for l in lines:
      if l.contains(needle):
        present = true
        if l.strip() == stripped:
          rearmed = true
    violations[i].presentOnBase = present
    violations[i].touchRearmed = rearmed

  # ── verdict ─────────────────────────────────────────────────────────────
  let verdict =
    if unknowns.len > 0: "UNKNOWN"
    elif violations.len > 0: "FAIL"
    else: "PASS"

  if verdict == "PASS" or verdict == "FAIL":
    echo verdict & " (added=" & $additions.len & ", violations=" & $violations.len & ")"
  else:
    echo "UNKNOWN (added=" & $additions.len & ", violations=" & $violations.len &
      ", unknowns=" & $unknowns.len & ")"

  var rearmedCount = 0
  var preExistingCount = 0
  for v in violations:
    echo v.path & ":" & $v.lineNo & " " & v.codePoint & " '" & $v.rune & "'  " & v.excerpt
    if v.touchRearmed:
      inc rearmedCount
      echo "    hint: pre-existing on base — this line was TOUCHED, not authored. " &
        "The whole line is re-judged, so the baseline text became a new violation. " &
        "Revert the touch or make the line plain ASCII (issue #422)."
    elif v.presentOnBase:
      inc preExistingCount
      echo "    hint: this code point already exists on base for this path — " &
        "touching a line re-judges all of its text (issue #422)."
    else:
      echo "    hint: new text introduced by this diff (not present on base for this path)."

  for u in unknowns:
    echo "  UNKNOWN: " & u
  for w in warnings:
    echo "  WARNING: " & w

  if rearmedCount > 0 or preExistingCount > 0:
    echo "# " & $(rearmedCount + preExistingCount) & " of " & $violations.len &
      " violations are pre-existing text re-armed by an edit (" &
      $rearmedCount & " of them whitespace-only touches)."

  echo "# base " & base & " (" & baseMode & ")"
  echo "# head " & head & "  merge-base " & mergeBase
  echo "# policy " & policy.path & " sha256=" & policy.sha256
  echo "# diff-sha256 " & diffDigest
  echo "# ripgrep " & rgVersion & " (policy " & policy.ripgrepVersion & ")  git " & gitVersion
  if exempted.len > 0: echo "# exempted " & exempted.join(",")
  if binarySkipped.len > 0: echo "# binary-skipped " & $binarySkipped.len
  if renamedPaths.len > 0: echo "# renames " & $renamedPaths.len

  if inputs.jsonPath.len > 0:
    var vnodes: seq[JsonNode] = @[]
    for v in violations:
      vnodes.add(%*{"path": v.path, "line": v.lineNo, "codePoint": v.codePoint,
                    "char": $v.rune, "excerpt": v.excerpt,
                    "preExistingOnBase": v.presentOnBase,
                    "touchRearmed": v.touchRearmed})
    var unodes: seq[JsonNode] = @[]
    for u in unknowns: unodes.add(%u)
    let report = %*{
      "schemaVersion": 1,
      "tool": ToolName,
      "dimension": "script-scan",
      "claim": policy.claim,
      "verdict": verdict,
      "policy": {"path": policy.path, "sha256": policy.sha256},
      "toolContract": {"ripgrepVersion": rgVersion, "gitVersion": gitVersion,
                       "assumeToolsOk": inputs.assumeToolsOk},
      "binding": {"baseSha": base, "headSha": head, "mergeBaseSha": mergeBase,
                  "baseMode": baseMode, "diffDigestSha256": diffDigest},
      "addedLineCount": additions.len,
      "violations": vnodes,
      "unknowns": unodes,
      "warnings": warnings,
      "exemptedChangedPaths": exempted,
      "binarySkipped": binarySkipped,
      "submoduleChanged": submoduleChanged,
      "renamedPaths": renamedPaths
    }
    try:
      writeFile(inputs.jsonPath, report.pretty() & "\n")
    except CatchableError as e:
      echo ToolName & " OUTPUT ERROR: " & e.msg
      quit(ExitUnknown)

  quit(case verdict
       of "PASS": ExitPass
       of "FAIL": ExitFail
       else: ExitUnknown)

when isMainModule:
  main()