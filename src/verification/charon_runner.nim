import core/trusted/layer_declaration
axiomLayer "infrastructure"
# axiomIoBoundary — the runner executes real subprocess I/O (`charon version`
# probe, `charon cargo` extraction). Declared-marker resolution (the
# io_module_registry is a FROZEN surface — same resolution the Rust replay
# adapter documents): every I/O proc carries an explicit axiomEffect pragma —
# §0.6 permits proc at the I/O boundary.
{.push raises: [].}

## Pinned Charon execution runner (feat/rust-lane-live-cli) — the ONLY product
## module that RUNS Charon. Every earlier Rust-lane stage CONSUMED
## pre-generated LLBC and treated Charon as RECORDED provenance
## (extraction_provenance: "Axiom CONSUMES pre-generated Charon LLBC and never
## runs Charon", quirk Q3); this module adds the producer-side execution lane
## and holds it to the same identity discipline:
##
##   IDENTITY GATE → EXTRACTION → FAIL-CLOSED, in that order, and the gate
##   dominates: a non-matching Charon NEVER reaches cargo.
##
## 1. IDENTITY GATE: `<charonExe> version` must parse as
##    `<semver> (<40-hex commit>)` and BOTH components must equal the pinned
##    constants (extraction_provenance.PinnedCharonVersion /
##    PinnedCharonPinCommit — the consumer repo is the pin SSOT, quirk Q3).
##    Binary absent → crNotFound; mismatch, invocation failure or unparseable
##    output → crPinMismatch with the measured vs pinned identity in the
##    reason (violation AND unverifiability both fail closed — the
##    declared-pin gate pattern shared with rust_replay_adapter /
##    verifyExtractionEnvironment).
## 2. EXTRACTION: `<charonExe> cargo --dest-file <workDir>/subject.llbc
##    -- --target-dir <workDir>/charon-target` runs with
##    workingDir = subjectRoot (cargo's own crate discovery), bounded by a
##    120 s timeout (infrastructure/process_utils.execCmdWithTimeout —
##    temp-file output capture, so an undrained pipe cannot deadlock;
##    SIGTERM→SIGKILL escalation; exit -1 = timed out or unspawnable).
##    Measured against the pinned binary 0.1.281
##    (798016509139eb51f0d764645f76d068d34ba5f6): a dependency-free crate
##    needs no network, and BOTH the LLBC and cargo's build tree land under
##    workDir — the subject tree is never written (Zero-Footprint Integrity).
## 3. FAIL-CLOSED: no exception escapes — every failure is an explicit not-ok
##    CharonRunResult (cr*) with a one-line human-readable reason. Nonzero
##    cargo exit → crRunFailed (output excerpt folded into the reason); exit
##    0 with the LLBC file absent → crOutputMissing (never a fabricated
##    path). Caller misuse (subject root not a directory, empty workDir) →
##    crInternal.
##
## Quirk Q4 discipline (docs/spec/rust_toolchain_quirks.md): the exe token is
## executed exactly as the caller names it — a bare name keeps PATH dispatch
## (charon is not a rustup shim, but the same discipline costs nothing and
## transfers); `findExe` is used for EXISTENCE probing only and its resolved
## path is never executed.

import std/[os, strutils]

import core/axiom_pragmas
import infrastructure/process_utils  # execCmdWithTimeout — the bounded-subprocess SSOT (never re-implemented)
import verification/extraction_provenance  # PinnedCharonPinCommit / PinnedCharonVersion — the pin SSOT
import verification/verification_subject  # isHexOfLen

# ---------------------------------------------------------------------------
# Types (the fixed CLI-lane contract)
# ---------------------------------------------------------------------------

type
  CharonRunnerError* = enum crOk, crNotFound, crPinMismatch, crRunFailed, crOutputMissing, crInternal
  CharonRunResult* = object
    ok*: bool
    error*: CharonRunnerError
    reason*: string      ## human-readable; on pin mismatch includes measured
                         ## vs pinned identity
    llbcPath*: string    ## absolute path to the produced LLBC file (ok only)
    versionLine*: string ## measured `charon version` output, verbatim

const
  CharonCargoTimeoutMs = 120_000
    ## Extraction budget for one `charon cargo` run (measured: ~0.5 s cold for
    ## the probe crate — 120 s is orders of magnitude of headroom, and the
    ## timeout is the only guard against a wedged cargo).
  CharonProbeTimeoutMs = 15_000
    ## Budget for the `charon version` probe (single exec, no compilation).
  CharonOutputFileName = "subject.llbc"
    ## Fixed deterministic LLBC name inside workDir — the destination is a
    ## function of the request, not of the crate's self-declared name.

func pinnedCharonIdentity*(): string {.raises: [].} =
  ## The pinned identity in the exact `charon version` render — the string
  ## the measured line must equal after parsing (both components).
  PinnedCharonVersion & " (" & PinnedCharonPinCommit & ")"

# ---------------------------------------------------------------------------
# Pure identity parsing + the pin gate (fail-closed, never raises)
# ---------------------------------------------------------------------------

func isSemverDigits(s: string): bool {.raises: [].} =
  ## Semver SHAPE check: non-empty dot-separated all-numeric components
  ## (`0.1.281`). This is structural only — semantic comparison happens
  ## against the pinned constant, never against a range.
  if s.len == 0:
    return false
  var parts = 0
  for comp in s.split('.'):
    inc parts
    if comp.len == 0:
      return false
    for c in comp:
      if c notin {'0'..'9'}:
        return false
  parts >= 2

func parseCharonVersionLine*(line: string): tuple[ok: bool; version: string; commit: string] {.raises: [].} =
  ## Parse the exact measured `charon version` shape: `<semver> (<40-hex>)`.
  ## ok=false on anything else — garbage NEVER parses into a passable
  ## identity (an unparseable probe is a pin failure, not a skip).
  let t = line.strip()
  if t.len == 0 or not t.endsWith(')'):
    return
  let open = t.find('(')
  if open < 2 or t[open - 1] != ' ':
    return
  let version = t[0 ..< open].strip()
  let commit = t[(open + 1) ..< (t.len - 1)].strip()
  if not isSemverDigits(version):
    return
  if not isHexOfLen(commit, 40):
    return
  (true, version, commit)

func charonPinVerdict*(versionLine: string): tuple[ok: bool; reason: string] {.raises: [].} =
  ## The pure pin gate over a MEASURED version line: ok("") only when BOTH
  ## parsed components equal the pinned constants; every other outcome
  ## carries a reason naming the measured AND the pinned identity (the
  ## consumer of the reason must be able to diff the two without re-running
  ## anything). Unverifiable (unparseable) and violated (parsed but
  ## different) are the same failure CLASS here — fail closed.
  let parsed = parseCharonVersionLine(versionLine)
  if not parsed.ok:
    return (false, "charon version output unparseable: '" & versionLine &
      "' (expected '<semver> (<40-hex commit>)'; pinned identity: '" &
      pinnedCharonIdentity() & "')")
  if parsed.version != PinnedCharonVersion:
    return (false, "measured charon version '" & parsed.version &
      "' != pinned '" & PinnedCharonVersion & "' (measured identity: '" &
      versionLine & "'; pinned identity: '" & pinnedCharonIdentity() & "')")
  if parsed.commit != PinnedCharonPinCommit:
    return (false, "measured charon commit '" & parsed.commit &
      "' != pinned '" & PinnedCharonPinCommit & "' (measured identity: '" &
      versionLine & "'; pinned identity: '" & pinnedCharonIdentity() & "')")
  (true, "")

# ---------------------------------------------------------------------------
# I/O boundary — measurement, then the gated extraction run
# ---------------------------------------------------------------------------

func firstNonEmptyLine(output: string): string {.raises: [].} =
  ## The verbatim first non-empty (whitespace-trimmed) line — `charon version`
  ## prints exactly one.
  for ln in output.splitLines():
    let t = ln.strip()
    if t.len > 0:
      return t
  ""

func excerptOf(s: string; maxLen: int = 240): string {.raises: [].} =
  ## One-line output excerpt for fail-closed diagnostics (newlines flattened
  ## so a reason stays one line — the adapter's 200-char discipline).
  let flat = s.replace('\r', ' ').replace('\n', ' ').strip()
  if flat.len > maxLen:
    flat[0 ..< maxLen] & "..."
  else:
    flat

proc charonExeAvailable(charonExe: string): bool {.
    raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Quirk Q4 discipline: findExe is EXISTENCE probing only — its resolved
  ## path is never executed; the exe token runs as named (a bare name keeps
  ## PATH dispatch; an explicit path is honored as given).
  try:
    if charonExe.len == 0:
      return false
    if charonExe.contains('/'):
      fileExists(charonExe)
    else:
      findExe(charonExe).len > 0
  except CatchableError:
    false

proc probeCharonVersion*(charonExe: string = "charon"): tuple[ok: bool, versionLine: string, reason: string] {.
    raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Measure `<charonExe> version` and hold the measured identity against the
  ## pinned constants (the shared identity gate; runPinnedCharonCargo refuses
  ## to proceed unless this probe agrees). ok=true ONLY on an exact match of
  ## BOTH pinned components; versionLine is the verbatim measured line when
  ## one was produced; reason names not-found / invocation failure /
  ## measured-vs-pinned divergence. The probe is bounded (CharonProbeTimeoutMs)
  ## and fail-closed: an unverifiable identity is a failed probe, never a
  ## pass.
  if not charonExeAvailable(charonExe):
    return (false, "", "charon not found (pinned charon required): '" & charonExe & "'")
  let (output, code) = execCmdWithTimeout("\"" & charonExe & "\" version",
                                          timeoutMs = CharonProbeTimeoutMs)
  if code != 0:
    var diag = "charon version invocation failed (exit " & $code &
               "; -1 = timed out after " & $CharonProbeTimeoutMs & "ms or unspawnable)"
    let measured = firstNonEmptyLine(output)
    if measured.len > 0:
      diag.add(": " & excerptOf(measured))
    return (false, measured, diag)
  let measured = firstNonEmptyLine(output)
  if measured.len == 0:
    return (false, "", "charon version produced no output (identity unverifiable — fail-closed)")
  let verdict = charonPinVerdict(measured)
  if not verdict.ok:
    return (false, measured, verdict.reason)
  (true, measured, "")

proc runPinnedCharonCargo*(subjectRoot: string; workDir: string; charonExe: string = "charon"): CharonRunResult {.
    raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## The pinned extraction run: identity gate → `charon cargo` → explicit
  ## not-ok on every deviation (see the module docstring for the staged
  ## contract). On ok the produced LLBC is at `llbcPath` (absolute) and
  ## `versionLine` records the gate's verbatim measurement; every failure
  ## mode lands in `error` + `reason` and NOTHING is returned as a success
  ## shape. Only workDir is written; the subject tree is untouched
  ## (cargo's build tree is redirected into workDir via `-- --target-dir`).
  if subjectRoot.len == 0 or not dirExists(subjectRoot):
    return CharonRunResult(ok: false, error: crInternal,
      reason: "subject root is not a directory: '" & subjectRoot & "'")
  if workDir.len == 0:
    return CharonRunResult(ok: false, error: crInternal,
      reason: "work dir is empty — no LLBC destination (fail-closed)")

  # ① The identity gate — a non-matching Charon NEVER reaches cargo.
  let probe = probeCharonVersion(charonExe)
  result.versionLine = probe.versionLine
  if not probe.ok:
    if charonExeAvailable(charonExe):
      result.error = crPinMismatch
    else:
      result.error = crNotFound
    result.reason = probe.reason
    return

  # ② The destination: absolute workDir paths for the LLBC and the redirected
  # cargo build tree (created here — cargo never writes into the subject).
  var destFile = ""
  var targetDir = ""
  try:
    createDir(workDir)
    let absWork = absolutePath(workDir)
    destFile = absWork / CharonOutputFileName
    targetDir = absWork / "charon-target"
  except CatchableError as e:
    result.error = crInternal
    result.reason = "cannot prepare work dir '" & workDir & "': " & e.msg
    return

  # ③ The bounded extraction run — workingDir = subjectRoot (cargo's own
  # crate discovery), stderr folded into the captured output.
  let cmd = "\"" & charonExe & "\" cargo --dest-file \"" & destFile &
            "\" -- --target-dir \"" & targetDir & "\""
  let (output, code) = execCmdWithTimeout(cmd, workingDir = subjectRoot,
                                          timeoutMs = CharonCargoTimeoutMs)
  if code != 0:
    result.error = crRunFailed
    var diag = "charon cargo failed (exit " & $code &
               "; -1 = timed out after " & $CharonCargoTimeoutMs & "ms or unspawnable)"
    let trimmed = output.strip()
    if trimmed.len > 0:
      diag.add(": " & excerptOf(trimmed))
    result.reason = diag
    return
  if not fileExists(destFile):
    result.error = crOutputMissing
    result.reason = "charon cargo exited 0 but the LLBC file is missing: '" & destFile & "'"
    return
  result.ok = true
  result.error = crOk
  result.llbcPath = destFile

{.pop.}
