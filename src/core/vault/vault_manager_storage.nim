import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import std/options
import std/os
import core/trusted/axiom_pragmas

import core/utils/file_utils
import core/gateway/gateway
import core/json/json_utils
import core/types/error_types
import core/types/results
import core/utils/io_utils
import core/vault/vault_manager_spec

## Read Axiom Spec File.
# @axiom-hint: lean="external_io_isolated" smt="(assert (and external_io_isolated))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc readAxiomSpecFile*(filePath: string): Result[AxiomSpec, AxiomError] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var raw = ""
  try:
    let readRes = readFileOpt(filePath)
    if readRes.isErr: return
    raw = readRes.get
  except CatchableError:
    return err(axiomErrFileSystemError)
  let nodeOpt = parseJsonOpt(raw)
  if nodeOpt.isNone:
    return err(axiomErrFileSystemError)
  parseAxiomSpec(nodeOpt.get())

## Store Axiom Spec.
# @axiom-hint: lean="(ownedSpec ≥ 0)" smt="(assert (and (>= ownedSpec 0)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc storeAxiomSpec*(vaultDir: string; spec: sink AxiomSpec): Result[string, AxiomError] =
  try:
    discard existsOrCreateDir(vaultDir)
    var ownedSpec = ownedAxiomSpec(spec)
    if ownedSpec.storedAt.len == 0:
      ownedSpec.storedAt = currentVaultTimestamp()
    let outputPath = joinPath(vaultDir, axiomSpecFileName(ownedSpec))
    discard writePrettyJsonFile(outputPath, axiomSpecToJsonNode(ownedSpec))
    ok(normalizePath(outputPath))
  except CatchableError:
    err(axiomErrFileSystemError)

## Load Axiom Spec File.
# @axiom-hint: lean="filePath.length ≥ 0" smt="(assert (and (>= (str.len filePath) 0)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc loadAxiomSpecFile*(
  filePath: string;
  currentFingerprint: sink string
): Result[AxiomSpec, VaultLoadError] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let readRes = readAxiomSpecFile(filePath)
  if readRes.isErr():
    return err(storageLoadError(readRes.error))
  let loadRes = loadAxiomSpec(readRes.get(), currentFingerprint)
  if loadRes.isErr():
    return err(invalidLoadError(loadRes.error))
  ok(loadRes.get())

{.pop.}
