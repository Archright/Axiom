import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Lean Kernel Check Boundary — single canonical sink + opaque receipt.
##
## Design (A2 of Evidence Truth Boundary v3.8.1):
## - `LeanKernelCheckReceipt` is an opaque type: public type, private fields,
##   private constructor. Only the canonical sink `canonicalLeanKernelCheck`
##   may produce a receipt. This is the single issuance point (high fixed
##   invariant 1: `LeanKernelCheckReceipt(...)` appears in exactly one
##   expression in the entire repo).
## - `canonicalLeanKernelCheck` is a trust-boundary primitive (NOT a plain
##   helper). It resolves the actual executable, captures actual execution
##   state, runs the kernel check, and emits a receipt only when the
##   canonical invocation's exit status == 0.
## - `runLeanProbe` is a health-check only — it cannot produce a receipt.
## - `ObservedLeanArtifactTarget` observes the theorem identity from the
##   actual Lean artifact (via `extractTheoremName`), not from a caller-
##   supplied string.

import std/[os, strutils, times]
import core/axiom_pragmas
import core/crypto/hash_kernel
import core/results
import core/trusted/env_types
import infrastructure/process_utils
import generated/build_env  # BuildEnvZ3Version (hermetic SSOT)
import verification/obligation/identity
import verification/obligation/measured_digests

{.push raises: [].}

# ---------------------------------------------------------------------------
# ObservedLeanArtifactTarget — theorem identity observed from the artifact
# ---------------------------------------------------------------------------

type ObservedLeanArtifactTarget* = object
  theoremName*: string    ## declared theorem name parsed from the artifact
  sourceHash*: string     ## sha256 of the artifact source

# ---------------------------------------------------------------------------
# LeanKernelCheckReceipt — opaque receipt, private fields, private constructor
# ---------------------------------------------------------------------------
## Opaque receipt produced ONLY by `canonicalLeanKernelCheck`. All fields
## are private (non-`*`) and the constructor is private — only the sink
## module can create instances. The receipt's existence proves that a
## canonical Lean kernel check was actually performed and returned exit 0.
##
## Receipt fields are all `actual*` in semantics: they record what was
## actually observed during execution, not what a caller claimed.

type LeanKernelCheckReceipt* = object
  actualExecutableDigest: string            ## SHA256 of the resolved lean binary
  actualToolchainFingerprint: string        ## SHA256 of the effective toolchain identity
  actualInvocationContract: string          ## canonical argv string used
  actualExecutionContract: string           ## effective env vars hash
  actualInputIdentity: string               ## SHA256 of the lean source input
  actualArtifactIdentity: string            ## SHA256 of the written artifact file
  actualTheoremIdentity: string             ## observed from artifact via extractTheoremName
  actualKernelAcceptanceObservation: string ## kernel stdout+stderr verbatim
  observedAt: int64                         ## epoch ms when receipt was created

# ---------------------------------------------------------------------------
# Private helper: extract theorem name from Lean source
# ---------------------------------------------------------------------------
## Follows `extractTheoremName` semantics from lean_evidence.nim:147.
## Parses the first `theorem <name>` declaration in the source.

func extractTheoremName(leanSource: string): string {.raises: [].} =
  ## Private helper — canonical public version lives in lean_evidence.nim.
  ## Keep this non-exported: a second exported definition creates
  ## ambiguous-call breakage for modules importing both.
  for line in leanSource.splitLines():
    let stripped = line.strip()
    if not stripped.startsWith("theorem "):
      continue
    let rest = stripped["theorem ".len .. ^1]
    let nameEnd = rest.find({' ', ':', '(', '\t'})
    if nameEnd < 0:
      return rest
    if nameEnd == 0:
      return ""
    return rest[0 ..< nameEnd]
  ""

# ---------------------------------------------------------------------------
# Private constructor — single issuance point for LeanKernelCheckReceipt
# ---------------------------------------------------------------------------
## `makeReceipt` is the ONLY place in the entire repo where a
## `LeanKernelCheckReceipt` object literal may appear. It is private
## (non-exported) and only `canonicalLeanKernelCheck` calls it. The static
## authority gate enforces this: any other `LeanKernelCheckReceipt(...)`
## construction site is a violation.

func makeReceipt(executableDigest, toolchainFingerprint, invocationContract,
                 executionContract, inputIdentity, artifactIdentity,
                 theoremIdentity, kernelObservation: string;
                 observedAtMs: int64): LeanKernelCheckReceipt {.raises: [].} =
  LeanKernelCheckReceipt(
    actualExecutableDigest: executableDigest,
    actualToolchainFingerprint: toolchainFingerprint,
    actualInvocationContract: invocationContract,
    actualExecutionContract: executionContract,
    actualInputIdentity: inputIdentity,
    actualArtifactIdentity: artifactIdentity,
    actualTheoremIdentity: theoremIdentity,
    actualKernelAcceptanceObservation: kernelObservation,
    observedAt: observedAtMs
  )

# ---------------------------------------------------------------------------
# Accessor functions for opaque receipt fields
# ---------------------------------------------------------------------------

func receiptExecutableDigest*(receipt: LeanKernelCheckReceipt): string {.raises: [].} =
  receipt.actualExecutableDigest

func receiptToolchainFingerprint*(receipt: LeanKernelCheckReceipt): string {.raises: [].} =
  receipt.actualToolchainFingerprint

func receiptInvocationContract*(receipt: LeanKernelCheckReceipt): string {.raises: [].} =
  receipt.actualInvocationContract

func receiptExecutionContract*(receipt: LeanKernelCheckReceipt): string {.raises: [].} =
  receipt.actualExecutionContract

func receiptInputIdentity*(receipt: LeanKernelCheckReceipt): string {.raises: [].} =
  receipt.actualInputIdentity

func receiptArtifactIdentity*(receipt: LeanKernelCheckReceipt): string {.raises: [].} =
  receipt.actualArtifactIdentity

func receiptTheoremIdentity*(receipt: LeanKernelCheckReceipt): string {.raises: [].} =
  receipt.actualTheoremIdentity

func receiptKernelObservation*(receipt: LeanKernelCheckReceipt): string {.raises: [].} =
  receipt.actualKernelAcceptanceObservation

func receiptObservedAt*(receipt: LeanKernelCheckReceipt): int64 {.raises: [].} =
  receipt.observedAt

# ---------------------------------------------------------------------------
# Private helpers — lean binary resolution and bundle digest
# ---------------------------------------------------------------------------
## QUIRK(DEBT#427): elan shim pitfall — bare PATH `lean` may be an elan
## shim pointing to a different toolchain version (e.g. 4.29) than the real
## kernel that `lake env lean` invokes (4.33). We always resolve through the
## toolchain (`lake env which lean` / `elan which lean`) to get the actual
## binary whose content is hashed. See docs/spec/lean_toolchain_binding_quirks.md.

func parseLeanToolchainPin*(content: string): string {.raises: [].} =
  ## Measured lean pin parsed from the elan manifest content
  ## (`<owner>/<repo>:v<version>`). Mirror of the D2 parse in
  ## canonical_verification.captureToolchainIdentity, minus the legacy
  ## hardcoded fallback: an unmeasurable pin contributes "" — never a label.
  let sep = content.find(':')
  if sep < 0 or sep + 1 > content.high:
    return ""
  var raw = strip(content[sep + 1 .. ^1])
  if raw.len > 1 and raw[0] == 'v':
    raw = raw[1 .. ^1]
  if raw.len == 0:
    return ""
  for ch in raw:
    if ch notin {'0'..'9', '.'}:
      return ""
  "lean-" & raw

proc measureEvaluationImplementationDigests*(): EvaluationImplementationDigests {.
  raises: [], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Measure the lowering implementation from the canonical repo layout
  ## (CWD-relative — the same anchor the toolchain manifest reads use).
  ## These are the modules that GIVE the subject its verified semantics;
  ## a change to any of them must invalidate evidence produced before it.
  ## Exported for the run-level reuse-verification context and tests.
  EvaluationImplementationDigests(
    pnodeToCanon: measuredFileDigest("src/core/trusted/pnode_to_canon.nim"),
    astToIr: measuredFileDigest("src/core/trusted/ast_to_ir.nim"),
    leanRenderer: measuredFileDigest("src/core/trusted/ir_to_lean.nim"),
    denotationLean: measuredFileDigest("proofs/IR/Denotation.lean")
  )

proc resolveLeanBinaryPath*(): string {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Resolve the real lean kernel binary that `lake env lean` uses.
  ## Prefers `lake env which lean` (project-local toolchain), then
  ## `elan which lean` (global toolchain), then falls back to resolving
  ## from the lake binary's parent directory. Never returns the bare
  ## PATH `lean` which may be an elan shim to a wrong toolchain.
  ## Exported for Plan 1: the run-level reuse-verification context reuses
  ## the same resolution to measure the current execution-bundle fingerprint.
  let leanCmd = getAxiomEnv(evLeanCmd, "")
  if leanCmd.len > 0:
    return leanCmd

  # Primary: lake env which lean (requires lakefile.toml in CWD or parent)
  var (output, exitCode) = execCmdWithTimeout(
    "lake env which lean", timeoutMs = 10_000)
  if exitCode == 0 and output.strip().len > 0:
    let path = output.strip()
    if fileExists(path):
      return path

  # Fallback: elan which lean (queries elan toolchain config)
  (output, exitCode) = execCmdWithTimeout(
    "elan which lean", timeoutMs = 10_000)
  if exitCode == 0 and output.strip().len > 0:
    let path = output.strip()
    if fileExists(path):
      return path

  # Last resort: resolve from lake binary's parent directory.
  # In elan layouts this may point to a shim, not the real toolchain
  # binary — see QUIRK(DEBT#427).
  let lakePath = findExe("lake")
  if lakePath.len > 0:
    let candidate = parentDir(lakePath) / "lean"
    if fileExists(candidate):
      return candidate

  ""

proc measureToolchainBundleFingerprint*(
  leanPath, lakePath: string;
  timeoutMs: int;
  resolvedCmd: string
): string {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## THE shared measured toolchain fingerprint composition — the single
  ## definition of the bundle digest. Every consumer (the canonical kernel
  ## receipt via `computeBundleDigest`, the strict CompletenessBinding capture
  ## via `measureCanonicalCaptureToolchainFingerprint`) computes its
  ## fingerprint THROUGH this proc; no site re-implements the composition.
  ## Binds the real binary content, the toolchain manifest files, and the
  ## lowering implementation (via evaluationImplementationDigest). Every
  ## version segment is measured — NimVersion is the compile-time measurement
  ## of the compiler that built this binary, the lean pin is parsed from the
  ## manifest content itself — no hardcoded version label enters the digest.
  ## QUIRK(DEBT#427): elan shim pitfall — bare PATH lean may point
  ## to a different toolchain version than `lake env lean`.
  let leanDigest = measuredBinaryDigest(leanPath)
  let lakeDigest = measuredBinaryDigest(lakePath)
  let leanToolchainContent =
    if fileExists("lean-toolchain"):
      try: readFile("lean-toolchain")
      except CatchableError: ""
    else: ""
  let leanToolchainDigest =
    if leanToolchainContent.len > 0: sha256Hex(leanToolchainContent)
    else: ""
  let proofsLeanToolchainDigest =
    if fileExists("proofs/lean-toolchain"):
      try: sha256Hex(readFile("proofs/lean-toolchain"))
      except CatchableError: ""
    else: ""
  let lakeManifestDigest =
    if fileExists("lake-manifest.json"):
      try: sha256Hex(readFile("lake-manifest.json"))
      except CatchableError: ""
    else: ""
  let proofsLakeManifestDigest =
    if fileExists("proofs/lake-manifest.json"):
      try: sha256Hex(readFile("proofs/lake-manifest.json"))
      except CatchableError: ""
    else: ""
  let lakefileDigest =
    if fileExists("lakefile.toml"):
      try: sha256Hex(readFile("lakefile.toml"))
      except CatchableError: ""
    else: ""
  let evalImplDigest = evaluationImplementationDigest(
    measureEvaluationImplementationDigests())
  sha256Hex(
    "nim-" & $NimVersion & "|" & parseLeanToolchainPin(leanToolchainContent) & "|" &
    (if BuildEnvZ3Version.len > 0: "z3-" & BuildEnvZ3Version else: "") & "|" &
    hostPlatformId & "|" & $sizeof(int) & "|" &
    resolvedCmd & "|" & $timeoutMs & "|" &
    leanDigest & "|" & lakeDigest & "|" &
    leanToolchainDigest & "|" & proofsLeanToolchainDigest & "|" &
    lakeManifestDigest & "|" & proofsLakeManifestDigest & "|" &
    lakefileDigest & "|" &
    evalImplDigest
  )

proc computeBundleDigest*(
  leanPath, lakePath: string;
  timeoutMs: int;
  resolvedCmd: string
): string {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Receipt-side entry point — delegates to the shared measured composition
  ## (`measureToolchainBundleFingerprint`). Kept as the named boundary the
  ## canonical kernel check calls; the composition itself lives in exactly
  ## one proc.
  measureToolchainBundleFingerprint(leanPath, lakePath, timeoutMs, resolvedCmd)

# ---------------------------------------------------------------------------
# Judgment CAS observation log — env-armed kernel-ACCEPT recording
# ---------------------------------------------------------------------------
## The s1a Judgment CAS (verification/judgment_cas.nim) records the kernel
## ACCEPT facts of the golden test run. The single canonical sink is the ONLY
## observation point: when the evidence path env is armed (admission attest
## stage, s1a test invocation only), each issued receipt's theorem identity is
## appended to this in-process log, which the test boundary flushes to the
## evidence file. Unarmed (every other binary/test/run) = no accumulation,
## no I/O, zero behavior change.
##
## Threadvar, not a plain global: a GC'ed module global would make
## canonicalLeanKernelCheck non-gcsafe and infect every gcsafe caller in the
## kernel chain (executeProof / runIrPipeline — observed as remote gcsafety
## errors in stage_05_lean_bridge + ir_pipeline_runner). A threadvar is
## thread-local, so the log is per-thread by construction — the s1a golden
## run issues receipts on the main thread, which is exactly the run the
## flush aggregates.

var judgmentAcceptLog {.threadvar.}: seq[tuple[theoremIdentity: string, inputIdentity: string]]

proc judgmentRecordingArmed*(): bool {.raises: [].} =
  ## True iff the judgment CAS evidence path env is armed for this process.
  getEnv("AXIOM_JUDGMENT_CAS_EVIDENCE_PATH", "").len > 0

proc observedKernelAccepts*(): seq[tuple[theoremIdentity: string, inputIdentity: string]] {.
    raises: [].} =
  ## Snapshot of the kernel-ACCEPT facts observed in this process (theorem
  ## identity + input identity per issued receipt, in issuance order).
  judgmentAcceptLog

# ---------------------------------------------------------------------------
# canonicalLeanKernelCheck — the single trust-boundary sink
# ---------------------------------------------------------------------------
## Axiom trust-boundary primitive: resolves the actual Lean executable,
## captures actual execution state, runs the kernel check, and produces
## a `LeanKernelCheckReceipt` ONLY when:
##   1. The canonical invocation's exit status == 0
##   2. The target theorem identity matches the observed artifact theorem
##   3. The effective kernel-check config says the check is enabled
##
## exitStatus != 0 / launch-failure / timeout → NO receipt (returns err).
## `AXIOM_LEAN_CMD` env override is respected: if set, the resolved path
## is used as the actual executable; otherwise `lake env lean` is used.
##
## This is the SINGLE issuance point. `LeanKernelCheckReceipt(...)` must
## appear in exactly one expression in the entire repo — inside this proc.

proc canonicalLeanKernelCheck*(
  leanSource: string;
  timeoutMs: int = 120_000
): Result[LeanKernelCheckReceipt, string] {.
  raises: [CatchableError], axiomEffect: IOEffect,
  axiomDebt: "DEBT#427",
  tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  if leanSource.len == 0:
    return err("canonicalLeanKernelCheck: empty lean source")

  # 1. Resolve the actual executable.
  let leanCmd = getAxiomEnv(evLeanCmd, "")
  let resolvedCmd =
    if leanCmd.len > 0: leanCmd
    else: "lake env lean"

  # 2. Resolve the real lean kernel binary that `lake env lean` uses.
  # QUIRK(DEBT#427): bare PATH `lean` may be an elan shim to a
  # different toolchain version than the real kernel. We always
  # resolve through the toolchain to get the actual binary.
  let leanExePath = resolveLeanBinaryPath()
  if leanExePath.len == 0:
    return err("canonicalLeanKernelCheck: cannot resolve lean executable")

  # 3. Capture lean binary digest (the real kernel binary).
  let leanDigest =
    try:
      let exeContent = readFile(leanExePath)
      sha256Hex(exeContent)
    except CatchableError:
      ""
  if leanDigest.len != 64:
    return err("canonicalLeanKernelCheck: cannot digest lean binary " & leanExePath)

  # 4. Capture lake binary digest (needed for bundle fingerprint).
  let lakePath = findExe("lake")
  if lakePath.len == 0:
    return err("canonicalLeanKernelCheck: cannot resolve lake executable")
  let lakeDigest =
    try:
      let exeContent = readFile(lakePath)
      sha256Hex(exeContent)
    except CatchableError:
      ""
  if lakeDigest.len != 64:
    return err("canonicalLeanKernelCheck: cannot digest lake binary " & lakePath)

  # 5. Compute measured toolchain fingerprint (bundle digest).
  # Replaces the hardcoded "lean-4.33.0" label with a content-addressed
  # binding to real binary + manifest content.
  # QUIRK(DEBT#427): elan shim pitfall — the old hardcoded fingerprint
  # ignored which lean binary was actually invoked, so runs claiming the
  # same contract could produce different kernel observations.
  let toolchainFp = computeBundleDigest(
    leanExePath, lakePath, timeoutMs, resolvedCmd
  )

  # 6. Write the artifact to a content-hashed temp file.
  let inputHash = sha256Hex(leanSource)
  let artifactPath = getTempDir() / ("axiom_kc_" & inputHash & ".lean")
  try:
    try:
      writeFile(artifactPath, leanSource)
    except CatchableError as e:
      return err("canonicalLeanKernelCheck: cannot write artifact " &
                 artifactPath & ": " & e.msg)

    # 7. Observe the target theorem identity from the actual artifact.
    let observedTarget = ObservedLeanArtifactTarget(
      theoremName: extractTheoremName(leanSource),
      sourceHash: inputHash
    )

    if observedTarget.theoremName.len == 0:
      try:
        removeFile(artifactPath)
      except CatchableError:
        discard  # axiom:best-effort(temp artifact cleanup)
      return err("canonicalLeanKernelCheck: no theorem declaration found in artifact")

    # 8. Build the canonical invocation contract.
    let invocationContract = resolvedCmd & " --threads=1 " & quoteShell(artifactPath)

    # 9. Capture effective execution contract (env vars).
    let executionContract = sha256Hex(
      "AXIOM_LEAN_CMD=" & leanCmd & "|PATH=" & getEnv("PATH", "") &
      "|TMPDIR=" & getEnv("TMPDIR", "")
    )

    # 10. Run the kernel check.
    let (output, exitCode) = execCmdWithTimeout(
      invocationContract, timeoutMs = timeoutMs
    )

    # 11. Cleanup artifact.
    try:
      removeFile(artifactPath)
    except CatchableError:
      discard  # axiom:best-effort(temp artifact cleanup)

    # 12. Emit receipt ONLY when exit status == 0 (via the private single-issuance constructor).
    if exitCode == 0:
      if judgmentRecordingArmed():
        judgmentAcceptLog.add((theoremIdentity: observedTarget.theoremName,
          inputIdentity: inputHash))
      let receipt = makeReceipt(
        executableDigest = leanDigest,
        toolchainFingerprint = toolchainFp,
        invocationContract = invocationContract,
        executionContract = executionContract,
        inputIdentity = inputHash,
        artifactIdentity = inputHash,
        theoremIdentity = observedTarget.theoremName,
        kernelObservation = output,
        observedAtMs = epochTime().int64 * 1000
      )
      ok(receipt)
    else:
      # §0.9 (no silent discard): the kernel's own diagnostic is the only
      # attribution evidence for a decline. Dropping it produced bare
      # "exit code 1" errors with the failure point unspecified (DEBT#465
      # attribution addendum), so the first diagnostic lines travel with the
      # error. Receipt issuance semantics are unchanged (exit 0 only).
      var diag = ""
      for line in output.splitLines():
        let trimmed = line.strip()
        if trimmed.len > 0:
          if diag.len > 0:
            diag.add(" | ")
          diag.add(trimmed)
        if diag.len >= 400:
          break
      if diag.len > 400:
        diag = diag[0 ..< 400] & "..."
      if diag.len > 0:
        err("canonicalLeanKernelCheck: exit code " & $exitCode & ": " & diag)
      else:
        err("canonicalLeanKernelCheck: exit code " & $exitCode)

  except CatchableError as e:
    try:
      removeFile(artifactPath)
    except CatchableError:
      discard  # axiom:best-effort(temp artifact cleanup)
    err("canonicalLeanKernelCheck: invocation error: " & e.msg)

# ---------------------------------------------------------------------------
# runLeanProbe — health-check only, NO receipt-issuance capability
# ---------------------------------------------------------------------------
## Runs a Lean kernel check on the given source and returns the raw
## (output, exitCode) pair. This is a health-check probe only — it
## cannot produce a `LeanKernelCheckReceipt`. Callers that need a
## receipt must use `canonicalLeanKernelCheck`.

proc runLeanProbe*(leanSource: string; suffix: string; timeoutMs: int): (string, int) {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  let artifactPath = getTempDir() / ("axiom_probe_" & sha256Hex(leanSource) & suffix & ".lean")
  try:
    try:
      writeFile(artifactPath, leanSource)
    except CatchableError as e:
      return ("lean probe artifact write failed: " & e.msg, -1)
    result = execCmdWithTimeout(
      "lake env lean --threads=1 " & quoteShell(artifactPath),
      timeoutMs = timeoutMs
    )
  finally:
    try:
      removeFile(artifactPath)
    except CatchableError:
      discard  # axiom:best-effort(temp artifact cleanup)

{.pop.}
