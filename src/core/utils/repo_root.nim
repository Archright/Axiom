{.push raises: [].}
import core/trusted/layer_declaration
axiomLayer "domain"
import core/trusted/env_access
import std/[os, staticos]
import core/trusted/axiom_pragmas_lite
const axiomRoot* = ".axiom_root"  ## Primary project root anchor (declarative).
func repoRootConst*(): string {.compileTime.} =
  ## Compile-time project root resolution.
  ## Walks up from currentSourcePath() until .axiom_root is found.
  ## Guard: parent == current detects filesystem root to prevent infinite loop.
  var current = currentSourcePath().parentDir()
  while current.len > 0:
    if staticFileExists(current / axiomRoot):
      return current
    let parent = current.parentDir()
    if parent == current:  # Root directory detection
      doAssert false, "Axiom root anchor (.axiom_root) not found from: " &
                      currentSourcePath()
    current = parent
  doAssert false, "Axiom root anchor not found from: " & currentSourcePath()
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc walkAnchorUpward(start: string): string {.raises: [], axiomEffect: IOEffect.} =
  ## First `.axiom_root`-bearing ancestor of the absolute `start`, or "" when
  ## no ancestor carries the anchor. Only absolute paths are probed: a
  ## relative or empty head makes `head / axiomRoot` resolve against the CWD,
  ## and `parentDir("/") == ""`, so the walk stops at the filesystem root
  ## instead of escaping to a CWD-relative "" probe (Q-013,
  ## docs/spec/nim_2_2_10_stdlib_quirks.md).
  result = ""
  if not isAbsolute(start):
    return
  var current = start
  for _ in 0..10:
    try:
      if fileExists(current / axiomRoot):
        return current
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
    let parent = parentDir(current)
    if parent.len == 0 or parent == current:
      break
    current = parent
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc findRepoRoot*(startDir: string = getAppDir()): string {.raises: [], axiomEffect: IOEffect.} =
  ## Check AXIOM_ROOT env var first for deterministic root injection.
  ## Falls back to walking up from `startDir` to find `.axiom_root` anchor,
  ## then from the absolute current directory — a binary outside the
  ## repository tree still resolves the repository when the CWD is inside it
  ## (DEBT#550). Deterministic: an anchor hit returns the unique ancestor
  ## directory with the anchor; otherwise the legacy one-level-up fallback.
  ## The result is always absolute and never "" — callers anchor-guard
  ## `result / axiomRoot`, and an empty root turns that guard into a
  ## CWD-relative match (Q-013).
  let envRoot = getAxiomEnv(evRoot)
  if envRoot.len > 0:
    # Normalize: strip trailing separators
    result = envRoot
    while result.len > 1 and result[^1] == '/':
      result = result[0 .. ^2]
    return result
  # Q-013/DEBT#550: a relative or empty start head makes `head / axiomRoot`
  # a CWD-relative probe — resolve the walk start against the absolute
  # current directory (same empty-start convention as axiomConfigPath).
  var start = startDir
  if not isAbsolute(start):
    try:
      start = getCurrentDir() / start
    except CatchableError:
      start = getAppDir()
  let anchored = walkAnchorUpward(start)
  if anchored.len > 0:
    return anchored
  try:
    let cwd = getCurrentDir()
    if cwd != start:
      let fromCwd = walkAnchorUpward(cwd)
      if fromCwd.len > 0:
        return fromCwd
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  # Fallback: one level up (legacy compat for bin/ layout) — absolute only,
  # so caller-side anchor guards fail closed instead of matching the CWD.
  result = parentDir(start)
  if not isAbsolute(result):
    result = start
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc axiomConfigPath*(startDir: string = ""): string {.raises: [], axiomEffect: IOEffect.} =
  ## Canonical axiom config file for the project containing `startDir`.
  ## `config/axiom.toml` is the Axiom-owned layout; a root `axiom.toml` is the
  ## subject-project contract written by `ax scope init` and stays supported.
  ## Returns "" when neither exists — callers keep optional-empty semantics.
  var start = startDir
  if start.len == 0:
    try:
      start = getCurrentDir()
    except CatchableError:
      start = getAppDir()
  let root = findRepoRoot(start)
  try:
    if fileExists(root / "config" / "axiom.toml"):
      return root / "config" / "axiom.toml"
    if fileExists(root / "axiom.toml"):
      return root / "axiom.toml"
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  ""
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc resolveRepoRoot*(): string {.axiomEffect: IOEffect.} =
  ## Runtime project root resolution wrapper.
  ## Calls findRepoRoot at runtime — allows exported proc address checks.
  findRepoRoot()
