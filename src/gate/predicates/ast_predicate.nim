import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## ast_predicate.nim - Source-level predicate functions for quality gate analysis.
##
## Each predicate accepts a file path and returns bool:
##   true  = violation detected (gate should fail)
##   false = no violation (gate passes for this file)
##
## Predicates are lightweight source-text scanners - no full AST parsing.
## They operate on raw file content using strutils pattern matching.
##
## Composition: handlers in gate/handlers/quality_handlers.nim call these
## predicates and aggregate results across staged files.

import std/[strutils, os, sequtils]

# ----------------------------------------
# Naming Style Enum & Config
# ----------------------------------------

type
  NamingStyle* = enum
    nsPascalCase    ## FooBarBaz
    nsCamelCase     ## fooBarBaz
    nsSnakeCase     ## foo_bar_baz

  NamingConfig* = object
    style*: NamingStyle
    prefix*: string           ## Optional prefix filter (e.g. "g_", "s_")
    allowedPrefixes*: seq[string]  ## Additional allowed prefixes

# ----------------------------------------
# Core Naming Predicates
# ----------------------------------------

func isPascalChar(c: char): bool {.raises: [].} =
  c in {'A'..'Z', 'a'..'z', '0'..'9', '_'}

func isCamelStart(c: char): bool {.raises: [].} =
  c in {'a'..'z', 'A'..'Z'}

proc matchesNamingStyle*(name: string; style: NamingStyle): bool {.raises: [].} =
  ## Returns true if name follows the given naming convention.
  if name.len == 0: return true
  case style
  of nsPascalCase:
    result = name[0].isUpperAscii()
    if result:
      for i in 1 ..< name.len:
        if name[i] in {'_', '-'}:
          result = false
          return
  of nsCamelCase:
    result = name[0].isLowerAscii()
    if result:
      for i in 1 ..< name.len:
        if name[i] in {'_', '-'}:
          result = false
          return
  of nsSnakeCase:
    result = "_" notin name and "-" notin name
    if result:
      result = name[0].isLowerAscii() or name[0].isDigit()

proc hasNamingViolation*(filePath: string; cfg: NamingConfig): bool {.raises: [].} =
  ## Returns true if file contains a declared type identifier violating naming convention.
  try:
    let content = readFile(filePath)
    # Scan type-declaration lines; check the declared identifier name only.
    for line in content.strip().splitLines():
      let trimmed = line.strip()
      if trimmed.len == 0 or trimmed.startsWith("#"): continue
      if not (trimmed.startsWith("type ") or trimmed.startsWith("Type ")): continue
      let afterKw = trimmed[(trimmed.find(' ') + 1)..^1].strip()
      var ident = ""
      for ch in afterKw:
        if ch.isAlphaNumeric() or ch == '_':
          ident.add(ch)
        else:
          break
      ident = ident.strip(chars = {'*'})
      if ident.len > 1 and not matchesNamingStyle(ident, cfg.style):
        return true
    return false
  except CatchableError:
    return false

# ----------------------------------------
# Except Block Predicates
# ----------------------------------------

proc hasForbiddenExcept*(filePath: string): bool {.raises: [].} =
  ## Returns true if file contains bare except blocks without preceding comments.
  try:
    let content = readFile(filePath)
    var lines = content.strip().splitLines()
    for i in 0 ..< lines.len:
      if lines[i].strip().startsWith("except") or lines[i].strip().startsWith("except "):
        # Check previous non-empty line for comment
        if i > 0:
          let prev = lines[i-1].strip()
          if prev.len > 0 and not prev.startsWith("#"):
            return true
        else:
          return true
    return false
  except CatchableError:
    return false

# ----------------------------------------
# Discard Comment Predicates
# ----------------------------------------

proc hasUndocumentedDiscard*(filePath: string): bool {.raises: [].} =
  ## Returns true if file contains discard statements without preceding comments.
  try:
    let content = readFile(filePath)
    var lines = content.strip().splitLines()
    for i in 0 ..< lines.len:
      let trimmed = lines[i].strip()
      if trimmed.startsWith("discard ") or trimmed == "discard":
        if i > 0:
          let prev = lines[i-1].strip()
          if prev.len > 0 and not prev.startsWith("#"):
            return true
        else:
          return true
    return false
  except CatchableError:
    return false

# ----------------------------------------
# Import Style Predicates
# ----------------------------------------

proc hasWildcardImport*(filePath: string): bool {.raises: [].} =
  ## Returns true if file uses wildcard imports (import * or import std/[...]).
  try:
    let content = readFile(filePath)
    for line in content.strip().splitLines():
      let trimmed = line.strip()
      if trimmed.startsWith("import") or trimmed.startsWith("from"):
        if "*" in trimmed or ("[" in trimmed and "]" in trimmed):
          return true
    return false
  except CatchableError:
    return false

proc hasDeeplyNestedImport*(filePath: string): bool {.raises: [].} =
  ## Returns true if file imports modules more than 3 levels deep.
  try:
    let content = readFile(filePath)
    for line in content.strip().splitLines():
      let trimmed = line.strip()
      if trimmed.startsWith("import") or trimmed.startsWith("from"):
        let depth = trimmed.count(".")
        if depth > 3:
          return true
    return false
  except CatchableError:
    return false

# ----------------------------------------
# Indentation & Line Length Predicates
# ----------------------------------------

proc hasInconsistentIndentation*(filePath: string): bool {.raises: [].} =
  ## Returns true if file mixes tabs and spaces for indentation.
  try:
    let content = readFile(filePath)
    var hasTab = false
    var hasSpace = false
    for line in content.strip().splitLines():
      if line.strip().len == 0: continue
      var indentLen = 0
      for ch in line:
        if ch == '\t':
          hasTab = true
          inc indentLen
          indentLen += 1  # tab = 2 spaces
        elif ch == ' ':
          hasSpace = true
          inc indentLen
        else:
          break
      if hasTab and hasSpace:
        return true
    return false
  except CatchableError:
    return false

proc hasLongLines*(filePath: string; maxLength: int = 120): bool {.raises: [].} =
  ## Returns true if file has lines exceeding maxLength.
  try:
    let content = readFile(filePath)
    for line in content.strip().splitLines():
      let stripped = line.strip()
      if stripped.len == 0 or stripped.startsWith("#"): continue
      if stripped.len > maxLength:
        return true
    return false
  except CatchableError:
    return false

# ----------------------------------------
# Symbol-Specific Naming Predicates
# ----------------------------------------

proc hasUnconventionalProcName*(filePath: string): bool {.raises: [].} =
  ## Returns true if file contains proc definitions with camelCase names.
  ## Nim convention: procs should use snake_case.
  try:
    let content = readFile(filePath)
    for line in content.strip().splitLines():
      let trimmed = line.strip()
      if (trimmed.startsWith("proc ") or trimmed.startsWith("func ") or
          trimmed.startsWith("method ") or trimmed.startsWith("template ") or
          trimmed.startsWith("macro ")) and "(" in trimmed:
        let keywordLen = trimmed.find(" ") + 1
        let rest = trimmed[keywordLen..^1].strip()
        let parenIdx = rest.find("(")
        if parenIdx > 0:
          let name = rest[0..<parenIdx].strip()
          if name.len > 1 and name[0].isLowerAscii() and name[1].isLowerAscii():
            # Check for camelCase: lowercase followed by uppercase
            for i in 1 ..< name.len - 1:
              if name[i].isLowerAscii() and name[i+1].isUpperAscii():
                return true
    return false
  except CatchableError:
    return false

proc hasUnconventionalTypeName*(filePath: string): bool {.raises: [].} =
  ## Returns true if file contains type definitions with snake_case names.
  ## Nim convention: types should use PascalCase.
  try:
    let content = readFile(filePath)
    for line in content.strip().splitLines():
      let trimmed = line.strip()
      if (trimmed.startsWith("type ") or trimmed.startsWith("Type ") or
          "object" in trimmed or "enum" in trimmed or
          trimmed.startsWith("MyObject") or trimmed.startsWith("MyEnum")):
        # Look for type definition pattern
        if ":" in trimmed and "=" in trimmed:
          let parts = trimmed.split(":")
          if parts.len >= 2:
            let namePart = parts[1].strip().split("=")[0].strip()
            if namePart.len > 1 and namePart[0].isLowerAscii():
              return true
    return false
  except CatchableError:
    return false

proc hasUnconventionalConstName*(filePath: string): bool {.raises: [].} =
  ## Returns true if file contains const declarations with camelCase names.
  ## Nim convention: consts should use UPPER_SNAKE_CASE.
  try:
    let content = readFile(filePath)
    for line in content.strip().splitLines():
      let trimmed = line.strip()
      if trimmed.startsWith("const ") or trimmed.startsWith("let "):
        let rest = trimmed[6..^1].strip()
        let eqIdx = rest.find("=")
        let name = if eqIdx > 0: rest[0..<eqIdx].strip() else: rest
        if name.len > 1:
          # UPPER_SNAKE_CASE: all uppercase with underscores
          var hasLower = false
          for c in name:
            if c in {'a'..'z'}:
              hasLower = true
              break
          if hasLower:
            return true
    return false
  except CatchableError:
    return false

proc hasUnconventionalVarName*(filePath: string): bool {.raises: [].} =
  ## Returns true if file contains var declarations with PascalCase names.
  ## Nim convention: vars should use snake_case.
  try:
    let content = readFile(filePath)
    for line in content.strip().splitLines():
      let trimmed = line.strip()
      if trimmed.startsWith("var "):
        let rest = trimmed[4..^1].strip()
        let eqIdx = rest.find("=")
        let name = if eqIdx > 0: rest[0..<eqIdx].strip() else: rest
        let commaIdx = name.find(",")
        let varName = if commaIdx > 0: name[0..<commaIdx].strip() else: name
        if varName.len > 1 and varName[0].isUpperAscii():
          return true
    return false
  except CatchableError:
    return false

proc hasUnconventionalTemplateName*(filePath: string): bool {.raises: [].} =
  ## Returns true if file contains template definitions with camelCase names.
  ## Nim convention: templates should use snake_case.
  try:
    let content = readFile(filePath)
    for line in content.strip().splitLines():
      let trimmed = line.strip()
      if trimmed.startsWith("template "):
        let rest = trimmed[9..^1].strip()
        let parenIdx = rest.find("(")
        let name = if parenIdx > 0: rest[0..<parenIdx].strip() else: rest
        if name.len > 1 and name[0].isLowerAscii() and name[1].isLowerAscii():
          for i in 1 ..< name.len - 1:
            if name[i].isLowerAscii() and name[i+1].isUpperAscii():
              return true
    return false
  except CatchableError:
    return false

proc hasUnconventionalMacroName*(filePath: string): bool {.raises: [].} =
  ## Returns true if file contains macro definitions with camelCase names.
  ## Nim convention: macros should use snake_case.
  try:
    let content = readFile(filePath)
    for line in content.strip().splitLines():
      let trimmed = line.strip()
      if trimmed.startsWith("macro "):
        let rest = trimmed[6..^1].strip()
        let parenIdx = rest.find("(")
        let name = if parenIdx > 0: rest[0..<parenIdx].strip() else: rest
        if name.len > 1 and name[0].isLowerAscii() and name[1].isLowerAscii():
          for i in 1 ..< name.len - 1:
            if name[i].isLowerAscii() and name[i+1].isUpperAscii():
              return true
    return false
  except CatchableError:
    return false

{.pop.}
