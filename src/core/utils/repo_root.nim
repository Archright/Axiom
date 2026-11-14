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
proc findRepoRoot*(startDir: string = getAppDir()): string {.raises: [], axiomEffect: IOEffect.} =
  ## Check AXIOM_ROOT env var first for deterministic root injection.
  ## Falls back to walking up from `startDir` to find `.axiom_root` anchor.
  ## Deterministic: returns the unique ancestor directory with the anchor.
  ## Fallback: one level up from startDir (legacy compat).
  let envRoot = getAxiomEnv(evRoot)
  if envRoot.len > 0:
    # Normalize: strip trailing separators
    result = envRoot
    while result.len > 1 and result[^1] == '/':
      result = result[0 .. ^2]
    return result
  result = startDir
  for _ in 0..10:
    try:
      if fileExists(result / axiomRoot):
        return result
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
    let parent = parentDir(result)
    if parent == result:
      break
    result = parent
  # Fallback: one level up (legacy compat for bin/ layout)
  result = parentDir(startDir)
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
