import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Integrity Guard Orchestrator (Wave 4)
##
## Orchestrates the physical injection of verified Axiom-IR contracts
## into original source files. Only runs after Lean 4 proof succeeds.
## Guarantees: backup before write, idempotent re-injection,
## zero modification on failure.

import std/strutils
import std/os
import core/utils/io_utils
import core/results
import frontend/nim/weaver
import core/frontend_ir
import core/axiom_pragmas
# axiomIoBoundary

## Apply Guard To Source.
# @axiom-hint: lean="modulePath.length = 0 ∨ functionName.length = 0 ∧ woven = sourceCode ∧ backupRes.isOk = true ∧ result = true ∧ false ∧ true ∧ modulePath.length = 0 ∨ functionName.length = 0 → result = false ∧ woven = sourceCode → result = true ∧ (result ≥ 0)" smt="(assert (and (or (= (str.len modulePath) 0) (= (str.len functionName) 0)) (= woven sourceCode) (= (option.isSome backupOpt) true) (= result true) false true (=> (or (= (str.len modulePath) 0) (= (str.len functionName) 0)) (= result false)) (=> (= woven sourceCode) (= result true)) (>= result 0)))"
proc applyGuardToSource*(
  modulePath: string;
  functionName: string;
  ir: FrontendIrNode;
  sourceCode: string
): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Inject Axiom-IR guards into the source file at modulePath.
  ## Returns true if the file was written successfully.
  ## On any failure the original source is preserved.
  if modulePath.len == 0 or functionName.len == 0:
    return false

  let woven = weaveGuards(sourceCode, ir)
  if woven == sourceCode:
    # Nothing to inject (no guards produced)
    return true

  let backupPath = modulePath & ".bak"

  # Create backup if not already present
  if not fileExists(backupPath):
    let writeRes = writeFileOpt(backupPath, sourceCode)
    if not writeRes.isOk:
      return false

  # Write woven source
  let writeRes = writeFileOpt(modulePath, woven)
  if not writeRes.isOk:
    # Attempt restore from backup on write failure
    if fileExists(backupPath):
      let backupRes = readFileOpt(backupPath)
      if backupRes.isOk:
        ## intentional-discard: restore from backup on write failure; best-effort recovery
        discard writeFileOpt(modulePath, backupRes.get())
    return false

  result = true

## Restore Source From Backup.
# @axiom-hint: lean="backupRes.isErr = true ∧ false ∧ backupRes.isErr = true → result = false ∧ (result ≥ 0)" smt="(assert (and (= (option.isNone backupOpt) true) false (=> (= (option.isNone backupOpt) true) (= result false)) (>= result 0)))"
proc restoreSourceFromBackup*(modulePath: string): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Roll back a source file from its .bak backup.
  let backupPath = modulePath & ".bak"
  if not fileExists(backupPath):
    return false
  let backupRes = readFileOpt(backupPath)
  if backupRes.isErr:
    return false
  let writeRes = writeFileOpt(modulePath, backupRes.get())
  result = writeRes.isOk

## I Source Guarded.
# @axiom-hint: lean="contentRes.isErr = true ∧ false ∧ contentRes.isErr = true → result = false ∧ (result ≥ 0)" smt="(assert (and (= (option.isNone contentOpt) true) false (=> (= (option.isNone contentOpt) true) (= result false)) (>= result 0)))"
proc isSourceGuarded*(modulePath: string): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Check whether the source file contains any AxiomGuard markers.
  if not fileExists(modulePath):
    return false
  let contentRes = readFileOpt(modulePath)
  if contentRes.isErr:
    return false
  result = GuardMarkerPrefix in contentRes.get()

{.pop.}
