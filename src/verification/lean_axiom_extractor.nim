import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
## Lean Axiom Extractor — parse `#print axioms` output from Lean CLI.
## Extracts axioms used by a declaration for TCB transparency.

import core/trusted/axiom_pragmas
import std/os
import std/osproc
import std/strutils
import std/re

proc extractLeanAxioms*(leanExe: string; modulePath: string; declName: string): seq[string] {.gcsafe, raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  ## Run `lean --run` with `#print axioms <declName>` and parse output.
  ## Returns empty seq on failure (safe fallback).
  var pattern: Regex
  try:
    pattern = re"""'[^']+'\s+depends on axioms:\s*\[(.*)\]"""
  except RegexError:
    return @[]
  try:
    let tmpFile = getTempDir() / "axiom_axiom_extract_" & $getCurrentProcessId() & ".lean"
    let content = "#print axioms " & declName & "\n"
    writeFile(tmpFile, content)
    defer: discard tryRemoveFile(tmpFile)

    let (output, exitCode) = execCmdEx(leanExe & " " & tmpFile, options = {poUsePath, poStdErrToStdOut})
    if exitCode != 0:
      return @[]

    var groups: array[1, string]
    if output.find(pattern, groups) >= 0:
      let axiomsStr = groups[0]
      if axiomsStr.len > 0:
        for axiom in axiomsStr.split(","):
          result.add(axiom.strip())
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

proc extractLeanAxiomsFromSource*(leanExe: string; source: string): seq[string] {.gcsafe, raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  ## Extract axioms from a Lean source string by compiling it.
  var pattern: Regex
  try:
    pattern = re"""'[^']+'\s+depends on axioms:\s*\[(.*)\]"""
  except RegexError:
    return @[]
  try:
    let tmpFile = getTempDir() / "axiom_axiom_source_" & $getCurrentProcessId() & ".lean"
    writeFile(tmpFile, source)
    defer: discard tryRemoveFile(tmpFile)

    let (output, exitCode) = execCmdEx(leanExe & " " & tmpFile, options = {poUsePath, poStdErrToStdOut})
    if exitCode != 0:
      return @[]

    var groups: array[1, string]
    for line in output.splitLines():
      if line.find(pattern, groups) >= 0:
        let axiomsStr = groups[0]
        if axiomsStr.len > 0:
          for axiom in axiomsStr.split(","):
            let stripped = axiom.strip()
            if stripped.len > 0 and stripped notin result:
              result.add(stripped)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

{.pop.}
