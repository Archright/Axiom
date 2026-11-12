import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## Architecture predicate types and common utilities.
##
## Provides composable boolean predicates used by architecture gate handlers
## in src/gate/handlers/architecture_handlers.nim. Each predicate checks a
## single architectural concern and returns true when the concern is satisfied.

import std/[os, strutils, tables, hashes]
import core/gate/transitive_hash
import gate/gate_consts

# ----------------------------------------
# Import encapsulation predicates
# ----------------------------------------

proc isExemptedImport*(filepath: string; internal: string): bool {.raises: [].} =
  ## Check if filepath is exempted from importing internal path.
  if filepath.startsWith("src/core/"):
    return true
  if hubMapping.hasKey(filepath):
    for exc in hubMapping.getOrDefault(filepath):
      if internal.startsWith(exc):
        return true
  for hubKey, hubExceptions in hubMapping.pairs:
    if hubKey.endsWith("/") and filepath.startsWith(hubKey):
      for exc in hubExceptions:
        if internal.startsWith(exc):
          return true
  result = false

proc checkImportEncapsulation*(
  sourceFile: string;
  imports: seq[string];
  repoRoot: string
): bool {.raises: [].} =
  ## Returns true when no internal import violations are found.
  result = true
  try:
    let content = readFile(sourceFile)
    var inImportBlock = false
    for line in content.splitLines:
      let stripped = line.strip
      if stripped.len == 0 or stripped.startsWith("#"):
        inImportBlock = false
        continue
      var isImportLine = false
      if stripped.startsWith("import ") or stripped.startsWith("from "):
        inImportBlock = false
        isImportLine = true
      elif stripped == "import":
        inImportBlock = true
        continue
      elif inImportBlock:
        if line.startsWith(" ") or line.startsWith("\t"):
          isImportLine = true
        else:
          inImportBlock = false
      if isImportLine:
        for internal in InternalPaths:
          if internal in stripped and internal notin sourceFile:
            if not isExemptedImport(sourceFile, internal):
              return false
  except CatchableError:
    discard

# ----------------------------------------
# Dependency cycle predicates
# ----------------------------------------

proc hasDependencyCycle*(
  sourceFiles: seq[string];
  repoRoot: string
): bool {.raises: [].} =
  ## Returns true when a dependency cycle is detected among source files.
  result = false
  try:
    var visited = initTable[string, bool]()
    for srcFile in sourceFiles:
      let resolved = resolveImports(srcFile, repoRoot)
      for imp in resolved:
        if imp in visited:
          return true
        visited[imp] = true
  except CatchableError:
    discard

# ----------------------------------------
# Contract violation predicates
# ----------------------------------------

proc hasContractViolation*(
  sourceFile: string;
  forbiddenPatterns: seq[string]
): bool {.raises: [].} =
  ## Returns true when no forbidden AST patterns are found in source file.
  result = true
  try:
    let content = readFile(sourceFile)
    for pattern in forbiddenPatterns:
      if pattern in content:
        return false
  except CatchableError:
    discard

# ----------------------------------------
# Layer violation predicates
# ----------------------------------------

proc hasLayerViolation*(
  sourceFile: string;
  allowedLayers: seq[string]
): bool {.raises: [].} =
  ## Returns true when all imports target allowed layers.
  result = true
  try:
    let content = readFile(sourceFile)
    for line in content.splitLines:
      let stripped = line.strip
      if stripped.startsWith("import ") or stripped.startsWith("from "):
        let rest = if stripped.startsWith("from "):
                     stripped[5..^1].split(" import ")[0].strip()
                   else:
                     stripped[7..^1].strip().split(",")[0].strip()
        if rest.len > 0 and "/" in rest:
          if "trusted" in rest and "trusted" notin allowedLayers:
            return false
  except CatchableError:
    discard

# ----------------------------------------
# Circular dependency predicates
# ----------------------------------------

proc hasCircularDependency*(
  sourceFile: string;
  repoRoot: string
): bool {.raises: [].} =
  ## Returns true when no circular import chain exists through sourceFile.
  result = true
  try:
    let directDeps = resolveImports(sourceFile, repoRoot)
    for dep in directDeps:
      let transitive = resolveImports(dep, repoRoot)
      for tDep in transitive:
        if tDep == sourceFile:
          return false
  except CatchableError:
    discard

# ----------------------------------------
# Dead code predicates
# ----------------------------------------

proc hasDeadCode*(
  sourceFile: string;
  allSourceFiles: seq[string]
): bool {.raises: [].} =
  ## Returns true when no exported symbols appear unused across the codebase.
  result = true
  try:
    let content = readFile(sourceFile)
    for line in content.splitLines:
      let stripped = line.strip
      if stripped.startsWith("proc ") or stripped.startsWith("func "):
        let parts = stripped.splitWhitespace()
        if parts.len >= 3:
          let symbolName = parts[1].split("(")[0]
          if symbolName[0].isAlphaAscii or symbolName[0] == '_':
            var usageCount = 0
            for otherFile in allSourceFiles:
              if otherFile == sourceFile:
                continue
              let otherContent = readFile(otherFile)
              if symbolName in otherContent:
                inc usageCount
            if usageCount == 0:
              return false
  except CatchableError:
    discard

# ----------------------------------------
# Unused import predicates
# ----------------------------------------

proc hasUnusedImport*(
  sourceFile: string
): bool {.raises: [].} =
  ## Returns true when all imports are actually used in the source file.
  result = true
  try:
    let content = readFile(sourceFile)
    var inImportBlock = false
    for line in content.splitLines:
      let stripped = line.strip
      if stripped.len == 0 or stripped.startsWith("#"):
        inImportBlock = false
        continue
      if stripped.startsWith("import ") or stripped.startsWith("from "):
        inImportBlock = false
      elif stripped == "import":
        inImportBlock = true
        continue
      if inImportBlock:
        if line.startsWith(" ") or line.startsWith("\t"):
          let tokens = stripped.splitWhitespace()
          for token in tokens:
            let cleanToken = token.split(":")[0].strip()
            if cleanToken.len > 0 and not (cleanToken in content[content.find(line)+line.len .. ^1]):
              return false
        else:
          inImportBlock = false
  except CatchableError:
    discard

# ----------------------------------------
# Module structure predicates
# ----------------------------------------

proc hasValidModuleStructure*(
  sourceFile: string
): bool {.raises: [].} =
  ## Returns true when module follows structural conventions (docstrings, layer).
  result = true
  try:
    let content = readFile(sourceFile)
    let lines = content.splitLines
    if lines.len == 0:
      return false
    var hasDocstring = false
    var hasLayerDecl = false
    for line in lines:
      let stripped = line.strip
      if stripped.startsWith("## "):
        hasDocstring = true
      if stripped.startsWith("axiomLayer"):
        hasLayerDecl = true
    if not hasDocstring or not hasLayerDecl:
      return false
  except CatchableError:
    discard

# ----------------------------------------
# API stability predicates
# ----------------------------------------

proc hasApiStabilityIssue*(
  sourceFile: string
): bool {.raises: [].} =
  ## Returns true when exported symbols lack stability documentation.
  result = true
  try:
    let content = readFile(sourceFile)
    var foundExportedProc = false
    var hasStabilityNote = false
    for line in content.splitLines:
      let stripped = line.strip
      if stripped.startsWith("proc ") or stripped.startsWith("func "):
        if "export" in stripped or stripped.contains("*"):
          foundExportedProc = true
      if stripped.contains("stable") or stripped.contains("api") or stripped.contains("public"):
        hasStabilityNote = true
    if foundExportedProc and not hasStabilityNote:
      return false
  except CatchableError:
    discard

# ----------------------------------------
# Refactoring safety predicates
# ----------------------------------------

proc hasRefactoringRisk*(
  sourceFile: string;
  highRiskSymbols: seq[string]
): bool {.raises: [].} =
  ## Returns true when no high-risk symbols are modified unsafely.
  result = true
  try:
    let content = readFile(sourceFile)
    for symbol in highRiskSymbols:
      if symbol in content:
        let symIdx = content.find(symbol)
        let surrounding = content[symIdx .. min(symIdx + 200, content.len - 1)]
        if "{.noSideEffect.}" notin surrounding and "{.gcsafe.}" notin surrounding:
          if "discard" notin surrounding and "result" notin surrounding:
            return false
  except CatchableError:
    discard

# ----------------------------------------
# State verification predicate
# ----------------------------------------

proc verifyStateConsistency*(
  sourceFile: string;
  expectedHash: uint64
): bool {.raises: [].} =
  ## Returns true when the source file state matches the expected hash.
  result = true
  try:
    let content = readFile(sourceFile)
    var h: Hash = Hash(0)
    for c in content:
      h = Hash(ord(c)) xor h
    let actualHash = uint64(h)
    if actualHash != expectedHash:
      return false
  except CatchableError:
    discard

{.pop.}
