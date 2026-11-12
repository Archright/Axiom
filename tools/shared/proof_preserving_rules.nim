import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}
## Proof-preserving algebraic transformation rules.
## Isomorphic transformations that maintain semantic equivalence.

import std/[strutils, os, sequtils]

type
  TransformRule* = enum
    trEffectUnion
    trKeywordConsist
    trImportElim
    trConflictResolve

  TransformResult* = object
    rule*: TransformRule
    file*: string
    changed*: bool
    details*: string
    lineNum*: int

# Rule 1: Effect Union — placeholder for effect inference
proc applyEffectUnion*(content: string; filePath: string): (string, seq[TransformResult]) =
  result = (content, @[])

# Rule 2: Keyword Consistency — func/proc alignment
proc applyKeywordConsistency*(content: string; filePath: string): (string, seq[TransformResult]) =
  var lines = content.splitLines
  var results: seq[TransformResult]
  # Collect forward declarations
  for i, line in lines:
    let s = line.strip
    if s.startsWith("func ") and "(" in s and not ("=" in s):
      let name = s[5..^1].split("(")[0].strip
      # Check if implementation uses proc
      for j, line2 in lines:
        if j != i and line2.strip.startsWith("proc " & name & "(") and "=" in line2:
          lines[i] = line.replace("func " & name, "proc " & name)
          results.add(TransformResult(rule: trKeywordConsist, file: filePath, changed: true, lineNum: i+1, details: "func\162proc: " & name))
          break
  result = (lines.join("\n"), results)

# Rule 3: Import Elimination
proc applyImportElimination*(content: string; filePath: string; unusedImports: seq[string]): (string, seq[TransformResult]) =
  var lines = content.splitLines
  var results: seq[TransformResult]
  for unused in unusedImports:
    for i, line in lines:
      let s = line.strip
      if s.startsWith("import "):
        let mods = s[7..^1].split(",").mapIt(it.strip)
        if mods.len == 1 and mods[0] == unused:
          lines[i] = ""
          results.add(TransformResult(rule: trImportElim, file: filePath, changed: true, lineNum: i+1, details: "removed: import " & unused))
        elif unused in mods:
          lines[i] = "import " & mods.filterIt(it != unused).join(", ")
          results.add(TransformResult(rule: trImportElim, file: filePath, changed: true, lineNum: i+1, details: "removed " & unused & " from multi-import"))
  result = (lines.filterIt(it.strip.len > 0).join("\n"), results)

# Rule 4: Conflict Resolution
proc applyConflictResolution*(content: string; filePath: string): (string, seq[TransformResult]) =
  var results: seq[TransformResult]
  if "CONFLICT_UNRESOLVED" in content:
    results.add(TransformResult(rule: trConflictResolve, file: filePath, changed: false, details: "CONFLICT marker found"))
  result = (content, results)
