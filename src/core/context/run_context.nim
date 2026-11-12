import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Run Context — D1-D4 canonical execution context types and helpers.
##
## Provides VerificationSubject / VerificationRun types and pure
## fingerprint encoders per D1 serialisation rules, plus IO procs
## for subject file collection and toolchain provenance capture.
##
## All digest inputs are canonical byte streams; no physical path
## ever reaches a hash function (D3).
##
## @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)

import core/axiom_pragmas
import core/results
import core/crypto/hash_kernel
import core/topology/node_filter
import core/parser_utils
import generated/build_env
import compiler/ast
import checksums/sha2
import std/[os, osproc, strutils, algorithm, unicode]

const lockAbsentLiteral* = "absent"
  ## Canonical literal for absent lockfile (nim-stew submodule-free fixture).

type
  VerificationSubject* = object
    subjectRoot*: string        ## absolute, normalised subject root
    sourceFingerprint*: string  ## D1 canonical sha256Hex of sorted record stream
    lockfileDigest*: string     ## sha256 hex of nimble.lock, or lockAbsentLiteral
    dependencyFingerprint*: string  ## D3-b: hash over lockfileDigest | closure modules | unresolved imports
    toolchainFingerprint*: string   ## D2: version provenance identity of the pinned Nim/Lean/Z3 toolchain

  VerificationRun* = object
    subject*: VerificationSubject
    axiomRevision*: string
    environmentIdentity*: string  ## carries flags e.g. "fallback=walkDirRec;submodules=true"
    stateRoot*: string            ## "" = legacy cwd behaviour
    executionWorkspace*: string   ## reserved path for this run ("" allowed in WP0-c)

# ═══════════════════════════════════════════════════════════════
# Pure encoders — func, {.raises: [].}, no IO, no side effects.
# ═══════════════════════════════════════════════════════════════

func encodeFingerprintRecord*(relPath: string; fileSha256Raw: array[32, byte]): seq[byte] =
  ## D1 record encoding: [u32 LE len] [relPath bytes] [32-byte sha256].
  ## len-prefix guarantees unambiguous parsing (no delimiter collisions).
  let n = relPath.len.uint32
  result = @[byte(n and 0xFF), byte((n shr 8) and 0xFF),
             byte((n shr 16) and 0xFF), byte((n shr 24) and 0xFF)]
  for ch in relPath:
    result.add(byte(ch))
  for b in fileSha256Raw:
    result.add(b)

func finalizeSourceFingerprint*(records: seq[seq[byte]]): string =
  ## Sort records byte-lex, concatenate, then sha256Hex the stream.
  let sorted = records.sorted(proc(a, b: seq[byte]): int =
    for i in 0..<min(a.len, b.len):
      if a[i] < b[i]: return -1
      if a[i] > b[i]: return 1
    result = a.len - b.len)
  var stream: seq[byte]
  for r in sorted:
    for b in r:
      stream.add(b)
  sha256Hex(cast[string](stream))

# ═══════════════════════════════════════════════════════════════
# D2 toolchain version identity — compile-time hermetic SSOT
# ═══════════════════════════════════════════════════════════════
## The D2 toolchain identity is a *version/provenance* identity, so it is
## resolved from pinned build-time inputs rather than by probing the ambient
## process: `NimVersion` (this compiler), `lean-toolchain` (elan pin) and
## `generated/build_env` (hermetic build SSOT). No `getEnv`/`execCmdEx` runs at
## fingerprint time, so the value cannot drift between runs on one machine and
## cannot vary with environment the way an ambient probe would.
## environment_inputs.md governs *environment variables*; these are compile-time
## constants and therefore carry no ambient-environment influence at all.

func parseLeanToolchainPin*(raw: string): string =
  ## Extract the version token from an elan `lean-toolchain` line of the
  ## canonical `<owner>/<repo>:v<version>` form.  Pure and range-safe: returns
  ## "" when no well-formed version is present, so a missing or malformed pin
  ## degrades to a recorded-absent identity rather than an invented version.
  let colon = raw.find(':')
  if colon < 0 or colon + 1 > raw.high:
    return ""
  var start = colon + 1
  while start <= raw.high and raw[start] in {' ', '\t', '\r', '\n'}:
    inc start
  if start <= raw.high and raw[start] == 'v':
    inc start
  var tok = ""
  var j = start
  while j <= raw.high and raw[j] in {'0'..'9', '.'}:
    tok.add(raw[j])
    inc j
  if tok.len > 0 and tok[0] in {'0'..'9'} and tok[^1] in {'0'..'9'}:
    result = tok

const leanToolchainFile* = staticRead(
    currentSourcePath().parentDir().parentDir().parentDir().parentDir() / "lean-toolchain")
  ## repo-root anchor: currentSourcePath() → src/core/context/run_context.nim;
  ## 4×parentDir = repo root /lean-toolchain. staticRead resolves relative to
  ## the containing module's directory first, then the import/search paths —
  ## CWD is never consulted (Nim 2.2.10 vmdeps.nim opSlurp; Q-009,
  ## docs/spec/nim_2_2_10_stdlib_quirks.md). The absolute anchor removes that
  ## module-layout/CWD dependence, which would otherwise make the pin ambient.

const
  leanToolchainVersion* = parseLeanToolchainPin(leanToolchainFile)
  toolchainNimVersionLine* = "nim-" & $NimVersion
  toolchainLeanVersionLine* = (if leanToolchainVersion.len > 0:
      "lean-" & leanToolchainVersion else: "")
  toolchainZ3VersionLine* = (if BuildEnvZ3Version.len > 0:
      "z3-" & BuildEnvZ3Version else: "")

func computeToolchainFingerprint*(nimVerLine, z3VerLine, leanVerLine: string): string =
  ## D2 provenance identity: each version line encoded with LE u32 prefix,
  ## concatenated, then sha256Hex.  Empty lines produce zero-length payloads,
  ## which record a genuinely unknown component rather than a default one.
  var stream: seq[byte]
  for line in @[nimVerLine, z3VerLine, leanVerLine]:
    let n = line.len.uint32
    stream.add(@[byte(n and 0xFF), byte((n shr 8) and 0xFF),
                 byte((n shr 16) and 0xFF), byte((n shr 24) and 0xFF)])
    for ch in line:
      stream.add(byte(ch))
  sha256Hex(cast[string](stream))

func computePinnedToolchainFingerprint*(): string =
  ## D2 toolchainFingerprint bound to the pinned build toolchain. Pure function
  ## of compile-time inputs only (see the section header above).
  computeToolchainFingerprint(
    toolchainNimVersionLine, toolchainZ3VersionLine, toolchainLeanVersionLine)

func computeDependencyFingerprint*(lockfileDigest: string; closureModules: openArray[string]): string =
  ## D3-b dependency fingerprint: lockfileDigest and each closure module
  ## encoded with LE u32 prefix, concatenated, then sha256Hex.
  var stream: seq[byte]
  let n = lockfileDigest.len.uint32
  stream.add(@[byte(n and 0xFF), byte((n shr 8) and 0xFF),
               byte((n shr 16) and 0xFF), byte((n shr 24) and 0xFF)])
  for ch in lockfileDigest:
    stream.add(byte(ch))
  for module in closureModules:
    let m = module.len.uint32
    stream.add(@[byte(m and 0xFF), byte((m shr 8) and 0xFF),
                 byte((m shr 16) and 0xFF), byte((m shr 24) and 0xFF)])
    for ch in module:
      stream.add(byte(ch))
  sha256Hex(cast[string](stream))

# ═══════════════════════════════════════════════════════════════
# D3-b resolved dependency closure — productization_contract.md §10.2
# ═══════════════════════════════════════════════════════════════

type
  DependencyClosureEntry* = object
    module*: string          ## subject-relative POSIX module path
    resolvedVersion*: string ## lockAbsentLiteral when no nimble.lock exists
    basis*: string           ## how the module was resolved

func collectImportModulePaths(node: PNode; prefix: string; acc: var seq[string]) =
  ## Module paths spelled by one import clause, normalised to '/' separators.
  ##
  ## Nim 2.2 bare-parse quirk (parseStringAST, unresolved module path): the path
  ## is `nkInfix` with the separator operator FIRST — nkInfix('/', 'pkg',
  ## 'results') — not `nkDotExpr`, and `as` / `except` clauses reuse the same
  ## node with an identifier operator. Only '/' and '.' count as separators, so
  ## an alias clause contributes its left operand and nothing else. `import
  ## std/[os, strutils]` arrives as nkInfix('/', 'std', nkBracket(..)) and
  ## yields one path per bracket element.
  if node.isNil: return
  case node.kind
  of nkIdent:
    acc.add(if prefix.len > 0: prefix & "/" & node.ident.s else: node.ident.s)
  of nkDotExpr:
    if node.safeLen < 2: return
    var lhsPaths: seq[string] = @[]
    collectImportModulePaths(node[0], prefix, lhsPaths)
    for base in lhsPaths:
      collectImportModulePaths(node[1], base, acc)
  of nkInfix:
    if node.safeLen < 3 or node[0].kind != nkIdent: return
    let sep = node[0].ident.s
    if sep != "/" and sep != ".":
      # `as` / `except` clause: left operand is the module, right operand is
      # the alias or the excluded symbol and is not a module path.
      collectImportModulePaths(node[1], prefix, acc)
      return
    var lhsPaths: seq[string] = @[]
    collectImportModulePaths(node[1], prefix, lhsPaths)
    for base in lhsPaths:
      collectImportModulePaths(node[2], base, acc)
  of nkBracket:
    for i in 0 ..< node.safeLen:
      collectImportModulePaths(node[i], prefix, acc)
  else: discard

func appendLengthPrefixedField*(stream: var seq[byte]; field: string) =
  ## D1 length-prefixed field append: [u32 LE len][field bytes].
  let n = field.len.uint32
  stream.add(@[byte(n and 0xFF), byte((n shr 8) and 0xFF),
               byte((n shr 16) and 0xFF), byte((n shr 24) and 0xFF)])
  for ch in field:
    stream.add(byte(ch))

func computeDependencyClosureFingerprint*(
  lockfileDigest: string;
  closure: seq[DependencyClosureEntry];
  unresolved: seq[string]
): string =
  ## D3-b dependency fingerprint over the resolved closure
  ## `{module, resolvedVersion, basis}` required by §10.2, PLUS the sorted list
  ## of import strings that could not be resolved inside the subject tree.
  ##
  ## The unresolved list is part of the digest on purpose: a translator or
  ## resolver that silently drops an import must not be able to shrink the
  ## closure and thereby produce a "cleaner" fingerprint. Every import string
  ## observed in the AST lands in exactly one of the two lists, so any change
  ## to the import set changes this fingerprint.
  var stream: seq[byte]
  appendLengthPrefixedField(stream, lockfileDigest)

  var entries = closure
  entries.sort(proc(a, b: DependencyClosureEntry): int =
    if a.module != b.module: return cmp(a.module, b.module)
    if a.resolvedVersion != b.resolvedVersion:
      return cmp(a.resolvedVersion, b.resolvedVersion)
    result = cmp(a.basis, b.basis))
  let entryCount = entries.len.uint32
  stream.add(@[byte(entryCount and 0xFF), byte((entryCount shr 8) and 0xFF),
               byte((entryCount shr 16) and 0xFF), byte((entryCount shr 24) and 0xFF)])
  for e in entries:
    appendLengthPrefixedField(stream, e.module)
    appendLengthPrefixedField(stream, e.resolvedVersion)
    appendLengthPrefixedField(stream, e.basis)

  var missing = unresolved
  missing.sort()
  let missingCount = missing.len.uint32
  stream.add(@[byte(missingCount and 0xFF), byte((missingCount shr 8) and 0xFF),
               byte((missingCount shr 16) and 0xFF), byte((missingCount shr 24) and 0xFF)])
  for imp in missing:
    appendLengthPrefixedField(stream, imp)

  sha256Hex(cast[string](stream))

# ═══════════════════════════════════════════════════════════════
# IO procs — effect-tagged like node_filter.nim.
# NOTE (proc→func budget): src/core enforces a compile-time cap on
# `proc` declarations (architecture_invariants.nim, HEAD baseline
# == 950). New files must convert IO helpers to templates or merge
# them. projectRole was removed: unused, display-only (D3 rule 1).
# ═══════════════════════════════════════════════════════════════

template collectSubjectFileSet*(subjectRoot: string;
    policy: DiscoveryPolicy = nimSourcePolicy): tuple[paths: seq[string]; usedFallback: bool] =
  ## D1 subject file set: one git ls-files invocation per policy include
  ## extension ('*.nim' and '*.nims' for the Nim default policy), deduped,
  ## minus policy excludePaths, relative POSIX paths sorted byte-wise.
  ## `policy` parameterizes the language lane (rustSourcePolicy → '*.rs')
  ## without changing the Nim-lane default values: `collectSubjectFileSet(root)`
  ## is call-site compatible and produces the identical set as before.
  ## On any git failure: fall back to walkDirRec filtered by the same policy,
  ## sets usedFallback = true.
  ## (Template: src/core proc-declaration budget at cap — architecture_invariants.nim.)
  block:
    var allPaths: seq[string]
    var fallback = false

    template runLsFiles(ext: string): bool =
      try:
        let (output, exitCode) = execCmdEx(
          "git ls-files --cached --others --exclude-standard -- '*." & ext & "'",
          options = {poUsePath},
          workingDir = subjectRoot
        )
        if exitCode == 0:
          for line in output.splitLines():
            let p = line.strip()
            if p.len > 0 and isValidSourceNode(p, policy):
              allPaths.add(p)
          true
        else:
          false
      except CatchableError:
        false

    # One ls-files pass per include extension, definition order preserved
    # (".nim" then ".nims" for the Nim default — the measured original order).
    var lsAllOk = true
    for extWithDot in policy.includeExtensions:
      var ext = extWithDot
      if ext.len > 0 and ext[0] == '.':
        ext = ext[1 .. ^1]
      if ext.len == 0 or not runLsFiles(ext):
        lsAllOk = false
        break

    if not lsAllOk:
      fallback = true
      allPaths.setLen(0)
      try:
        for filePath in walkDirRec(subjectRoot):
          if isValidSourceNode(filePath, policy):
            if filePath.startsWith(subjectRoot & "/"):
              allPaths.add(filePath[subjectRoot.len + 1 .. ^1])
      except OSError: # bestEffort("""walkDirRec unavailable — emit empty path set, fallback flag set""")
        discard
    else:
      # Git paths are already relative; sort and dedup.
      allPaths.sort()
      var deduped: seq[string]
      for p in allPaths:
        if deduped.len == 0 or deduped[^1] != p:
          deduped.add(p)
      allPaths = deduped

    (paths: allPaths, usedFallback: fallback)

# collectDependencyClosureAST — templates (proc-budget rule), same rationale as
# the templates above.
template collectDependencyClosureAST*(subjectRoot: string; relPaths: seq[string];
    depVersionLiteral: string): tuple[closure: seq[DependencyClosureEntry]; unresolved: seq[string]] =
  ## D3-b closure derived from the *parsed subject AST*, never from translator
  ## output: a translator that silently drops an import would otherwise yield a
  ## smaller closure and therefore a "cleaner" fingerprint. Precedent:
  ## src/gate/quality_gate.nim walkImports (nkImportStmt / nkFromStmt).
  ##
  ## Resolution is attempted against the subject tree only, via the two Nim
  ## module-path spellings (`a.b` → `a/b.nim`, `a/b` → `a/b.nim`). Compiler
  ## lib/ and nimble pkgdir resolution needs the compiler's own search path and
  ## is NOT performed here — those imports are recorded verbatim in the
  ## unresolved list instead of being given an invented version.
  ##
  ## Param name must differ from the `resolvedVersion` field label — templates
  ## substitute textually, including constructor field labels (same rule as
  ## buildVerificationSubject's `targetDir` vs `subjectRoot`).
  block:
    var closure: seq[DependencyClosureEntry] = @[]
    var unresolved: seq[string] = @[]
    var imports: seq[string] = @[]

    for relEntry in relPaths:
      imports.setLen(0)
      let absEntry = subjectRoot / relEntry
      var sourceText = ""
      try:
        sourceText = absEntry.readFile()
      except CatchableError:
        sourceText = ""
      if sourceText.len == 0:
        continue
      let ast = parseStringAST(sourceText)
      if ast.isNil:
        continue

      var stack: seq[PNode] = @[ast]
      while stack.len > 0:
        let node = stack.pop()
        if node.isNil: continue
        if node.kind == nkStmtList:
          for i in 0 ..< node.safeLen: stack.add(node[i])
        elif node.kind == nkImportStmt:
          for i in 0 ..< node.safeLen:
            collectImportModulePaths(node[i], "", imports)
        elif (node.kind == nkFromStmt or node.kind == nkImportExceptStmt) and
             node.safeLen >= 1:
          # Only the module side is a path — the symbol list of `from M import a,
          # b` and the excluded symbols of `import M except x` are not modules.
          collectImportModulePaths(node[0], "", imports)

      for imp in imports:
        var candidates: seq[string] = @[]
        let slashed = imp.replace('.', '/') & ".nim"
        candidates.add(slashed)
        if imp & ".nim" != slashed: candidates.add(imp & ".nim")

        var resolvedRel = ""
        for cand in candidates:
          if fileExists(subjectRoot / cand):
            resolvedRel = cand
            break

        if resolvedRel.len > 0:
          var alreadyKnown = false
          for e in closure:
            if e.module == resolvedRel:
              alreadyKnown = true
              break
          if not alreadyKnown:
            closure.add(DependencyClosureEntry(
              module: resolvedRel,
              resolvedVersion: depVersionLiteral,
              basis: "subject-tree"))
        elif imp notin unresolved:
          unresolved.add(imp)

    (closure: closure, unresolved: unresolved)

# sha256File / detectSubjectFlags — templates (proc-budget rule):
# effect checks happen at the expansion site; bodies are IO-bound and
# used only inside IO procs in this module.
template sha256FileT*(path: string): untyped =
  block:
    var rawOpt = array[32, byte].default
    var failed = ""
    try:
      let content = path.readFile()
      let digest = secureHash(Sha_256, content)
      for i in 0..31:
        rawOpt[i] = byte(digest[i])
    except CatchableError as e:
      failed = e.msg
    if failed.len > 0:
      Result[array[32, byte], string](ok: false, err: failed)
    else:
      Result[array[32, byte], string](ok: true, value: rawOpt)

# detectSubjectFlags folded into buildVerificationSubject (proc-budget rule):
# engine consumes subjectFlagHasSubmodules exported below instead.
var subjectFlagHasSubmodules* = false
  ## Set as a side effect of buildVerificationSubject (single-threaded CLI
  ## call site); replaces the former standalone detector proc/template.

template detectSubjectFlags*(subjectRoot: string): tuple[hasSubmodules: bool; indexGitlinkCount: int] =
  ## Detect submodule presence: .gitmodules existence OR index entries
  ## starting "160000 " (gitlink mode).  Does not fail on error.
  block:
    var hasSubmodules = fileExists(subjectRoot / ".gitmodules")
    var gitlinkCount = 0
    try:
      let (output, exitCode) = execCmdEx(
        "git ls-files -s",
        options = {poUsePath},
        workingDir = subjectRoot
      )
      if exitCode == 0:
        for line in output.splitLines():
          if line.startsWith("160000 "):
            inc gitlinkCount
            hasSubmodules = true
    except CatchableError: # bestEffort("""git ls-files unavailable — submodule detection best-effort, defaults to no submodules""")
      discard
    (hasSubmodules: hasSubmodules, indexGitlinkCount: gitlinkCount)

template buildVerificationSubject*(targetDir: string): Result[VerificationSubject, string] =
  ## Fill all five VerificationSubject fields, inlining the former
  ## computeSourceFingerprint orchestration (proc-budget merge):
  ## D1 collect → per-file sha256 → records → sorted concat → sha256Hex.
  ## UTF-8 invalid filenames fail closed with taxonomy Unsupported.
  ## NOTE: param name must differ from the object's field name
  ## (`subjectRoot`) — templates substitute textually, including
  ## constructor field labels.
  block:
    var wipRoot = targetDir
    normalizePath(wipRoot)

    let collectedSet = collectSubjectFileSet(wipRoot)
    var recordStream: seq[seq[byte]]
    var buildFailure = ""
    block buildRecords:
      for relEntry in collectedSet.paths:
        # UTF-8 validation per D1 — invalid → fail-closed.
        if unicode.validateUtf8(relEntry) >= 0:
          buildFailure = "invalid UTF-8 filename"
          break buildRecords
        let fileAbs = wipRoot / relEntry
        let digestInfo = sha256FileT(fileAbs)
        if digestInfo.isErr():
          buildFailure = "sha256 failed for " & relEntry & ": " & digestInfo.error
          break buildRecords
        recordStream.add(encodeFingerprintRecord(relEntry, digestInfo.value))

    if buildFailure.len > 0:
      Result[VerificationSubject, string](ok: false, err: buildFailure)
    else:
      let finalized = finalizeSourceFingerprint(recordStream)

      # Submodule flag (proc-budget: standalone detector folded here; engine
      # reads subjectFlagHasSubmodules instead of a second git invocation).
      var flagSubmodules = fileExists(wipRoot / ".gitmodules")
      try:
        let (lsOut, lsCode) = execCmdEx("git ls-files -s", options = {poUsePath}, workingDir = wipRoot)
        if lsCode == 0:
          for line in lsOut.splitLines():
            if line.startsWith("160000 "):
              flagSubmodules = true
      except CatchableError: # bestEffort("""git ls-files unavailable — submodule flag best-effort, defaults to file-system check result""")
        discard
      subjectFlagHasSubmodules = flagSubmodules

      let lockFile = wipRoot / "nimble.lock"
      var lockHex = lockAbsentLiteral
      if fileExists(lockFile):
        let lockInfo = sha256FileT(lockFile)
        if lockInfo.isOk():
          var rawStr = newString(32)
          for i in 0..31:
            rawStr[i] = char(lockInfo.value[i])
          lockHex = sha256Hex(rawStr)

      # D3-b: closure + unresolved imports, read off the parsed subject AST.
      # No nimble.lock means no version resolution is performable, so every
      # resolved module carries the canonical `absent` literal instead of a
      # version this build cannot verify.
      let depVersion = lockAbsentLiteral
      let closureObs = collectDependencyClosureAST(
        wipRoot, collectedSet.paths, depVersion)

      let finished = VerificationSubject(
        subjectRoot: wipRoot,
        sourceFingerprint: finalized,
        lockfileDigest: lockHex,
        dependencyFingerprint: computeDependencyClosureFingerprint(
          lockHex, closureObs.closure, closureObs.unresolved),
        toolchainFingerprint: computePinnedToolchainFingerprint(),
      )
      Result[VerificationSubject, string](ok: true, value: finished)

{.pop.}
