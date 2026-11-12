import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
## IO Axiom Builder — Content-addressable I/O effect axiom table.
##
## Reads io_effect_spec.lean, extracts axiom declarations, builds a
## deterministic table of I/O properties for the Sieve pipeline.
## Follows the project's content-addressable caching pattern.

import std/strutils
import std/tables
import std/os
import core/trusted/axiom_pragmas
# axiomIoBoundary

type
  IoAxiomKind* = enum
    iakAxiom     ## Structural axiom (unproved, but semantically necessary)
    iakTheorem   ## Proved theorem (rfl or tactic proof)

  IoAxiomEntry* = object
    name*: string           ## "readFile_after_write", "write_isolation", etc.
    kind*: IoAxiomKind
    proposition*: string    ## The Lean proposition text
    proved*: bool           ## true if theorem, false if axiom

  IoAxiomTable* = Table[string, IoAxiomEntry]

const ioEffectSpecRelPath* = "src/verification/io_effect_spec.lean"

func parseLeanAxiomLine(line: string): (string, IoAxiomKind, string) {.raises: [].} =
  ## Parse a single Lean axiom/theorem declaration line.
  ## Returns (name, kind, proposition) or ("", iakAxiom, "") if not a declaration.
  let trimmed = line.strip()
  if trimmed.startsWith("axiom "):
    let rest = trimmed[6 .. ^1]
    let spaceIdx = rest.find(' ')
    if spaceIdx > 0:
      let name = rest[0 ..< spaceIdx]
      let prop = rest[spaceIdx + 1 .. ^1]
      return (name, iakAxiom, prop)
  elif trimmed.startsWith("theorem "):
    let rest = trimmed[8 .. ^1]
    let spaceIdx = rest.find(' ')
    if spaceIdx > 0:
      let name = rest[0 ..< spaceIdx]
      let prop = rest[spaceIdx + 1 .. ^1]
      return (name, iakTheorem, prop)
  ("", iakAxiom, "")

func buildIoAxiomTable*(leanSource: string): IoAxiomTable {.raises: [].} =
  ## Build axiom table from Lean source text. Pure function.
  result = initTable[string, IoAxiomEntry]()
  for line in leanSource.splitLines():
    let (name, kind, prop) = parseLeanAxiomLine(line)
    if name.len > 0:
      result[name] = IoAxiomEntry(
        name: name,
        kind: kind,
        proposition: prop,
        proved: kind == iakTheorem
      )

proc loadIoAxiomTable*(repoRoot: string = ""): IoAxiomTable {.raises: [IOError, OSError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Load io_effect_spec.lean from disk and build the axiom table.
  ## I/O boundary — called once at pipeline initialization.
  let root = if repoRoot.len > 0: repoRoot else: getCurrentDir()
  let specPath = joinPath(root, ioEffectSpecRelPath)
  if not fileExists(specPath):
    return initTable[string, IoAxiomEntry]()
  let source = readFile(specPath)
  buildIoAxiomTable(source)

func hasAxiom*(table: IoAxiomTable; name: string): bool {.raises: [].} =
  table.hasKey(name)

func isProved*(table: IoAxiomTable; name: string): bool {.raises: [].} =
  if not table.hasKey(name): return false
  let entry = table.getOrDefault(name, IoAxiomEntry())
  entry.proved

func axiomNames*(table: IoAxiomTable): seq[string] {.raises: [].} =
  result = @[]
  for k in table.keys():
    result.add(k)

{.pop.}
