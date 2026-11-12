import core/trusted/layer_declaration
axiomLayer "verification"
{.push raises: [CatchableError].}

## Execution context capture — the ONE site that measures the current
## execution identity.
##
## The canonical execution contract was previously re-assembled at each call
## site (src/cli/axiom_engine.nim, src/verification/obligation/
## canonical_verification.nim), which let the platform component drift into a
## literal while the rest stayed measured. It is assembled here once, from
## measured inputs only:
##
##   platform  — identity.hostPlatformId (compiled-in hostOs/hostCpu)
##   config    — canonical execution-config digest, conditions (c)
##   bundle    — lean_kernel_boundary.computeBundleDigest, condition (b)
##   toolchain — canonical_verification.captureToolchainIdentity (D2), condition (e)
##   epoch     — sha256(toolchain|config|bundle) = the EXECUTION semantic epoch
##   engineBuild — attestation_orchestrator.verifierEngineBuildId, condition (e):
##                 the content-based verifier build identity, observable for
##                 EVERY verdict class (green/red/refusal) — the state envelope
##                 is the run-level observation surface, so a run that produced
##                 no per-node certificate files (a DISPROVED subject, for
##                 instance) still binds to the verifier build that ran it.
##
## §A3: the value named `executionEpoch` below is the execution semantic epoch.
## It is NOT the CI epoch / cutover generation of docs/agents/ci_epoch_cutover.md;
## a CI generation number must never enter this identity.
##
## Fail-closed: a component that cannot be measured stays empty, so no reuse
## record and no restored state can match it.

import std/os
import core/axiom_pragmas
import core/crypto/hash_kernel
import core/trusted/env_access
import verification/accounting/run_accounting
import verification/attestation_orchestrator
import verification/obligation/canonical_verification
import verification/obligation/identity
import verification/obligation/lean_kernel_boundary

const
  contractInvocation* = "lake env lean --threads=1 <artifact>.lean"
  ## Canonical argv role literal — physical paths never enter the contract.
  contractWorkdirRole* = "<execution>"
  contractFsBoundaryRole* = "<subject>"
  contractNetworkPolicy* = "deny"
  contractResourcePolicy* = "cpu=1,mem=512MB"
  bundleDigestTimeoutMs* = 120_000

func canonicalExecutionContractForRun*(repoRoot: string): ExecutionContract {.raises: [].} =
  ## The run-level execution contract: identical shape on the write path
  ## (`ax prove`) and the read path (`ax report`), so a state written by one
  ## process re-validates against another process on the same host.
  ## `mountedInputs` is empty at run level — the per-unit input binding is
  ## covered by §15.3 condition (a), the subject fingerprint.
  canonicalExecutionContract(
    invocation = contractInvocation,
    platform = hostPlatformId,
    workdir = contractWorkdirRole,
    allowedEnv = @[
      EnvVarSpec(name: "AXIOM_LEAN_CMD", canonicalValue: canonicalizeEnvValue("AXIOM_LEAN_CMD", getEnv("AXIOM_LEAN_CMD", ""), repoRoot)),
      EnvVarSpec(name: "PATH", canonicalValue: canonicalizeEnvValue("PATH", getEnv("PATH", ""), repoRoot)),
      EnvVarSpec(name: "TMPDIR", canonicalValue: canonicalizeEnvValue("TMPDIR", getEnv("TMPDIR", ""), repoRoot))
    ],
    fsBoundary = contractFsBoundaryRole,
    networkPolicy = contractNetworkPolicy,
    mountedInputs = "",
    resourcePolicy = contractResourcePolicy
  )

proc captureReuseVerificationContext*(): ReuseVerificationContext {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Current reuse-verification context (execution path AND read path). The
  ## measured canonical execution-bundle fingerprint uses the same Lean
  ## resolution as the kernel check, so both sides of a comparison resolve the
  ## same binary (QUIRK(DEBT#427): an elan shim may point elsewhere).
  let leanCmd = getAxiomEnv(evLeanCmd, "")
  let resolvedCmd = if leanCmd.len > 0: leanCmd else: "lake env lean"
  let leanPath = try: resolveLeanBinaryPath() except CatchableError: ""
  let lakePath = findExe("lake")
  let bundleFp = computeBundleDigest(leanPath, lakePath, bundleDigestTimeoutMs, resolvedCmd)
  let configDigest = executionContractDigest(canonicalExecutionContractForRun(getCurrentDir()))
  let toolchainIdentity = captureToolchainIdentity()
  result = ReuseVerificationContext(
    executionBundleFingerprint: bundleFp,
    executionConfigDigest: configDigest,
    toolchainIdentity: toolchainIdentity,
    currentEpoch: sha256Hex(toolchainIdentity & "|" & configDigest & "|" & bundleFp),
    verifierBuildId: verifierEngineBuildId(),
    platform: hostPlatformId
  )

{.pop.}