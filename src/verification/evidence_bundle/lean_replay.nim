import core/trusted/layer_declaration
axiomLayer "infrastructure"

## Verifier-side Lean replay — re-executes the certificate's embedded
## `leanSource` on the pinned kernel and returns the freshly OBSERVED axiom
## names alongside the verdict.
##
## Deliberately NOT part of `verification/kernel_reexecution` (a checker-closure
## member): the Evidence Bundle verifier is an external consumer of evidence,
## not an admission adjudicator, so it must not expand the Tier C closure
## (ADR-0025 §9 "closure 팽창 금지"). No judgment logic is duplicated — the
## appended `#print axioms` target, the observation parser, the INV-6 allowlist
## gate and the verdict vocabulary all come from the shared, pinned module;
## only the process-invocation boilerplate lives here.

import std/[json, os, osproc, strutils]
import core/axiom_pragmas
import core/crypto/hash_kernel
import core/trusted/env_types
import infrastructure/process_utils
import verification/kernel_reexecution

proc reexecuteLeanObserved*(certJson: JsonNode; leanExe: string; timeoutMs: int):
    tuple[verdict: KernelVerdict; axes: seq[string]] {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Mirrors `reexecuteLean` exactly (QUIRK(runGitEx-argv-flattening): the Lean
  ## source travels through a temp FILE, never inline) and additionally returns
  ## the observed axiom names so the verifier can compare the three surfaces
  ## (certificate `axiomsUsed`, KAA `observedAxiomSet`, fresh run).
  result = (verdict: krMissingInput, axes: @[])
  if certJson.isNil or certJson.kind != JObject:
    return
  let leanSource = certJson.getOrDefault("leanSource").getStr("")
  if leanSource.len == 0:
    return
  let artifactSource =
    if "#print axioms" in leanSource:
      leanSource
    else:
      let target = firstDeclaredName(leanSource)
      if target.len == 0:
        return
      leanSource & "\n#print axioms " & target & "\n"
  let cmdBase =
    if leanExe.len > 0:
      leanExe
    else:
      let envCmd = getAxiomEnv(evLeanCmd, "")
      if envCmd.len > 0: envCmd else: "lake env lean"
  var artifactPath = ""
  var output = ""
  var exitCode = -1
  try:
    artifactPath = getTempDir() / ("axiom_kreexec_" & sha256Hex(artifactSource) & ".lean")
    writeFile(artifactPath, artifactSource)
    (output, exitCode) = execCmdWithTimeout(
      cmdBase & " --threads=1 " & quoteShell(artifactPath),
      timeoutMs = timeoutMs)
  except CatchableError:
    if artifactPath.len > 0:
      try: removeFile(artifactPath)
      except CatchableError: discard  # axiom:best-effort(temp artifact cleanup)
    result.verdict = krInternalError
    return
  if artifactPath.len > 0:
    try: removeFile(artifactPath)
    except CatchableError: discard  # axiom:best-effort(temp artifact cleanup)
  if exitCode == -1:
    result.verdict = krTimeout
    return
  if exitCode != 0:
    result.verdict = krCompileError
    return
  let observation = parsePrintAxiomsObservations(output)
  result.axes = observation.names
  result.verdict = evaluateObservedAxioms(observation)