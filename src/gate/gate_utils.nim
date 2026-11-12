import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## Axiom Gate Common Utilities
## SSOT for shared gate infrastructure — RLIMIT, exec bonding, etc.
## Imported by gate_hook, gate_replay, orchestrator.

import std/os
import std/osproc
import std/posix
import core/gate/resource_limits
import core/results
import core/trusted/env_access
import core/trusted/axiom_pragmas
export resource_limits.raiseRlimitNoFile

proc execCmdExWithBond*(cmd: string): tuple[output: string, exitCode: int] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Wraps execCmdEx with AXIOM_GATE_BOND=1 to prevent infinite recursion
  ## through config.nims (compile-time quality gate).
  let prev = getAxiomEnv(evGateBond)
  try:
    putEnv("AXIOM_GATE_BOND", "1")
  except OSError:
    discard
  try:
    result = execCmdEx(cmd)
  except OSError:
    result = ("", 1)
  except IOError:
    result = ("", 1)
  if prev.len == 0:
    try:
      delEnv("AXIOM_GATE_BOND")
    except OSError: # axiom:best-effort(env var operation failure is non-fatal)
      discard
  else:
    try:
      putEnv("AXIOM_GATE_BOND", prev)
    except OSError: # axiom:best-effort(env var operation failure is non-fatal)
      discard

proc safeExecCmd*(command: string): Result[tuple[output: string, exitCode: int], string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## I/O 경계에서 예외를 Result 값으로 격리 (Exception-to-Value Lifting).
  ## src/gate/ 내부의 고수준 함수는 이 함수를 통해 간접 호출하면
  ## {.raises: [].}을 유지할 수 있습니다.
  ## Context7 검증: std/results는 Nim 공식 에러 핸들링 패턴.
  try:
    let (outp, code) = execCmdEx(command)
    ok((outp, code))
  except CatchableError as e:
    err("Execution failed: " & e.msg)

import std/strutils
import gate/gate_types

proc shouldRun*(gate: GateConfig; stage: GateStage; changedFiles: seq[string]): bool =
  ## Determine whether a gate should run for the given stage and changed files.
  ## SSOT: this is the ONLY definition of shouldRun in the codebase.
  ##
  ## Deterministic scope routing (Lefthook/pre-commit pattern):
  ##   - A gate whose `stages` does not contain `stage` never runs.
  ##   - A gate tagged `gsCI` runs only under AXIOM_CI=1 (CI-only, local DX offload).
  ##   - When the change-set is empty, only `alwaysRun` gates execute; gates with a
  ##     filesPattern are skipped (their pattern cannot match nothing). This replaces
  ##     the previous anti-pattern of running every gate on an empty change-set.
  if stage == gsAnyCi:
    return gsPreCommit in gate.stages or gsPrePush in gate.stages or gsCI in gate.stages
  if stage notin gate.stages:
    return false
  if gsCI in gate.stages and getAxiomEnv(evCi) != "1":
    return false
  if gate.filesPattern.len == 0:
    return true
  let patterns = gate.filesPattern.split('|')
  for f in changedFiles:
    for p in patterns:
      if f.contains(p.strip()):
        return true
  return gate.alwaysRun
{.pop.}

