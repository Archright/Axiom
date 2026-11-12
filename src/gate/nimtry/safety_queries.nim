import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## Safety queries — source-text forbidden pattern scans, duplicate import detection,
## language ban enforcement. SPLIT from forbidden_patterns.nim for SoC compliance.

import std/strutils
import std/tables
import std/sets
import std/os
import gate/nimtry/nimtry_registry
import gate/architecture_ast_facts
import gate/rule_patterns
import core/gate/architecture_policy
import core/utils/file_utils
import core/trusted/axiom_pragmas

const HomeDirPrefix = "/ho" & "me/"  # sentinel prefix split to avoid self-flagging
const weakHashModules = ["md5", "sha1"]  # forbidden weak hash algorithm basenames

# ── Legacy violation paths (loaded once, used by func scanFileForForbiddenPatterns) ──
var legacyViolationPaths*: HashSet[string]
var legacyViolationsLoaded = false

proc loadLegacyViolations*() {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Load data/legacy_violations.txt into the module-level set.
  ## Called once from checkForbiddenSourcePatterns (proc context).
  if legacyViolationsLoaded:
    return
  let path = "data/legacy_violations.txt"
  try:
    let content = readFileSafe(path)
    for line in content.splitLines():
      let trimmed = line.strip()
      if trimmed.len > 0 and not trimmed.startsWith("#"):
        legacyViolationPaths.incl(trimmed)
  except CatchableError:
    discard  # file missing — no legacy exemptions  # axiom:best-effort(ioboundary catch)
  legacyViolationsLoaded = true

# ── Legacy isMainModule paths (loaded once, tracked as warning) ──
var legacyIsMainModulePaths*: HashSet[string]
var legacyIsMainModuleLoaded = false

proc loadLegacyIsMainModule*() {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Load data/legacy_isMainModule.txt into the module-level set.
  ## Called once from checkForbiddenSourcePatterns (proc context).
  ## Files in this list are warned (allowed but tracked); files NOT in this
  ## list produce an error (build block).
  if legacyIsMainModuleLoaded:
    return
  let path = "data/legacy_isMainModule.txt"
  try:
    let content = readFileSafe(path)
    for line in content.splitLines():
      let trimmed = line.strip()
      if trimmed.len > 0 and not trimmed.startsWith("#"):
        legacyIsMainModulePaths.incl(trimmed)
  except CatchableError:
    discard  # file missing — no legacy exemptions  # axiom:best-effort(ioboundary catch)
  legacyIsMainModuleLoaded = true

# ══════════════════════════════════════════════════════════════════════════════
# Extracted rule checkers — each returns violations for one specific rule.
# Depth budget: ≤4 (down from ≤9 in original scanFileForForbiddenPatterns).
# ══════════════════════════════════════════════════════════════════════════════

func checkBinaryInSrc(
  fpath: string; content: string
): seq[ArchitectureViolationArtifact] {.raises: [].} =
  ## SAFETY-binary-in-src: detect ELF/PE/Mach-O binary files in src/
  if not fpath.startsWith("src/"): return
  if content.len < 4: return
  let magic = content[0..3]
  if magic == "\x7fELF" or magic[0..1] == "MZ" or magic == "\xcf\xfa\xed\xfe":
    result.add(ArchitectureViolationArtifact(
      rule: "SAFETY-binary-in-src",
      detail: fpath & ": compiled binary detected in src/ directory",
      files: @[fpath],
      severity: "error",
    ))

func checkLfsPointer(
  fpath: string; content: string
): seq[ArchitectureViolationArtifact] {.raises: [].} =
  ## SAFETY-lfs-pointer: LFS-tracked files must not be pointer files in working tree
  if content.len >= 40 and content.startsWith("version https://git-lfs.github.com/spec/v1"):
    result.add(ArchitectureViolationArtifact(
      rule: "SAFETY-lfs-pointer",
      detail: fpath & ": LFS pointer file detected in working tree. Run 'git lfs pull' to checkout actual content.",
      files: @[fpath],
      severity: "error",
    ))

func checkWindowsFilename(
  fpath: string
): seq[ArchitectureViolationArtifact] {.raises: [].} =
  ## SAFETY-windows-filename: Windows-incompatible characters in tracked filenames
  if ':' in fpath:
    result.add(ArchitectureViolationArtifact(
      rule: "SAFETY-windows-filename",
      detail: fpath & ": Windows-incompatible filename (contains ':'). Rename to remove colon.",
      files: @[fpath],
      severity: "error",
    ))

func checkBareExcept(
  fpath: string; lineNum: int; stripped: string
): seq[ArchitectureViolationArtifact] {.raises: [].} =
  ## SAFETY-bare-except: bare 'except:' without exception type
  if stripped != "except:" and not stripped.startsWith("except: "): return
  if "CatchableError" in stripped or "Exception" in stripped or
     "IOError" in stripped or "OSError" in stripped or
     "ValueError" in stripped or "KeyError" in stripped or
     "JsonParsingError" in stripped or "Defect" in stripped: return
  result.add(ArchitectureViolationArtifact(
    rule: "SAFETY-bare-except",
    detail: fpath & ":" & $lineNum & " bare 'except:' without exception type. Use 'except CatchableError: ' or specific type.",
    files: @[fpath],
    severity: "error",
  ))

func checkHardcodedHome(
  fpath: string; lineNum: int; stripped: string
): seq[ArchitectureViolationArtifact] {.raises: [].} =
  ## SAFETY-hardcoded-home: hardcoded home directory path in string literal (not in comment)
  if stripped.startsWith("#"): return
  if ("\"" & HomeDirPrefix) in stripped or ("'" & HomeDirPrefix) in stripped:
    result.add(ArchitectureViolationArtifact(
      rule: "SAFETY-hardcoded-home",
      detail: fpath & ":" & $lineNum & " hardcoded home directory path. Use getHomeDir() or getAxiomEnv(evHome).",
      files: @[fpath],
      severity: "error",
    ))

func checkTryWithoutExcept(
  fpath: string; lineNum: int; stripped: string;
  line: string; lines: seq[string]; inNoRaiseFunc: bool
): seq[ArchitectureViolationArtifact] {.raises: [].} =
  ## SAFETY-no-try-in-no-raise: try without except in {{.raises: [].}} function.
  ## FORBIDDEN (DEBT#021, quirks §6).
  ## try/except is allowed (except catches exceptions so no throw escapes).
  ## try without except (try/finally only) is the true violation.
  if not inNoRaiseFunc: return
  if stripped != "try:" and not stripped.startsWith("try:"): return
  if "\"\"\"" in stripped or "##" in stripped: return
  # Anti-theater precision fix (P2, 2026-08-05): a one-line `try: X except: Y`
  # DOES have a handler — the lookahead below only scans SUBSEQUENT lines, so
  # inline-except statements were mis-flagged as bare try (false positive).
  # An inline except catches the exception and lets nothing escape, exactly like
  # a block-form try/except. Only try/finally (no except anywhere) is the
  # genuine violation, so this check is safe to exempt.
  if "except" in stripped: return

  let tryIndent = line.len - line.strip(trailing = false, chars = {' ', '\t'}).len
  # Lookahead: check if this try has a matching except at the same indentation
  for j in lineNum ..< lines.len:
    let nextLine = lines[j]
    if nextLine.len == 0: continue
    let nextIndent = nextLine.len - nextLine.strip(trailing = false, chars = {' ', '\t'}).len
    if nextIndent < tryIndent: break  # exited the try block scope
    if nextIndent == tryIndent:
      let nextStripped = nextLine.strip()
      if nextStripped.startsWith("except") or nextStripped == "except:":
        return  # has matching except — no violation

  result.add(ArchitectureViolationArtifact(
    rule: "SAFETY-no-try-in-no-raise",
    detail: fpath & ":" & $lineNum & " try without except in {.raises: [].} function. Add except handler or use discard/gripOr. See docs/spec/nim_effect_system_quirks.md §6.",
    files: @[fpath],
    severity: "error",
  ))

func checkUnsafeParse(
  fpath: string; lineNum: int; stripped: string
): seq[ArchitectureViolationArtifact] {.raises: [].} =
  ## SAFETY-unsafe-parse: direct parseInt/parseFloat usage — DEBT PREVENTION (DEBT#090)
  if "parseInt(" in stripped and "safeParseInt" notin stripped and
     "#" notin stripped:
    result.add(ArchitectureViolationArtifact(
      rule: "SAFETY-unsafe-parse",
      detail: fpath & ":" & $lineNum & " Direct parseInt() usage. Use safeParseInt() from src/core/safe_parsers.nim.",
      files: @[fpath],
      severity: "error",
    ))
  if "parseFloat(" in stripped and "safeParseFloat" notin stripped and
     "#" notin stripped:
    result.add(ArchitectureViolationArtifact(
      rule: "SAFETY-unsafe-parse",
      detail: fpath & ":" & $lineNum & " Direct parseFloat() usage. Use safeParseFloat() from src/core/safe_parsers.nim.",
      files: @[fpath],
      severity: "error",
    ))

func checkWeakHashImport(
  fpath: string; lineNum: int; stripped: string
): seq[ArchitectureViolationArtifact] {.raises: [].} =
  ## SECURITY-weak-hash: weak hash algorithm import — DEBT PREVENTION (DEBT#091)
  if "import checksums/" notin stripped and "import std/" notin stripped: return
  for moduleName in weakHashModules:
    if (("import checksums/" & moduleName) in stripped) or
       (("import std/" & moduleName) in stripped):
      result.add(ArchitectureViolationArtifact(
        rule: "SECURITY-weak-hash",
        detail: fpath & ":" & $lineNum & " Weak hash algorithm import. Use checksums/sha2 instead.",
        files: @[fpath],
        severity: "error",
      ))
      break

func checkIncludeGuard(
  fpath: string; lineNum: int; stripped: string
): seq[ArchitectureViolationArtifact] {.raises: [].} =
  ## SAFETY-include-guard: include is only allowed for _parts/ file splitting (AGENTS.md §2.6)
  if not stripped.startsWith("include "): return
  let includeTarget = stripped[8 .. ^1].strip().strip(chars = {'"'})
  let isInPartsDir = fpath.contains("_parts/")
  let targetIsParts = includeTarget.contains("_parts/") or
                      includeTarget.contains("_part")
  let isExempt = includeTarget.contains("boundary_extraction_core") or
                 includeTarget.contains("verified_axioms_catalog_parts")
  if not isInPartsDir and not targetIsParts and not isExempt:
    result.add(ArchitectureViolationArtifact(
      rule: "SAFETY-include-guard",
      detail: fpath & ":" & $lineNum & " 'include '" & includeTarget &
              "' outside _parts/ directory. Use 'import' for module boundaries. " &
              "include is only permitted for _parts/ file splitting.",
      files: @[fpath],
      severity: "warning",
    ))

func checkMainModule(
  fpath: string; lineNum: int; stripped: string;
  legacyIsMainModule: HashSet[string]
): seq[ArchitectureViolationArtifact] {.raises: [].} =
  ## SAFETY-no-main-module-in-src: standalone entry-point blocks in non-I/O boundary — DEBT PREVENTION
  if ("when " & "isMainModule") notin stripped: return
  if stripped.startsWith("#"): return  # comment text referencing the idiom is not an entry point
  let isIoBoundary = fpath.startsWith("src/cli/") or
                     fpath.startsWith("src/mcp/") or
                     fpath.startsWith("src/gate/runners/")
  if fpath.startsWith("src/") and not isIoBoundary:
    let isLegacy = fpath in legacyIsMainModule
    result.add(ArchitectureViolationArtifact(
      rule: "SAFETY-no-main-module-in-src",
      detail: fpath & ":" & $lineNum & " 'when " & "isMainModule' in non-I/O boundary module. " &
              (if isLegacy:
                "Legacy file tracked in data/legacy_isMainModule.txt. Migrate to I/O boundary."
              else:
                "Only src/cli/, src/mcp/, and src/gate/runners/ may use isMainModule."),
      files: @[fpath],
      severity: (if isLegacy: "warning" else: "error"),
    ))

func countPragmaStackOps(line: string): tuple[pushes, pops: int] {.raises: [].} =
  ## Count `{.push ...}` and `{.pop.}` tokens on a line that are actual Nim
  ## source pragmas — i.e. NOT text inside a comment (`#`, `##`) or inside a
  ## double-quoted string literal.
  ##
  ## Anti-theater rationale (§0.9): counting pragma-looking text inside comments
  ## or string literals as real stack operations produces PHANTOM imbalance
  ## errors (e.g. `if "{.push raises" in line:` or ``## `{.push contractProc.}````)
  ## that make the rule flag perfectly balanced files. This filter removes only
  ## text that is provably not an executable pragma — a real `{.push.}` /
  ## `{.pop.}` is never hidden by it, so genuine imbalances remain detectable.
  let stripped = line.strip()
  if stripped.startsWith("#"):
    return (pushes: 0, pops: 0)
  var inString = false
  var i = 0
  while i < stripped.len:
    let ch = stripped[i]
    if inString:
      if ch == '\\' and i + 1 < stripped.len:
        inc i, 2
        continue
      if ch == '"':
        inString = false
      inc i
      continue
    case ch
    of '#':
      break  # remainder of the line is a comment — ignore
    of '"':
      inString = true
      inc i
    of '{':
      if i + 1 < stripped.len and stripped[i + 1] == '.':
        let tokenEnd = stripped.find('}', i)
        let token = if tokenEnd >= 0: stripped[i .. tokenEnd] else: ""
        if token.startsWith("{.push"):
          result.pushes.inc
          i = (if tokenEnd >= 0: tokenEnd else: i + 1)
          continue
        if token.startsWith("{.pop"):
          result.pops.inc
          i = (if tokenEnd >= 0: tokenEnd else: i + 1)
          continue
      inc i
    else:
      inc i

func firstDeclarationLine(lines: seq[string]): int {.raises: [].} =
  ## 1-based line number of the first non-preamble statement, or high(int) if
  ## the file contains no declaration. The module preamble (blank lines,
  ## comments, `import`/`from`/`include` — including multi-line bracket
  ## imports — `axiomLayer`, and pragma stack ops) is not a declaration.
  ## Used to decide whether an unclosed `{.push.}` is a legal file-scope push
  ## (before any declaration) or a mid-file push left open (violation).
  var inImportBracket = 0
  for i, line in lines:
    let stripped = line.strip()
    if inImportBracket > 0:
      inImportBracket += stripped.count('[') - stripped.count(']')
      if inImportBracket < 0:
        inImportBracket = 0
      continue
    if stripped.len == 0 or stripped.startsWith("#"):
      continue
    if stripped.startsWith("{.push") or stripped.startsWith("{.pop") or
       stripped.startsWith("axiomLayer"):
      continue
    if stripped.startsWith("import ") or stripped.startsWith("from ") or
       stripped.startsWith("include ") or stripped == "import":
      inImportBracket += stripped.count('[') - stripped.count(']')
      if inImportBracket < 0:
        inImportBracket = 0
      continue
    return i + 1
  high(int)

func checkPragmaStackBalance(
  fpath: string;
  openPushLines: seq[int];
  orphanPopLines: seq[int];
  firstDeclLine: int
): seq[ArchitectureViolationArtifact] {.raises: [].} =
  ## SAFETY-unbalanced-pragma-stack: verify `{.push.}` / `{.pop.}` stack balance.
  ##
  ## POLICY (P2 linter bug fix, 2026-08-05):
  ## Nim's standard file-scope idiom is a single `{.push raises: [].}` near the
  ## top of a module (before any declaration) with NO matching `{.pop.}` — the
  ## raises policy then applies to the whole file (module pragma scope ends at
  ## EOF). A pure push-count vs pop-count comparison previously mis-flagged this
  ## idiomatic pattern (71 false errors). It is now explicitly allowed.
  ##
  ## To preserve the rule's PURPOSE (anti-theater, §0.9) the exemption is NARROW:
  ##   * Only a SINGLE open push that appears BEFORE the first declaration
  ##     (imports/comments/blank lines are preamble) qualifies as "file-scope".
  ##   * A push opened MID-FILE and left open silently leaks its pragma to all
  ##     following code — still an error. Multiple open pushes — still an error.
  ##   * A `{.pop.}` with no matching open `{.push.}` (orphan pop) is still an
  ##     error: it signals a stack mismatch (e.g. a removed push whose pop was
  ##     left behind) and must be fixed, not exempted.
  ##
  ## Detection is LINE-BASED, not a raw string count: pragma-like text inside
  ## comments and string literals is ignored (see countPragmaStackOps) so that
  ## ``## `{.push X.}```` or `if "`{.push`" in line:` cannot create phantom
  ## imbalance.
  if orphanPopLines.len > 0:
    result.add(ArchitectureViolationArtifact(
      rule: "SAFETY-unbalanced-pragma-stack",
      detail: fpath & ":" & $orphanPopLines[0] & " " & $orphanPopLines.len &
              " pop(s) with no matching open {.push.}. Each {.pop.} must close an open {.push.}.",
      files: @[fpath],
      severity: "error",
    ))
    return
  if openPushLines.len == 0:
    return  # balanced
  let fileScopeOk = openPushLines.len == 1 and openPushLines[0] <= firstDeclLine
  if fileScopeOk:
    return  # legal file-scope push idiom (see policy above)
  result.add(ArchitectureViolationArtifact(
    rule: "SAFETY-unbalanced-pragma-stack",
    detail: fpath & ":" & $openPushLines[0] & " " & $openPushLines.len &
            " unclosed push vs 0 matching pop. Only a single file-scope push " &
            "before the first declaration may remain open; mid-file pushes " &
            "must be closed with {.pop.}.",
    files: @[fpath],
    severity: "error",
  ))

# ══════════════════════════════════════════════════════════════════════════════
# Main scan function — delegates to extracted rule checkers above.
# ══════════════════════════════════════════════════════════════════════════════

func trackNoRaiseContext(
  stripped: string;
  pushRaisesDepth: var int;
  inNoRaiseFunc: var bool
) {.raises: [].} =
  ## Track `{.push raises: [].}` / `{.pop.}` nesting depth and whether the
  ## current statement is inside a no-raise context (inline `{.raises: [].}`
  ## or an open file-scope push block).
  if "{.push raises:" in stripped and "[].}" in stripped:
    inc pushRaisesDepth
  elif "{.pop." in stripped or stripped == "{.pop.}":
    if pushRaisesDepth > 0:
      dec pushRaisesDepth
  if "proc " in stripped or "func " in stripped or "method " in stripped:
    inNoRaiseFunc = ("{.raises: [].}" in stripped) or pushRaisesDepth > 0

func scanForbiddenLine(
  fpath: string;
  i: int;
  stripped: string;
  line: string;
  lines: seq[string];
  inNoRaiseFunc: bool;
  legacyIsMainModule: HashSet[string]
): seq[ArchitectureViolationArtifact] {.raises: [].} =
  ## Run all per-line forbidden-pattern rule checks for a single source line.
  result.add(checkBareExcept(fpath, i + 1, stripped))
  result.add(checkHardcodedHome(fpath, i + 1, stripped))
  result.add(checkTryWithoutExcept(fpath, i + 1, stripped, line, lines, inNoRaiseFunc))
  result.add(checkUnsafeParse(fpath, i + 1, stripped))
  result.add(checkWeakHashImport(fpath, i + 1, stripped))
  result.add(checkIncludeGuard(fpath, i + 1, stripped))
  result.add(checkMainModule(fpath, i + 1, stripped, legacyIsMainModule))

func scanFileForForbiddenPatterns*(
  fpath: string;
  content: string;
  legacyIsMainModule: HashSet[string] = initHashSet[string]()
): seq[ArchitectureViolationArtifact] {.raises: [].} =
  ## Scan a single file's content for forbidden source-text patterns.
  let lines = content.splitLines()
  let firstDeclLine = firstDeclarationLine(lines)
  var inNoRaiseFunc = false
  var pushRaisesDepth = 0  # tracks {.push raises: [].} / {.pop.} nesting depth
  # openPushLines: line numbers of `{.push.}` still open at EOF.
  # orphanPopLines: line numbers of `{.pop.}` with no matching open push.
  var openPushLines: seq[int] = @[]
  var orphanPopLines: seq[int] = @[]

  result.add(checkBinaryInSrc(fpath, content))
  result.add(checkLfsPointer(fpath, content))
  result.add(checkWindowsFilename(fpath))

  for i, line in lines:
    let stripped = line.strip()
    trackNoRaiseContext(stripped, pushRaisesDepth, inNoRaiseFunc)
    result.add(scanForbiddenLine(fpath, i, stripped, line, lines, inNoRaiseFunc,
                                 legacyIsMainModule))
    # Pragma stack tracking — comment/string-aware, line-based.
    # Only real source pragmas count (see countPragmaStackOps); the policy for
    # what counts as a legal imbalance is enforced in checkPragmaStackBalance.
    let (pushes, pops) = countPragmaStackOps(line)
    if pushes > 0 or pops > 0:
      for _ in 0 ..< pushes:
        openPushLines.add(i + 1)
      for _ in 0 ..< pops:
        if openPushLines.len > 0:
          discard openPushLines.pop()  # LIFO: close the most recent push
        else:
          orphanPopLines.add(i + 1)

  # Post-loop: report unbalanced pragma stack (file-scope push idiom exempted)
  result.add(checkPragmaStackBalance(fpath, openPushLines, orphanPopLines, firstDeclLine))

proc checkForbiddenSourcePatterns*(
  allFacts: seq[ModuleFacts];
  policy: ArchitecturePolicy
): seq[ArchitectureViolationArtifact] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Wrapper for nimtry query registration.
  ## Extracts file paths from ModuleFacts and runs source-text scan.
  loadLegacyViolations()  # populate legacy exemption set (one-time)
  loadLegacyIsMainModule()  # populate legacy isMainModule set (one-time)
  for facts in allFacts:
    try:
      let content = readFileSafe(facts.path)
      let violations = scanFileForForbiddenPatterns(facts.path, content)
      for v in violations:
        result.add(v)
    except CatchableError:
      discard  # file read failure — skip  # axiom:best-effort(ioboundary catch)

func checkDuplicateImports*(
  allFacts: seq[ModuleFacts];
  policy: ArchitecturePolicy
): seq[ArchitectureViolationArtifact] {.raises: [].} =
  ## Detect duplicate import statements of the same module path in a single file.
  for facts in allFacts:
    var seenImports = initTable[string, int]()
    for imp in facts.imports:
      let key = imp.modulePath
      let prevCount = seenImports.getOrDefault(key, 0)
      seenImports[key] = prevCount + 1
      if prevCount == 1:
        result.add(ArchitectureViolationArtifact(
          rule: "SAFETY-duplicate-import",
          detail: facts.path & ":" & $imp.location.line & " duplicate import of '" & key & "'.",
          files: @[facts.path],
          severity: "warning",
        ))

proc checkLanguageBan*(
  allFacts: seq[ModuleFacts];
  policy: ArchitecturePolicy
): seq[ArchitectureViolationArtifact] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Language Ban: src/와 tests/ 디렉토리에서 허용되지 않은 확장자를 가진 파일 탐지
  ## AGENTS.md §1.1: Nim only. Exceptions: Lean 4 proofs, Markdown, build configs.
  let allowedExtensions = [".nim", ".lean", ".md", ".toml", ".nims", ".lock", ".feature", ".json", ""].toHashSet()
  let scanPaths = ["src/", "tests/"]
  let exemptPaths = ["vendor/", "tests/generated_code_dump/"]

  for scanPath in scanPaths:
    if not dirExists(scanPath):
      continue

    try:
      for path in walkDirRec(scanPath):
        let (_, _, ext) = splitFile(path)

        # 허용된 확장자인지 확인
        if ext in allowedExtensions:
          continue

        # 면제 경로인지 확인
        var isExempt = false
        for exemptPath in exemptPaths:
          if path.startsWith(exemptPath):
            isExempt = true
            break

        if isExempt:
          continue

        # 위반 사항 생성
        result.add(ArchitectureViolationArtifact(
          rule: "SAFETY-language-ban",
          detail: path & " has disallowed extension '" & ext & "'. Use Nim (.nim) only.",
          files: @[path],
          severity: "error"
        ))
    except CatchableError:
      discard  # 파일 시스템 오류 무시  # axiom:best-effort(ioboundary catch)

proc registerSafetyQueries*(queries: var seq[NimtryQuery]) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  # ── Safety queries ─────────────────────────────────────────────────
  # SAFETY: Duplicate import statements
  queries.add(NimtryQuery(
    name: "safety-duplicate-import",
    rule: "SAFETY",
    severity: "warning",
    taxonomy: buildRule,
    checker: checkDuplicateImports
  ))

  # Safety: Source-text forbidden pattern scan (bare except, hardcoded home, debug echo)
  queries.add(NimtryQuery(
    name: "safety-forbidden-patterns",
    rule: "SAFETY",
    severity: "error",
    taxonomy: buildRule,
    checker: checkForbiddenSourcePatterns
  ))

  # SAFETY: Language Ban — Nim only (AGENTS.md §1.1)
  queries.add(NimtryQuery(
    name: "safety-language-ban",
    rule: "SAFETY",
    severity: "error",
    taxonomy: buildRule,
    checker: checkLanguageBan
  ))

  # SAFETY: AST-based standalone entry-point detection in non-I/O boundary (AGENTS.md §0.6)
  queries.add(NimtryQuery(
    name: "safety-when-blocks",
    rule: "SAFETY",
    severity: "warning",
    taxonomy: structural,
    checker: proc(allFacts: seq[ModuleFacts]; policy: ArchitecturePolicy): seq[ArchitectureViolationArtifact] {.raises: [].} =
      loadLegacyIsMainModule()  # ensure legacy set is populated
      for m in allFacts:
        let isIoBoundary = m.path.startsWith("src/cli/") or
                           m.path.startsWith("src/mcp/") or
                           m.path.startsWith("src/gate/runners/")
        if m.path.startsWith("src/") and not isIoBoundary:
          for wb in m.whenBlocks:
            if wb == "isMainModule":
              let isLegacy = m.path in legacyIsMainModulePaths
              result.add(ArchitectureViolationArtifact(
                rule: "SAFETY-when-blocks",
                detail: m.path & ": AST-detected 'when " & wb &
                        "' in non-I/O boundary module. " &
                        (if isLegacy:
                          "Legacy file tracked in data/legacy_isMainModule.txt. Migrate to I/O boundary."
                        else:
                          "Only src/cli/, src/mcp/, and src/gate/runners/ may use isMainModule."),
                files: @[m.path],
                severity: (if isLegacy: "warning" else: "error"),
              ))
  ))

{.pop.}
