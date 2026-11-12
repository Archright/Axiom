import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

import std/[json, os, strutils, strformat]
import core/ast_kernel
import core/results
import core/crypto/hash_kernel
import ../tests/fixtures/legacy_reference

type
  SlocDiffRecord* = object
    file*: string
    affectedLines*: seq[int]
    legacySloc*: int
    pnodeSloc*: int
    sourceHash*: string
    algorithmVersion*: string
    policyVersion*: string

proc walkNimFiles(root: string): seq[string] =
  if fileExists(root):
    if root.endsWith(".nim"):
      result.add(root)
    return
  let skipDirs = @["src/core/solver", "src/core/api", "src/core/gate", "src/core/topology",
    "src/core/audit", "src/core/identity", "src/core/judge", "src/core/observer",
    "src/core/trusted", "src/verification", "src/personas", "src/cli"]
  for path in walkDirRec(root):
    if path.endsWith(".nim"):
      var skipped = false
      for sd in skipDirs:
        if path.startsWith(sd):
          skipped = true
          break
      if not skipped:
        result.add(path)

proc computeLegacySloc(lines: seq[string]): int =
  countEffectiveSLOC(lines, 1, lines.len)

proc computePnodeSloc(source: string): int =
  let parsed = parseSourceToPNode(source)
  if parsed.isErr:
    return 0
  sourceSloc(parsed.get)

proc diffFile(path: string): SlocDiffRecord =
  let source = readFile(path)
  let lines = source.splitLines()
  let legacy = computeLegacySloc(lines)
  let pnode = computePnodeSloc(source)
  let hash = sha256Hex(source)
  SlocDiffRecord(
    file: path,
    affectedLines: @[1, lines.len],
    legacySloc: legacy,
    pnodeSloc: pnode,
    sourceHash: hash,
    algorithmVersion: EffectiveSlocAlgorithmVersion,
    policyVersion: EffectiveSlocPolicyVersion
  )

proc scanCommand(files: seq[string]) =
  var totalLegacy = 0
  var totalPnode = 0
  var diffCount = 0
  var skipped = 0
  for i, f in files:
    let rec = diffFile(f)
    if rec.pnodeSloc == 0 and rec.legacySloc == 0 and rec.sourceHash.len > 0:
      inc skipped
      stderr.writeLine fmt"[{i+1}/{files.len}] SKIPPED (parse timeout): {f}"
    else:
      totalLegacy += rec.legacySloc
      totalPnode += rec.pnodeSloc
      if rec.legacySloc != rec.pnodeSloc:
        inc diffCount
      if (i + 1) mod 50 == 0 or i + 1 == files.len:
        echo fmt"[{i+1}/{files.len}] processed, {diffCount} differing so far"
  echo fmt"Total files: {files.len}, Skipped: {skipped}, Differing: {diffCount}"
  echo fmt"Total legacy SLOC: {totalLegacy}, Total PNode SLOC: {totalPnode}"

proc diffCommand(files: seq[string]) =
  var records: seq[SlocDiffRecord]
  var totalLegacy = 0
  var totalPnode = 0
  var diffCount = 0
  for f in files:
    let rec = diffFile(f)
    records.add(rec)
    totalLegacy += rec.legacySloc
    totalPnode += rec.pnodeSloc
    if rec.legacySloc != rec.pnodeSloc:
      inc diffCount
  let output = %*records
  let dataDir = "data"
  if not dirExists(dataDir):
    createDir(dataDir)
  writeFile(dataDir / "sloc_differential.json", output.pretty())
  echo fmt"Differential complete: {files.len} files, {diffCount} differing"
  echo fmt"Total legacy SLOC: {totalLegacy}, Total PNode SLOC: {totalPnode}"
  let expectedCorrection = files.len - diffCount
  echo fmt"Historical comparison: expected-correction={expectedCorrection} (was 1040), ambiguous={diffCount} (was 56)"
  if expectedCorrection == 1040 and diffCount == 56:
    echo "MATCH: current counts match historical 1040/56"
  else:
    echo "MISMATCH: current counts do NOT match historical 1040/56"

proc main(args: seq[string]) =
  if args.len < 1:
    echo "Usage: sloc_ratify <scan|diff> [path1] [path2] ..."
    return
  let cmd = args[0]
  let paths = if args.len > 1: args[1 .. ^1] else: @["src/"]
  var allFiles: seq[string]
  for p in paths:
    allFiles.add(walkNimFiles(p))
  case cmd
  of "scan": scanCommand(allFiles)
  of "diff": diffCommand(allFiles)
  else: echo fmt"Unknown command: {cmd}"

when isMainModule:
  main(commandLineParams())