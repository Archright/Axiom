## publication_script_eval.nim — script-scan dimension of the
## publication-integrity gate.
##
## EXACT CLAIM: a landing diff may add no Unicode code point whose Unicode
## Script property is outside {ASCII range, Latin, Greek, Common, Inherited},
## except exact-path product i18n exemptions.
##
## NOT THE CLAIM: "English-only". Latin-script non-English prose, Greek prose,
## Common/Inherited punctuation, HTML entities, Unicode escapes, images, and
## GitHub conversation text are outside this stage's detection.
##
## Adjudication (fail-closed):
##   - added lines only; context/removed lines are never scanned;
##   - a modified non-English line emits a new added line and FAILS;
##   - renames keep debt in place only inside the non-exempt zone; a rename
##     out of an exempt path is fully rescanned at its destination;
##   - invalid UTF-8 is UNKNOWN (rg silently drops invalid bytes, so the
##     evaluator validates strictly itself);
##   - submodule (gitlink) changes, binary document extensions, quoted paths,
##     missing/mismatched tools, bad baseline, and policy errors are UNKNOWN;
##   - UNKNOWN is BLOCKING, never a pass.
##
## Verdicts (closed set): PASS / FAIL / UNKNOWN.
## Exit: 0 = PASS, 1 = FAIL, 2 = UNKNOWN.
##
## Part of the publication-integrity gate (docs/spec/publication_integrity_gate.md,
## ADR-0044). The policy SSOT is compliance/policy/script-scan-policy.yml.

import std/[json, options, os, osproc, parseopt, sets, strutils, unicode]
import core/trusted/layer_declaration
import core/crypto/hash_kernel
import core/results
import tools/ci/publication_yaml

axiomLayer "tools"

const
  ToolName = "publication_script_eval"
  ExitPass = 0
  ExitFail = 1
  ExitUnknown = 2
  DefaultPolicy = "compliance/policy/script-scan-policy.yml"
  AllowedScriptNames = ["Latin", "Greek", "Common", "Inherited"]
  MaxDetailChars = 400

# ---------------------------------------------------------------------------
# Inputs
# ---------------------------------------------------------------------------

type
  Inputs = object
    policyPath: string
    rgPath: string
    headSha: string
    baseSha: string
    repoRoot: string
    outPath: string

proc parseArgs(): Result[Inputs, string] =
  var inputs = Inputs(policyPath: DefaultPolicy, repoRoot: ".", outPath: "")
  var p = initOptParser(commandLineParams())
  while true:
    p.next()
    case p.kind
    of cmdEnd:
      break
    of cmdLongOption, cmdShortOption:
      let key = p.key
      var val = p.val
      if val.len == 0:
        p.next()
        if p.kind != cmdArgument:
          return err("option '--" & key & "' requires a value")
        val = p.key
      case key
      of "policy": inputs.policyPath = val
      of "rg": inputs.rgPath = val
      of "head": inputs.headSha = val
      of "base": inputs.baseSha = val
      of "repo-root": inputs.repoRoot = val
      of "out": inputs.outPath = val
      else: return err("unknown option: --" & key)
    of cmdArgument:
      return err("unexpected argument '" & p.key & "'")
  if inputs.rgPath.len == 0:
    return err("--rg <path> is required")
  if inputs.headSha.len == 0:
    return err("--head <40-hex> is required")
  if inputs.outPath.len == 0:
    return err("--out <report.json> is required")
  ok(inputs)

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

type
  RunResult = tuple[output: string, exitCode: int]

proc runShell(cmd: string): RunResult =
  try:
    let outp = execCmdEx(cmd)
    (outp.output, outp.exitCode)
  except CatchableError as e:
    ("", 128 + 1)

proc isHexSha(s: string): bool =
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

proc semverAtLeast(actual, minimum: string): bool =
  let a = parseSemver(actual)
  let m = parseSemver(minimum)
  if a.major < 0 or m.major < 0: return false
  if a.major != m.major: return a.major > m.major
  if a.minor != m.minor: return a.minor > m.minor
  a.patch >= m.patch

proc isValidUtf8(s: string): bool =
  ## Strict UTF-8 validator (overlong, surrogate, and >U+10FFFF rejected).
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

proc isQuotedOrAmbiguous(p: string): bool =
  ## Git C-quotes paths that contain whitespace/quotes/backslashes or, with
  ## quotePath=true, non-ASCII. A quoted path is fail-closed UNKNOWN.
  if p.len == 0: return false
  if p[0] == '"' or p.contains('"') or p.contains('\\'): return true
  if p.contains(' ') or p.contains('\t'): return true
  false

proc extensionOf(path: string): string =
  let ext = splitFile(path).ext
  if ext.len > 0 and ext[0] == '.': ext[1 .. ^1].toLowerAscii()
  else: ext.toLowerAscii()

# ---------------------------------------------------------------------------
# Policy (restricted YAML SSOT)
# ---------------------------------------------------------------------------

type
  Policy = object
    path: string
    sha256: string
    baselineCommit: string
    allowedScripts: seq[string]
    exemptPaths: seq[string]
    exemptReasons: seq[string]
    documentExtensions: seq[string]
    ripgrepVersion: string
    gitMinVersion: string
    claim: string
    limitations: seq[string]

proc loadPolicy(path: string): Result[Policy, string] =
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
  let dups = yHasDuplicateKeys(root)
  if dups.len > 0:
    return err("policy has duplicate keys: " & dups.join(","))

  var p = Policy(path: path)
  p.sha256 = sha256Hex(text)
  if yStr(root, "schemaVersion") != "1":
    return err("policy schemaVersion must be \"1\"")
  if yStr(root, "policyId").len == 0:
    return err("policy policyId is required")
  if yStr(root, "dimension") != "script-scan":
    return err("policy dimension must be \"script-scan\"")
  if yStr(root, "stage") != "1":
    return err("policy stage must be \"1\"")
  if yStr(root, "scope") != "added-lines":
    return err("policy scope must be \"added-lines\"")
  p.baselineCommit = yStr(root, "baselineCommit")
  if not isHexSha(p.baselineCommit):
    return err("policy baselineCommit must be a 40-hex commit sha")
  p.claim = yStr(root, "claim")
  if p.claim.len == 0:
    return err("policy claim is required")
  p.limitations = yListStrs(root, "declaredLimitations")
  if p.limitations.len == 0:
    return err("policy declaredLimitations is required")

  p.allowedScripts = yListStrs(root, "allowedScripts")
  var seen: seq[string] = @[]
  for s in p.allowedScripts:
    if s notin AllowedScriptNames:
      return err("policy allowedScripts contains an unknown script: " & s)
    if s in seen:
      return err("policy allowedScripts contains a duplicate: " & s)
    seen.add(s)
  for s in AllowedScriptNames:
    if s notin seen:
      return err("policy allowedScripts must list exactly: " &
        AllowedScriptNames.join(","))

  let exemptNodes = yListMaps(root, "exemptPaths")
  for n in exemptNodes:
    let ep = yStr(n, "path")
    let reason = yStr(n, "reason")
    if ep.len == 0 or reason.len == 0:
      return err("policy exemptPaths entries need path and reason")
    if ep.contains('*') or ep.contains('?'):
      return err("policy exemptPaths must be exact paths, no wildcards: " & ep)
    p.exemptPaths.add(ep)
    p.exemptReasons.add(reason)

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
# Git (environment-isolated, deterministic)
# ---------------------------------------------------------------------------

proc gitCmd(repoRoot: string, args: seq[string]): string =
  result = "env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null " &
    "GIT_CONFIG_NOSYSTEM=1 LC_ALL=C git -C " & quoteShell(repoRoot)
  for a in args:
    result.add(" " & quoteShell(a))

proc gitRun(repoRoot: string, args: seq[string]): RunResult =
  let errPath = getTempDir() / ("script_eval_git_" & $getCurrentProcessId() & ".err")
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

proc resolveBase(inputs: Inputs, policy: Policy): Result[string, string] =
  let base = if inputs.baseSha.len > 0: inputs.baseSha else: policy.baselineCommit
  if not isHexSha(base):
    return err("base is not a 40-hex commit sha")
  let head = inputs.headSha
  if not isHexSha(head):
    return err("head is not a 40-hex commit sha")
  let baseExists = gitRun(inputs.repoRoot, @["cat-file", "-e", base & "^{commit}"])
  if baseExists.exitCode != 0:
    return err("base commit not found: " & base)
  let headExists = gitRun(inputs.repoRoot, @["cat-file", "-e", head & "^{commit}"])
  if headExists.exitCode != 0:
    return err("head commit not found: " & head)
  let anc = gitRun(inputs.repoRoot, @["merge-base", "--is-ancestor", base, head])
  if anc.exitCode == 1:
    return err("base is not an ancestor of head: " & base & ".." & head)
  if anc.exitCode != 0:
    return err("ancestry check failed: " & anc.output)
  let mb = gitRun(inputs.repoRoot, @["merge-base", base, head])
  if mb.exitCode != 0:
    return err("merge-base failed: " & mb.output)
  let mergeBase = mb.output.strip()
  if mergeBase != base:
    return err("merge-base differs from the declared base (" & mergeBase &
      " != " & base & ")")
  ok(base)

proc gitShowBlob(repoRoot, head, path: string): Result[string, string] =
  let r = gitRun(repoRoot, @["show", head & ":" & path])
  if r.exitCode != 0:
    return err("cannot read blob " & path & " at " & head & ": " & detail(r.output))
  ok(r.output)

# ---------------------------------------------------------------------------
# Deterministic diff command
# ---------------------------------------------------------------------------

proc diffCommand(repoRoot, base, head: string): string =
  ## copy detection is never enabled (`-C`/`--find-copies` absent); the
  ## deprecated-looking `--no-find-copies` is NOT a copy switch (it is an
  ## abbreviation of --no-find-copies-harder) and is deliberately not used.
  result = "env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null " &
    "GIT_CONFIG_NOSYSTEM=1 LC_ALL=C git -C " & quoteShell(repoRoot) &
    " -c core.quotePath=false -c diff.renames=true" &
    " diff -U0 --no-prefix --no-color --no-ext-diff --no-textconv" &
    " --find-renames=50% --diff-algorithm=myers --submodule=short" &
    " --ignore-submodules=none " & quoteShell(base & ".." & head)
  let errPath = getTempDir() / ("script_eval_diff_" & $getCurrentProcessId() & ".err")
  result.add(" 2>" & quoteShell(errPath))

# ---------------------------------------------------------------------------
# Diff parser
# ---------------------------------------------------------------------------

type
  Addition = object
    path: string
    lineNo: int
    content: string

  FileSection = object
    oldPath: string
    newPath: string
    isNew: bool
    isDeleted: bool
    isRename: bool
    isCopy: bool
    isBinary: bool
    submoduleLog: bool
    oldMode: string
    newMode: string
    renameFrom: string
    renameTo: string
    additions: seq[Addition]

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

proc parseDiff(text: string): seq[FileSection] =
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
# Report assembly
# ---------------------------------------------------------------------------

proc main() {.raises: [].} =
  let inputsRes = parseArgs()
  if inputsRes.isErr:
    echo ToolName & " INPUT ERROR: " & inputsRes.error
    quit(ExitUnknown)
  let inputs = inputsRes.get

  let policyRes = loadPolicy(inputs.policyPath)
  if policyRes.isErr:
    echo ToolName & " POLICY ERROR: " & policyRes.error
    quit(ExitUnknown)
  let policy = policyRes.get

  var unknowns: seq[string] = @[]
  var violations: seq[JsonNode] = @[]
  var violationKeys = initHashSet[string]()
  var additions: seq[Addition] = @[]
  var exempted: seq[string] = @[]
  var binarySkipped: seq[string] = @[]
  var submoduleChanged: seq[string] = @[]
  var renamedPaths: seq[string] = @[]

  # ── tool contract ─────────────────────────────────────────────────────
  var rgVersion = ""
  var rgSha = ""
  if not fileExists(inputs.rgPath):
    unknowns.add("ripgrep binary not found: " & inputs.rgPath)
  else:
    try: rgSha = sha256Hex(readFile(inputs.rgPath))
    except CatchableError: rgSha = ""
    let v = runShell(quoteShell(inputs.rgPath) & " --version")
    if v.exitCode != 0:
      unknowns.add("ripgrep --version failed: " & detail(v.output))
    else:
      let first = v.output.splitLines()[0]
      if first.startsWith("ripgrep "):
        # Upstream release builds print "ripgrep 14.1.0 (rev <sha>)"; distro
        # builds print "ripgrep 14.1.0". The policy pins the release number,
        # not the build revision, so compare the first whitespace token.
        let rest = first["ripgrep ".len .. ^1].strip()
        let tokens = strutils.splitWhitespace(rest)
        if tokens.len > 0:
          rgVersion = tokens[0]
      if rgVersion != policy.ripgrepVersion:
        unknowns.add("ripgrep version mismatch: policy=" & policy.ripgrepVersion &
          " actual=" & rgVersion)

  var gitVersion = ""
  let gv = gitRun(inputs.repoRoot, @["--version"])
  if gv.exitCode != 0:
    unknowns.add("git --version failed: " & detail(gv.output))
  else:
    let first = gv.output.splitLines()[0]
    if first.startsWith("git version "):
      gitVersion = first["git version ".len .. ^1].strip()
    if not semverAtLeast(gitVersion, policy.gitMinVersion):
      unknowns.add("git version below policy floor: policy>=" & policy.gitMinVersion &
        " actual=" & gitVersion)

  # ── exempt path liveness ─────────────────────────────────────────────
  for ep in policy.exemptPaths:
    let tracked = gitRun(inputs.repoRoot, @["ls-files", "--error-unmatch", ep])
    if tracked.exitCode != 0:
      unknowns.add("exempt path is not tracked: " & ep)

  # ── baseline and diff ────────────────────────────────────────────────
  var base = ""
  let baseRes = resolveBase(inputs, policy)
  if baseRes.isErr:
    unknowns.add(baseRes.error)
  else:
    base = baseRes.get

  var diffText = ""
  var mergeBase = ""
  if base.len > 0:
    let mb = gitRun(inputs.repoRoot, @["merge-base", base, inputs.headSha])
    if mb.exitCode == 0: mergeBase = mb.output.strip()
    diffText = ""
    let errPath = getTempDir() / ("script_eval_diff_" & $getCurrentProcessId() & ".err")
    let diffRun = runShell("env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null " &
      "GIT_CONFIG_NOSYSTEM=1 LC_ALL=C git -C " & quoteShell(inputs.repoRoot) &
      " -c core.quotePath=false -c diff.renames=true" &
      " diff -U0 --no-prefix --no-color --no-ext-diff --no-textconv" &
      " --find-renames=50% --diff-algorithm=myers --submodule=short" &
      " --ignore-submodules=none " & quoteShell(base & ".." & inputs.headSha) &
      " 2>" & quoteShell(errPath))
    if diffRun.exitCode != 0:
      var errText = ""
      try:
        if fileExists(errPath):
          errText = readFile(errPath)
          removeFile(errPath)
      except CatchableError as exc:
        errText = "stderr unreadable: " & exc.msg
      unknowns.add("git diff failed (" & $diffRun.exitCode & "): " & detail(errText))
    else:
      diffText = diffRun.output

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
        let blob = gitShowBlob(inputs.repoRoot, inputs.headSha, dstp)
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
          let blob = gitShowBlob(inputs.repoRoot, inputs.headSha, dstp)
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

  # ── scan the collected added lines with the pinned detector ──────────
  var scanPath = ""
  if additions.len > 0 and unknowns.len == 0:
    scanPath = getTempDir() / ("script_eval_scan_" & $getCurrentProcessId() & ".txt")
    try:
      var f = open(scanPath, fmWrite)
      for a in additions:
        f.write(a.content)
        f.write("\n")
      f.close()
    except CatchableError as e:
      unknowns.add("cannot write scan file: " & e.msg)

  if scanPath.len > 0:
    var pattern = "[^\\x00-\\x7F"
    for s in policy.allowedScripts:
      pattern.add("\\p{" & s & "}")
    pattern.add("]")
    let cmd = quoteShell(inputs.rgPath) & " --no-config -o -n --text -e " &
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
        try:
          let rune = runeAt(m, 0)
          cp = "U+" & toHex(ord(rune), 4)
        except CatchableError:
          unknowns.add("cannot decode matched code point at " & rec.path & ":" & $rec.lineNo)
          continue
        let key = rec.path & ":" & $rec.lineNo & ":" & cp
        if key notin violationKeys:
          violationKeys.incl(key)
          violations.add(%*{"path": rec.path, "line": rec.lineNo, "codePoint": cp})
    elif r.exitCode == 1:
      discard
    else:
      unknowns.add("ripgrep exited " & $r.exitCode & ": " & detail(r.output))

  if scanPath.len > 0:
    try: removeFile(scanPath)
    except CatchableError: discard  # axiom:best-effort(temp scan file cleanup — verdict already fixed)

  let verdict =
    if unknowns.len > 0: "UNKNOWN"
    elif violations.len > 0: "FAIL"
    else: "PASS"

  var scannedPaths = initHashSet[string]()
  for a in additions: scannedPaths.incl(a.path)

  var violationNodes: seq[JsonNode] = @[]
  for v in violations: violationNodes.add(v)
  var unknownNodes: seq[JsonNode] = @[]
  for u in unknowns: unknownNodes.add(%u)

  let report = %*{
    "schemaVersion": 1,
    "dimension": "script-scan",
    "claim": policy.claim,
    "verdict": verdict,
    "policy": {"path": policy.path, "sha256": policy.sha256},
    "tool": {"name": "ripgrep", "version": rgVersion, "sha256": rgSha,
             "path": inputs.rgPath},
    "git": {"version": gitVersion, "minVersion": policy.gitMinVersion},
    "binding": {
      "baseSha": base,
      "headSha": inputs.headSha,
      "mergeBaseSha": mergeBase,
      "baselineCommit": policy.baselineCommit,
      "diffDigestSha256": diffDigest,
    },
    "addedLineCount": additions.len,
    "scannedFileCount": scannedPaths.len,
    "exemptedChangedPaths": exempted,
    "binarySkipped": binarySkipped,
    "submoduleChanged": submoduleChanged,
    "renamedPaths": renamedPaths,
    "violations": violationNodes,
    "unknowns": unknownNodes,
    "declaredLimitations": policy.limitations,
  }

  try:
    writeFile(inputs.outPath, report.pretty() & "\n")
  except CatchableError as e:
    echo ToolName & " OUTPUT ERROR: " & e.msg
    quit(ExitUnknown)

  echo ToolName & ": " & verdict & " (added=" & $additions.len &
    ", violations=" & $violations.len & ", unknowns=" & $unknowns.len & ")"
  for v in violations:
    echo "  VIOLATION: " & v{"path"}.getStr() & ":" &
      $v{"line"}.getInt() & " " & v{"codePoint"}.getStr()
  for u in unknowns:
    echo "  UNKNOWN: " & u
  quit(case verdict
       of "PASS": ExitPass
       of "FAIL": ExitFail
       else: ExitUnknown)

when isMainModule:
  main()