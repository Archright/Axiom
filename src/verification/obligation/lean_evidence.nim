import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Lean Evidence — Acceptance/Validation separation + obligation binding.
##
## Design (W1-B):
## - `runLeanKernelCheck` produces a PURE acceptance fact (`LeanKernelResult`):
##   kernel exit code only. No sorry scanning, no text inference, no vacuity
##   claims. The acceptance fact is separate from Axiom-owned validation.
## - `validateEvidence` is the Axiom-owned validation layer: artifact
##   integrity, sorry scan, `#print axioms` allowlist check, negative mutation
##   (vacuity) check, and obligation binding. It composes a `LeanEvidence`
##   that pins binding + acceptance + validation + axiomProfile + artifactHash.
##
## Hash domains (documented — they are NOT interchangeable):
## * `ObligationBinding.propositionHash` — sha256 of the CANONICAL proposition
##   string (IR-level), computed by `bindObligation` at obligation-generation
##   time. NOT a hash of the rendered Lean text.
## * `LeanEvidence.artifactHash` — sha256 of the exact rendered Lean artifact
##   (`leanSource`) that was validated. Pins the evidence to a byte-exact file.
## * `ObligationBinding.sourceHash` — sha256 of the derivation source (the
##   input the obligation was generated from, e.g. the module/function source).
## * `LeanKernelResult.diagnosticsHash` — sha256 of the raw kernel output.
##
## Axiom-profile collection choice: direct CLI invocation (append
## `#print axioms <target>` and run `lean --threads=1 <file>`), NOT the LSP
## round-trip. Rationale: no server lifecycle, deterministic single-file
## check, and it reuses the exact `'<decl>' depends on axioms: [...]` output
## format the LSP path parses — parsing stays on the shared pure helper
## `extractAxiomsFromDiagnosticMessage` (via the `parseAxiomProfile` aggregator).
##
## Negative mutation: local port of `lean_lsp_compiler.buildNegativeTestSource`
## (conclusion replaced by `False`; mutated file must FAIL to compile). Ported
## rather than imported to keep this module free of the heavy compiler module
## and its legacy verified/vacuity coupling. The two copies must stay in sync:
## both anchor on `:= by` AND `:=\nby` conclusions via the same whitespace-run
## scan (`findTacticConclusionAnchor`) because `irFuncDefToTheorem` emits the
## newline form.
##
## Result contract of `validateEvidence`:
## * `ok(evidence)` — ALL checks passed; `evidence.validation == voValid`.
## * `err(reason)` — rejected or unverifiable; `reason` starts with
##   `InvalidEvidencePrefix` (determinate rejection, voInvalid) or
##   `UnverifiableEvidencePrefix` (cannot decide, voUnverifiable). Use
##   `outcomeFromReason` to recover the typed outcome.

import std/[os, strutils]
import core/axiom_pragmas
import core/crypto/hash_kernel
import core/results
import infrastructure/process_utils
import verification/lean_lsp_protocol

{.push raises: [].}

# ---------------------------------------------------------------------------
# Outcome vocabulary and reason prefixes
# ---------------------------------------------------------------------------

const
  InvalidEvidencePrefix* = "invalid: "
  UnverifiableEvidencePrefix* = "unverifiable: "

type
  ValidationOutcome* = enum
    voValid         ## all Axiom-owned checks passed
    voInvalid       ## a determinate check failed (rejection reason recorded)
    voUnverifiable  ## cannot decide (timeout, missing report, unbuildable mutation)

func outcomeFromReason*(reason: string): ValidationOutcome {.raises: [].} =
  ## Typed classification of a `validateEvidence` error reason.
  result =
    if reason.startsWith(InvalidEvidencePrefix):
      voInvalid
    elif reason.startsWith(UnverifiableEvidencePrefix):
      voUnverifiable
    else:
      voValid  # unreachable for real error reasons; default for empty/unknown input

# ---------------------------------------------------------------------------
# ObligationBinding — canonical obligation identity pin
# ---------------------------------------------------------------------------

type
  ObligationBinding* = object
    obligationId*: string
    propositionHash*: string  ## sha256 of the CANONICAL proposition (IR-side)
    sourceHash*: string       ## sha256 of the derivation source (provenance)

func bindObligation*(obligationId, proposition, source: string): ObligationBinding {.raises: [].} =
  ## Deterministic obligation binding. `proposition` is the canonical
  ## proposition string (not the rendered Lean text); `source` is the
  ## derivation source the obligation came from.
  ObligationBinding(
    obligationId: obligationId,
    propositionHash: sha256Hex(proposition),
    sourceHash: sha256Hex(source)
  )

# ---------------------------------------------------------------------------
# LeanKernelResult — pure acceptance fact (kernel exit status only)
# ---------------------------------------------------------------------------

type
  LeanKernelResult* = object
    kernelAccepted*: bool   ## true IFF `lean` exited 0 (no text inference)
    exitStatus*: int        ## 0 = accepted; -1 = timeout/launch failure (execCmdWithTimeout convention)
    diagnostics*: string    ## captured kernel stdout+stderr, verbatim
    diagnosticsHash*: string  ## sha256 of diagnostics (tamper check on validation)

# ---------------------------------------------------------------------------
# LeanEvidence — composed Axiom-owned validation record
# ---------------------------------------------------------------------------

type
  LeanEvidence* = object
    binding*: ObligationBinding
    acceptance*: LeanKernelResult
    validation*: ValidationOutcome
    axiomProfile*: seq[string]  ## axiom names the artifact provably depends on
    artifactHash*: string       ## sha256 of the exact validated leanSource

# ---------------------------------------------------------------------------
# Pure helpers
# ---------------------------------------------------------------------------

func parseAxiomProfile*(raw: string): seq[string] {.raises: [].} =
  ## Aggregate `#print axioms` reports embedded in raw kernel output.
  ## Reuses `extractAxiomsFromDiagnosticMessage` (the good parser) per line,
  ## preserving order and de-duplicating.
  for line in raw.splitLines():
    for axiom in extractAxiomsFromDiagnosticMessage(line):
      if axiom notin result:
        result.add(axiom)

func validateAxiomProfile*(axioms: seq[string]): Result[void, string] {.raises: [], axiomDecision.} =
  ## Allowlist gate over a captured axiom profile (pure; no lean needed).
  ## Rejects any `sorryAx`-bearing axiom and any axiom outside
  ## `LeanAxiomAllowlist` (fail-closed, mirrors lean_lsp_protocol semantics).
  for axiom in axioms:
    if axiom.contains("sorryAx"):
      return err(InvalidEvidencePrefix & "axiom profile contains sorry axiom '" & axiom & "'")
  for axiom in axioms:
    if not isLeanAxiomAllowed(axiom):
      return err(InvalidEvidencePrefix & "axiom '" & axiom & "' is not in the allowlist " &
                 "(" & LeanAxiomAllowlist.join(", ") & ")")
  Result[void, string](ok: true)

func extractTheoremName*(leanSource: string): string {.raises: [].} =
  ## Name of the first `theorem <name>` declaration in the artifact.
  ## Handles `theorem foo :` (single-line name) and `theorem foo` followed by
  ## a type on later lines (name ends at whitespace, ':' or '(').
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

func containsSorryMarker(text: string): bool {.raises: [].} =
  ## Fail-closed sorry scan (repo-wide convention, see lean_sorry_gate.md).
  ## Lowercase scan matches `sorry`, `sorryAx`, `Lean.sorryAx` and the
  ## `declaration uses 'sorry'` kernel warning uniformly.
  let lowered = text.toLowerAscii()
  "sorry" in lowered

func briefReason(text: string; limit = 160): string {.raises: [].} =
  ## First non-empty output line, trimmed and capped, for error reasons.
  for line in text.splitLines():
    let s = line.strip()
    if s.len > 0:
      return s[0 ..< min(limit, s.len)]
  "(no output)"

func findTacticConclusionAnchor(source: string): int {.raises: [].} =
  ## Index of the `:=` separating a theorem's type from its tactic proof,
  ## or -1. Renderer output uses either `:= by` (single line) or `:=\nby`
  ## (tactic block on the next line, cf. irFuncDefToTheorem), so the anchor
  ## accepts any whitespace run between `:=` and `by` and requires `by` to
  ## be the standalone keyword (not an identifier prefix such as `bytes`).
  var searchFrom = 0
  while true:
    let idx = source.find(":=", searchFrom)
    if idx < 0:
      return -1
    var after = idx + 2
    while after < source.len and source[after] in {' ', '\t', '\n', '\r'}:
      inc after
    if after + 2 <= source.len and source[after ..< after + 2] == "by" and
        (after + 2 == source.len or source[after + 2] notin IdentChars):
      return idx
    searchFrom = idx + 2

func buildNegativeMutation(leanSource: string): string {.raises: [].} =
  ## Local port of lean_build/lean_lsp_compiler.buildNegativeTestSource:
  ## replaces the theorem's proposition with `False`. If the mutated artifact
  ## compiles, the original theorem is trivial/vacuous.
  let idx = findTacticConclusionAnchor(leanSource)
  if idx < 0:
    return ""
  var colonIdx = -1
  var parenDepth = 0
  for i in countdown(idx - 1, 0):
    let c = leanSource[i]
    if c == ')':
      parenDepth += 1
    elif c == '(':
      parenDepth -= 1
    elif c == ':' and parenDepth == 0:
      colonIdx = i
      break
  if colonIdx < 0:
    return ""
  leanSource[0 ..< colonIdx + 1] & " False " & leanSource[idx .. ^1]

{.pop.}

# ---------------------------------------------------------------------------
# Lean invocation helper
# ---------------------------------------------------------------------------

proc runLeanProbe(leanSource: string; suffix: string; timeoutMs: int): (string, int)
  {.gcsafe, raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Writes `leanSource` to a content-hashed temp artifact and runs
  ## `lean --threads=1 <file>`. Returns (output, exitCode); per
  ## execCmdWithTimeout convention exitCode == -1 means timeout/launch failure.
  ## --threads=1 pins single-threaded elaboration for deterministic output.
  let artifactPath = getTempDir() / ("axiom_ev_" & sha256Hex(leanSource) & suffix & ".lean")
  try:
    try:
      writeFile(artifactPath, leanSource)
    except CatchableError as e:
      return ("lean artifact write failed: " & e.msg, -1)
    result = execCmdWithTimeout("lean --threads=1 " & quoteShell(artifactPath), timeoutMs = timeoutMs)
  finally:
    try:
      removeFile(artifactPath)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary cleanup)

# ---------------------------------------------------------------------------
# runLeanKernelCheck — pure acceptance boundary
# ---------------------------------------------------------------------------

proc runLeanKernelCheck*(
  leanSource: string;
  extraArgs: seq[string] = @[];
  timeoutMs = 120_000
): Result[LeanKernelResult, string] {.gcsafe, raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## PURE acceptance fact: write the source to `getTempDir()/"axiom_ev_<hash>.lean"`,
  ## run `lean --threads=1 <file>`, kernelAccepted := (exit code == 0).
  ## NO sorry scanning, NO text inference, NO vacuity claims here — those are
  ## Axiom-owned `validateEvidence` concerns.
  if leanSource.len == 0:
    return err("runLeanKernelCheck: empty lean source")
  let artifactPath = getTempDir() / ("axiom_ev_" & sha256Hex(leanSource) & ".lean")
  try:
    try:
      writeFile(artifactPath, leanSource)
    except CatchableError as e:
      return err("runLeanKernelCheck: cannot write artifact " & artifactPath & ": " & e.msg)
    let args =
      if extraArgs.len > 0: " " & extraArgs.join(" ")
      else: ""
    let cmd = "lean --threads=1" & args & " " & quoteShell(artifactPath)
    let (output, exitCode) = execCmdWithTimeout(cmd, timeoutMs = timeoutMs)
    ok(LeanKernelResult(
      kernelAccepted: exitCode == 0,
      exitStatus: exitCode,
      diagnostics: output,
      diagnosticsHash: sha256Hex(output)
    ))
  except CatchableError as e:
    err("runLeanKernel: invocation error: " & e.msg)
  finally:
    try:
      removeFile(artifactPath)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary cleanup)

# ---------------------------------------------------------------------------
# validateEvidence — Axiom-owned validation layer
# ---------------------------------------------------------------------------

proc validateEvidence*(
  binding: ObligationBinding;
  kernel: LeanKernelResult;
  leanSource: string;
  axiomTarget: string;
  expectedArtifactHash: string = "";
  canonicalProposition: string = "";
  timeoutMs = 120_000
): Result[LeanEvidence, string] {.gcsafe, raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Axiom-owned validation: artifact integrity, binding, sorry absence,
  ## allow-listed axiom profile, and non-vacuity (negative mutation).
  ##
  ## `axiomTarget` is the theorem name probed with `#print axioms <axiomTarget>`.
  ## `canonicalProposition` (optional) is the proposition the obligation was
  ## canonicalized from; when provided, `binding.propositionHash` must match
  ## its deterministic hash, and `expectedArtifactHash` (optional) pins the
  ## rendered artifact to a hash known at render time.
  ##
  ## ok ⇔ all checks passed (validation = voValid). err reasons start with
  ## InvalidEvidencePrefix (voInvalid) or UnverifiableEvidencePrefix (voUnverifiable).
  let artifactHash = sha256Hex(leanSource)

  # 1. Artifact integrity (rendered-text pin).
  if expectedArtifactHash.len > 0 and expectedArtifactHash != artifactHash:
    return err(InvalidEvidencePrefix & "artifact hash mismatch: expected " &
      expectedArtifactHash & ", got " & artifactHash)

  # 2. Binding structural integrity.
  if binding.obligationId.len == 0:
    return err(InvalidEvidencePrefix & "binding.obligationId is empty")
  if binding.propositionHash.len == 0:
    return err(InvalidEvidencePrefix & "binding.propositionHash is empty")
  if binding.sourceHash.len == 0:
    return err(InvalidEvidencePrefix & "binding.sourceHash is empty")

  # 3. Binding — canonical proposition hash consistency (when provided).
  if canonicalProposition.len > 0 and sha256Hex(canonicalProposition) != binding.propositionHash:
    return err(InvalidEvidencePrefix & "binding.propositionHash mismatch: " &
      sha256Hex(canonicalProposition) & " != " & binding.propositionHash)

  # 4. Binding — theorem name in the artifact must reference the obligation.
  let theoremName = extractTheoremName(leanSource)
  if theoremName.len == 0:
    return err(InvalidEvidencePrefix & "no theorem declaration found in artifact")
  if theoremName != binding.obligationId and not theoremName.contains("obligation_" & binding.obligationId):
    return err(InvalidEvidencePrefix & "artifact theorem '" & theoremName &
      "' does not bind to obligation '" & binding.obligationId & "'")
  if axiomTarget != theoremName:
    return err(InvalidEvidencePrefix & "axiomTarget '" & axiomTarget &
      "' does not match artifact theorem '" & theoremName & "'")

  # 5. Acceptance fact tamper check (diagnostics hash must agree).
  if kernel.diagnosticsHash.len > 0 and kernel.diagnosticsHash != sha256Hex(kernel.diagnostics):
    return err(InvalidEvidencePrefix & "kernel diagnosticsHash mismatch (tampering suspected)")

  # 6. Acceptance gate — the kernel must have accepted the artifact.
  if not kernel.kernelAccepted:
    if kernel.exitStatus == -1:
      return err(UnverifiableEvidencePrefix & "lean kernel timed out or failed to launch (exitStatus -1)")
    return err(InvalidEvidencePrefix & "lean kernel rejected at exit code " & $kernel.exitStatus)

  # 7. Sorry absence — source and diagnostics (fail-closed, belt over the
  #    axiom profile check below).
  if containsSorryMarker(leanSource) or containsSorryMarker(kernel.diagnostics):
    return err(InvalidEvidencePrefix & "sorry/sorryAx marker found in source or kernel diagnostics")

  # 8. Axiom profile — targeted `#print axioms <axiomTarget>` round-trip.
  #    Direct CLI choice documented in the module header.
  var axiomProfile: seq[string]
  try:
    let probeSource = leanSource & "\n#print axioms " & axiomTarget & "\n"
    let (output, exitCode) = runLeanProbe(probeSource, "_axioms", timeoutMs)
    if exitCode == -1:
      return err(UnverifiableEvidencePrefix & "axiom profile probe timed out or failed to launch")
    if exitCode != 0:
      return err(InvalidEvidencePrefix & "axiom profile probe failed (exit " & $exitCode & "): " & briefReason(output))
    # Report presence: the positive form is `'<decl>' depends on axioms: [...]`,
    # the clean form is `'<decl>' does not depend on any axioms`. Both must be
    # recognized — a missing report (neither form) means we cannot confirm a
    # sorry-free axiom profile.
    let reportEmitted =
      "depends on axioms" in output or "does not depend on any axioms" in output
    if not reportEmitted:
      return err(UnverifiableEvidencePrefix & "axiom probe produced no 'depends on axioms' report; cannot confirm sorry-free axiom profile")
    axiomProfile = parseAxiomProfile(output)
    let verdict = validateAxiomProfile(axiomProfile)
    if verdict.isErr:
      return err(verdict.error)
  except CatchableError as e:
    return err("axiom profile probe error: " & e.msg)

  # 9. Negative mutation — non-vacuity (mutated conclusion False must FAIL).
  try:
    let mutationSource = buildNegativeMutation(leanSource)
    if mutationSource.len == 0:
      return err(UnverifiableEvidencePrefix & "cannot build negative mutation (no ':= by' or ':=\\nby' conclusion found)")
    let (_, mutationExit) = runLeanProbe(mutationSource, "_negative", timeoutMs)
    if mutationExit == 0:
      return err(InvalidEvidencePrefix & "negative mutation compiled — original theorem is trivial/vacuous")
    if mutationExit == -1:
      return err(UnverifiableEvidencePrefix & "negative mutation probe timed out or failed to launch")
    # mutationExit != 0 → mutated artifact correctly rejected → non-vacuous.
  except CatchableError as e:
    return err("negative mutation probe error: " & e.msg)

  ok(LeanEvidence(
    binding: binding,
    acceptance: kernel,
    validation: voValid,
    axiomProfile: axiomProfile,
    artifactHash: artifactHash
  ))

{.pop.}