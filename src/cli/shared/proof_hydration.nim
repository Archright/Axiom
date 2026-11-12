import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [].}
## Shared Proof State Hydration — canonical VKD projection for ax report.
##
## getCanonicalVkdMetrics is journal-driven (TrustCommit authority) and is
## consumed by ax report (report_cli.nim); the vault-scan helpers in this
## module feed the engineering baseline snapshot (baseline_snapshot_core.nim)
## only. Canonical ASI lives in verification/proof_state_builder.nim, not
## here.

import infrastructure/logging_facade
import std/json
import std/os
import std/strutils
import core/results
import core/types/vkd_types
import core/proof/proof_integrity
import core/trusted/axiom_pragmas
import core/trusted/trust_commit
import core/types/certificate_types
import verification/certificate_verifier
import verification/cert_reconcile

const StableVaultDir* {.axiomDebt: "DEBT#433".} = "src" / "verification" / "certificates"
  ## Stable certificate vault (tracked reference store on disk). Post-#936
  ## no reader consumes this const: getCanonicalVkdMetrics is journal-driven
  ## (TrustCommit authority) and never reads this store, and the vault-scan
  ## helper (countKernelSymbolsDeepVerified, consumed by baseline_snapshot_core)
  ## takes its certDir as a caller-supplied parameter.
  ## read-side SSOT mirrors resolveVaultDir in src/cli/axiom_engine.nim.
  ## env-based override (AXIOM_PROVE_VAULT_DIR) is intentionally NOT
  ## consulted here: this module is pure ({.raises: [].}) and has no env
  ## access.
  ## DEBT#433: No structural test asserts product readers do not read tracked
  ## reference store. The pre-#936 proof_hydration vault-scan fallback that
  ## read the reference store was removed (90dcbfdf2); this tracked-marker
  ## const is retained pending DEBT#433 registry resolution.

proc readVaultCertNodes*(certDir: string): seq[JsonNode] {.raises: [].} =
  ## Reads all JSON certificate entries from the stable vault. Pure helper —
  ## every I/O operation is guarded so this never raises (fail-closed: empty).
  result = @[]
  if not dirExists(certDir):
    return
  try:
    for kind, path in walkDir(certDir):
      if kind != pcFile or not path.endsWith(".json"):
        continue
      try:
        let node = parseJson(readFile(path))
        if node.kind == JObject:
          result.add(node)
      except CatchableError:  # axiom:best-effort(unreadable or malformed cert skipped from informational vault scan)
        discard
  except CatchableError:
    result = @[]

proc countKernelSymbolsDeepVerified*(
  scope: KernelScopeInfo;
  certProvider: proc(modulePath: string; functionName: string): JsonNode {.raises: [].};
  verifier: DeepVerifyFn
): int {.raises: [].} =
  ## CANONICAL VKD numerator predicate — the number of kernel symbols that are
  ## admitted via proof_integrity.isVkdAdmissible (certGreen-only gate).
  ##
  ## Lives in the presentation layer (src/cli/shared) NOT src/core — the three
  ## consumers (report_cli.nim, baseline_snapshot_core.nim, this module) are all
  ## CLI-layer, and adding procs to src/core trips the architecture_invariants
  ## procCount<=950 guard. The predicate itself (isVkdAdmissible) remains core.
  ##
  ## Iterates only over `scope.kernelSymbols`, so Set Membership is satisfied
  ## by construction — a matching cert's `modulePath::functionName` equals the
  ## symbol being counted. Fail-closed: empty/degraded scope yields 0.
  if scope.kernelTotal <= 0 or scope.kernelSymbols.len == 0:
    return 0
  for symbol in scope.kernelSymbols:
    if symbol in scope.kernelExemptSymbols:
      continue
    let sep = symbol.find("::")
    if sep <= 0:
      continue
    let modulePath = symbol[0 ..< sep]
    let functionName = symbol[sep + 2 .. ^1]
    let cert = certProvider(modulePath, functionName)
    if cert.isNil or cert.kind != JObject:
      continue
    let entry = RuntimeAxiomEntry(name: functionName, isKernel: true)
    if proof_integrity.isVkdAdmissible(cert, entry, scope, verifier) == proof_integrity.varAdmit:
      inc result

proc countKernelSymbolsDeepVerified*(
  certDir: string;
  scope: KernelScopeInfo
): int {.raises: [].} =
  ## Canonical VKD numerator predicate — number of kernel_symbols (Set Membership)
  ## that pass proof_integrity.isVkdAdmissible (certGreen-only gate over
  ## 3-stage zero-trust + Set Membership).
  ##
  ## # CANONICAL DECLARATION: proof_integrity.isVkdAdmissible is the
  ## SINGLE GENUINE QUALIFICATION PREDICATE. All callers (countKernelVerified in
  ## baseline_snapshot_core.nim, this function, and report_cli.nim) delegate to
  ## countKernelSymbolsByAdmitted — ensuring VKD numerator convergence.
  ##
  ## Iterates only over `scope.kernelSymbols`, so Set Membership is satisfied
  ## by construction — a matching cert's `modulePath::functionName` equals the
  ## symbol being counted. Fail-closed: empty/degraded scope, empty vault, or
  ## I/O errors all yield 0.
  let certs = readVaultCertNodes(certDir)
  result = countKernelSymbolsDeepVerified(scope,
    proc (modulePath: string; functionName: string): JsonNode {.raises: [].} =
      for cert in certs:
        if cert{"modulePath"}.getStr("") == modulePath and
           cert{"functionName"}.getStr("") == functionName:
          return cert
      nil
    , certificate_verifier.isDeepVerified)

proc getCanonicalVkdMetrics*(
  repoRoot: string;
  forceHydration: bool = false
): VkdMetrics {.raises: [].} =
  ## Single source of truth for VKD metrics — TrustCommit journal authority.
  ##
  ## Numerator: kernel symbols whose CURRENT-CONTEXT evidence exists as a v1
  ## full-cert certGreen claim in the TrustCommit journal
  ## (data/trusted/journal), gated by verifyCertificateClosure and
  ## proof_integrity.isVkdAdmissible, quarantined/deduplicated per
  ## cert_reconcile.computeJournalVkdAdmission. v2 compact `entries[]`
  ## journal records are checkpoints and never admit.
  ## Denominator: |VKS| from data/verification_scope.lock in the same
  ## context (vksTotal; kernelTotal fallback for pre-v3 locks).
  ## The L1 cache (logs/ax_proof_state.json) and the reference certificate
  ## vault (src/verification/certificates) are NOT authority here and are
  ## never read (first journal-driven version ignores the cache entirely).
  ## `forceHydration` is retained for API compatibility and ignored — the
  ## journal is always the live authority; no cache/hydration pass exists.
  try:
    let scope = loadKernelScope(repoRoot / "data" / "verification_scope.lock", failClosed = true)
    let totalFuncs = if scope.vksTotal > 0: scope.vksTotal else: scope.kernelTotal
    if totalFuncs <= 0:
      return VkdMetrics(failed: true)
    # The journal root is the SAME authority the writer used; `repoRoot` stays
    # the source root for staleness/binding checks.
    let admission = computeJournalVkdAdmission(activeJournalRoot(repoRoot), scope, repoRoot)
    if admission.isErr():
      logError("proof_hydration", "fail-closed: journal VKD admission unavailable: " & admission.error)
      return VkdMetrics(failed: true)
    VkdMetrics(verifiedCount: admission.value.counted, totalCount: totalFuncs)
  except CatchableError as e:
    # Fail-closed: unreadable lock/journal yields explicit FAIL (never a fabricated ratio).
    logError("proof_hydration", "fail-closed: journal-driven VKD unavailable: " & e.msg)
    return VkdMetrics(failed: true)

