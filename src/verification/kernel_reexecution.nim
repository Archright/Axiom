import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Kernel Re-execution (certification continuity contract — Phase 3).
##
## `ax cert verify --kernel` deep-verification basis: re-execute the pinned
## kernels on the certificate's embedded inputs — Lean (`lake env lean
## --threads=1` typecheck + `#print axioms` allowlist, contract INV-6) and
## Z3 (recorded smtlib2 under the rlimit-primary envelope, contract INV-10).
## run.conclusion and step census are explicitly NOT attestation evidence
## (INV-5): only a fresh kernel verdict counts.
##
## Fail-closed: any verdict other than krPassed → certificate not attested.
## The recorded smtlib2/leanSource artifacts were captured at certify time;
## re-execution re-runs them FRESH — a cached result from a previous run is
## never trusted.

import std/algorithm
import std/json
import std/os
import std/osproc
import std/strutils
import std/times
import core/axiom_pragmas
import core/crypto/hash_kernel
import core/proof/proof_budget
import core/results
import core/sync/sync_utils_process
import core/trusted/env_types
import core/trusted/solver_invocation
import core/types/z3_solver_config
import core/judge/lean_replay
import core/utils/repo_root
import core/trusted/stdlib_shield
import infrastructure/process_utils
import infrastructure/source_identity_cache
import verification/canonical_json
import verification/solver/z3_pool
import verification/verification_subject

when defined(posix):
  import std/posix

axiomIoBoundary()

# ─── Verdicts ────────────────────────────────────────────────────────────────

type KernelVerdict* = enum
  krPassed          ## kernel re-execution passed (lean: typecheck + allowlisted axioms; z3: fresh unsat)
  krAxiomViolation  ## observed proof depends on an axiom outside the allowlist
  krSorry           ## observed proof depends on sorry (sorryAx family) — kernel soundness violation
  krCompileError    ## lean artifact failed kernel typecheck
  krTimeout         ## kernel re-execution exceeded its wall-clock budget and was killed
  krZ3Mismatch      ## z3 re-execution did not yield unsat
  krZ3Error         ## z3 binary missing / not checksum-pinned — fail-closed
  krMissingInput    ## certificate carries no leanSource/smtlib2 evidence to re-execute
  krInternalError   ## unexpected internal failure during re-execution

const
  defaultLeanReexecTimeoutMs* = 120_000  ## matches canonicalLeanKernelCheck budget
  defaultZ3ReexecTimeoutMs* = 120_000
  z3BinaryChecksumsPolicyPath* = "data/policy/z3_binary_checksums.json"
  kernelReexecSentinel* = "AXIOM_KERNEL_REEXEC_FIN"

# ─── Pure allowlist / verdict logic ──────────────────────────────────────────

func axiomAllowlist*(): seq[string] {.raises: [].} =
  ## INV-6 allowlist — the ONLY axiom names a kernel-verified proof may depend
  ## on. THE definition is `canonicalAxiomAllowlist` in
  ## `core/judge/lean_replay.nim`: the three Lean 4.33.0
  ## primitive axioms. `funext` is a theorem over `Quot.sound`, not a
  ## primitive axiom, and is intentionally absent.
  @canonicalAxiomAllowlist

func isAxiomAllowed*(axiomName: string): bool {.raises: [].} =
  ## Deny-first: any name containing a sorry/trustCompiler/native_decide marker
  ## is rejected regardless of allowlist shape; everything else must be an
  ## EXACT allowlist member. Empty names never pass (fail-closed).
  if axiomName.len == 0:
    return false
  let lower = axiomName.toLowerAscii()
  if "sorry" in lower:
    return false
  if "trustcompiler" in lower:
    return false
  if "native_decide" in lower:
    return false
  for allowed in axiomAllowlist():
    if axiomName == allowed:
      return true
  false

const verdictReasons: array[KernelVerdict, string] = [
  "kernel re-execution passed",
  "observed proof depends on an axiom outside the allowlist {propext, Classical.choice, Quot.sound}",
  "observed proof depends on sorry (sorryAx family) — kernel soundness violation",
  "lean artifact failed kernel typecheck",
  "kernel re-execution timed out and was killed",
  "z3 re-execution did not yield unsat — recorded query no longer proves the claim",
  "z3 binary missing or failing the pinned checksum policy — fail-closed",
  "certificate carries no leanSource/smtlib2 evidence to re-execute",
  "internal error during kernel re-execution"
]

func kernelVerdictReason*(v: KernelVerdict): string {.raises: [].} =
  ## Precise reason string for a verdict — the CLI surfaces this verbatim.
  verdictReasons[v]

# ─── Lean `#print axioms` observation parsing (pure) ─────────────────────────

type AxiomPrintObservation* = object
  names*: seq[string]       ## observed axiom names (union across #print commands)
  observedAny*: bool        ## true iff at least one result set was parsed

func parsePrintAxiomsObservations*(output: string): AxiomPrintObservation {.raises: [].} =
  ## Parses Lean `#print axioms` result text (toolchain-pinned 4.33.0 format):
  ##   '<thm>' depends on axioms: [ax1, ax2]
  ##   '<thm>' does not depend on any axioms
  ## A long bracket list may continue on following lines — the parser
  ## accumulates until `]` closes. `does not depend on any axioms` records an
  ## observed-but-empty set (kernel-pure). A `depends on axioms:` marker with
  ## no parseable bracket is NOT an observation (fail-closed: unobservable
  ## axiom set never counts as pass).
  result = AxiomPrintObservation(names: @[], observedAny: false)
  var pending = ""
  for rawLine in output.splitLines():
    if "does not depend on any axioms" in rawLine:
      result.observedAny = true
      continue
    if pending.len == 0:
      let marker = rawLine.find("depends on axioms:")
      if marker < 0:
        continue
      pending = rawLine[min(marker + "depends on axioms:".len, rawLine.high) .. ^1]
    else:
      pending.add("\n" & rawLine)
    let openIdx = pending.find('[')
    if openIdx < 0:
      pending = ""
      continue
    let openRest = pending[openIdx + 1 .. ^1]
    let closeIdx = openRest.find(']')
    if closeIdx < 0:
      continue  # bracket list continues on a later line
    result.observedAny = true
    for tok in openRest[0 ..< closeIdx].split(','):
      let t = tok.strip()
      if t.len > 0 and t notin result.names:
        result.names.add(t)
    pending = ""

func evaluateObservedAxioms*(observation: AxiomPrintObservation): KernelVerdict {.raises: [].} =
  ## INV-6 composition: no observation → krMissingInput (cannot attest);
  ## empty observed set → krPassed (kernel-pure); any unallowed name →
  ## krSorry (sorry family) or krAxiomViolation (everything else).
  if not observation.observedAny:
    return krMissingInput
  for name in observation.names:
    if isAxiomAllowed(name):
      continue
    if "sorry" in name.toLowerAscii():
      return krSorry
    return krAxiomViolation
  krPassed

# ─── Lean observation target + source hazards (pure) ────────────────────────

const kernelDisablingLeanOptions*: array[1, string] = ["debug.skipKernelTC"]
  ## `set_option <name> ...` values that switch off the kernel typechecker.
  ## A source carrying one of these cannot produce a meaningful kernel
  ## observation — it is krMissingInput, never a verdict about the theorem.

func stripLeanComments(source: string): seq[string] {.raises: [].} =
  ## Line-oriented comment stripper for declaration/target scanning. Handles
  ## `--` line comments and (possibly multi-line) `/- ... -/` block comments.
  ## This is a scanner, not a Lean parser: it exists to reject ambiguity and
  ## to locate the observation target, never to decide a verdict.
  result = @[]
  var inBlock = false
  for rawLine in source.splitLines():
    var line = rawLine
    if inBlock:
      let endIdx = line.find("-/")
      if endIdx < 0:
        result.add("")
        continue
      let after = endIdx + 2
      line = if after < line.len: line[after .. ^1] else: ""
      inBlock = false
    var searching = true
    while searching:
      let startIdx = line.find("/-")
      if startIdx < 0:
        searching = false
      else:
        let endIdx = line.find("-/", startIdx + 2)
        if endIdx < 0:
          line = line[0 ..< startIdx]
          inBlock = true
          searching = false
        else:
          let after = endIdx + 2
          let tail = if after < line.len: line[after .. ^1] else: ""
          line = line[0 ..< startIdx] & " " & tail
    let commentIdx = line.find("--")
    if commentIdx >= 0:
      line = line[0 ..< commentIdx]
    result.add(line)

func leanSourceHazards*(source: string): seq[string] {.raises: [].} =
  ## Kernel-bypass constructs: `debug.skipKernelTC`, `run_cmd`, `#eval`, and
  ## `set_option` values that disable kernel checking. Non-empty result means
  ## the source is NOT admissible for a kernel observation (krMissingInput).
  ## Comments are stripped first so documentation mentions do not trigger it.
  result = @[]
  for line in stripLeanComments(source):
    let stripped = line.strip()
    if "debug.skipKernelTC" in stripped and "debug.skipKernelTC" notin result:
      result.add "debug.skipKernelTC"
    if "run_cmd" in stripped and "run_cmd" notin result:
      result.add "run_cmd"
    if "#eval" in stripped and "#eval" notin result:
      result.add "#eval"
    if stripped.startsWith("set_option"):
      let rest = stripped["set_option".len .. ^1].strip()
      let nameEnd = rest.find({' ', '\t'})
      let optionName = if nameEnd < 0: rest else: rest[0 ..< nameEnd]
      for banned in kernelDisablingLeanOptions:
        if optionName == banned:
          let hazard = "set_option " & banned
          if hazard notin result:
            result.add hazard

func declaredTheorems*(source: string): seq[string] {.raises: [].} =
  ## Every `theorem`/`lemma` declaration name, namespace-qualified from the
  ## surrounding `namespace ... end` blocks and with `@[attr]` / `private` /
  ## `protected` / `noncomputable` / `unsafe` / `partial` prefixes stripped.
  result = @[]
  var scopes: seq[tuple[kind: string, name: string]] = @[]
  for line in stripLeanComments(source):
    var stripped = line.strip()
    if stripped.len == 0:
      continue
    if stripped.startsWith("namespace "):
      let name = stripped["namespace ".len .. ^1].strip()
      if name.len > 0:
        scopes.add (kind: "namespace", name: name)
      continue
    if stripped == "section" or stripped.startsWith("section "):
      let name = if stripped.len > "section".len: stripped["section".len .. ^1].strip() else: ""
      scopes.add (kind: "section", name: name)
      continue
    if stripped == "end" or stripped.startsWith("end "):
      if scopes.len > 0:
        let top = scopes[^1]
        let endName = if stripped.len > "end".len: stripped["end".len .. ^1].strip() else: ""
        if endName.len == 0 or endName == top.name:
          scopes.setLen(scopes.len - 1)
      continue
    var scopePrefix = ""
    for scope in scopes:
      if scope.kind == "namespace" and scope.name.len > 0:
        scopePrefix = if scopePrefix.len == 0: scope.name else: scopePrefix & "." & scope.name
    while stripped.startsWith("@["):
      let closeIdx = stripped.find(']')
      if closeIdx < 0:
        break
      let after = closeIdx + 1
      stripped = (if after < stripped.len: stripped[after .. ^1] else: "").strip()
    var changed = true
    while changed:
      changed = false
      for modifier in ["private ", "protected ", "noncomputable ", "nonrec ",
                       "unsafe ", "partial "]:
        if stripped.startsWith(modifier):
          stripped = stripped[modifier.len .. ^1].strip()
          changed = true
    for keyword in ["theorem ", "lemma "]:
      if stripped.startsWith(keyword):
        let rest = stripped[keyword.len .. ^1]
        let nameEnd = rest.find({' ', '\t', ':'})
        var name = if nameEnd < 0: rest else: rest[0 ..< nameEnd]
        if name.startsWith("_root_."):
          name = name["_root_.".len .. ^1]
        elif scopePrefix.len > 0:
          name = scopePrefix & "." & name
        if name.len > 0 and name notin result:
          result.add name
        break

func explicitAxiomPrintTarget*(source: string): string {.raises: [].} =
  ## The first explicit `#print axioms <name>` target in CODE (comments are
  ## ignored). "" means the source relies on an appended observation command.
  for line in stripLeanComments(source):
    let idx = line.find("#print axioms")
    if idx < 0:
      continue
    let rest = line[idx + "#print axioms".len .. ^1].strip()
    if rest.len == 0:
      continue
    let nameEnd = rest.find({' ', '\t'})
    let name = if nameEnd < 0: rest else: rest[0 ..< nameEnd]
    if name.len > 0 and not name.startsWith("#"):
      return name
  ""

func leanObservationTarget*(source: string): tuple[target: string, problem: string] {.raises: [].} =
  ## Selects the declaration a fresh `#print axioms` observes:
  ##   * an explicit `#print axioms <name>` wins when present;
  ##   * otherwise the source must contain EXACTLY ONE `theorem`/`lemma`
  ##     declaration (attributes, `private`, and namespace-qualified names are
  ##     supported). Zero or more than one → no target (krMissingInput).
  ## `def` is never a target — a definition is not an observed proposition.
  let explicit = explicitAxiomPrintTarget(source)
  if explicit.len > 0:
    return (target: explicit, problem: "")
  let theorems = declaredTheorems(source)
  if theorems.len == 0:
    return (target: "", problem: "no theorem/lemma declaration to bind (fail-closed)")
  if theorems.len > 1:
    return (target: "", problem: "ambiguous #print axioms target — " &
      $theorems.len & " theorem/lemma declarations, an explicit '#print axioms <name>' is required (fail-closed)")
  (target: theorems[0], problem: "")

func firstDeclaredName*(leanSource: string): string {.raises: [].} =
  ## First `theorem <name>` / `def <name>` declaration — the target for an
  ## appended `#print axioms <name>` observation line. Empty if none.
  for line in leanSource.splitLines():
    let stripped = line.strip()
    if stripped.startsWith("theorem ") or stripped.startsWith("def "):
      let rest = stripped[(if stripped.startsWith("theorem "): "theorem ".len else: "def ".len) .. ^1]
      let nameEnd = rest.find({' ', ':', '(', '\t'})
      if nameEnd < 0:
        return rest
      if nameEnd == 0:
        return ""
      return rest[0 ..< nameEnd]
  ""

# ─── Z3 verdict composition (pure) ───────────────────────────────────────────

func z3ResultVerdict*(exitCode: int; timedOut: bool; output: string): KernelVerdict {.raises: [].} =
  ## INV-10 fail-closed mapping: fresh run must exit cleanly AND answer unsat.
  ## Anything else — timeout, non-zero exit, sat/unknown — is a mismatch.
  ##
  ## The ⟨error_response⟩ form is rejected here rather than being left to the
  ## exit code alone to catch: the exit status is a whole-run property that says
  ## nothing about WHICH command was refused, and Z3 answers a rejected command
  ## with `(error …)` and then keeps answering later ones. Routing both rules
  ## through one detector keeps this path from reading a tool failure as a
  ## kernel proof — which for a certificate re-execution would be the most
  ## consequential misreading available (INV-5: only a fresh kernel verdict counts).
  if timedOut:
    return krTimeout
  if solverResponse(output, exitCode) == srUnsat:
    return krPassed
  krZ3Mismatch

func composeKernelVerdict*(
  leanVerdict, z3Verdict: KernelVerdict;
  leanPresent, z3Present: bool
): KernelVerdict {.raises: [].} =
  ## Overall `--kernel` verdict: every evidence class embedded in the cert
  ## must re-execute to krPassed. No embedded evidence at all → fail-closed
  ## krMissingInput (nothing to attest). The first failing class decides.
  if not leanPresent and not z3Present:
    return krMissingInput
  if leanPresent and leanVerdict != krPassed:
    return leanVerdict
  if z3Present and z3Verdict != krPassed:
    return z3Verdict
  krPassed

# ─── Kernel observation (VS-188 Phase 1) ────────────────────────────────────

const leanCheckerUnavailableMarker* = "leanchecker:unavailable"
  ## Loudly-recorded skipped deep check when the `leanchecker` binary cannot
  ## be resolved. An absent checker is additive; a PRESENT checker that
  ## rejects is fail-closed (krCompileError).

type
  LeanObservation* = object
    ## What a FRESH Lean run observed — never what a certificate claims.
    observed*: bool             ## true iff a run produced a parseable #print axioms result
    theoremName*: string        ## the declaration the axiom set was printed for
    axiomSet*: seq[string]      ## observed axioms, sorted + deduplicated
    verdict*: KernelVerdict
    leanSourceDigest*: string   ## sha256 of the exact source handed to Lean
    outputDigest*: string       ## sha256 of the complete runner output
    toolchainIdentity*: string  ## pinned lean version + checker path digest
    skippedChecks*: seq[string] ## loudly-recorded skipped deep checks

  Z3Observation* = object
    ## What a FRESH Z3 run observed under the recorded query and option set.
    observed*: bool
    queryDigest*: string        ## sha256 of the recorded smtlib2 query
    outputDigest*: string       ## sha256 of the complete z3 output
    verdict*: KernelVerdict
    optionsDigest*: string      ## digest of the pinned determinism option set
    binaryDigest*: string       ## sha256 of the executed z3 binary
    randomSeed*: int
    rlimit*: int
    timeoutMs*: int

  KernelObservation* = object
    ## The pair of fresh kernel observations a certificate binds.
    lean*: LeanObservation
    z3*: Z3Observation
    verificationMode*: string   ## "lean+z3" | "lean-only" | "z3-only" | ""

func normalizeAxiomSet*(names: openArray[string]): seq[string] {.raises: [].} =
  ## Canonical observed-axiom order: non-empty, deduplicated, lexicographic.
  result = @[]
  for name in names:
    if name.len > 0 and name notin result:
      result.add name
  result.sort()

func observationVerificationMode*(leanObserved, z3Observed: bool): string {.raises: [].} =
  ## The mode is a PURE function of which kernels actually produced an
  ## observation — a caller cannot claim "lean+z3" while one side is absent.
  if leanObserved and z3Observed:
    "lean+z3"
  elif leanObserved:
    "lean-only"
  elif z3Observed:
    "z3-only"
  else:
    ""

func parseKernelVerdictName*(raw: string): Result[KernelVerdict, string] {.raises: [],
    axiomDecision(id = "DECISION-VS188-05",
      reason = "Verdict names are decoded by exact match only; any unknown token fails closed instead of degrading to a permissive default",
      adr = "docs/spec/certification_continuity_contract.md",
      introduced = "v34-vs188").} =
  case raw
  of "krPassed": ok(krPassed)
  of "krAxiomViolation": ok(krAxiomViolation)
  of "krSorry": ok(krSorry)
  of "krCompileError": ok(krCompileError)
  of "krTimeout": ok(krTimeout)
  of "krZ3Mismatch": ok(krZ3Mismatch)
  of "krZ3Error": ok(krZ3Error)
  of "krMissingInput": ok(krMissingInput)
  of "krInternalError": ok(krInternalError)
  else: err("kernel observation: unknown verdict '" & raw & "' (fail-closed)")

func leanObservationJson*(o: LeanObservation): JsonNode {.raises: [].} =
  var axioms = newJArray()
  for name in o.axiomSet:
    axioms.add(%name)
  var skipped = newJArray()
  for name in o.skippedChecks:
    skipped.add(%name)
  %*{
    "observed": o.observed,
    "theoremName": o.theoremName,
    "axiomSet": axioms,
    "verdict": $o.verdict,
    "leanSourceDigest": o.leanSourceDigest,
    "outputDigest": o.outputDigest,
    "toolchainIdentity": o.toolchainIdentity,
    "skippedChecks": skipped}

func z3ObservationJson*(o: Z3Observation): JsonNode {.raises: [].} =
  %*{
    "observed": o.observed,
    "queryDigest": o.queryDigest,
    "outputDigest": o.outputDigest,
    "verdict": $o.verdict,
    "optionsDigest": o.optionsDigest,
    "binaryDigest": o.binaryDigest,
    "randomSeed": o.randomSeed,
    "rlimit": o.rlimit,
    "timeoutMs": o.timeoutMs}

func kernelObservationJson*(o: KernelObservation): JsonNode {.raises: [].} =
  %*{
    "lean": leanObservationJson(o.lean),
    "z3": z3ObservationJson(o.z3),
    "verificationMode": o.verificationMode}

func kernelObservationDigest*(o: KernelObservation): string {.raises: [].} =
  ## Content address of the observation projection — the value the certificate
  ## signs as `observationDigest`.
  sha256Hex(canonicalJsonString(kernelObservationJson(o)))

func observationJsonString(node: JsonNode; key, what: string): Result[string, string] {.raises: [].} =
  let v = node{key}
  if v.isNil or v.kind != JString:
    return err("kernel observation: " & what & " missing or not a string (fail-closed)")
  ok(v.getStr())

func observationJsonBool(node: JsonNode; key, what: string): Result[bool, string] {.raises: [].} =
  let v = node{key}
  if v.isNil or v.kind != JBool:
    return err("kernel observation: " & what & " missing or not a bool (fail-closed)")
  ok(v.getBool())

func observationJsonInt(node: JsonNode; key, what: string): Result[int, string] {.raises: [].} =
  let v = node{key}
  if v.isNil or v.kind != JInt:
    return err("kernel observation: " & what & " missing or not an int (fail-closed)")
  ok(v.getInt())

func observationJsonStringSeq(node: JsonNode; key, what: string): Result[seq[string], string] {.raises: [].} =
  let v = node{key}
  if v.isNil or v.kind != JArray:
    return err("kernel observation: " & what & " missing or not an array (fail-closed)")
  var names: seq[string] = @[]
  for el in v.items:
    if el.kind != JString:
      return err("kernel observation: " & what & " element is not a string (fail-closed)")
    names.add el.getStr()
  ok(names)

func parseLeanObservation*(node: JsonNode): Result[LeanObservation, string] {.raises: [],
    axiomDecision(id = "DECISION-VS188-06",
      reason = "A recorded Lean observation is decoded field-by-field with mandatory presence; a partial or mistyped observation is rejected rather than read as an empty kernel result",
      adr = "docs/spec/certification_continuity_contract.md",
      introduced = "v34-vs188").} =
  if node.isNil or node.kind != JObject:
    return err("kernel observation: lean observation missing (fail-closed)")
  let observed = observationJsonBool(node, "observed", "lean.observed")
  if observed.isErr: return err(observed.error)
  let theoremName = observationJsonString(node, "theoremName", "lean.theoremName")
  if theoremName.isErr: return err(theoremName.error)
  let axiomSet = observationJsonStringSeq(node, "axiomSet", "lean.axiomSet")
  if axiomSet.isErr: return err(axiomSet.error)
  let verdictRaw = observationJsonString(node, "verdict", "lean.verdict")
  if verdictRaw.isErr: return err(verdictRaw.error)
  let verdict = parseKernelVerdictName(verdictRaw.get)
  if verdict.isErr: return err(verdict.error)
  let sourceDigest = observationJsonString(node, "leanSourceDigest", "lean.leanSourceDigest")
  if sourceDigest.isErr: return err(sourceDigest.error)
  let outputDigest = observationJsonString(node, "outputDigest", "lean.outputDigest")
  if outputDigest.isErr: return err(outputDigest.error)
  let toolchainIdentity = observationJsonString(node, "toolchainIdentity", "lean.toolchainIdentity")
  if toolchainIdentity.isErr: return err(toolchainIdentity.error)
  let skipped = observationJsonStringSeq(node, "skippedChecks", "lean.skippedChecks")
  if skipped.isErr: return err(skipped.error)
  ok(LeanObservation(
    observed: observed.get,
    theoremName: theoremName.get,
    axiomSet: axiomSet.get,
    verdict: verdict.get,
    leanSourceDigest: sourceDigest.get,
    outputDigest: outputDigest.get,
    toolchainIdentity: toolchainIdentity.get,
    skippedChecks: skipped.get))

func parseZ3Observation*(node: JsonNode): Result[Z3Observation, string] {.raises: [],
    axiomDecision(id = "DECISION-VS188-07",
      reason = "A recorded Z3 observation is decoded with mandatory presence for every solver binding (options, binary, seed, rlimit, timeout); omission cannot be read as a default run",
      adr = "docs/spec/certification_continuity_contract.md",
      introduced = "v34-vs188").} =
  if node.isNil or node.kind != JObject:
    return err("kernel observation: z3 observation missing (fail-closed)")
  let observed = observationJsonBool(node, "observed", "z3.observed")
  if observed.isErr: return err(observed.error)
  let queryDigest = observationJsonString(node, "queryDigest", "z3.queryDigest")
  if queryDigest.isErr: return err(queryDigest.error)
  let outputDigest = observationJsonString(node, "outputDigest", "z3.outputDigest")
  if outputDigest.isErr: return err(outputDigest.error)
  let verdictRaw = observationJsonString(node, "verdict", "z3.verdict")
  if verdictRaw.isErr: return err(verdictRaw.error)
  let verdict = parseKernelVerdictName(verdictRaw.get)
  if verdict.isErr: return err(verdict.error)
  let optionsDigest = observationJsonString(node, "optionsDigest", "z3.optionsDigest")
  if optionsDigest.isErr: return err(optionsDigest.error)
  let binaryDigest = observationJsonString(node, "binaryDigest", "z3.binaryDigest")
  if binaryDigest.isErr: return err(binaryDigest.error)
  let randomSeed = observationJsonInt(node, "randomSeed", "z3.randomSeed")
  if randomSeed.isErr: return err(randomSeed.error)
  let rlimit = observationJsonInt(node, "rlimit", "z3.rlimit")
  if rlimit.isErr: return err(rlimit.error)
  let timeoutMs = observationJsonInt(node, "timeoutMs", "z3.timeoutMs")
  if timeoutMs.isErr: return err(timeoutMs.error)
  ok(Z3Observation(
    observed: observed.get,
    queryDigest: queryDigest.get,
    outputDigest: outputDigest.get,
    verdict: verdict.get,
    optionsDigest: optionsDigest.get,
    binaryDigest: binaryDigest.get,
    randomSeed: randomSeed.get,
    rlimit: rlimit.get,
    timeoutMs: timeoutMs.get))

func parseKernelObservation*(node: JsonNode): Result[KernelObservation, string] {.raises: [],
    axiomDecision(id = "DECISION-VS188-08",
      reason = "Both halves of a kernel observation must decode before either is trusted; a half-present observation cannot be replayed as evidence",
      adr = "docs/spec/certification_continuity_contract.md",
      introduced = "v34-vs188").} =
  if node.isNil or node.kind != JObject:
    return err("kernel observation: observation missing (fail-closed)")
  let lean = parseLeanObservation(node{"lean"})
  if lean.isErr: return err(lean.error)
  let z3 = parseZ3Observation(node{"z3"})
  if z3.isErr: return err(z3.error)
  let mode = observationJsonString(node, "verificationMode", "verificationMode")
  if mode.isErr: return err(mode.error)
  ok(KernelObservation(lean: lean.get, z3: z3.get, verificationMode: mode.get))

func kernelObservationValidationError*(o: KernelObservation;
                                      leanSource, smtlib2: string): string {.raises: [].} =
  ## "" = self-consistent; otherwise the rejection reason. This is the gate
  ## both the witness parser and the certificate writer use, so a recorded
  ## observation can never claim a kernel fact its own digests/flags deny.
  if o.lean.observed:
    if o.lean.theoremName.len == 0:
      return "kernel observation: theoremName required when the lean run was observed (fail-closed)"
    if o.lean.axiomSet != normalizeAxiomSet(o.lean.axiomSet):
      return "kernel observation: axiomSet must be sorted and deduplicated (fail-closed)"
    if not isHexOfLen(o.lean.leanSourceDigest, 64):
      return "kernel observation: leanSourceDigest must be 64 lowercase hex (fail-closed)"
    if leanSource.len > 0 and o.lean.leanSourceDigest != sha256Hex(leanSource):
      return "kernel observation: leanSourceDigest does not match the bound leanSource (fail-closed)"
    if not isHexOfLen(o.lean.outputDigest, 64):
      return "kernel observation: lean outputDigest must be 64 lowercase hex (fail-closed)"
    if o.lean.toolchainIdentity.len == 0:
      return "kernel observation: toolchainIdentity required when the lean run was observed (fail-closed)"
    if o.lean.toolchainIdentity.contains('\n') or o.lean.toolchainIdentity.contains('\r'):
      return "kernel observation: toolchainIdentity must be a single line (fail-closed)"
    for name in o.lean.axiomSet:
      if not isAxiomAllowed(name):
        return "kernel observation: observed axiom '" & name & "' is outside the INV-6 allowlist (fail-closed)"
    let recomputed = evaluateObservedAxioms(AxiomPrintObservation(
      names: o.lean.axiomSet, observedAny: true))
    if o.lean.verdict != recomputed:
      return "kernel observation: lean verdict '" & $o.lean.verdict &
        "' is not the allowlist evaluation of the recorded axiom set ('" & $recomputed & "') (fail-closed)"
  else:
    if o.lean.theoremName.len > 0 or o.lean.axiomSet.len > 0:
      return "kernel observation: an unobserved lean run cannot claim a theorem or axioms (fail-closed)"
  if o.z3.observed:
    if not isHexOfLen(o.z3.queryDigest, 64):
      return "kernel observation: z3 queryDigest must be 64 lowercase hex (fail-closed)"
    if smtlib2.len > 0 and o.z3.queryDigest != sha256Hex(smtlib2):
      return "kernel observation: z3 queryDigest does not match the bound smtlib2 (fail-closed)"
    if not isHexOfLen(o.z3.outputDigest, 64):
      return "kernel observation: z3 outputDigest must be 64 lowercase hex (fail-closed)"
    if o.z3.optionsDigest != deterministicSolverOptionsDigest():
      return "kernel observation: z3 optionsDigest is not the pinned determinism option set (fail-closed)"
    if not isHexOfLen(o.z3.binaryDigest, 64):
      return "kernel observation: z3 binaryDigest must be 64 lowercase hex (fail-closed)"
    if o.z3.randomSeed != Z3PinnedRandomSeed:
      return "kernel observation: z3 randomSeed must equal the pinned non-zero seed (fail-closed)"
    if o.z3.rlimit != z3DeterministicBudget:
      return "kernel observation: z3 rlimit must equal the pinned deterministic budget (fail-closed)"
    if o.z3.timeoutMs <= 0:
      return "kernel observation: z3 timeoutMs must be positive (fail-closed)"
  let expectedMode = observationVerificationMode(o.lean.observed, o.z3.observed)
  if o.verificationMode != expectedMode:
    return "kernel observation: verificationMode '" & o.verificationMode &
      "' is inconsistent with the observed flags (expected '" & expectedMode & "') (fail-closed)"
  ""

func isPassingKernelObservation*(o: KernelObservation;
                                 leanSource, smtlib2: string): bool {.raises: [].} =
  ## A certificate-grade observation: both kernels observed AND passed, every
  ## observed axiom allowlisted, every digest self-consistent, and the
  ## mandatory plain `leanchecker` replay actually ran. A run whose checker
  ## was unavailable is an INCOMPLETE observation (`skippedChecks` names it),
  ## never a pass — "could not verify" must not be read as "verified".
  if kernelObservationValidationError(o, leanSource, smtlib2).len > 0:
    return false
  if leanCheckerUnavailableMarker in o.lean.skippedChecks:
    return false
  o.lean.observed and o.lean.verdict == krPassed and
    o.z3.observed and o.z3.verdict == krPassed and
    o.verificationMode == "lean+z3"

func freshObservationBindingError*(recorded: KernelObservation;
                                   fresh: LeanObservation): string {.raises: [],
    axiomDecision(id = "DECISION-VS188-09",
      reason = "A cold re-execution must bind the FRESH observation to the recorded one field by field; deriving a verdict from the embedded artifact alone cannot tell a forged claim from an honest one",
      adr = "docs/spec/cert_lifecycle_contracts.md",
      introduced = "v34-vs188").} =
  ## "" = the fresh Lean run observed exactly what the certificate records;
  ## otherwise the fail-closed rejection reason. This is the comparison the
  ## cold paths were missing: `kernelObservationValidationError` only checks a
  ## record against ITSELF, so a consistently forged cert (claim
  ## `theoremName=inc3_correct` over a source that proves `decoy_true`) passed
  ## every check. Here the second operand comes from a real run, so the claim
  ## can only survive by being true.
  ##
  ## Order matters for diagnosis, not for strength: an unobserved run is
  ## rejected first (nothing to compare), then the theorem identity - the axis
  ## a decoy source attacks - then the axiom set, then the digests that bind
  ## the exact bytes and toolchain.
  if not fresh.observed:
    return "fresh observation: the re-executed run produced no #print axioms result (fail-closed)"
  if recorded.lean.theoremName != fresh.theoremName:
    return "fresh observation: observed theorem '" & fresh.theoremName &
      "' is not the recorded theoremName '" & recorded.lean.theoremName &
      "' - the embedded source does not state the claimed theorem (fail-closed)"
  if normalizeAxiomSet(recorded.lean.axiomSet) != normalizeAxiomSet(fresh.axiomSet):
    return "fresh observation: observed axiom set [" & fresh.axiomSet.join(", ") &
      "] is not the recorded set [" & recorded.lean.axiomSet.join(", ") & "] (fail-closed)"
  if recorded.lean.leanSourceDigest != fresh.leanSourceDigest:
    return "fresh observation: leanSourceDigest '" & fresh.leanSourceDigest &
      "' does not bind the recorded digest '" & recorded.lean.leanSourceDigest & "' (fail-closed)"
  if recorded.lean.outputDigest != fresh.outputDigest:
    return "fresh observation: outputDigest '" & fresh.outputDigest &
      "' is not the recorded output digest '" & recorded.lean.outputDigest & "' (fail-closed)"
  if recorded.lean.toolchainIdentity != fresh.toolchainIdentity:
    return "fresh observation: toolchain '" & fresh.toolchainIdentity &
      "' is not the recorded toolchain '" & recorded.lean.toolchainIdentity & "' (fail-closed)"
  ""

# ─── Loader (fail-closed, never crashes on malformed input) ──────────────────

proc loadCertJsonForReexecution*(certPath: string): Result[JsonNode, string] {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Fail-closed certificate loading: unreadable file or malformed JSON →
  ## err (never crash). The structural verifier already ran at this point;
  ## this is the re-execution input extraction path.
  let text =
    try: readFile(certPath)
    except CatchableError as e: return err("certificate file unreadable: " & e.msg)
  if text.len == 0:
    return err("certificate file is empty")
  var node: JsonNode
  try:
    node = parseJson(text)
  except CatchableError as e:
    return err("malformed certificate JSON: " & e.msg)
  if node.isNil or node.kind != JObject:
    return err("certificate is not a JSON object")
  ok(node)

# ─── Z3 binary checksum pinning (INV-10) ─────────────────────────────────────

const
  z3BinaryIdentitySchema* = "axiom-z3-binary-identity/1"
    ## Stat-identity cache schema tag — a foreign/stale schema is discarded.
  z3BinaryIdentityCacheRelPath* = ".axiom/cache/z3_binary_identity.json"
    ## Z3-binary digest acceleration cache (project-root relative).

type
  Z3BinaryIdentityStats* = object
    ## Acceleration observability seam (SourceIdentityStats twin): reused =
    ## stat-identity cache HIT, rehashed = full read+hash, racy = identity
    ## matched but the git racy-git rule forced a rehash.
    reused*, rehashed*, racy*: int

  Z3IdentityCacheEntry = object
    path: string
    ident: StatIdentity
    digest: string
    writtenAtNs: int64

proc z3IdentityNowNs(): int64 {.raises: [].} =
  let t = getTime()
  t.toUnix * 1_000_000_000'i64 + t.nanosecond.int64

when defined(posix):
  proc z3IdentityCacheFileTrusted(path: string): bool {.raises: [].} =
    ## source_identity_cache.cacheFileTrusted twin: only a regular file owned
    ## by the effective user and not group/other-writable is read; anything
    ## else is treated as absent (recompute).
    var st: Stat
    if lstat(path.cstring, st) != 0:
      return false
    if (int64(st.st_mode) and int64(S_IFMT)) != int64(S_IFREG):
      return false
    if st.st_uid != geteuid():
      return false
    if (int64(st.st_mode) and (int64(S_IWGRP) or int64(S_IWOTH))) != 0:
      return false
    true

proc loadZ3IdentityCache(path: string): Z3IdentityCacheEntry {.raises: [].} =
  ## Fail-closed loader: unreadable/invalid/corrupt/untrusted cache or a
  ## foreign schema → default entry (miss → recompute). Numbers are stored as
  ## strings so 64-bit fields survive every JSON number precision boundary.
  when defined(posix):
    if not fileExists(path) or not z3IdentityCacheFileTrusted(path):
      return
    try:
      let node = parseFile(path)
      if node{"schema"}.getStr("") != z3BinaryIdentitySchema:
        return
      result.writtenAtNs = parseBiggestInt(node{"writtenAtNs"}.getStr("0"))
      result.path = node{"path"}.getStr("")
      result.digest = node{"digest"}.getStr("")
      result.ident = StatIdentity(
        dev: parseBiggestInt(node{"dev"}.getStr("0")),
        ino: parseBiggestInt(node{"ino"}.getStr("0")),
        size: parseBiggestInt(node{"size"}.getStr("0")),
        mtimeNs: parseBiggestInt(node{"mtimeNs"}.getStr("0")),
        ctimeNs: parseBiggestInt(node{"ctimeNs"}.getStr("0")),
        mode: parseBiggestInt(node{"mode"}.getStr("0")),
        kind: node{"kind"}.getStr(""))
    except CatchableError:
      result = Z3IdentityCacheEntry()

proc saveZ3IdentityCache(path: string; entry: Z3IdentityCacheEntry) {.raises: [].} =
  ## Best-effort atomic write (PID-unique tmp + chmod 0600 + safeMoveFile).
  ## The tmp file lands in the destination directory, so the move is an
  ## atomic same-filesystem rename(2) — the atomicWriteFile precedent.
  ## Failure is ignored — the cache is acceleration ONLY.
  let tmpPath = path & ".tmp." & $getCurrentProcessId()
  try:
    let dir = parentDir(path)
    if not dirExists(dir):
      createDir(dir)
    let body = %*{
      "schema": z3BinaryIdentitySchema,
      "writtenAtNs": $entry.writtenAtNs,
      "path": entry.path,
      "dev": $entry.ident.dev,
      "ino": $entry.ident.ino,
      "size": $entry.ident.size,
      "mtimeNs": $entry.ident.mtimeNs,
      "ctimeNs": $entry.ident.ctimeNs,
      "mode": $entry.ident.mode,
      "kind": entry.ident.kind,
      "digest": entry.digest}
    writeFile(tmpPath, $body)
    when defined(posix):
      discard chmod(tmpPath.cstring, 0o600)
    safeMoveFile(tmpPath, path)
  except CatchableError: # axiom:best-effort(z3 identity cache write is speed-only; the digest is always recomputable from the live binary)
    discard tryRemoveFile(tmpPath)

proc readZ3BinaryStable(z3Bin: string; first: StatIdentity):
    tuple[digest: string, ident: StatIdentity] {.
    raises: [CatchableError], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read, then re-stat (source_identity_cache.readAndDigestStable twin): a
  ## mismatch means the binary changed during the read — retry once, then
  ## fail closed (never return a digest of an unstable file).
  var ident = first
  for _ in 0 .. 1:
    let content = readFile(z3Bin)
    let after = statIdentity(z3Bin)
    if sameIdentity(ident, after):
      return (sha256Hex(content), after)
    ident = after
  raise newException(OSError, "z3 binary changed while hashing: " & z3Bin)

proc z3BinaryDigestWithStats*(z3Bin: string; projectRoot: string;
                              stats: var Z3BinaryIdentityStats): string {.
    raises: [CatchableError], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## sha256 of the Z3 binary bytes — the INV-10 verdict input, with a
  ## stat-identity acceleration cache (the source_identity_cache pattern).
  ## The OS kernel already knows whether the bytes changed
  ## (dev/ino/size/mtime_ns/ctime_ns/mode), so a cached digest is reused ONLY
  ## when the entry's path and full stat identity match AND the entry is not
  ## racily clean (git racy-git rule, second granularity — the
  ## source_identity_cache.isRacy predicate). Every anomaly — unreadable/
  ## invalid/corrupt cache, untrusted cache file, non-64-hex cached digest,
  ## path change, or a non-posix platform without a trustworthy stat identity
  ## — recomputes from the live bytes; an unreadable binary returns ""
  ## (fail-closed). The cache is acceleration ONLY: never evidence, never a
  ## verdict input beyond supplying the digest the live bytes would produce;
  ## same-UID processes are INSIDE the trust boundary (DEBT#524 — local
  ## single-writer boundary, no forgery defense claimed; the policy
  ## comparison below stays fail-closed regardless of the digest source).
  when not defined(posix):
    inc stats.rehashed
    try:
      return sha256Hex(readFile(z3Bin))
    except CatchableError:
      return ""
  else:
    let cachePath = projectRoot / z3BinaryIdentityCacheRelPath
    let cached = loadZ3IdentityCache(cachePath)
    var first: StatIdentity
    var statOk = true
    try:
      first = statIdentity(z3Bin)
    except CatchableError:
      statOk = false
    if not statOk:
      # unstatable binary: the plain read below fails -> "" (fail-closed)
      inc stats.rehashed
      try:
        return sha256Hex(readFile(z3Bin))
      except CatchableError:
        return ""
    if cached.path == z3Bin and sameIdentity(cached.ident, first) and
        isHexOfLen(cached.digest, 64):
      if not isRacy(cached.ident, cached.writtenAtNs):
        inc stats.reused
        return cached.digest
      inc stats.racy
    try:
      let stable = readZ3BinaryStable(z3Bin, first)
      inc stats.rehashed
      saveZ3IdentityCache(cachePath, Z3IdentityCacheEntry(
        path: z3Bin, ident: stable.ident, digest: stable.digest,
        writtenAtNs: z3IdentityNowNs()))
      stable.digest
    except CatchableError:
      ""

proc z3BinaryChecksumAcceptedWithStats*(z3Bin: string; projectRoot: string;
                                        stats: var Z3BinaryIdentityStats): bool {.
    raises: [CatchableError], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Runtime pinning: the ACTUAL z3 binary's sha256 must match an entry in
  ## data/policy/z3_binary_checksums.json. Missing policy file, unreadable
  ## binary, or no matching checksum → false (fail-closed, never pass). The
  ## digest comes from z3BinaryDigestWithStats (stat-identity-cached), but the
  ## pin comparison itself is UNCHANGED — the verdict is bit-identical to the
  ## full-rehash path and any digest mismatch still returns false; a cache
  ## anomaly recomputes, it can never manufacture a pass.
  let root = if projectRoot.len > 0: projectRoot else: resolveRepoRoot()
  let policyText =
    try: readFile(root / z3BinaryChecksumsPolicyPath)
    except CatchableError: ""
  if policyText.len == 0:
    return false
  var policy: JsonNode
  try:
    policy = parseJson(policyText)
  except CatchableError:
    return false
  if policy.isNil or policy.kind != JObject:
    return false
  let versions = policy.getOrDefault("versions")
  if versions.isNil or versions.kind != JObject:
    return false
  let actual = z3BinaryDigestWithStats(z3Bin, root, stats)
  if actual.len == 0:
    return false
  for _, recorded in versions.pairs:
    if recorded.kind == JString and recorded.getStr("") == actual:
      return true
  false

proc z3BinaryChecksumAccepted*(z3Bin: string; projectRoot: string = ""): bool {.
    raises: [CatchableError], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var stats: Z3BinaryIdentityStats
  z3BinaryChecksumAcceptedWithStats(z3Bin, projectRoot, stats)

# ─── Lean kernel re-execution ────────────────────────────────────────────────
# `reexecuteLeanObservedKernel` lives AFTER the leanchecker section below: the
# observed run is the single authority that also drives the optional
# `leanchecker --fresh` deep check, and Nim requires the definition first.

# ─── Z3 re-execution ─────────────────────────────────────────────────────────

proc reexecuteZ3Observed*(certJson: JsonNode; z3Path: string; timeoutMs: int): Z3Observation {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Re-executes the certificate's recorded smtlib2 on a FRESH z3 process
  ## (never a pool worker, never a cached result — INV-10), returning the
  ## complete observation (query/output/options/binary digests, pinned seed,
  ## rlimit and process timeout). The query is wrapped in the canonical
  ## rlimit-primary envelope (buildZ3QueryEnvelope) and the fresh verdict must
  ## be unsat. The resolved binary must match the pinned checksum policy
  ## (missing/unpinned binary → krZ3Error, fail-closed).
  result = Z3Observation(
    observed: false,
    queryDigest: "",
    outputDigest: "",
    verdict: krMissingInput,
    optionsDigest: deterministicSolverOptionsDigest(),
    binaryDigest: "",
    randomSeed: Z3PinnedRandomSeed,
    rlimit: z3DeterministicBudget,
    timeoutMs: timeoutMs)
  if certJson.isNil or certJson.kind != JObject:
    return
  let smtlib2 = certJson.getOrDefault("smtlib2").getStr("")
  if smtlib2.len == 0:
    return
  result.queryDigest = sha256Hex(smtlib2)
  let z3Bin = if z3Path.len > 0: z3Path else: resolveZ3Path()
  if z3Bin.len == 0 or not fileExists(z3Bin):
    result.verdict = krZ3Error
    return
  var identityStats: Z3BinaryIdentityStats
  result.binaryDigest = z3BinaryDigestWithStats(z3Bin, "", identityStats)
  if not z3BinaryChecksumAccepted(z3Bin):
    result.verdict = krZ3Error
    return
  var envelopeDigest = ""
  let payload = buildZ3QueryEnvelope(
    smtlib2, timeoutMs, kernelReexecSentinel,
    canonicalEnvelopeDigest = envelopeDigest)
  var queryPath = ""
  try:
    queryPath = getTempDir() / ("axiom_z3reexec_" & sha256Hex(smtlib2) & ".smt2")
    writeFile(queryPath, payload)
    let res = runProcessWithTimeout(z3Bin, @["-smt2", queryPath], timeoutMs)
    if queryPath.len > 0:
      try: removeFile(queryPath)
      except CatchableError: discard  # axiom:best-effort(temp artifact cleanup)
    result.observed = true
    result.outputDigest = sha256Hex(res.output)
    result.verdict = z3ResultVerdict(res.exitCode, res.timedOut, res.output)
  except CatchableError:
    if queryPath.len > 0:
      try: removeFile(queryPath)
      except CatchableError: discard  # axiom:best-effort(temp artifact cleanup)
    result.verdict = krZ3Error

proc reexecuteZ3*(certJson: JsonNode; z3Path: string; timeoutMs: int): KernelVerdict {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Thin verdict wrapper over `reexecuteZ3Observed` (existing callers).
  reexecuteZ3Observed(certJson, z3Path, timeoutMs).verdict

# ─── Independent Lean checker deep-check (certification-continuity Phase 6) ─

type LeanCheckerVerdict* = enum
  lcPassed   ## leanchecker re-validation of a FRESH compile of the artifact passed
  lcMismatch ## checker present and ran, but re-validation failed (fail-closed)
  lcSkipped  ## checker binary absent (or no artifact) — deep check skipped LOUDLY (additive)

func leanCheckerVerdictReason*(v: LeanCheckerVerdict): string =
  case v
  of lcPassed: "leanchecker re-validation passed"
  of lcMismatch: "leanchecker re-validation MISMATCH — independent kernel-level re-check failed"
  of lcSkipped: "leanchecker binary not found — independent deep check skipped (additive)"

proc resolveLeanChecker(explicit: string): string =
  ## Resolution order: explicit argument > PATH lookup (the `leanchecker`
  ## binary ships with every elan-installed Lean 4 toolchain). "" when absent.
  ##
  ## `AXIOM_LEANCHECKER_CMD` is honored ONLY under `-d:testing`: on the
  ## certification path an environment variable could point the "mandatory"
  ## replay at an arbitrary binary (`/bin/true`), which would turn an
  ## unverified artifact into a pass. Test harnesses opt in explicitly; the
  ## product path resolves the pinned toolchain only.
  if explicit.len > 0:
    return explicit
  when defined(testing):
    let envCmd = getEnv("AXIOM_LEANCHECKER_CMD", "")
    if envCmd.len > 0:
      return envCmd
  try:
    result = findExe("leanchecker")
  except OSError:
    discard  # axiom:best-effort(checker lookup best-effort — absent → lcSkipped)

proc leanCheckerStagingDir(): string {.raises: [].} =
  ## Dedicated user-owned staging dir: leanchecker ENUMERATES every directory
  ## on LEAN_PATH, and shared temp roots carry inaccessible entries (e.g.
  ## systemd-private service dirs) that abort the scan with EACCES.
  getTempDir() / "axiom_lcheck"

proc compileLeanArtifact(leanSource, cmdBase, dir, leanPath, oleanPath: string;
                         timeoutMs: int): bool {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Fresh compile of the certificate artifact into <dir>/<Mod>.olean. Runs in
  ## the temp dir: from the repo root, `lake env lean` enforces a project-root
  ## confinement that refuses out-of-tree artifacts (in root dir) — the temp
  ## dir is root-free, so the pinned lean compiles freely.
  try:
    writeFile(leanPath, leanSource)
    let (_, code) = execCmdWithTimeout(
      cmdBase & " --threads=1 -o " & quoteShell(oleanPath) & " " & quoteShell(leanPath),
      workingDir = dir,
      timeoutMs = timeoutMs)
    result = code == 0 and fileExists(oleanPath)
  except CatchableError:
    result = false

proc leanCheckerSearchPath(realChecker, dir, leanCmd: string): string {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## LEAN_PATH for the checker = temp dir (fresh artifact) + the toolchain's
  ## library search path. From a root-free staging dir `lake env` prints no
  ## LEAN_PATH, so the pinned Lean's own `--print-prefix` is the canonical
  ## source; elan `leanchecker` binaries are hardlinked outside the toolchain,
  ## so parent-dir guessing cannot locate the stdlib (kept only as a last
  ## resort).
  var basePath = ""
  let (envOut, _) = execCmdWithTimeout("lake env", workingDir = dir, timeoutMs = 30_000)
  for line in envOut.splitLines:
    if line.startsWith("LEAN_PATH="):
      basePath = line["LEAN_PATH=".len .. ^1]
      break
  if basePath.len == 0:
    let printPrefix = leanCmd & " --print-prefix"
    let (prefixOut, prefixCode) = execCmdWithTimeout(printPrefix,
      workingDir = dir, timeoutMs = 30_000)
    if prefixCode == 0:
      let prefix = prefixOut.strip()
      if prefix.len > 0 and dirExists(prefix / "lib" / "lean"):
        basePath = prefix / "lib" / "lean"
  if basePath.len == 0:
    # fallback: checker's own toolchain root (real elan symlink case)
    let sysroot = parentDir(parentDir(realChecker))
    if dirExists(sysroot / "lib" / "lean"):
      basePath = sysroot / "lib" / "lean"
  result = dir
  if basePath.len > 0:
    result = result & ":" & basePath

proc checkLeanWithLeanChecker*(certJson: JsonNode; leanExe: string = "";
                               checkerExe: string = ""; projectRoot: string = "";
                               timeoutMs: int = defaultLeanReexecTimeoutMs;
                               deep: bool = false): LeanCheckerVerdict {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Plain `leanchecker <Module>` replay of the certificate's leanSource
  ## compiled FRESH to a temp .olean (never a cached build — same rule as
  ## reexecuteLean). This is the MANDATORY gate on the observation path
  ## (docs/spec/lean_sorry_gate.md §3.2); it re-runs the kernel over the
  ## artifact in a fresh process.
  ##
  ## `deep = false` (default) replays the artifact's own module. `deep = true`
  ## adds `--fresh`, which also re-checks imported modules; measured cost on
  ## Lean 4.33.0 is 69–98 s for an `Init` import (~130 s for `Std`), so it is
  ## OPT-IN and never implicit — the canonical mint budget cannot absorb it.
  ##
  ## Absent checker binary → lcSkipped (caller records it loudly; the
  ## observation is then NON-PASSING — "could not verify" ≠ "verified");
  ## present + failed → lcMismatch (fail-closed). Honest scope (contract §8.3):
  ## leanchecker is the same Lean kernel re-run in a fresh process, not a
  ## second independent prover.
  if certJson.isNil or certJson.kind != JObject:
    return lcSkipped
  let leanSource = certJson.getOrDefault("leanSource").getStr("")
  if leanSource.len == 0:
    return lcSkipped  # no artifact to double-check; the mandatory path verdicts it
  let checker = resolveLeanChecker(checkerExe)
  if checker.len == 0 or not fileExists(checker):
    return lcSkipped
  let cmdBase =
    if leanExe.len > 0:
      leanExe
    else:
      let envCmd = getAxiomEnv(evLeanCmd, "")
      if envCmd.len > 0: envCmd else: "lake env lean"
  let moduleName = "AxiomLcheck" & sha256Hex(leanSource)
  let dir = leanCheckerStagingDir()
  try:
    if not dirExists(dir):
      createDir(dir)
  except CatchableError:
    return lcMismatch  # cannot stage the artifact — fail-closed
  let leanPath = dir / moduleName & ".lean"
  let oleanPath = dir / moduleName & ".olean"
  if not compileLeanArtifact(leanSource, cmdBase, dir, leanPath, oleanPath, timeoutMs):
    try: removeFile(leanPath)
    except CatchableError: discard  # axiom:best-effort(temp artifact cleanup)
    return lcMismatch
  let realChecker =
    try: expandFilename(checker)
    except OSError: checker  # axiom:best-effort(symlink resolution failure — run the resolved path)
  var exitCode = -1
  try:
    let (_, code) = execCmdWithTimeout(
      "env LEAN_PATH=" & quoteShell(leanCheckerSearchPath(realChecker, dir, cmdBase)) &
        " " & quoteShell(realChecker) & (if deep: " --fresh " else: " ") & moduleName,
      workingDir = dir,
      timeoutMs = timeoutMs)
    exitCode = code
  except CatchableError:
    exitCode = -1
  try: removeFile(leanPath)
  except CatchableError: discard  # axiom:best-effort(temp artifact cleanup)
  try: removeFile(oleanPath)
  except CatchableError: discard  # axiom:best-effort(temp artifact cleanup)
  if exitCode == 0:
    return lcPassed
  lcMismatch

# ─── Observed Lean re-execution (VS-188 Phase 1) ────────────────────────────

proc leanToolchainIdentity(cmdBase, checker: string): string {.raises: [].} =
  ## One-line identity of the toolchain that produced a Lean observation:
  ## the pinned compiler's `--version` first line plus the checker's SHA-256.
  ## `checker:none` / `checker:unreadable` are recorded verbatim — the
  ## observation never pretends a checker ran when it did not.
  var leanVersion = "unknown"
  try:
    let probe = execCmdWithTimeout(cmdBase & " --version", timeoutMs = 30_000)
    if probe[1] == 0:
      let first = probe[0].strip().splitLines()
      if first.len > 0 and first[0].len > 0:
        leanVersion = first[0]
  except CatchableError:
    discard  # axiom:best-effort(version probe — identity stays "unknown")
  var checkerPart = "checker:none"
  if checker.len > 0:
    try:
      if fileExists(checker):
        checkerPart = "checker:sha256:" & sha256Hex(readFile(checker))
      else:
        checkerPart = "checker:missing"
    except CatchableError:
      checkerPart = "checker:unreadable"
  "lean:" & leanVersion & ";" & checkerPart

proc reexecuteLeanObservedKernel*(certJson: JsonNode; leanExe: string; timeoutMs: int;
                            checkerExe: string = ""): LeanObservation {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Re-executes the certificate's embedded leanSource on the pinned Lean
  ## kernel and returns the COMPLETE fresh observation: the selected theorem,
  ## the sorted observed axiom set, the allowlist verdict, source/output
  ## digests and loudly-recorded skipped checks.
  ##
  ## Target binding: an explicit `#print axioms <name>` wins; otherwise the
  ## source must declare exactly ONE `theorem`/`lemma` (zero or >1 →
  ## krMissingInput). `def` is never used as the observation target.
  ##
  ## Hazards (`debug.skipKernelTC`, `run_cmd`, `#eval`, kernel-disabling
  ## `set_option`) make the source inadmissible → krMissingInput, never a
  ## verdict about the theorem.
  ##
  ## Deep check: when `leanchecker` resolves, the source is compiled FRESH to
  ## an olean in a temp dir and replayed with `leanchecker --fresh <Module>`.
  ## Absent checker → `skippedChecks: ["leanchecker:unavailable"]` (additive);
  ## present checker that rejects → krCompileError (fail-closed). The timeout
  ## is bounded by the caller's budget and the canonical kernel budget.
  result = LeanObservation(
    observed: false,
    theoremName: "",
    axiomSet: @[],
    verdict: krMissingInput,
    leanSourceDigest: "",
    outputDigest: "",
    skippedChecks: @[])
  if certJson.isNil or certJson.kind != JObject:
    return
  let leanSource = certJson.getOrDefault("leanSource").getStr("")
  if leanSource.len == 0:
    return
  result.leanSourceDigest = sha256Hex(leanSource)
  let hazards = leanSourceHazards(leanSource)
  if hazards.len > 0:
    result.skippedChecks = @["lean-hazard:" & hazards.join(",")]
    return
  let target = leanObservationTarget(leanSource)
  if target.problem.len > 0:
    result.skippedChecks = @["lean-target:" & target.problem]
    return
  result.theoremName = target.target
  let artifactSource =
    if explicitAxiomPrintTarget(leanSource).len > 0:
      leanSource
    else:
      leanSource & "\n#print axioms " & target.target & "\n"
  let cmdBase =
    if leanExe.len > 0:
      leanExe
    else:
      let envCmd = getAxiomEnv(evLeanCmd, "")
      if envCmd.len > 0: envCmd else: "lake env lean"
  let checker = resolveLeanChecker(checkerExe)
  result.toolchainIdentity = leanToolchainIdentity(cmdBase, checker)
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
  result.outputDigest = sha256Hex(output)
  if exitCode == -1:
    result.verdict = krTimeout
    return
  if exitCode != 0:
    result.verdict = krCompileError
    return
  let parsed = parsePrintAxiomsObservations(output)
  result.observed = parsed.observedAny
  result.axiomSet = normalizeAxiomSet(parsed.names)
  result.verdict = evaluateObservedAxioms(parsed)
  if not result.observed:
    result.verdict = krMissingInput
    return
  if result.verdict != krPassed:
    return
  if checker.len == 0 or not fileExists(checker):
    result.skippedChecks = @[leanCheckerUnavailableMarker]
    return
  var certLike = newJObject()
  certLike["leanSource"] = %leanSource
  let boundedTimeout = max(1, min(timeoutMs, defaultLeanReexecTimeoutMs))
  case checkLeanWithLeanChecker(certLike, leanExe, checkerExe, "", boundedTimeout)
  of lcPassed:
    result.skippedChecks = @[]
  of lcSkipped:
    result.skippedChecks = @[leanCheckerUnavailableMarker]
  of lcMismatch:
    result.verdict = krCompileError

proc reexecuteLean*(certJson: JsonNode; leanExe: string; timeoutMs: int): KernelVerdict {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Thin verdict wrapper over `reexecuteLeanObservedKernel` (existing callers).
  reexecuteLeanObservedKernel(certJson, leanExe, timeoutMs).verdict

# ─── Lean IR meta-check worker (certification-continuity Phase 3.5) ─────────

proc checkIRWithLeanWorker*(irBytes: openArray[byte]; leanWorkerExe: string = "";
                            projectRoot: string = ""; timeoutMs: int = 60_000): KernelVerdict {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Tier-1 semantic-closure structural check: serialize IRExpr bytes are
  ## decoded + MetaM-checked by the standalone Lean worker
  ## (`proofs/.lake/build/bin/ircheck --check-file <path>`, built from
  ## IR/IRCheckWorker.lean — the file-mode twin of IR/LeanWorker.lean).
  ##
  ## The payload travels via a temp FILE (never argv — QUIRK(quirk#runGitEx-
  ## argv-flattening): whitespace/newline payloads would be re-split by shell
  ## semantics; the only argv tokens are the quoted worker path and the
  ## quoted temp path). Verdict mapping:
  ##   empty bytes                  → krMissingInput
  ##   worker binary not resolvable → krInternalError (fail-closed)
  ##   exit 0                       → krPassed (decode + meta-check OK)
  ##   non-zero exit                → krCompileError (decode/meta-check failed)
  ##   timeout                      → krTimeout
  if irBytes.len == 0:
    return krMissingInput
  let root = if projectRoot.len > 0: projectRoot else: resolveRepoRoot()
  let worker =
    if leanWorkerExe.len > 0:
      leanWorkerExe
    else:
      let envCmd = getEnv("AXIOM_IRCHECK_CMD", "")
      if envCmd.len > 0: envCmd else: root / "proofs" / ".lake" / "build" / "bin" / "ircheck"
  if not fileExists(worker):
    return krInternalError
  var payload = newString(irBytes.len)
  for i in 0 ..< irBytes.len:
    payload[i] = char(irBytes[i])
  var artifactPath = ""
  var output = ""
  var exitCode = -1
  try:
    artifactPath = getTempDir() / ("axiom_ircheck_" & sha256Hex(payload) & ".bin")
    writeFile(artifactPath, payload)
    (output, exitCode) = execCmdWithTimeout(
      quoteShell(worker) & " --check-file " & quoteShell(artifactPath),
      timeoutMs = timeoutMs)
  except CatchableError:
    if artifactPath.len > 0:
      try: removeFile(artifactPath)
      except CatchableError: discard  # axiom:best-effort(temp artifact cleanup)
    return krInternalError
  if artifactPath.len > 0:
    try: removeFile(artifactPath)
    except CatchableError: discard  # axiom:best-effort(temp artifact cleanup)
  if exitCode == -1:
    return krTimeout
  if exitCode == 0:
    return krPassed
  krCompileError

{.pop.}
