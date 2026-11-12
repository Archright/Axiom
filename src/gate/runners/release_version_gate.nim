import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

import std/json
import std/os
import std/osproc
import std/strutils
import std/options
import core/results
import core/axiom_pragmas
import core/macros/best_effort
import core/release/version_derive
import infrastructure/logging_facade


# axiomIoBoundary

const
  GateTag = "[release-version-gate]"
  LegacyMinor = 4
  LegacyPatch = 12

type
  PushRef = object
    localRef: string
    localSha: string
    remoteRef: string
    remoteSha: string

proc parsePushRefs(): seq[PushRef] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let raw = getEnv("AXIOM_PUSH_REFS")
  if raw.len == 0: return
  let j = parseJson(raw)
  for item in j:
    result.add(PushRef(
      localRef: item{"localRef"}.getStr(""),
      localSha: item{"localSha"}.getStr(""),
      remoteRef: item{"remoteRef"}.getStr(""),
      remoteSha: item{"remoteSha"}.getStr("")
    ))

proc readFileSafe(path: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], bestEffort("file read may fail on missing or permission-denied; empty string is treated as no version data").} =
  try: readFile(path)
  except: ""

proc parseNimbleVersion(repoRoot: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let content = readFileSafe(repoRoot / "axiom.nimble")
  for line in content.splitLines():
    let s = line.strip()
    if s.startsWith("version"):
      let eq = s.find('=')
      if eq >= 0:
        return s[eq + 1 .. ^1].strip().strip(chars = {'"'}).strip(chars = {'\''})

func stripVPrefix(tag: string): string =
  if tag.len > 0 and tag[0] == 'v': tag[1 .. ^1] else: tag

func isLegacyTag(tag: string): bool {.raises: [].} =
  let v = parseSemVer(tag)
  if v.isNone: return false
  let vv = v.get()
  vv.major == 0 and (vv.minor < LegacyMinor or (vv.minor == LegacyMinor and vv.patch <= LegacyPatch))

proc runGit(repoRoot, args: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], bestEffort("git command may fail on missing repo or broken ref; empty string is treated as no data").} =
  try:
    let (outp, code) = execCmdEx("git " & args, workingDir = repoRoot)
    if code == 0: outp.strip() else: ""
  except: ""

proc checkTag(repoRoot, tagName, refSpec: string): tuple[ok: bool, msg: string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if isLegacyTag(tagName):
    return (false, tagName & ": legacy tag namespace is frozen (v0.4.12 and below)")

  let tagVer = stripVPrefix(tagName)

  let nimbleVer = parseNimbleVersion(repoRoot)
  if nimbleVer.len == 0 or nimbleVer != tagVer:
    return (false, tagName & ": axiom.nimble version \"" & nimbleVer & "\" != tag \"" & tagVer & "\"")

  let lastTag = runGit(repoRoot, "describe --tags --abbrev=0 --match \"v[0-9]*\" " & refSpec & "^")
  if lastTag.len == 0:
    return (true, "")

  let logRaw = runGit(repoRoot, "log " & lastTag & ".." & refSpec & " --format=%s%x1f%b%x1e")
  if logRaw.len == 0:
    let lastV = parseSemVer(lastTag)
    if lastV.isSome:
      let expected = $lastV.get()
      if expected != tagVer:
        return (false, tagName & ": derived version \"" & expected & "\" != tag \"" & tagVer & "\" (no commits since " & lastTag & ")")
    return (true, "")

  var subjects: seq[string]
  var bodies: seq[string]
  for record in logRaw.split('\x1e'):
    if record.len == 0: continue
    let parts = record.split('\x1f')
    subjects.add(parts[0])
    bodies.add(if parts.len >= 2: parts[1] else: "")

  let derived = deriveNextVersion(lastTag, subjects, bodies)
  case derived.outcome
  of doOk:
    let expected = $derived.version
    if expected != tagVer:
      return (false, tagName & ": derived version \"" & expected & "\" != tag \"" & tagVer & "\"")
  of doNoBump:
    let lastV = parseSemVer(lastTag)
    if lastV.isSome:
      let expected = $lastV.get()
      if expected != tagVer:
        return (false, tagName & ": derived version \"" & expected & "\" != tag \"" & tagVer & "\" (no bump from " & lastTag & ")")
  of doBadTag:
    return (false, tagName & ": last tag \"" & lastTag & "\" is not valid semver")

proc parseNimbleDumpVersion(jsonText: string): Result[string, string] =
  ## Extracts the `version` field from `nimble dump --json`; parsing lives here,
  ## outside src/core, so the core module stays func-only.
  var node: JsonNode
  try:
    node = parseJson(jsonText)
  except CatchableError:
    return Result[string, string](ok: false, err: "invalid nimble dump JSON: " & getCurrentExceptionMsg())
  let versionNode = node{"version"}
  if node.kind != JObject or versionNode == nil or versionNode.kind != JString:
    return Result[string, string](ok: false, err: "nimble dump JSON has no string 'version' field")
  validateNimbleVersionString(versionNode.getStr())

type GateArgs = object
  tag, nimbleJson, binary, lakefile: string

proc parseGateArgs(): tuple[args: GateArgs, code: int] {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Release-boundary mode: --tag <vX.Y.Z> --nimble-json <path>
  ## [--lakefile <path>] [--binary <path>]
  result.code = 0
  var i = 1
  while i <= paramCount():
    case paramStr(i)
    of "--tag":
      inc i
      if i > paramCount():
        logError(GateTag, "--tag requires a value"); return (result.args, 1)
      result.args.tag = paramStr(i)
    of "--nimble-json":
      inc i
      if i > paramCount():
        logError(GateTag, "--nimble-json requires a path"); return (result.args, 1)
      result.args.nimbleJson = paramStr(i)
    of "--binary":
      inc i
      if i > paramCount():
        logError(GateTag, "--binary requires a path"); return (result.args, 1)
      result.args.binary = paramStr(i)
    of "--lakefile":
      inc i
      if i > paramCount():
        logError(GateTag, "--lakefile requires a path"); return (result.args, 1)
      result.args.lakefile = paramStr(i)
    else:
      logError(GateTag, "unknown argument: " & paramStr(i)); return (result.args, 1)
    inc i

proc checkArgsPresent(a: GateArgs): bool {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if a.tag.len == 0:
    logError(GateTag, "--tag is required"); return false
  if a.nimbleJson.len == 0 and a.binary.len == 0 and a.lakefile.len == 0:
    logError(GateTag, "--tag requires --nimble-json, --lakefile and/or --binary")
    return false
  true

proc checkNimbleJson(tag, path: string): bool {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var content: string
  try:
    content = readFile(path)
  except CatchableError:
    logError(GateTag, "cannot read nimble metadata: " & path); return false
  let parsed = parseNimbleDumpVersion(content)
  if not parsed.ok:
    logError(GateTag, "nimble metadata invalid: " & parsed.err); return false
  let checked = validateReleaseVersion(tag, parsed.value)
  if not checked.ok:
    logError(GateTag, "metadata mismatch: " & checked.err); return false
  logInfo(GateTag, "metadata PASS: tag=" & tag & " nimble=" & parsed.value)
  true

proc checkLakefile(tag, path: string): bool {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var content: string
  try:
    content = readFile(path)
  except CatchableError:
    logError(GateTag, "cannot read lakefile: " & path); return false
  let parsed = parseLakeVersion(content)
  if parsed.isNone:
    logError(GateTag, "lakefile has no valid X.Y.Z version"); return false
  let checked = validateLakeVersion(tag, parsed.get())
  if not checked.ok:
    logError(GateTag, "lakefile mismatch: " & checked.err); return false
  logInfo(GateTag, "lakefile PASS: tag=" & tag & " lake=" & parsed.get())
  true

proc checkBinary(tag, path: string): bool {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var output: string
  var code: int
  try:
    (output, code) = execCmdEx(quoteShell(path) & " --version")
  except CatchableError:
    logError(GateTag, "cannot execute binary: " & path); return false
  if code != 0:
    logError(GateTag, "binary --version exited " & $code); return false
  let checked = validateBinaryVersion(tag, output)
  if not checked.ok:
    logError(GateTag, "binary mismatch: " & checked.err); return false
  logInfo(GateTag, "binary PASS: tag=" & tag & " output=" & output.strip())
  true

proc runCli(): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let (a, argCode) = parseGateArgs()
  if argCode != 0: return argCode
  if not checkArgsPresent(a): return 1
  if a.nimbleJson.len > 0 and not checkNimbleJson(a.tag, a.nimbleJson): return 1
  if a.lakefile.len > 0 and not checkLakefile(a.tag, a.lakefile): return 1
  if a.binary.len > 0 and not checkBinary(a.tag, a.binary): return 1
  0

proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  for arg in commandLineParams():
    if arg == "--tag":
      quit(runCli())
  let repoRoot = if paramCount() >= 1: paramStr(1) else: getCurrentDir()
  let pushRefs = parsePushRefs()

  var tagRefs: seq[tuple[name: string, refSpec: string]]
  for pr in pushRefs:
    if pr.localRef.startsWith("refs/tags/v"):
      let tagName = pr.localRef["refs/tags/".len .. ^1]
      if tagName.len > 1 and tagName[0] == 'v':
        tagRefs.add((tagName, pr.localRef))

  if tagRefs.len == 0:
    logInfo(GateTag, "No version tags in push — gate passes silently")
    quit(0)

  var failures: seq[string]
  for (tagName, refSpec) in tagRefs:
    let (ok, msg) = checkTag(repoRoot, tagName, refSpec)
    if ok:
      logInfo(GateTag, tagName & ": PASS")
    else:
      logError(GateTag, msg)
      failures.add(msg)

  if failures.len > 0:
    logError(GateTag, $failures.len & " tag(s) failed consistency check")
    quit(1)

  logInfo(GateTag, "All version tags pass consistency checks")
  quit(0)

when isMainModule: main()

{.pop.}
