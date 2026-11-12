import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## Architecture gate handlers — predicate composition layer.
##
## Each handler composes one or more predicates from gate/predicates/types.nim
## into a single boolean check suitable for declareGate registration.
## Handlers are intentionally thin (3-5 lines) to keep the dispatch table
## declarative and easy to audit.

import std/[os, strutils, strformat]
import gate/gate_registry
import gate/predicates/types

# ---------------------------------------------------------------------------
# Handler 1: Import Encapsulation Gate
# ---------------------------------------------------------------------------

proc handleImportEncapsulationGate*(ctx: GateContext): bool {.nimcall, raises: [].} =
  # axiom:architecture-handler
  ## Verifies all internal imports pass through hub modules.
  try:
    for srcFile in ctx.stagedFiles:
      if not srcFile.endsWith(".nim"):
        continue
      if not checkImportEncapsulation(srcFile, @[], ctx.repoRoot):
        return false
    result = true
  except CatchableError:
    result = false

# ---------------------------------------------------------------------------
# Handler 2: Dependency Cycle Gate
# ---------------------------------------------------------------------------

proc handleDependencyCycleGate*(ctx: GateContext): bool {.nimcall, gcsafe, raises: [].} =
  # axiom:architecture-handler
  ## Detects cyclic dependencies among staged Nim source files.
  try:
    var nimFiles: seq[string] = @[]
    for f in ctx.stagedFiles:
      if f.endsWith(".nim"):
        nimFiles.add(f)
    if hasDependencyCycle(nimFiles, ctx.repoRoot):
      return false
    result = true
  except CatchableError:
    result = false

# ---------------------------------------------------------------------------
# Handler 3: Contract Violation Gate
# ---------------------------------------------------------------------------

proc handleContractViolationGate*(ctx: GateContext): bool {.nimcall, gcsafe, raises: [].} =
  # axiom:architecture-handler
  ## Checks staged files against forbidden AST patterns.
  let forbiddenPatterns = @["bareExcept", "checkTrue", "discardResult"]
  try:
    for srcFile in ctx.stagedFiles:
      if not srcFile.endsWith(".nim"):
        continue
      if hasContractViolation(srcFile, forbiddenPatterns):
        return false
    result = true
  except CatchableError:
    result = false

# ---------------------------------------------------------------------------
# Handler 4: Layer Violation Gate
# ---------------------------------------------------------------------------

proc handleLayerViolationGate*(ctx: GateContext): bool {.nimcall, gcsafe, raises: [].} =
  # axiom:architecture-handler
  ## Ensures imports respect declared layer boundaries.
  let allowedLayers = @["core", "gate", "domain", "infrastructure"]
  try:
    for srcFile in ctx.stagedFiles:
      if not srcFile.endsWith(".nim"):
        continue
      if hasLayerViolation(srcFile, allowedLayers):
        return false
    result = true
  except CatchableError:
    result = false

# ---------------------------------------------------------------------------
# Handler 5: Circular Dependency Gate
# ---------------------------------------------------------------------------

proc handleCircularDependencyGate*(ctx: GateContext): bool {.nimcall, gcsafe, raises: [].} =
  # axiom:architecture-handler
  ## Validates no circular import chains exist through staged files.
  try:
    for srcFile in ctx.stagedFiles:
      if not srcFile.endsWith(".nim"):
        continue
      if hasCircularDependency(srcFile, ctx.repoRoot):
        return false
    result = true
  except CatchableError:
    result = false

# ---------------------------------------------------------------------------
# Handler 6: Dead Code Gate
# ---------------------------------------------------------------------------

proc handleDeadCodeGate*(ctx: GateContext): bool {.nimcall, gcsafe, raises: [].} =
  # axiom:architecture-handler
  ## Flags exported symbols that appear unused across the codebase.
  try:
    var allNimFiles: seq[string] = @[]
    for f in ctx.stagedFiles:
      if f.endsWith(".nim"):
        allNimFiles.add(f)
    for srcFile in ctx.stagedFiles:
      if not srcFile.endsWith(".nim"):
        continue
      if hasDeadCode(srcFile, allNimFiles):
        return false
    result = true
  except CatchableError:
    result = false

# ---------------------------------------------------------------------------
# Handler 7: Unused Import Gate
# ---------------------------------------------------------------------------

proc handleUnusedImportGate*(ctx: GateContext): bool {.nimcall, gcsafe, raises: [].} =
  # axiom:architecture-handler
  ## Verifies all imports in staged files are actually used.
  try:
    for srcFile in ctx.stagedFiles:
      if not srcFile.endsWith(".nim"):
        continue
      if hasUnusedImport(srcFile):
        return false
    result = true
  except CatchableError:
    result = false

# ---------------------------------------------------------------------------
# Handler 8: Module Structure Gate
# ---------------------------------------------------------------------------

proc handleModuleStructureGate*(ctx: GateContext): bool {.nimcall, gcsafe, raises: [].} =
  # axiom:architecture-handler
  ## Checks that modules follow structural conventions.
  try:
    for srcFile in ctx.stagedFiles:
      if not srcFile.endsWith(".nim"):
        continue
      if hasValidModuleStructure(srcFile):
        return false
    result = true
  except CatchableError:
    result = false

# ---------------------------------------------------------------------------
# Handler 9: API Stability Gate
# ---------------------------------------------------------------------------

proc handleApiStabilityGate*(ctx: GateContext): bool {.nimcall, gcsafe, raises: [].} =
  # axiom:architecture-handler
  ## Ensures exported symbols have stability documentation.
  try:
    for srcFile in ctx.stagedFiles:
      if not srcFile.endsWith(".nim"):
        continue
      if hasApiStabilityIssue(srcFile):
        return false
    result = true
  except CatchableError:
    result = false

# ---------------------------------------------------------------------------
# Handler 10: Refactoring Safety Gate
# ---------------------------------------------------------------------------

proc handleRefactoringSafetyGate*(ctx: GateContext): bool {.nimcall, gcsafe, raises: [].} =
  # axiom:architecture-handler
  ## Prevents unsafe modifications to high-risk symbols.
  let highRiskSymbols = @["result", "globalState", "singleton"]
  try:
    for srcFile in ctx.stagedFiles:
      if not srcFile.endsWith(".nim"):
        continue
      if hasRefactoringRisk(srcFile, highRiskSymbols):
        return false
    result = true
  except CatchableError:
    result = false

#.pop.

when isMainModule:
  echo "Architecture handlers loaded: 10 handlers registered"
  let dummyCtx = GateContext(repoRoot: ".", stagedFiles: @[])
  let handlers = [
    ("import-encapsulation", handleImportEncapsulationGate),
    ("dependency-cycle", handleDependencyCycleGate),
    ("contract-violation", handleContractViolationGate),
    ("layer-violation", handleLayerViolationGate),
    ("circular-dependency", handleCircularDependencyGate),
    ("dead-code", handleDeadCodeGate),
    ("unused-import", handleUnusedImportGate),
    ("module-structure", handleModuleStructureGate),
    ("api-stability", handleApiStabilityGate),
    ("refactoring-safety", handleRefactoringSafetyGate),
  ]
  for i in 0 ..< handlers.len:
    let name = handlers[i][0]
    let h = handlers[i][1]
    let ok = h(dummyCtx)
    echo &"  {name}: {ok}"
    echo &"  {name}: {ok}"
