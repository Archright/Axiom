import core/trusted/layer_declaration
axiomLayer "domain"
import std/[os, strutils]
import macros
import core/axiom_pragmas
import core/utils/repo_root

const
  CastDocAnnotation = "## [SEE: nim_effect_system_quirks"
  CastDocPattern = "cast(noSideEffect)"
  EffectHintsLock = "src/gate/architecture_policy.lock"
  ShieldModules: array[2, string] = ["stdlib_shield.nim", "effect_shim.nim"]
  FfiPatterns: array[4, string] = ["importc", "importcpp", "dynlib", "compile"]

const
  CompetingSsotFiles = ["CONTEXT.md", "POLICY.md", "RULES.md"]

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc findRepoRootCt*(): string {.raises: [].} =
  var dir = currentSourcePath().parentDir()
  for _ in 0 .. 24:
    if fileExists(dir / axiomRoot):
      return dir
    let p = dir.parentDir()
    if p == dir:
      break
    dir = p
  dir

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func fileHasFfiPragma*(content: string): bool {.raises: [].} =
  for line in content.splitLines():
    for pat in FfiPatterns:
      if pat in line:
        return true
  false

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func isShieldModule*(modulePath: string): bool {.raises: [].} =
  let (_, _, name) = splitFile(modulePath)
  for s in ShieldModules:
    if name == s:
      return true
  false

# ── Persistent checks ────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc runCastDocScan*(repoRoot: string): seq[string] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  for path in walkDirRec(repoRoot / "src", yieldFilter = {pcFile}):
    if path.endsWith(".nim") and not path.contains("axiom_ast_lint"):
      let content = readFile(path)
      let lines = content.splitLines()
      for i in 0 ..< lines.len:
        if CastDocPattern in lines[i]:
          if i == 0 or CastDocAnnotation notin lines[i - 1]:
            result.add(path & ":" & $(i + 1) &
                       " — cast(noSideEffect) without preceding SEE annotation")

type EffectHintEntry = object
  path: string
  reason: string

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func parseEffectHintModules*(lockText: string): seq[EffectHintEntry] {.raises: [].} =
  var inSection = false
  for line in lockText.splitLines():
    let stripped = line.strip()
    if stripped.startsWith("["):
      if stripped == "[effect_hints]":
        inSection = true
      elif inSection and (stripped.startsWith("[effect_hints.") or
          (stripped.startsWith("[") and stripped != "[effect_hints]")):
        inSection = false
      continue
    if not inSection:
      continue
    if stripped.len == 0 or stripped.startsWith("#"):
      continue
    let eqPos = stripped.find("\" =")
    if eqPos < 0:
      continue
    let quoteStart = stripped.find("\"")
    if quoteStart < 0 or quoteStart >= eqPos:
      continue
    let path = stripped[quoteStart + 1 ..< eqPos]
    if not path.endsWith(".nim"):
      continue
    var reason = ""
    let reasonIdx = stripped.find("reason = \"")
    if reasonIdx >= 0:
      let rStart = reasonIdx + "reason = \"".len
      let rEnd = stripped.find("\"", rStart)
      if rEnd > rStart:
        reason = stripped[rStart ..< rEnd]
    result.add(EffectHintEntry(path: path, reason: reason))

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc runEffectHintsScan*(repoRoot: string): seq[string] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let lockPath = repoRoot / EffectHintsLock
  if not fileExists(lockPath):
    result.add("MISSING lock file: " & lockPath)
    return
  let entries = parseEffectHintModules(readFile(lockPath))
  if entries.len == 0:
    return
  for entry in entries:
    let absPath = repoRoot / entry.path
    if not fileExists(absPath):
      result.add("MISSING: " & entry.path &
                 " — listed in [effect_hints] but not found in repo")
      continue
    if isShieldModule(entry.path):
      continue
    if fileHasFfiPragma(readFile(absPath)):
      continue
    result.add("NO-FFI: " & entry.path &
               " — listed in [effect_hints] but contains no FFI pragma " &
               "(importc/importcpp/dynlib/compile) and is not a known shield module")

# ── Track A checks (node: called from axiomAstLint macro, NOT from static: block) ──

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc runAstLintChecks*(repoRoot: string): tuple[advisories: seq[string], errors: seq[string]] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result.advisories = runCastDocScan(repoRoot)
  result.errors = runEffectHintsScan(repoRoot)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro axiomAstLint*(body: untyped): untyped =
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
  proc walk(n: NimNode) {.raises: [].} =
    if n.kind == nnkStmtList:
      for i in 1 ..< n.len:
        let cur = n[i]
        let prev = n[i - 1]
        if cur.kind == nnkCast and CastDocPattern.replace("(", "").replace(")", "") in $cur:
          let annotated = prev.kind == nnkCommentStmt and CastDocAnnotation in $prev
          if not annotated:
            echo "[axiomAstLint][advisory] cast(noSideEffect) at " &
                 cur.lineInfo & " without preceding SEE annotation"
        walk(cur)
  walk(body)
  body

static:
  let root = findRepoRootCt()

  let agmdPath = root / "AGENTS.md"

  # ── Memory policy check ──
  for f in CompetingSsotFiles:
    if fileExists(root / f):
      echo "[axiomAstLint][error] Competing SSOT file: " & f
      doAssert false, "Competing SSOT detected"
  if fileExists(agmdPath):
    let agmd = readFile(agmdPath)
    let markers = ["메모리에 기록하지 말 것", "프로젝트 정책/규칙/컨벤션은 모두 AGENTS.md에"]
    for m in markers:
      if m notin agmd:
        echo "[axiomAstLint][error] AGENTS.md missing marker: " & m
        doAssert false, "Missing memory policy marker"

  # ── Single-file dir check ──
  let coreDir = root / "src" / "core"
  if dirExists(coreDir):
    for kind, path in walkDir(coreDir):
      if kind == pcDir:
        let dirName = lastPathPart(path)
        if not dirName.startsWith("."):
          var nimCount = 0
          var nimName = ""
          for fk, fp in walkDir(path):
            if fk == pcFile and fp.endsWith(".nim"):
              nimCount.inc; nimName = lastPathPart(fp)
          if nimCount == 1:
            let allowlist = ["passes", "protocol", "reporting", "text"]
            var allowed = false
            for a in allowlist:
              if dirName == a: allowed = true; break
            if not allowed:
              echo "[axiomAstLint][advisory] Single-file dir: " & (path.replace(root & "/", "")) & "/ (" & nimName & ")"
