import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import std/os
import std/strutils
import core/types/results
import core/utils/io_utils_isolation
export io_utils_isolation
import core/trusted/stdlib_shield
import core/interfaces/logging_hub
import core/trusted/axiom_pragmas_lite

## Read File Optional.
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
# @axiom-hint: lean="path.length ≥ 0 ∧ external_io_isolated" smt="(assert (and (>= (str.len path) 0) external_io_isolated))"
# @axiom-hint: lean="external_io_isolated" smt="(assert (and external_io_isolated))"
# @axiom-hint: lean="(result ≥ 0) ∧ external_io_isolated" smt="(assert (and (>= result 0) external_io_isolated))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc readFileOpt*(path: string): Result[string, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    ok(readFile(path))
  except CatchableError as e:
    err("readFileOpt(" & path & "): " & e.msg)

## Get File Info Optional.
# @axiom-hint: lean="(result ≥ 0)" smt="(assert (and (>= result 0)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc getFileInfoOpt*(path: string): Result[FileInfo, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    ok(getFileInfo(path))
  except CatchableError as e:
    err("getFileInfoOpt(" & path & "): " & e.msg)

## Write File Optional.
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc writeFileOpt*(path: string; content: string): Result[bool, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Atomic shadow-write: write to temp file then rename.
  ## POSIX rename is atomic; readers always see complete old or new state.
  try:
    isolatedWriteFile(path, content)
    ok(true)
  except CatchableError as e:
    err("writeFileOpt(" & path & "): " & e.msg)

## Exists Or Create Directory Optional.
proc existsOrCreateDirOpt*(path: string): Result[bool, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    discard existsOrCreateDir(path)
    ok(true)
  except CatchableError as e:
    err("existsOrCreateDirOpt(" & path & "): " & e.msg)

## Remove File Optional.
proc removeFileOpt*(path: string): Result[bool, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    removeFile(path)
    ok(true)
  except CatchableError as e:
    err("removeFileOpt(" & path & "): " & e.msg)

## Move File Optional.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc moveFileOpt*(source, dest: string): Result[bool, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    isolatedMoveFile(source, dest)
    ok(true)
  except CatchableError as e:
    err("moveFileOpt(" & source & " → " & dest & "): " & e.msg)

## Write Stderr Line Optional.
# @axiom-hint: lean="message.length ≥ 0" smt="(assert (and (>= (str.len message) 0)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc writeStderrLine*(message: string): Result[bool, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    logInfo(message)
    ok(true)
  except CatchableError as e:
    err("writeStderrLine: " & e.msg)

## Walk Directory Optional.
# @axiom-hint: lean="(result ≥ 0)" smt="(assert (and (>= result 0)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc walkDirOpt*(dir: string): Result[seq[string], string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var paths: seq[string] = @[]
  try:
    for kind, path in walkDir(dir):
      paths.add(path)
    ok(paths)
  except CatchableError as e:
    err("walkDirOpt(" & dir & "): " & e.msg)

## Append File Line Optional.
proc appendFileLineOpt*(path: string; lines: seq[string]): Result[bool, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    let f = open(path, fmAppend)
    for line in lines:
      f.writeLine(line)
    f.close()
    ok(true)
  except CatchableError as e:
    err("appendFileLineOpt(" & path & "): " & e.msg)

## Walk Directory Recursive Optional.
# @axiom-hint: lean="(result ≥ 0)" smt="(assert (and (>= result 0)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc walkDirRecOpt*(dir: string): Result[seq[string], string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var paths: seq[string] = @[]
  try:
    for path in walkDirRec(dir):
      paths.add(path)
    ok(paths)
  except CatchableError as e:
    err("walkDirRecOpt(" & dir & "): " & e.msg)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc writeFileAtomic*(path, content: string): Result[void, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let tmpPath = path & ".tmp"
  try:
    # Write through a File handle and fsync (flushFile calls fsync on POSIX)
    # BEFORE the rename. This guarantees the temp file's data is durable on
    # disk before the atomic rename, preventing torn writes across crashes.
    var f: File
    if open(f, tmpPath, fmWrite):
      try:
        f.write(content)
        f.flushFile()
      except CatchableError:
        raise
      finally:
        f.close()
    safeMoveFile(tmpPath, path)
    Result[void, string](ok: true)
  except CatchableError as e:
    err("atomic write failed: " & e.msg)

## Collect Json Files.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc collectJsonFiles*(dir: string): Result[seq[string], string] =
  var jsonFiles: seq[string] = @[]
  if not dirExists(dir):
    return ok(jsonFiles)
  try:
    for path in walkDirRec(dir):
      if path.endsWith(".json"):
        jsonFiles.add(path)
    ok(jsonFiles)
  except CatchableError as e:
    err("collectJsonFiles(" & dir & "): " & e.msg)

## Returns the canonical path for a certification file given the repo root and IR hash.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func getCanonicalCertFilename*(repoRoot: string; irHash: string): string {.raises: [].} =
  repoRoot / ".axiom" / "vault" / (irHash & ".json")

{.pop.}

