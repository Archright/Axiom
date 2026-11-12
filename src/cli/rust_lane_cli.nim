import core/trusted/layer_declaration
axiomLayer "presentation"
# axiomIoBoundary — the lane executes the pinned `charon cargo` extraction
# (subprocess), reads subject/state files and, when armed, appends the
# extraction provenance record to the GitHub side-ref ledger. Every I/O proc
# carries an explicit axiomEffect pragma — §0.6 permits proc at the I/O
# boundary (the charon_runner.nim / rust_rust_pipeline.nim discipline).
{.push raises: [].}

## Rust subject lane CLI (feat/rust-lane-live-cli) — the delegation target of
## `ax prove --project <cargo-crate>`. When the explicit `--project` subject
## root carries a `Cargo.toml`, the engine hands the run to THIS module and the
## entire Nim pipeline is skipped; with `--project` absent or pointing at a
## non-cargo directory this file is never entered (zero behavior change).
##
## The lane OWNS no verification logic, no verdict vocabulary, no gate and no
## authority — it is CLI plumbing that CHAINS the existing, individually
## verified pieces:
##
##   scope lock (rust_targets, validateRustScopeSection — fail-closed)
##     → pinned charon extraction (charon_runner.runPinnedCharonCargo; the
##       identity gate dominates — a non-matching charon NEVER reaches cargo;
##       the produced LLBC is the ONLY LLBC this lane consumes: no fallback to
##       any pre-existing file, the committed fixture LLBC is test-only input)
##     → LLBC fun_decl enumeration (llbcFunDeclNamePaths — the producer's own
##       structured-name SSOT: free functions = the Ident-path join;
##       inherent-impl methods = the owner's nominal Adt path + method,
##       intern-resolved; scalar-owner impls are unaddressable and skipped,
##       Q11)
##     → per-target classification:
##         a. producer grammar rejection (rustSubjectOutcome →
##            outcomeOutOfScopeUnknown) → "unknown", fail-closed out-of-subset.
##         b. differential not agreed (verdict != eaAgree) → "unknown",
##            fail-closed BEFORE the declared check (no partial evidence).
##         c. symbol not declared in rust_targets → the DECLARATION-FREE
##            guard attempt (rust_rust_pipeline.rustGuardObligationAttempt):
##            one kernel proof attempt per mechanical checked-add goal and,
##            on kernel decline, a Z3 `ranges ∧ ¬goal` query whose model is
##            logged (log lines only). STILL "unknown" — non-claiming by
##            contract (no spec, no certificate, no KAA).
##         d. declared + extraction agreed → closed spec parse (identifiers,
##            non-negative integer literals, binary +, ==, parentheses —
##            anything else fail-closed) → the EXISTING issuance chain
##            (rust_rust_pipeline.rustSubjectIssuance) with extraction
##            provenance armed (subjectRoot + produced llbcPath + EvidenceCas
##            ledger transport when GITHUB_TOKEN is present).
##         e. issuance blocks surface VERBATIM (honest-failure protocol):
##            issued → "verified"; kernel decline → counterexample
##            confirmation attempted in-pipeline (confirmed → "failed");
##            provenance → PENDING "unknown".
##
## KERNEL-DECLINE COUNTEREXAMPLE PATH — the declared lane attempts
## confirmation INSIDE rustSubjectIssuance: the SMT query (rustCanonicalToIr
## FuncDef + irToSmtScript + Z3) asserts the theorem's hypothesis domain
## (type ranges ∪ body-derived overflow conditions) and negates the spec
## post, so a SAT model is an IN-DOMAIN candidate; its `get-model` bindings
## project into replay input literals (rust_symbolic_test_synth
## .modelToRustTestInputs → rust_replay_adapter.replayConfirmedRustDisproof)
## and only a replay AGREEMENT flips the entry to "failed" (blockReason
## carries the payload; blockStage stays "kernel"). Any unsealed step keeps
## the cvUnresolved precedent (batch_uap/ir_pipeline_runner.nim:1450-1458):
## "unknown", never fabricated literals. The UNDECLARED lane's guard attempt
## replays its SAT candidates only as an OBSERVATION (the overflow-discretion
## class, out-of-subset per §3 of the certified subset): with the subject's
## crate module bound (src/lib.rs), a replayed OVERFLOW panic confirms the
## counterexample in the reason text ("VIOLATED … profile-bound, not language
## semantics") while the entry classification stays "unknown" — non-claiming
## by contract (no spec, no certificate, no KAA) — and the model literals,
## panic report and measured replay toolchain travel ONLY on the log lines,
## never inside a reason.
##
## EXIT SEMANTICS — derived, never invented: the report document carries the
## run summary (verified / failedCount / timeoutCount / verifiedRatio /
## statusCounts) and the exit code is the EXISTING single rule
## (wf_runners.axProofShortcutExitCode → decision_algebra.projectRunOutcome →
## cli_outcome.runExitCode), including the AXIOM_REQUIRE_PERFECT_ASI=1 gate.
## Lane-local additions: a spec-decode failure is a per-target "error" entry
## and sets summary.blockingFailure (the existing fail-closed lever inside
## axProofShortcutExitCode → exit 1); target-RESOLUTION failures (missing
## scope lock, --target NotFound/Ambiguous) never produce a report — they are
## CliError INVALID_INPUT (exit 3), the engine's own channel.

import std/[algorithm, json, options, os, strutils, tables, unicode]

import cli/cert_cli  # DefaultLedgerRepo — the ledger repo SSOT constant
import cli/cli_outcome
import cli/wf_runners  # axProofShortcutExitCode — THE run-exit rule
import core/crypto/hash_kernel
import core/json/json_utils
import core/results
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/axiom_pragmas
  # (also provides validateRustScopeSection — axiom_pragmas_procs is an
  # include fragment of core/axiom_pragmas, never imported directly)
import core/trusted/env_access
import core/trusted/env_types
import core/trusted/rust_canonical  # RustCanonical field access (params)
import core/types/vkd_types  # initKernelRatio — the ratio SSOT constructor
import core/context/run_context
  # collectSubjectFileSet + sha256FileT + D1 fingerprint primitives — the
  # §6c v2 subject.sourceFingerprint measurement reuses the ONE D1 discipline
import core/topology/node_filter  # rustSourcePolicy — the D1 `.rs` policy
import core/utils/canonical_projection  # sortedCanonicalJson — THE canonical form
import core/utils/constants  # axiomReportSchemaVersion + §6c v2 constants
import core/utils/repo_root  # resolveRepoRoot — repo anchor for the Lean worker legs
import verification/attestation_orchestrator  # currentUtcTimestamp
import verification/cert_vault_role  # resolveVaultDirForWrite — DECISION-0622
import verification/charon_runner
import verification/evidence_ledger  # EvidenceCasRefName — the side ref the extraction record lands on
import verification/extraction_agreement  # ea* verdict vocabulary
import verification/extraction_provenance
  # fileSha256Hex + rustToolchainIdentityToken/validate — the §6c v2
  # measurement primitives (cli→verification has existing precedent)
import verification/ledger_side_ref  # liveLedgerTransport / LedgerTransport
import verification/llbc_to_canonical
  # RustFileTableRejection — the structured producer rejection facts;
  # llbcFunDeclNamePaths — the enumeration SSOT (the candidate names are the
  # producer's own structured match keys, ONE source of name semantics)
import verification/rust_replay_adapter
  # subjectGitIdentity + rustToolchainFingerprint — §6c v2 measured anchors
import verification/rust_rust_pipeline
import verification/unified_trajectory  # logStage/skReport — the trajectory SSOT the engine's report stage uses

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type RustLaneCliReport* = object
  ## The lane's report, projected by the engine hook into the existing
  ## ProofReport channel (outputJson → stdout block, logLines → stderr block,
  ## exitCode → the single exit boundary). Defined here — NOT ProofReport —
  ## so the lane never imports the engine (no cycle).
  outputJson*: string
  logLines*: seq[string]
  exitCode*: int

type SpecParseResult = object
  ok*: bool
  expr*: IRExpr
  sort*: RustType          ## the term's type (int kind vs bool kind)
  isProp*: bool            ## bool PROP (comparison/combinator) vs VALUE (0/1)
  reason*: string

type SpecTypeEnvEntry = tuple[name: string, ty: RustType]

type LaneClaimIdentity = object
  ## The §6c v2 production-time claim identity of the SINGLE certified-scope
  ## target, measured from the objects the run actually consumes (the
  ## scope-lock entry, the spec sidecar via the SAME specEntryFor, the module
  ## file via the SAME resolution walk). All-or-nothing: `measured == false`
  ## records the gap reason and NO identity sidecar is produced.
  measured*: bool
  gapReason*: string
  symbol*: string
  specRef*: string
  postSha256*: string
  moduleAbs*: string
  rejection*: RustFileTableRejection
    ## the structured producer rejection of this target (zero = none) —
    ## populated ONLY from RustSubjectOutcome.rejection (the validator's own
    ## violation facts), never re-derived here
  embedded*: seq[LlbcEmbeddedEntry]
    ## populated ONLY from RustSubjectOutcome.embeddedFiles (the validator's
    ## own classification), never re-derived here
  leafReason*: string
    ## the EXACT reason string the target entry carries — skeleton material
    ## only (memory), never written into the sidecar

# ---------------------------------------------------------------------------
# Pure helpers (the CLOSED spec grammar)
# ---------------------------------------------------------------------------

func isSpecIdentStart(c: char): bool {.raises: [].} = c in {'a'..'z', '_'}
func isSpecIdentChar(c: char): bool {.raises: [].} = c in {'a'..'z', '0'..'9', '_'}

func specBoolValueExpr(e: IRExpr; sort: RustType; isProp: bool): IRExpr =
  ## Bool PROP (comparison/combinator) → its Int 0/1 VALUE `ite(prop,1,0)`.
  ## A bool value passes through. Mirrors the derivation's embed rule so the
  ## spec post and the body share one value sort.
  if sort.kind == rtyBool and isProp:
    IRExpr(kind: irIf, ifCond: e, ifThen: irLit(1), ifElse: irLit(0),
           typ: irTypeBitVec64())
  else:
    e

func specBoolPropExpr(e: IRExpr; sort: RustType; isProp: bool): IRExpr =
  ## Bool VALUE → its Prop form `e = 1`; a Prop passes through. Mirrors
  ## rust_extraction_agreement.asBoolProp (the single coercion rule).
  if sort.kind == rtyBool and not isProp:
    irBinOp(boEq, e, irLit(1))
  else:
    e

proc specPrimary(s: string; pos: var int; env: seq[SpecTypeEnvEntry];
                 resultTy: RustType): SpecParseResult {.raises: [].}
proc specAdditive(s: string; pos: var int; env: seq[SpecTypeEnvEntry];
                  resultTy: RustType): SpecParseResult {.raises: [].}
proc specComparison(s: string; pos: var int; env: seq[SpecTypeEnvEntry];
                    resultTy: RustType): SpecParseResult {.raises: [].}
proc specAnd(s: string; pos: var int; env: seq[SpecTypeEnvEntry];
             resultTy: RustType): SpecParseResult {.raises: [].}
proc specOr(s: string; pos: var int; env: seq[SpecTypeEnvEntry];
            resultTy: RustType): SpecParseResult {.raises: [].}

proc specPrimary(s: string; pos: var int; env: seq[SpecTypeEnvEntry];
                 resultTy: RustType): SpecParseResult {.raises: [].} =
  ## primary := ident | true | false | non-negative-integer | "(" specOr ")"
  ## The grammar is CLOSED: no operators beyond the lane's spec family, no
  ## negative literals, no calls. Anything else is an explicit not-ok.
  while pos < s.len and s[pos] in {' ', '\t'}: inc pos
  if pos >= s.len:
    return SpecParseResult(ok: false, reason: "spec 'post' ended where a term was expected")
  let c = s[pos]
  if c == '(':
    inc pos
    let inner = specOr(s, pos, env, resultTy)
    if not inner.ok:
      return inner
    while pos < s.len and s[pos] in {' ', '\t'}: inc pos
    if pos >= s.len or s[pos] != ')':
      return SpecParseResult(ok: false, reason: "spec 'post' expected ')' — outside the closed grammar")
    inc pos
    return inner
  if c in {'0'..'9'}:
    let start = pos
    while pos < s.len and s[pos] in {'0'..'9'}: inc pos
    var value: uint64 = 0
    for i in start ..< pos:
      let digit = uint64(s[i].ord - '0'.ord)
      if value > (uint64.high - digit) div 10:
        return SpecParseResult(ok: false, reason: "spec 'post' integer literal overflow — outside the closed grammar")
      value = value * 10 + digit
    # Two-part literal form: [0, 2^63) in the signed domain, [2^63, 2^64−1]
    # in the u64 domain — never a truncated reinterpretation.
    let expr = if value < 0x8000000000000000'u64: irLit(cast[int64](value))
               else: irLitU64(value)
    return SpecParseResult(ok: true, expr: expr, sort: rustU64Type(),
                           isProp: false, reason: "")
  if isSpecIdentStart(c):
    let start = pos
    inc pos
    while pos < s.len and isSpecIdentChar(s[pos]): inc pos
    let name = s[start ..< pos]
    if name == "true" or name == "false":
      return SpecParseResult(ok: true,
        expr: irLit(if name == "true": 1'i64 else: 0'i64),
        sort: rustBoolType(), isProp: false, reason: "")
    if name == "result":
      return SpecParseResult(ok: true, expr: irVar(name, irTypeBitVec64()),
                             sort: resultTy, isProp: false, reason: "")
    for entry in env:
      if entry.name == name:
        return SpecParseResult(ok: true, expr: irVar(name, irTypeBitVec64()),
                               sort: entry.ty, isProp: false, reason: "")
    return SpecParseResult(ok: false, reason:
      "spec 'post' references unknown identifier '" & name &
      "' (neither 'result' nor a declared subject parameter) — fail-closed")
  SpecParseResult(ok: false, reason:
    "spec 'post' character '" & c & "' is outside the closed grammar " &
    "(identifiers, non-negative integer literals, '+', '==', '<', '&&', " &
    "'||', parentheses)")

proc specAdditive(s: string; pos: var int; env: seq[SpecTypeEnvEntry];
                  resultTy: RustType): SpecParseResult {.raises: [].} =
  ## additive := primary ("+" primary)* — integer operands only.
  let first = specPrimary(s, pos, env, resultTy)
  if not first.ok:
    return first
  result = first
  while true:
    while pos < s.len and s[pos] in {' ', '\t'}: inc pos
    if pos < s.len and s[pos] == '+':
      inc pos
      let rhs = specPrimary(s, pos, env, resultTy)
      if not rhs.ok:
        return rhs
      if result.sort.kind != rtyInt or rhs.sort.kind != rtyInt:
        return SpecParseResult(ok: false, reason:
          "spec 'post' '+' requires integer operands — outside the closed grammar")
      result = SpecParseResult(ok: true,
        expr: irAdd(result.expr, rhs.expr), sort: result.sort,
        isProp: false, reason: "")
    else:
      return

proc specComparison(s: string; pos: var int; env: seq[SpecTypeEnvEntry];
                    resultTy: RustType): SpecParseResult {.raises: [].} =
  ## comparison := additive (("==" | "<") additive)?
  ## Both sides int (Eq/Lt) or both bool (Eq; bool RHS embedded as 0/1).
  let lhs = specAdditive(s, pos, env, resultTy)
  if not lhs.ok:
    return lhs
  while pos < s.len and s[pos] in {' ', '\t'}: inc pos
  if pos + 1 < s.len and s[pos] == '=' and s[pos + 1] == '=':
    pos += 2
    let rhs = specAdditive(s, pos, env, resultTy)
    if not rhs.ok:
      return rhs
    if lhs.sort.kind == rtyInt and rhs.sort.kind == rtyInt:
      return SpecParseResult(ok: true, expr: irEq(lhs.expr, rhs.expr),
                             sort: rustBoolType(), isProp: true, reason: "")
    if lhs.sort.kind == rtyBool and rhs.sort.kind == rtyBool:
      let lv = specBoolValueExpr(lhs.expr, lhs.sort, lhs.isProp)
      let rv = specBoolValueExpr(rhs.expr, rhs.sort, rhs.isProp)
      return SpecParseResult(ok: true, expr: irEq(lv, rv),
                             sort: rustBoolType(), isProp: true, reason: "")
    return SpecParseResult(ok: false, reason:
      "spec 'post' '==' compares int with bool — outside the closed grammar")
  if pos < s.len and s[pos] == '<':
    if pos + 1 < s.len and s[pos + 1] == '=':
      return SpecParseResult(ok: false, reason:
        "spec 'post' '<=' is outside the closed grammar (only '<' and '==')")
    inc pos
    let rhs = specAdditive(s, pos, env, resultTy)
    if not rhs.ok:
      return rhs
    if lhs.sort.kind != rtyInt or rhs.sort.kind != rtyInt:
      return SpecParseResult(ok: false, reason:
        "spec 'post' '<' requires integer operands — outside the closed grammar")
    return SpecParseResult(ok: true, expr: irBinOp(boLt, lhs.expr, rhs.expr),
                           sort: rustBoolType(), isProp: true, reason: "")
  lhs

proc specAnd(s: string; pos: var int; env: seq[SpecTypeEnvEntry];
             resultTy: RustType): SpecParseResult {.raises: [].} =
  ## conjunction := comparison ("&&" comparison)* — bool operands only.
  var lhs = specComparison(s, pos, env, resultTy)
  if not lhs.ok:
    return lhs
  while true:
    while pos < s.len and s[pos] in {' ', '\t'}: inc pos
    if pos + 1 < s.len and s[pos] == '&' and s[pos + 1] == '&':
      pos += 2
      let rhs = specComparison(s, pos, env, resultTy)
      if not rhs.ok:
        return rhs
      if lhs.sort.kind != rtyBool or rhs.sort.kind != rtyBool:
        return SpecParseResult(ok: false, reason:
          "spec 'post' '&&' requires boolean operands — outside the closed grammar")
      lhs = SpecParseResult(ok: true,
        expr: irBinOp(boAnd,
                      specBoolPropExpr(lhs.expr, lhs.sort, lhs.isProp),
                      specBoolPropExpr(rhs.expr, rhs.sort, rhs.isProp)),
        sort: rustBoolType(), isProp: true, reason: "")
    else:
      return lhs

proc specOr(s: string; pos: var int; env: seq[SpecTypeEnvEntry];
            resultTy: RustType): SpecParseResult {.raises: [].} =
  ## disjunction := conjunction ("||" conjunction)* — bool operands only.
  var lhs = specAnd(s, pos, env, resultTy)
  if not lhs.ok:
    return lhs
  while true:
    while pos < s.len and s[pos] in {' ', '\t'}: inc pos
    if pos + 1 < s.len and s[pos] == '|' and s[pos + 1] == '|':
      pos += 2
      let rhs = specAnd(s, pos, env, resultTy)
      if not rhs.ok:
        return rhs
      if lhs.sort.kind != rtyBool or rhs.sort.kind != rtyBool:
        return SpecParseResult(ok: false, reason:
          "spec 'post' '||' requires boolean operands — outside the closed grammar")
      lhs = SpecParseResult(ok: true,
        expr: irBinOp(boOr,
                      specBoolPropExpr(lhs.expr, lhs.sort, lhs.isProp),
                      specBoolPropExpr(rhs.expr, rhs.sort, rhs.isProp)),
        sort: rustBoolType(), isProp: true, reason: "")
    else:
      return lhs

proc parseClosedSpecPost*(text: string; env: seq[SpecTypeEnvEntry];
                          resultTy: RustType): SpecParseResult {.raises: [].} =
  ## The CLOSED spec-post parser: `disjunction`. Builds the lane's IRExpr
  ## family — "result"/params → irVar(BV64), "+" → irAdd, "==" → irEq,
  ## "<" → boLt, "&&" → boAnd, "||" → boOr, true/false → 1/0. Bool typing is
  ## explicit (sort + isProp) so `result == (ch == 34 || …)` lowers to
  ## `result == ite(prop, 1, 0)` — the SAME embed the body derivation uses.
  ## Exactly the specAddAdd shape and the v1.3 bool-expression shape; anything
  ## else fails closed. proc, not func — the mutually recursive descent
  ## defeats the effect inference (the parseLlbcFile purity precedent);
  ## raises: [] still holds.
  var pos = 0
  let r = specOr(text, pos, env, resultTy)
  if not r.ok:
    return r
  while pos < text.len and text[pos] in {' ', '\t'}: inc pos
  if pos != text.len:
    return SpecParseResult(ok: false, reason:
      "spec 'post' has trailing input — outside the closed grammar")
  r

# ---------------------------------------------------------------------------
# I/O boundary
# ---------------------------------------------------------------------------

func laneLedgerRepo*(): string {.raises: [].} =
  ## Mirror of cert_cli.ledgerRepo() (the side-ref ledger repo projection):
  ## AXIOM_REPO env override, else the DefaultLedgerRepo constant — imported
  ## from cli/cert_cli so the default lives in exactly one place.
  let r = getEnv("AXIOM_REPO", "")
  if r.len > 0: r else: DefaultLedgerRepo

proc laneVaultDir(): string {.raises: [CatchableError],
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## DECISION-0622 write-side vault resolution with an empty task vault (the
  ## lane branch runs before buildProofTask, so no axiom.toml vault_dir is in
  ## scope): AXIOM_PROVE_VAULT_DIR env, else <state>/build/certificates.
  ## Raises on the canonical-write guard — the caller fails closed on it.
  var env = initTable[string, string]()
  env["AXIOM_PROVE_VAULT_DIR"] = getAxiomEnv(evProveVaultDir)
  resolveVaultDirForWrite("", env)

proc findDepInfo(workDir, crateName: string): string {.
    raises: [CatchableError], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Locate the rustc dep-info for the extracted crate under the lane's
  ## charon work dir (`charon-target/**/lib<crate>.d`). "" = not found — the
  ## input contract then fails closed (the authoritative input set is
  ## unavailable). Deterministic: the first byte-lex path wins.
  if crateName.len == 0:
    return ""
  let target = "lib" & crateName & ".d"
  var hits: seq[string] = @[]
  for path in walkDirRec(workDir / "charon-target"):
    let (dir, name, ext) = splitFile(path)
    if name & ext == target:
      hits.add(path)
  if hits.len == 0:
    return ""
  hits.sort()
  hits[0]

proc loadScopeLock(stateRoot: string): Result[JsonNode, CliError] {.
    raises: [CatchableError], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The scope lock follows the STATE root (resolveScopeLockPath discipline:
  ## with --project the lock lives at $AXIOM_STATE_DIR/data). Missing,
  ## unreadable, or rust-section-invalid → INVALID_INPUT, fail-closed.
  let lockPath = stateRoot / "data" / "verification_scope.lock"
  if not fileExists(lockPath):
    return err(CliError(kind: CliOutcome.INVALID_INPUT, msg:
      "[AXIOM] rust lane requires the verification scope lock (fail-closed): " &
      "not found at '" & lockPath & "' — with --project the lock is resolved " &
      "from the state root ($AXIOM_STATE_DIR/data/verification_scope.lock)"))
  var lockData: JsonNode
  try:
    lockData = parseJson(readFile(lockPath))
  except CatchableError as e:
    return err(CliError(kind: CliOutcome.INVALID_INPUT, msg:
      "[AXIOM] rust lane cannot read the verification scope lock (fail-closed): " &
      lockPath & ": " & e.msg))
  let rustCheck = validateRustScopeSection(lockData)
  if rustCheck.checked and not rustCheck.ok:
    return err(CliError(kind: CliOutcome.INVALID_INPUT, msg:
      "[AXIOM] rust lane refuses an invalid vks_rust scope declaration " &
      "(fail-closed): " & rustCheck.reason))
  ok(lockData)

proc resolveSpecsFile(specRefPath: string; projectAbs: string;
    repoRoot: string): Result[string, string] {.raises: [],
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Resolve the specRef's path half against the anchors it can honestly name:
  ## the repo root (the committed, repo-relative form), the subject root, and
  ## the subject root's bare sidecar name. First existing path wins; none →
  ## explicit not-ok (fail-closed — no silent spec substitution).
  let candidates = @[repoRoot / specRefPath, projectAbs / specRefPath,
                     projectAbs / splitFile(specRefPath).name]
  for c in candidates:
    if fileExists(c):
      return ok(c)
  err("specRef path '" & specRefPath &
      "' does not resolve against the repo root or the subject root (fail-closed)")

proc specEntryFor(specRef: string; symbol: string; projectAbs: string;
    repoRoot: string): Result[JsonNode, string] {.
    raises: [CatchableError], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## "<path>#<symbol>" → the subject-owned spec object in axiom.specs.json.
  ## The fragment must name EXACTLY the declared symbol; the specs file must
  ## carry a "post" string for it. Every deviation is an explicit not-ok.
  let hash = specRef.find('#')
  if hash < 0:
    return err("specRef '" & specRef & "' has no '#symbol' fragment (fail-closed)")
  let pathPart = specRef[0 ..< hash]
  let frag = specRef[(hash + 1) ..< specRef.len]
  if frag != symbol:
    return err("specRef fragment '" & frag & "' does not match the declared symbol '" &
               symbol & "' (fail-closed)")
  let fileRes = resolveSpecsFile(pathPart, projectAbs, repoRoot)
  if fileRes.isErr:
    return err(fileRes.error)
  var specs: JsonNode
  try:
    specs = parseJson(readFile(fileRes.get()))
  except CatchableError as e:
    return err("spec sidecar unreadable: " & fileRes.get() & ": " & e.msg)
  let specsObj = specs{"specs"}
  if specsObj.isNil or specsObj.kind != JObject:
    return err("spec sidecar has no 'specs' object: " & fileRes.get() & " (fail-closed)")
  let entry = specsObj{frag}
  if entry.isNil or entry.kind != JObject:
    return err("spec sidecar has no entry for '" & frag & "': " &
               fileRes.get() & " (fail-closed)")
  let post = entry{"post"}
  if post.isNil or post.kind != JString or post.getStr().len == 0:
    return err("spec entry '" & frag & "' has no non-empty string 'post' (fail-closed)")
  ok(entry)

proc resolveLaneModule*(lockModule: string; projectAbs: string;
    repoRoot: string): string {.
    raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The declaration's own scope-lock module entry, resolved; the subject's
  ## src/lib.rs is the fallback (the crate's only module). "" = unresolvable
  ## (fail-closed). The §6c v2 claim measurement reuses the SAME resolution
  ## walk as the declared issuance path — one module identity, one discipline.
  ## Audit F4 (fail-closed): a lock module relative path that exists as
  ## DISTINCT files in BOTH the repo tree and the subject tree is an
  ## ambiguous subject binding — no candidate is chosen, the identity bundle
  ## gaps. Only an unambiguous owner (exactly one tree holds the file, or
  ## both joins name the SAME file) resolves.
  let inRepo = normalizePathEnd(repoRoot / lockModule)
  let inSubject = normalizePathEnd(projectAbs / lockModule)
  let repoHit = fileExists(inRepo)
  let subjectHit = fileExists(inSubject)
  if subjectHit and repoHit:
    if inSubject == inRepo:
      return inSubject
    return ""
  if subjectHit:
    return inSubject
  if repoHit:
    return inRepo
  let fallback = projectAbs / "src" / "lib.rs"
  if fileExists(fallback):
    return fallback
  ""

proc subjectSourceFingerprint*(subjectRoot: string): string {.
    raises: [CatchableError], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The D1 fingerprint over the subject `.rs` set — the SAME construction
  ## the rust subject input contract's (c1) half uses (rustSourcePolicy
  ## collection + encodeFingerprintRecord + finalizeSourceFingerprint), so
  ## the §6c v2 bundle binds exactly what the contract would bind. "" = the
  ## measurement gap (fail-closed): an unreadable file, an invalid UTF-8
  ## name, or a degenerate empty set is never folded into a passable digest.
  var records: seq[seq[byte]]
  let collected = collectSubjectFileSet(subjectRoot, rustSourcePolicy)
  for relEntry in collected.paths:
    if validateUtf8(relEntry) >= 0:
      return ""
    let digestInfo = sha256FileT(subjectRoot / relEntry)
    if digestInfo.isErr():
      return ""
    records.add(encodeFingerprintRecord(relEntry, digestInfo.value))
  if records.len == 0:
    return ""
  finalizeSourceFingerprint(records)

type LaneIdentityMeasurement = object
  ## The §6c v2 production-time identity measurement outcome. `gap == ""` iff
  ## the identity document is fully measured (all-or-nothing — a partial
  ## sidecar is never written).
  gap*: string
  doc*: JsonNode

proc measureSkReportIdentity*(projectAbs, stateRoot, repoRoot,
                              charonMeasured: string;
                              claim: LaneClaimIdentity): LaneIdentityMeasurement {.
    raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## THE §6c v2 production-time identity measurement (bundle production
  ## authority: the lane — productization_contract.md §6c v2). Every field
  ## comes from an EXISTING primitive over the objects the run actually
  ## consumed; the first unmeasurable field fails the WHOLE bundle
  ## (all-or-nothing) with a verbatim gap reason — no partial sidecar, no
  ## default value, never a fabricated identity. Local state only: no
  ## GITHUB_TOKEN dependency (the remote ledger stays on the issuance path).
  if not claim.measured:
    result.gap = "claim identity unmeasurable: " & claim.gapReason
    return
  let git = subjectGitIdentity(projectAbs)
  if git.gitRef.len == 0:
    result.gap = "subject git identity unmeasurable (rev-parse failed or not a git repo)"
    return
  var moduleRel = ""
  try:
    moduleRel = relativePath(claim.moduleAbs, projectAbs)
  except CatchableError:
    moduleRel = ""
  if moduleRel.len == 0 or isAbsolute(moduleRel) or moduleRel.startsWith(".."):
    result.gap = "resolved module '" & claim.moduleAbs &
      "' has no subject-relative form (fail-closed)"
    return
  let moduleSha = fileSha256Hex(claim.moduleAbs)
  if moduleSha.isErr:
    result.gap = "module digest unmeasurable: " & moduleSha.error
    return
  let srcFp = subjectSourceFingerprint(projectAbs)
  if srcFp.len == 0:
    result.gap = "subject source fingerprint unmeasurable (empty or unreadable `.rs` set)"
    return
  let lockSha = fileSha256Hex(stateRoot / "data" / "verification_scope.lock")
  if lockSha.isErr:
    result.gap = "scope lock digest unmeasurable: " & lockSha.error
    return
  if charonMeasured.len == 0:
    result.gap = "charon measured identity absent"
    return
  let token = rustToolchainIdentityToken(rustToolchainFingerprint(""))
  let tokenProblem = validateRustToolchainIdentityToken(token)
  if tokenProblem.len > 0:
    result.gap = "rust toolchain identity unmeasurable: " & tokenProblem
    return
  let cargoLock = fileSha256Hex(projectAbs / "Cargo.lock")
  if cargoLock.isErr:
    result.gap = "Cargo.lock digest unmeasurable (a comparable run requires " &
      "the placed lock — dependencies unpinned otherwise): " & cargoLock.error
    return
  let cargoMan = fileSha256Hex(projectAbs / "Cargo.toml")
  if cargoMan.isErr:
    result.gap = "Cargo.toml digest unmeasurable: " & cargoMan.error
    return
  var rejectionNode: JsonNode = newJNull()
  if claim.rejection.rule.len > 0:
    var skeletonSha = ""
    if claim.rejection.rawPath.len > 0 and claim.leafReason.len > 0:
      skeletonSha = sha256Hex(claim.leafReason.replace(
        claim.rejection.rawPath, axiomSkReportSkeletonMarker))
    rejectionNode = %*{
      "rule": %claim.rejection.rule,
      "index": %claim.rejection.index,
      "crateName": %claim.rejection.crateName,
      "contentSha256": %claim.rejection.contentSha256,
      "skeletonSha256": %skeletonSha,
    }
  result.doc = %*{
    "schemaVersion": %axiomSkReportIdentitySchemaVersion,
    "identity": %*{
      "subject": %*{
        "commit": %git.gitRef,
        "modulePath": %moduleRel,
        "moduleSha256": %moduleSha.get(),
        "sourceFingerprint": %srcFp,
      },
      "claim": %*{
        "symbol": %claim.symbol,
        "specRef": %claim.specRef,
        "postSha256": %claim.postSha256,
      },
      "scope": %*{
        "rustTargetsSha256": %lockSha.get(),
      },
      "toolchain": %*{
        "charon": %charonMeasured,
        "rustc": %token,
        "cargoLockSha256": %cargoLock.get(),
        "cargoManifestSha256": %cargoMan.get(),
        "nim": %("Nim " & NimVersion),
      },
      "rejection": rejectionNode,
    },
  }
  if claim.embedded.len > 0:
    var embeddedArr: seq[JsonNode] = @[]
    for e in claim.embedded:
      embeddedArr.add(%*{
        "index": %e.index,
        "crateName": %e.crateName,
        "contentSha256": %e.contentSha256,
      })
    result.doc{"identity"}["embeddedContentAttested"] = %embeddedArr

proc classifyIssuanceBlock(rec: RustIssuanceRecord): tuple[status: string; reason: string] {.
    raises: [].} =
  ## The honest-failure projection of one issuance record (issued handled by
  ## the caller). Provenance is the PENDING family (network/ledger
  ## unavailable is not a verification verdict); a CONFIRMED kernel decline
  ## is the "failed" branch (the counterexample was replayed against the
  ## real subject — an observed disagreement, not a pending question); the
  ## unconfirmed kernel decline stays the cvUnresolved "unknown" precedent;
  ## the writer's refusal is OUR mint failing (error-class); every other
  ## stage is PENDING "unknown".
  if rec.counterexampleConfirmed:
    return ("failed", rec.blockReason)
  if rec.blockStage == "provenance":
    ("unknown", "provenance unavailable: " & rec.blockReason)
  elif rec.blockStage == "kernel":
    # Kernel decline. A CONFIRMED decline was already returned as "failed"
    # above (the replay observed an in-domain counterexample); this branch is
    # the UNCONFIRMED residue — the Lean kernel yields no solver model by
    # itself, so without the in-pipeline SMT+replay confirmation there are no
    # replay input literals to project (see the module docstring).
    # cvUnresolved precedent — fail-closed "unknown", never "failed".
    ("unknown", "spec declined by kernel; counterexample unconfirmed " &
      "(cvUnresolved precedent, ir_pipeline_runner.nim:1450-1458): " &
      rec.blockReason)
  elif rec.blockStage == "writer":
    ("error", "certificate writer refused (" & rec.blockStage & "): " & rec.blockReason)
  else:
    ("unknown", rec.blockStage & ": " & rec.blockReason)

proc runRustLaneCli*(projectAbs: string; stateRoot: string; target: string):
    Result[RustLaneCliReport, CliError] {.
    raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## THE lane. See the module docstring for the staged contract.
  var log: seq[string] = @[]
  let repoRoot = resolveRepoRoot()

  # ① Scope lock (state-root discipline) → the declared denominator.
  let lockRes = loadScopeLock(stateRoot)
  if lockRes.isErr:
    return err(lockRes.error)
  let lockData = lockRes.get()
  var declared = initTable[string, JsonNode]()
  for entry in lockData{"rust_targets"}.elems:
    declared[entry{"symbol"}.getStr()] = entry

  # ② The certificate vault (DECISION-0622) — fail closed before any work.
  var vaultDir = ""
  try:
    vaultDir = laneVaultDir()
  except CatchableError as e:
    return err(CliError(kind: CliOutcome.INVALID_INPUT, msg:
      "[AXIOM] rust lane cannot resolve the certificate vault (fail-closed): " & e.msg))
  try:
    createDir(vaultDir)
  except CatchableError as e:
    return err(CliError(kind: CliOutcome.INVALID_INPUT, msg:
      "[AXIOM] rust lane cannot create the certificate vault dir '" & vaultDir &
      "' (fail-closed): " & e.msg))

  # ③ The pinned extraction — the identity gate dominates; the produced LLBC
  # is the ONLY document this lane consumes (never a pre-existing file).
  let workDir = stateRoot / ".axiom" / "rust-lane" / sha256Hex(projectAbs)[0 ..< 16]
  let charonExe = getEnv("AXIOM_CHARON_BIN", "charon")
  let run = runPinnedCharonCargo(projectAbs, workDir, charonExe)
  log.add("[AXIOM][rust-lane] charon pinned='" & pinnedCharonIdentity() &
          "' measured='" & run.versionLine & "' ok=" & $run.ok)

  var report = %*{
    "schemaVersion": %axiomReportSchemaVersion,
    "subjectLane": %"rust",
    "charon": %*{
      "pinned": %pinnedCharonIdentity(),
      "measured": %run.versionLine,
      "ok": %run.ok,
      "reason": %run.reason
    }
  }

  # §6c v2 production-time claim identity — declared before `finish` so the
  # report-production closure captures it; MEASURED after the candidate
  # enumeration (below), which is still before any `finish` call.
  var laneClaim = LaneClaimIdentity(
    gapReason: "run ended before single-target claim measurement")

  proc finish(report: JsonNode): RustLaneCliReport {.
      raises: [CatchableError], axiomEffect: IOEffect,
      tags: [AxiomIOEffect, IOEffect, RootEffect].} =
    # §6c v2 — the production-time identity sidecar at THE report production
    # point (the lane is the bundle production authority,
    # productization_contract.md §6c v2; all-or-nothing). A measurement gap
    # writes NOTHING: the payload then carries no identityBundleDigest key
    # and the §6c comparison records identity unknown (fail-closed), with
    # the gap logged verbatim on the existing lane log channel. Local state
    # only — no GITHUB_TOKEN dependency (the remote ledger stays where it
    # is: the issuance path). Any unexpected failure is a gap too — the
    # sidecar is best-effort local state, never a crash channel.
    try:
      let identity = measureSkReportIdentity(projectAbs, stateRoot, repoRoot,
                                             run.versionLine, laneClaim)
      if identity.gap.len == 0:
        report["identityBundleDigest"] = %identityBindingDigest(identity.doc)
        let payloadSha = sha256Hex(sortedCanonicalJson(report))
        var doc = identity.doc
        doc["binding"] = %*{"payloadSha256": %payloadSha}
        if laneClaim.rejection.rule.len > 0:
          doc{"binding"}["rejection"] = %*{
            "reasonLeaf": %axiomSkReportRejectionReasonLeaf,
            "rawPath": %laneClaim.rejection.rawPath,
          }
        createDir(workDir)
        writeFile(workDir / "skreport-identity.json",
                  sortedCanonicalJson(doc) & "\n")
      else:
        log.add("[AXIOM][rust-lane] §6c identity sidecar skipped: " & identity.gap)
    except Exception as e:
      if not report{"identityBundleDigest"}.isNil:
        report.delete("identityBundleDigest")
      log.add("[AXIOM][rust-lane] §6c identity sidecar failed (gap): " & e.msg)
    let exitCode = axProofShortcutExitCode(report,
      requirePerfectAsi = getAxiomEnv(evRequirePerfectAsi) == "1")
    # The report document's durable observable: the SAME trajectory sink the
    # engine's report stage writes (logStage(skReport, extra) →
    # <state>/logs/ax_prove_trajectory.jsonl, state-root routed). The stdout
    # channel is the engine's own emitAxShortcutResult discipline (flag-gated
    # for prove) — the lane changes neither.
    logStage(skReport, "", "rust subject lane completed", extra = report)
    RustLaneCliReport(outputJson: renderJsonMultiline(report),
                      logLines: log, exitCode: exitCode)

  proc entryFor(name: string; status: string; reason: string): JsonNode {.
      raises: [].} =
    %*{"name": %name, "status": %status, "reason": %reason}

  if not run.ok:
    # PENDING family — every declared target unverified; NEVER a certificate,
    # NEVER success-by-default claims: the summary says so honestly.
    var entries = newJArray()
    var declCount = 0
    for entry in lockData{"rust_targets"}.elems:
      entries.add(entryFor(entry{"symbol"}.getStr(), "unknown",
        "pinned charon extraction unavailable (" & $run.error & "): " & run.reason))
      inc declCount
    report["targets"] = entries
    report["summary"] = %*{
      "verified": %0, "failedCount": %0, "timeoutCount": %0,
      "verifiedRatio": %0.0,
      "statusCounts": %*{"verified": %0, "failed": %0, "unknown": %declCount, "error": %0}
    }
    log.add("[AXIOM][rust-lane] extraction failed: " & run.reason)
    return ok(finish(report))

  # ④ Read the produced LLBC and enumerate the extractable declarations.
  var llbcText = ""
  var llbcRoot: JsonNode = nil
  try:
    llbcText = readFile(run.llbcPath)
    llbcRoot = parseJson(llbcText)
  except CatchableError as e:
    var entries = newJArray()
    var declCount = 0
    for entry in lockData{"rust_targets"}.elems:
      entries.add(entryFor(entry{"symbol"}.getStr(), "error",
        "produced LLBC unreadable after a successful extraction (fail-closed): " & e.msg))
      inc declCount
    report["targets"] = entries
    report["summary"] = %*{
      "verified": %0, "failedCount": %0, "timeoutCount": %0,
      "verifiedRatio": %0.0, "blockingFailure": %true,
      "statusCounts": %*{"verified": %0, "failed": %0, "unknown": %0, "error": %declCount}
    }
    return ok(finish(report))
  let declNames = llbcFunDeclNamePaths(llbcRoot)
  let llbcPath = run.llbcPath
  # The rustc dep-info is the authoritative input set for the Phase 1-A
  # contract (the exact-set mode is structurally impossible for real crates:
  # cfg-excluded files never reach the LLBC). Absent → the contract fails
  # closed with the dep-info reason, never a widened pass.
  let crateName = llbcRoot{"translated"}{"crate_name"}.getStr()
  let depInfoPath = findDepInfo(workDir, crateName)
  log.add("[AXIOM][rust-lane] dep-info " &
          (if depInfoPath.len > 0: depInfoPath
           else: "absent (legacy exact-set contract mode)"))

  # ⑤ The candidate set (--target filter; NotFound/Ambiguous refuse to run an
  # implicit verification — the canonicalTargetRefusal discipline).
  var candidates: seq[string] = @[]
  if target.len > 0:
    for d in declNames:
      if d.fullName == target or d.lastSegment == target:
        candidates.add(d.fullName)
    if candidates.len == 0:
      return err(CliError(kind: CliOutcome.INVALID_INPUT, msg:
        "[AXIOM] --target " & target & " resolved to no extraction targets " &
        "(NotFound or Ambiguous). The rust lane requires exactly one match; " &
        "0 matches = NotFound, >1 = Ambiguous. Refusing an implicit " &
        "verification run on an unresolved target."))
    if candidates.len > 1:
      return err(CliError(kind: CliOutcome.INVALID_INPUT, msg:
        "[AXIOM] --target " & target & " resolved to more than one extraction " &
        "target (Ambiguous): " & candidates.join(", ") &
        ". The rust lane requires exactly one match."))
  else:
    for d in declNames:
      candidates.add(d.fullName)

  # ⑤b §6c v2 — measure the production-time claim identity of the SINGLE
  # certified-scope target from the objects the run consumes (scope-lock
  # entry, spec sidecar via the SAME specEntryFor, module via the SAME walk
  # as the declared issuance path). Runs before classification, so the
  # d1/d2-shape refusal path carries the claim binding too. All-or-nothing:
  # any gap keeps laneClaim unmeasured and NO sidecar is produced.
  block measureClaim:
    if candidates.len != 1:
      laneClaim.gapReason = "candidate count is " & $candidates.len &
        " — the §6c certified scope is exactly one target"
      break measureClaim
    let name = candidates[0]
    if not declared.hasKey(name):
      laneClaim.gapReason = "target '" & name &
        "' is not declared in vks_rust (no spec identity to bind)"
      break measureClaim
    let lockEntry = declared[name]
    let specRefTxt = lockEntry{"specRef"}.getStr()
    if specRefTxt.len == 0:
      laneClaim.gapReason = "scope-lock entry has an empty specRef"
      break measureClaim
    let specRes = specEntryFor(specRefTxt, name, projectAbs, repoRoot)
    if specRes.isErr:
      laneClaim.gapReason = "spec sidecar unmeasurable: " & specRes.error
      break measureClaim
    let postTxt = specRes.get(){"post"}.getStr()
    if postTxt.len == 0:
      laneClaim.gapReason = "spec entry has an empty 'post'"
      break measureClaim
    let moduleAbs = resolveLaneModule(lockEntry{"module"}.getStr(),
                                      projectAbs, repoRoot)
    if moduleAbs.len == 0:
      laneClaim.gapReason = "subject module not found (fail-closed): declared '" &
        lockEntry{"module"}.getStr() & "'"
      break measureClaim
    laneClaim = LaneClaimIdentity(measured: true, symbol: name,
      specRef: specRefTxt, postSha256: sha256Hex(postTxt),
      moduleAbs: moduleAbs)

  # ⑥ Per-target classification + issuance (the EXISTING chain).
  # The provenance transport arms ONLY on a present GITHUB_TOKEN — without it
  # issuance blocks at the provenance stage, which IS the honest fail-closed
  # path and is surfaced verbatim (PENDING), never bypassed. The transport is
  # constructed against EvidenceCasRefName: the extraction record lands on the
  # EvidenceCas side ref, and a live transport must never read another ref's
  # tip (the liveLedgerTransport refName contract — the certificates default
  # would make every append a non-fast-forward 422).
  let ledgerToken = getEnv("GITHUB_TOKEN", "")
  var extractionLedger = none(LedgerTransport)
  if ledgerToken.len > 0:
    extractionLedger = some(liveLedgerTransport(ledgerToken, EvidenceCasRefName))
  let ledgerRepo = laneLedgerRepo()
  log.add("[AXIOM][rust-lane] ledger transport " &
          (if ledgerToken.len > 0: "armed (live)" else: "absent — provenance will fail closed") &
          "; repo=" & ledgerRepo)

  var entries = newJArray()
  var verified = 0
  var failed = 0
  var errorCount = 0
  var unknownCount = 0

  for name in candidates:
    # The candidate IS the producer's structured match key (the enumeration
    # SSOT) — the run binds exactly the SELECTED decl, never its bare last
    # segment re-derived here (the DEBT#510 first-match re-binding is gone).
    let outcome = rustSubjectOutcome(llbcText, name, rcheckExe = "",
                                     projectRoot = repoRoot,
                                     timeoutMs = 60_000,
                                     subjectRoot = projectAbs,
                                     depInfoPath = depInfoPath)
    if candidates.len == 1:
      laneClaim.embedded = outcome.embeddedFiles
    if outcomeOutOfScopeUnknown(outcome):
      entries.add(entryFor(name, "unknown",
        "out-of-subset grammar (fail-closed): " & outcome.agreement.reason))
      inc unknownCount
      continue
    if outcome.agreement.verdict != eaAgree:
      # Fail-closed BEFORE the obligation stage: this is mechanically the
      # block the issuance chain records (producer/extraction stage + the
      # agreement's own reason) — surfaced without a duplicated differential.
      # The §6c v2 rejection binding records the validator's own structured
      # facts (when this IS the files-table refusal) together with the EXACT
      # reason string the entry carries — skeleton material for the sidecar,
      # never a reason rewrite.
      let stage = if outcome.producer.ok: "extraction" else: "producer"
      let reasonTxt = stage & ": " & outcome.agreement.reason
      entries.add(entryFor(name, "unknown", reasonTxt))
      if candidates.len == 1:
        laneClaim.rejection = outcome.rejection
        laneClaim.leafReason = reasonTxt
      inc unknownCount
      continue
    if not declared.hasKey(name):
      # Undeclared + extraction-sound: the declaration-free guard attempt.
      # Still "unknown" — a guard discharge is non-claiming by contract (no
      # spec, no certificate, no KAA); the reason text is the aggregated
      # per-goal classification, and the raw Z3 model text stays on the log
      # lines only. The subject's crate module (src/lib.rs, when present) is
      # bound so a replayed OVERFLOW panic can CONFIRM a declined+SAT goal —
      # the confirmation refines the reason text only; the model literals,
      # panic report and replay toolchain below stay LOG-CHANNEL ONLY.
      var guardModulePath = ""
      let guardModuleCandidate = projectAbs / "src" / "lib.rs"
      if fileExists(guardModuleCandidate):
        guardModulePath = guardModuleCandidate
      let rec = rustGuardObligationAttempt(llbcText, name,
                                           projectRoot = repoRoot,
                                           timeoutMs = 60_000,
                                           subjectRoot = projectAbs,
                                           subjectModulePath = guardModulePath)
      entries.add(entryFor(name, "unknown", rec.reason))
      inc unknownCount
      for i, g in rec.goalOutcomes:
        log.add("[AXIOM][rust-lane] guard " & name & " goal[" & $i & "/" &
                $rec.goalCount & "] proved=" & $g.proved &
                " declinedByKernel=" & $g.declinedByKernel &
                " z3Sat=" & $g.z3Sat & " scriptDigest=" & g.z3ScriptDigest &
                " modelRaw=<<<" & g.z3ModelRaw & ">>>" &
                " confirmed=" & $g.confirmed &
                " replayInputs=<<<" & g.replayInputs & ">>>" &
                " panicEvidence=<<<" & g.panicEvidence & ">>>" &
                " admissionNote=<<<" & g.admissionNote & ">>>" &
                " replayToolchain=" & g.replayToolchain &
                " extraction=" & pinnedCharonIdentity())
      continue

    # Declared + extraction agreed: the closed spec parse, then issuance.
    var specEnv: seq[SpecTypeEnvEntry] = @[]
    for p in outcome.producer.canonical.params:
      specEnv.add((name: p.name, ty: p.ty))
    let specRes = specEntryFor(declared[name]{"specRef"}.getStr(), name,
                               projectAbs, repoRoot)
    if specRes.isErr:
      entries.add(entryFor(name, "error", specRes.error))
      inc errorCount
      continue
    let postText = specRes.get(){"post"}.getStr()
    let parsed = parseClosedSpecPost(postText, specEnv,
                                     outcome.producer.canonical.retType)
    if not parsed.ok:
      entries.add(entryFor(name, "error",
        "spec 'post' decode failed (fail-closed): " & parsed.reason))
      inc errorCount
      continue

    # Module path: the declaration's own scope-lock module entry, resolved
    # via the same walk the §6c v2 claim measurement reuses; the subject's
    # src/lib.rs is the fallback (the crate's only module).
    let lockModule = declared[name]{"module"}.getStr()
    let modulePath = resolveLaneModule(lockModule, projectAbs, repoRoot)
    if modulePath.len == 0:
      entries.add(entryFor(name, "error",
        "subject module not found (fail-closed): declared '" & lockModule & "'"))
      inc errorCount
      continue
    var sourceCode = ""
    try:
      sourceCode = readFile(modulePath)
    except CatchableError as e:
      entries.add(entryFor(name, "error",
        "subject module unreadable (fail-closed): " & modulePath & ": " & e.msg))
      inc errorCount
      continue

    let rec = rustSubjectIssuance(
      llbcText, name, parsed.expr,
      certDir = vaultDir,
      modulePath = modulePath,
      sourceCode = sourceCode,
      projectRoot = repoRoot,
      timeoutMs = 60_000,
      subjectRoot = projectAbs,
      depInfoPath = depInfoPath,
      llbcPath = llbcPath,
      extractionLedger = extractionLedger,
      extractionLedgerRepo = ledgerRepo)
    if rec.issued:
      var entry = entryFor(name, "verified", "")
      entry["certPath"] = %rec.certPath
      entry["irHash"] = %rec.irHash
      entries.add(entry)
      inc verified
      log.add("[AXIOM][rust-lane] verified: " & name & " → " & rec.certPath)
      continue
    let (status, reason) = classifyIssuanceBlock(rec)
    var entry = entryFor(name, status, reason)
    entry["blockStage"] = %rec.blockStage
    entries.add(entry)
    if status == "failed":
      inc failed
    elif status == "error":
      inc errorCount
    else:
      inc unknownCount
    log.add("[AXIOM][rust-lane] " & name & " → " & status &
            " (stage=" & rec.blockStage & "): " & reason)

  # ⑦ The report + the pinned exit projection.
  let total = candidates.len
  let ratio = toFloat(getKernelRatioOr(initKernelRatio(verified, total), defaultKernelRatio()))
  report["targets"] = entries
  var summary = %*{
    "verified": %verified,
    "failedCount": %failed,
    "timeoutCount": %0,
    "verifiedRatio": %ratio,
    "statusCounts": %*{
      "verified": %verified, "failed": %failed,
      "unknown": %unknownCount, "error": %errorCount
    }
  }
  if errorCount > 0:
    summary["blockingFailure"] = %true
  report["summary"] = summary
  log.add("[AXIOM][rust-lane] done: verified=" & $verified & "/" & $total &
          " failed=" & $failed & " unknown=" & $unknownCount & " error=" & $errorCount)
  ok(finish(report))

{.pop.}
