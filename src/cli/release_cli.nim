import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}

import std/os
import std/osproc
import std/options
import std/strutils
import core/axiom_pragmas
import core/release/version_derive
import infrastructure/logging_facade

proc getLastTag(): tuple[tag: string, ok: bool] {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let (outp, code) = execCmdEx(
    "git describe --tags --abbrev=0 --match v[0-9]*",
    options = {poStdErrToStdOut, poUsePath})
  if code != 0:
    return ("", false)
  (outp.strip(), true)

proc getCommitLogSince(tag: string): tuple[subjects: seq[string], bodies: seq[string]] {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let (outp, code) = execCmdEx(
    "git log " & tag & "..HEAD --format=%s%x1f%b%x1e",
    options = {poStdErrToStdOut, poUsePath})
  if code != 0 or outp.len == 0:
    return (@[], @[])
  var subjects: seq[string] = @[]
  var bodies: seq[string] = @[]
  for record in outp.split('\x1e'):
    let r = record.strip()
    if r.len == 0: continue
    let sep = r.find('\x1f')
    if sep < 0:
      subjects.add(r)
      bodies.add("")
    else:
      subjects.add(r[0 ..< sep])
      bodies.add(if sep + 1 < r.len: r[sep + 1 .. ^1] else: "")
  (subjects, bodies)

proc isCleanWorktree(): bool {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let (outp, code) = execCmdEx("git status --porcelain",
    options = {poStdErrToStdOut, poUsePath})
  code == 0 and outp.strip().len == 0

func semVerLess(a, b: SemVer): bool =
  if a.major != b.major: a.major < b.major
  elif a.minor != b.minor: a.minor < b.minor
  else: a.patch < b.patch

proc updateVersionLine(path, version: string): bool {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if not fileExists(path): return false
  let content = readFile(path)
  var lines = content.splitLines()
  var found = false
  for i, line in lines:
    let s = line.strip()
    if s.startsWith("version") and '=' in s:
      let eqPos = line.find('=')
      lines[i] = line[0 .. eqPos] & " \"" & version & "\""
      found = true
      break
  if found:
    let trailing = if content.endsWith("\n"): "\n" else: ""
    writeFile(path, lines.join("\n") & trailing)
  found

type
  ReleaseOptions = object
    dryRun: bool
    requested: string
    hasRequested: bool
    acceptNonDerived: bool

proc parseReleaseArgs(args: seq[string]): tuple[opts: ReleaseOptions, code: int] {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result.code = 0
  var i = 0
  while i < args.len:
    case args[i]
    of "--dry-run":
      result.opts.dryRun = true
    of "--accept-non-derived":
      result.opts.acceptNonDerived = true
    of "--version":
      if i + 1 >= args.len:
        logError("release_cli", "ax release: --version requires a value")
        return (result.opts, 2)
      inc i
      result.opts.requested = args[i]
      result.opts.hasRequested = true
    else:
      logError("release_cli", "ax release: unknown argument '" & args[i] & "'")
      return (result.opts, 2)
    inc i
  if result.opts.acceptNonDerived and not result.opts.hasRequested:
    logError("release_cli",
      "ax release: --accept-non-derived requires an explicit --version")
    return (result.opts, 2)

proc resolveExplicitVersion(opts: ReleaseOptions; tag: string; lastV: SemVer;
                            dr: DeriveResult): tuple[versionStr: string, code: int] {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Explicit human version: must be greater than the last tag, and must not
  ## silently diverge from the Conventional-Commits derivation.
  let requestedV = parseSemVer(opts.requested)
  if requestedV.isNone:
    logError("release_cli",
      "ax release: requested version '" & opts.requested & "' is not X.Y.Z")
    return ("", 2)
  if not semVerLess(lastV, requestedV.get()):
    logError("release_cli",
      "ax release: requested " & opts.requested & " is not greater than last tag " & tag)
    return ("", 2)
  case dr.outcome
  of doBadTag:
    logError("release_cli",
      "ax release: last tag '" & tag & "' is not a valid semver")
    return ("", 2)
  of doNoBump:
    logError("release_cli",
      "ax release: no release-worthy commits since " & tag &
      " — refusing explicit " & opts.requested & " without a derived bump")
    return ("", 3)
  of doOk:
    if $dr.version != $requestedV.get():
      if not opts.acceptNonDerived:
        logError("release_cli",
          "ax release: derived " & $dr.version & " != requested " &
          $requestedV.get() & " — refusing to guess; re-run with " &
          "--accept-non-derived to authorise the explicit version")
        return ("", 5)
      logInfo("release_cli",
        "derived " & $dr.version & " != requested " & $requestedV.get() &
        " — proceeding under explicit human override (--accept-non-derived)")
    return (requestedV.get().withPrefix(), 0)

proc resolveVersion(opts: ReleaseOptions; tag: string; lastV: SemVer;
                    dr: DeriveResult): tuple[versionStr: string, code: int] {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if opts.hasRequested:
    return resolveExplicitVersion(opts, tag, lastV, dr)
  case dr.outcome
  of doBadTag:
    logError("release_cli",
      "ax release: last tag '" & tag & "' is not a valid semver")
    ("", 2)
  of doNoBump:
    if opts.dryRun:
      stderr.writeLine("no-bump")
    else:
      logError("release_cli",
        "ax release: no release-worthy commits since " & tag)
    ("", 3)
  of doOk:
    (dr.version.withPrefix(), 0)

proc runGitCommand(cmd: string): tuple[output: string, exitCode: int] {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  execCmdEx(cmd, options = {poStdErrToStdOut, poUsePath})

proc stageAndCommit(versionStr: string): tuple[ok: bool, msg: string] {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let (addOut, addCode) = runGitCommand("git add axiom.nimble lakefile.toml")
  if addCode != 0:
    return (false, "git add failed: " & addOut.strip())
  let (commitOut, commitCode) = runGitCommand(
    "git commit -m " & quoteShell("chore(release): " & versionStr))
  if commitCode != 0:
    discard runGitCommand("git reset")
    return (false, "git commit failed: " & commitOut.strip())
  (true, "")

proc writeReleaseCommit(versionStr: string; hasRequested: bool): int {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let bareVersion = versionStr[1..^1]
  if not isCleanWorktree():
    logError("release_cli", "ax release: worktree is not clean")
    return 4

  let nimblePath = "axiom.nimble"
  let lakePath = "lakefile.toml"
  let nimbleOrig = readFile(nimblePath)
  let lakeOrig = readFile(lakePath)
  if not updateVersionLine(nimblePath, bareVersion):
    logError("release_cli",
      "ax release: cannot find version line in axiom.nimble")
    return 1
  if not updateVersionLine(lakePath, bareVersion):
    writeFile(nimblePath, nimbleOrig)
    logError("release_cli",
      "ax release: cannot find version line in lakefile.toml")
    return 1

  let (committed, commitErr) = stageAndCommit(versionStr)
  if not committed:
    writeFile(nimblePath, nimbleOrig)
    writeFile(lakePath, lakeOrig)
    logError("release_cli", "ax release: " & commitErr)
    return 1

  let (hashOut, hashCode) = runGitCommand("git rev-parse --short HEAD")
  let commitHash = if hashCode == 0: hashOut.strip() else: "?"

  echo "release commit " & versionStr & " prepared"
  echo "  commit: " & commitHash
  if hasRequested:
    echo "  tag:    not created (release-ship owns official tag creation)"
    return 0
  let tagMsg = "release " & versionStr
  let (tagOut, tagCode) = execCmdEx(
    "git tag -a " & versionStr & " -m " & quoteShell(tagMsg),
    options = {poStdErrToStdOut, poUsePath})
  if tagCode != 0:
    logError("release_cli",
      "ax release: git tag failed: " & tagOut.strip())
    return 1
  echo "  tag:    " & versionStr & " (legacy mode)"
  0

proc runReleaseCommand*(args: seq[string]): int {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let (opts, parseCode) = parseReleaseArgs(args)
  if parseCode != 0: return parseCode

  let (tag, tagOk) = getLastTag()
  if not tagOk:
    logError("release_cli", "ax release: no semver tag found")
    return 2

  let lastV = parseSemVer(tag)
  if lastV.isNone:
    logError("release_cli",
      "ax release: last tag '" & tag & "' is not a valid semver")
    return 2

  let (subjects, bodies) = getCommitLogSince(tag)
  let dr = deriveNextVersion(tag, subjects, bodies)
  let (versionStr, versionCode) = resolveVersion(opts, tag, lastV.get(), dr)
  if versionCode != 0: return versionCode

  if opts.dryRun:
    echo versionStr
    return 0

  writeReleaseCommit(versionStr, opts.hasRequested)
{.pop.}
