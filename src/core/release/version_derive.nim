import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## Version Derivation Engine — SSOT: git commit history (Conventional Commits).
## Pure module: no IO, no process execution. Callers supply tag/subject strings.
##
## Bump policy (approved 2026-07-27):
##   BREAKING CHANGE / `type!:`  -> major
##   feat                        -> minor
##   fix, perf                   -> patch
##   refactor/docs/test/ci/build/chore/revert -> none
import std/os
import std/strutils
import std/options
import core/parsers/safe_parsers
import core/results

type
  BumpKind* = enum
    bkNone
    bkPatch
    bkMinor
    bkMajor

  SemVer* = object
    major*: int
    minor*: int
    patch*: int

func `$`*(v: SemVer): string =
  $v.major & "." & $v.minor & "." & $v.patch

func withPrefix*(v: SemVer): string =
  "v" & $v

func parseSemVer*(raw: string): Option[SemVer] =
  ## Accepts "0.4.12" or "v0.4.12". Rejects anything else.
  var s = raw.strip()
  if s.len > 1 and s[0] == 'v':
    s = s[1..^1]
  let parts = s.split('.')
  if parts.len != 3:
    return none(SemVer)
  var nums: array[3, int]
  for i, p in parts:
    if p.len == 0:
      return none(SemVer)
    for c in p:
      if c notin {'0'..'9'}:
        return none(SemVer)
    let parsedNum = safeParseInt(p)
    if parsedNum.isErr:
      return none(SemVer)
    nums[i] = parsedNum.get
  some(SemVer(major: nums[0], minor: nums[1], patch: nums[2]))

func normalizeReleaseTag*(tag: string): Option[string] =
  ## Accepts "vX.Y.Z" or "X.Y.Z"; returns canonical "X.Y.Z".
  let v = parseSemVer(tag)
  if v.isNone: return none(string)
  some($v.get())

func validateReleaseVersion*(tag, packageVersion: string): Result[void, string] =
  ## Exact tag↔package equality after stripping one optional leading "v".
  let tagNorm = normalizeReleaseTag(tag)
  if tagNorm.isNone:
    return Result[void, string](ok: false, err: "invalid release tag '" & tag & "' (expected vX.Y.Z)")
  let pkgNorm = normalizeReleaseTag(packageVersion)
  if pkgNorm.isNone:
    return Result[void, string](ok: false, err: "invalid package version '" & packageVersion & "' (expected X.Y.Z)")
  if tagNorm.get() != pkgNorm.get():
    return Result[void, string](ok: false, err: "release tag " & tagNorm.get() & " != package version " & pkgNorm.get())
  Result[void, string](ok: true)

func validateNimbleVersionString*(version: string): Result[string, string] =
  ## Validates a version string already extracted from `nimble dump --json`.
  let normalized = normalizeReleaseTag(version)
  if normalized.isNone:
    return Result[string, string](ok: false, err: "nimble version is not X.Y.Z: '" & version & "'")
  Result[string, string](ok: true, value: normalized.get())

func validateBinaryVersion*(expected, output: string): Result[void, string] =
  ## `bin/ax --version` must emit exactly one X.Y.Z (optionally v-prefixed) line.
  let expectedNorm = normalizeReleaseTag(expected)
  if expectedNorm.isNone:
    return Result[void, string](ok: false, err: "invalid expected version '" & expected & "'")
  let text = output.strip()
  if text.len == 0:
    return Result[void, string](ok: false, err: "binary --version produced empty output")
  let lines = text.splitLines()
  if lines.len != 1:
    return Result[void, string](ok: false, err: "binary --version must emit exactly one line")
  let actualNorm = normalizeReleaseTag(lines[0])
  if actualNorm.isNone:
    return Result[void, string](ok: false, err: "binary --version is not X.Y.Z: '" & lines[0] & "'")
  if actualNorm.get() != expectedNorm.get():
    return Result[void, string](ok: false, err: "binary version " & actualNorm.get() & " != expected " & expectedNorm.get())
  Result[void, string](ok: true)

## ── Canonical product version (SSOT: axiom.nimble) ──────────────────────────
## staticRead resolves relative to this module; 4×parentDir = repo root.
## Fail-closed: a missing or malformed version aborts compilation instead of
## silently producing "unknown".
const axiomNimbleContent = staticRead(
    currentSourcePath().parentDir().parentDir().parentDir().parentDir() / "axiom.nimble")

func extractNimbleVersion(content: string): string =
  for line in content.splitLines():
    let stripped = line.strip()
    if stripped.startsWith("version"):
      let eqPos = stripped.find('=')
      if eqPos >= 0:
        let valuePart = stripped[eqPos + 1..^1].strip()
        if valuePart.len >= 2 and valuePart[0] == '"' and valuePart[^1] == '"':
          return valuePart[1..^2]
        return valuePart
  ""

const
  axiomVersion* = extractNimbleVersion(axiomNimbleContent)
  axiomVersionWithPrefix* = "v" & axiomVersion

static:
  doAssert axiomVersion.len > 0, "axiom.nimble: version line is missing"
  doAssert parseSemVer(axiomVersion).isSome,
    "axiom.nimble: version must be X.Y.Z, got '" & axiomVersion & "'"

func parseLakeVersion*(content: string): Option[string] =
  ## Parses `version = "X.Y.Z"` from lakefile.toml; normalizes to X.Y.Z.
  for line in content.splitLines():
    let s = line.strip()
    if s.len == 0 or s[0] == '#':
      continue
    if s.startsWith("version") and '=' in s:
      let valuePart = s.split('=', maxsplit = 1)[1].strip()
      if valuePart.len >= 2 and valuePart[0] == '"' and valuePart[^1] == '"':
        return normalizeReleaseTag(valuePart[1..^2])
      return normalizeReleaseTag(valuePart)
  none(string)

func validateLakeVersion*(tag, lakeVersion: string): Result[void, string] =
  ## Exact tag↔lakefile version equality after normalization.
  let tagNorm = normalizeReleaseTag(tag)
  if tagNorm.isNone:
    return Result[void, string](ok: false, err: "invalid release tag '" & tag & "' (expected vX.Y.Z)")
  let lakeNorm = normalizeReleaseTag(lakeVersion)
  if lakeNorm.isNone:
    return Result[void, string](ok: false, err: "invalid lake version '" & lakeVersion & "' (expected X.Y.Z)")
  if tagNorm.get() != lakeNorm.get():
    return Result[void, string](ok: false, err: "release tag " & tagNorm.get() & " != lake version " & lakeNorm.get())
  Result[void, string](ok: true)

const
  conventionalTypes = [
    "feat", "fix", "refactor", "perf", "test",
    "docs", "build", "ci", "chore", "revert"
  ]

func splitTypeToken(subject: string): string =
  ## Extract the leading `type[(scope)][!]` token before ": ".
  let colon = subject.find(':')
  if colon <= 0:
    return ""
  subject[0 ..< colon]

func classifyCommit*(subject: string; body: string = ""): BumpKind =
  ## Classify a single commit by Conventional Commit semantics.
  ## `body` is scanned for the "BREAKING CHANGE:" / "BREAKING-CHANGE:" footer.
  if body.contains("BREAKING CHANGE:") or body.contains("BREAKING-CHANGE:"):
    return bkMajor
  var token = splitTypeToken(subject)
  if token.len == 0:
    return bkNone
  var breaking = false
  if token.endsWith("!"):
    breaking = true
    token = token[0 ..< token.len - 1]
  let paren = token.find('(')
  if paren >= 0:
    if not token.endsWith(")"):
      return bkNone
    token = token[0 ..< paren]
  if token notin conventionalTypes:
    return bkNone
  if breaking:
    return bkMajor
  case token
  of "feat": bkMinor
  of "fix", "perf": bkPatch
  else: bkNone

func maxBump*(kinds: openArray[BumpKind]): BumpKind =
  result = bkNone
  for k in kinds:
    if k > result:
      result = k

func bump*(v: SemVer; kind: BumpKind): SemVer =
  case kind
  of bkMajor: SemVer(major: v.major + 1, minor: 0, patch: 0)
  of bkMinor: SemVer(major: v.major, minor: v.minor + 1, patch: 0)
  of bkPatch: SemVer(major: v.major, minor: v.minor, patch: v.patch + 1)
  of bkNone: v

type
  DeriveOutcome* = enum
    doOk           ## bump derived
    doNoBump       ## no release-worthy commits since last tag
    doBadTag       ## last tag is not a valid semver

  DeriveResult* = object
    outcome*: DeriveOutcome
    version*: SemVer   ## valid only when outcome == doOk
    bumpKind*: BumpKind

func deriveNextVersion*(lastTag: string;
                        subjects: openArray[string];
                        bodies: openArray[string] = []): DeriveResult =
  ## Pure derivation: next version = f(lastTag, commits since lastTag).
  ## `bodies[i]` (when provided) pairs with `subjects[i]`.
  let base = parseSemVer(lastTag)
  if base.isNone:
    return DeriveResult(outcome: doBadTag)
  var kinds = newSeq[BumpKind](subjects.len)
  for i, s in subjects:
    let body = if i < bodies.len: bodies[i] else: ""
    kinds[i] = classifyCommit(s, body)
  let top = maxBump(kinds)
  if top == bkNone:
    return DeriveResult(outcome: doNoBump, bumpKind: bkNone)
  DeriveResult(outcome: doOk, version: bump(base.get(), top), bumpKind: top)
{.pop.}
