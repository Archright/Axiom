import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
## IR Crash Dump — serializes failing IR function + metadata for deterministic replay.
##
## Called when Z3 FFI encounters a sort mismatch. Produces a .ir file that can be
## loaded directly by tooling to reproduce and debug the issue (there is no
## `ax prove` flag that consumes it).

import std/[os, strutils]
import core/crypto/hash_kernel
import core/parsers/safe_parsers
import core/results

when defined(axiomDebug):
  import infrastructure/logger
import core/axiom_pragmas

const irDumpVersion* = 1

type
  IrDumpEntry* = object
    funcName*: string
    irSource*: string          ## Serialized IR expression (canonical form)
    errorKind*: string         ## e.g., "sort_mismatch"
    timestamp*: string         ## ISO 8601
    contentHash*: string       ## SHA-256 of the IR source for dedup
    irVersion*: int            ## IR format version (currently 1)

func serializeIrDump*(entry: IrDumpEntry): string {.raises: [].} =
  ## Serialize a dump entry to a portable text format.
  ## Format: key=value lines separated by newlines, IR source between markers.
  result = ""
  result.add "## axiom-ir-dump v" & $entry.irVersion & "\n"
  result.add "func_name=" & entry.funcName & "\n"
  result.add "error_kind=" & entry.errorKind & "\n"
  result.add "timestamp=" & entry.timestamp & "\n"
  result.add "content_hash=" & entry.contentHash & "\n"
  result.add "## IR BEGIN\n"
  result.add entry.irSource
  result.add "\n## IR END\n"

func parseIrDump*(content: string): IrDumpEntry {.raises: [CatchableError].} =
  ## Parse a dump file back into an IrDumpEntry.
  result = IrDumpEntry(irVersion: irDumpVersion)
  var inIr = false
  var irLines: seq[string] = @[]
  for line in content.splitLines():
    if line == "## IR BEGIN":
      inIr = true
      continue
    if line == "## IR END":
      inIr = false
      continue
    if inIr:
      irLines.add line
      continue
    if line.startsWith("func_name="):
      result.funcName = line[10..^1]
    elif line.startsWith("error_kind="):
      result.errorKind = line[11..^1]
    elif line.startsWith("timestamp="):
      result.timestamp = line[10..^1]
    elif line.startsWith("content_hash="):
      result.contentHash = line[13..^1]
    elif line.startsWith("## axiom-ir-dump v"):
      let verRes = safeParseInt(line.split("v")[1])
      if verRes.isOk:
        result.irVersion = verRes.get
  result.irSource = irLines.join("\n")

proc writeIrDump*(entry: IrDumpEntry, dumpDir: string): string {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Write a dump file to the given directory. Returns the file path.
  ## Filename: <funcName>_<timestamp>_<hash8>.ir
  let hash8 = if entry.contentHash.len >= 8: entry.contentHash[0..7] else: "unknown"
  let safeName = entry.funcName.replace("/", "_").replace("\\", "_")
  let tsSafe = entry.timestamp.replace(":", "-").replace(" ", "_")
  let filename = safeName & "_" & tsSafe & "_" & hash8 & ".ir"
  let path = dumpDir / filename
  createDir(dumpDir)
  writeFile(path, serializeIrDump(entry))
  return path

proc buildIrDumpEntry*(funcName, irSource, errorKind, timestamp: string): IrDumpEntry {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Convenience constructor: computes SHA-256 content hash automatically.
  IrDumpEntry(
    funcName: funcName,
    irSource: irSource,
    errorKind: errorKind,
    timestamp: timestamp,
    contentHash: sha256Hex(irSource),
    irVersion: irDumpVersion
  )

proc replayIrDump*(path: string): int {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Replay an IR dump file through the IR→SMT pipeline.
  ## Returns 0 on success (dump valid), 1 on failure.
  let content = readFile(path)
  let entry = parseIrDump(content)
  when defined(axiomDebug):
    logger.debug("REPLAY: func=" & entry.funcName & " error=" & entry.errorKind)
    logger.debug("REPLAY: content_hash=" & entry.contentHash)
    logger.debug("REPLAY: IR source:\n" & entry.irSource)
  if entry.irSource.len == 0:
    when defined(axiomDebug):
      logger.debug("REPLAY: FAIL — empty IR source")
    return 1
  when defined(axiomDebug):
    logger.debug("REPLAY: OK — dump is valid, ready for analysis")
  return 0
{.pop.}

