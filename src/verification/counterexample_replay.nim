import core/trusted/layer_declaration
axiomLayer "infrastructure"
# axiomIoBoundary — S5 counterexample replay executes real subprocess I/O
# (`nim c -r` harness, read-only git queries, file hashing). Registered in
# src/gate/nimtry/io_module_registry.nim (ioModules) — §0.6 permits proc at
# the I/O boundary; every I/O proc carries an explicit axiomEffect pragma.
{.push raises: [].}
## Counterexample Replay Execution Adapter (PROPOSITION_DISPROVED milestone S4-S5).
##
## Authority = 0 (Authority ≠ Adapter): this module OBSERVES only. The
## promotion verdict stays exactly where it was — P4 `finalizeVerdict`
## (cvConfirmed → vsDisproved). The pipeline calls this adapter only after
## cvConfirmed; replay agreement completes the PROPOSITION_DISPROVED payload (glossary:
## docs/spec/bug_verdict_glossary.md §2.2 — exact commit · exact input ·
## violation statement · replay record), and any disagreement or
## unavailability is decided by the caller as fail-closed cvUnresolved.
##
## What the adapter does, end to end:
##   1. fold the replay record identity: subjectGitRef, treeMerkle,
##      moduleSha256 (+ post-run re-hash), worktree-stability predicate
##      (worktreeStable — subject inputs + repo status + tracked content,
##      RELATIVE pre/post equality, never a repo-wide clean requirement),
##      hostPlatformId,
##      and the GateEnvLock triple (nimVersion / nimHash / stdlibHash —
##      measured the same way precompile_gates.buildCurrentFingerprint does);
##   2. synthesize a harness wrapper under the AXIOM_STATE_DIR tmp tree that
##      imports the subject module via compile-time `--path:` flags only —
##      the subject tree is never written;
##   3. run `nim c -r` (the repo-pinned 2.2.10 toolchain) and capture the
##      observed output + exit code;
##   4. re-evaluate the violated postconditions concretely on the observed
##      result (`evalConcreteIr`) — `propertyHolds == false` is the replay
##      agreement (the real toolchain reproduces the violation).
##
## Failure semantics: every unverifiable step collapses to `rvUnavailable`;
## `pure` functions never raise. Nothing here writes into the CAS — a failed
## replay is not reusable evidence (evidence_cas.nim isReusableOutcome).
##
## Pipeline integration: `replayConfirmedDisproof` is the single entry the
## pipeline drives after a P4 promotion (see
## ir_pipeline_runner.runIrPipelineWithCas post-processing; the BMC lane is
## the only lane whose disproof models are concrete entry inputs — inductive
## CHC lane results carry provenance vpInductiveLoop and are excluded).
##
## Harness resolution contract (docs/spec/counterexample_replay_adapter.md §3,
## docs/spec/replay_harness_config_quirks.md Q5/Q6):
##   - the subject module is spliced with `include <module>` (not `import`) —
##     self-kernel collateral entries are mostly PRIVATE symbols that `import`
##     can never expose; `include` rides the same `--path:` search and never
##     writes the subject tree;
##   - the subject repo binding is discovered from the SUBJECT MODULE's git
##     toplevel, not from the caller's analysis root — an external `--project`
##     run proves self-kernel collateral whose modules live in the Axiom repo,
##     and the identity folds (subjectGitRef/treeMerkle), the
##     worktree-stability checks, and the compile `--path:` roots must all
##     describe THAT repo;
##   - plain-harness compiles (never the d2-agent stamped template) additionally
##     ride the subject repo's nimble `requires` roots and the Nim toolchain
##     root — the repo's config.nims path injections that a skipped-config
##     compile otherwise loses (Q5).

import std/[algorithm, options, os, osproc, strutils, tables, sets]

import core/trusted/axiom_pragmas
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/crypto/hash_kernel
import core/types/obligation_evidence
import core/trusted/ir_to_smt  # irExprToSmt — propertyViolated SMT projection
import core/utils/repo_root  # findRepoRoot — self-kernel module-path candidate
import verification/obligation/identity
import verification/obligation/canonical_verification  # SubjectParseBoundComponents (S6 composite replay shape)
import verification/symbolic_test_synth  # bindingToNimLiteral / z3BvHexToI64 / modelToTestInputs

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  ReplayVerdict* = enum
    rvAgree         ## harness ran; property concretely violated (violation reproduced)
    rvDisagree      ## harness ran; property actually holds — solver model contradicted
    rvUnavailable   ## harness / git / property evaluation could not be established

  ReplayConfig* = object
    subjectRepoRoot*: string    ## git root of the subject ("" → discovered via git)
    subjectModulePath*: string  ## absolute path of the subject module file
    funcName*: string
    paramNames*: seq[string]    ## subject parameter names, positional order
    inputLiterals*: seq[string] ## Nim source literals, positional (model → modelToTestInputs)
    postconditions*: seq[IRExpr]## the violated property conjuncts (concretely re-evaluated)
    callExpr*: string = ""      ## S6: non-empty → the harness echoes `$<callExpr>`
                                ## instead of `$funcName(args)`. Used by the
                                ## β-composite replay, whose composite name never
                                ## exists in the subject module — the echoed
                                ## expression composes the two ORIGINAL subject
                                ## symbols (element 4: the real subject code path).
    harnessSource*: string = "" ## d2-agent binding: non-empty → this IS the
                                ## harness source (the stamped template with the
                                ## model value rendered); the plain
                                ## renderReplayHarness wrapper is skipped. The
                                ## template imports the subject's public API
                                ## module and observes the ORIGINAL decoder.
    depSearchPaths*: seq[string] ## d2-agent binding only: explicit `--path:`
                                 ## entries for the subject's nimble dependency
                                 ## package roots (appended AFTER the subject
                                 ## paths — the subject tree keeps priority).
                                 ## Resolved per replay by
                                 ## resolveD2AgentDepSearchPaths (nimble store
                                 ## discovery, AXIOM_REPLAY_DEP_PATHS override).
                                 ## Every other replay path leaves this empty —
                                 ## zero-diff for C_out/base36/base32 and
                                 ## self-kernel collateral harnesses.

  CompositeReplayShape* = object
    ## S6: how a synthesized β-composite maps onto REAL subject symbols for
    ## replay. Built by the caller from the §2.1a composite parse-bound
    ## components (outer/inner originals + measured typedesc carrier) and the
    ## funcDef's value parameter. Empty carrier/name → not replayable as a
    ## composite (the adapter fails closed, never guesses a token).
    outerSymbol*: string = ""
    innerSymbol*: string = ""
    carrierTypename*: string = ""
    valueParam*: string = ""

  ReplayRecord* = object
    verdict*: ReplayVerdict
    exitCode*: int              ## harness `nim c -r` exit code
    observedOutput*: string     ## verbatim harness stdout/stderr (trimmed)
    harnessDir*: string
    ## GateEnvLock triple — measured exactly as precompile_gates.buildCurrentFingerprint
    nimVersion*: string
    nimHash*: string
    stdlibHash*: string
    hostPlatform*: string       ## identity.hostPlatformId fold
    subjectGitRef*: string      ## exact subject commit (PROPOSITION_DISPROVED element 1)
    subjectTreeMerkle*: string  ## git tree OID of the subject commit
    moduleSha256*: string       ## sha256 of subject module bytes before the run
    moduleSha256AfterRun*: string  ## re-hash after the run — drift detection
    worktreeStable*: bool       ## worktree state unchanged across the run
                                ## (subject inputs + repo status + repo
                                ## tracked content — RELATIVE pre/post
                                ## equality, predicate v2; pre-existing
                                ## noise is on both sides and cannot break
                                ## the seal)
    subjectInputsPre*: string   ## (b) subject-inputs digest sha256, pre-run
    subjectInputsPost*: string  ## (b) subject-inputs digest sha256, post-run
    repoFootprintPre*: string   ## (c)+(d) combined repo-footprint sha256, pre-run
    repoFootprintPost*: string  ## (c)+(d) combined repo-footprint sha256, post-run
    diagnostics*: string        ## first failure reason ("" when verdict == rvAgree)

  ConcreteValueKind* = enum
    ckInt
    ckBool

  ConcreteValue* = object
    case kind*: ConcreteValueKind
    of ckInt: i*: int64
    of ckBool: b*: bool

const ReplayBeginMarker* = "AXIOM_REPLAY_BEGIN"
const ReplayEndMarker* = "AXIOM_REPLAY_END"

const ReplayModulePlaceholder* = "<module>"
  ## The d2-agent harness template's import slot — fixed by the overlay's
  ## subject pin at synthesis time (the engine stamps the template).

const ReplayValuePlaceholder* = "<lit>"
  ## The d2-agent harness template's model-value slot — the replay renders the
  ## exact solver-model byte literal here (contract §replay: the observation
  ## is the ORIGINAL decoder's reject decision on a document embedding
  ## chr(<lit>)).

const D2AgentSubjectDepPackages*: seq[string] = @["serialization",
    "faststreams", "stew", "results"]
  ## The arnetheduck/status-im dependency stack the d2-agent subject
  ## (nim-toml-serialization @ 4aa8e22; its nimble declares faststreams >=
  ## 0.5.0, serialization >= 0.5.3, stew) resolves at replay-compile time.
  ## DESIGN (docs/spec/replay_harness_config_quirks.md Q4): the package roots
  ## are resolved AT RUNTIME from the local nimble store — no committed
  ## absolute paths; newest version wins; fail-closed when a named package is
  ## absent. `AXIOM_REPLAY_DEP_PATHS` overrides the discovery wholesale.

const ReplayDepPathsEnvVar* = "AXIOM_REPLAY_DEP_PATHS"
  ## Explicit dep-root override for the d2-agent replay (design (b)): ':'
  ## -separated package roots used verbatim as `--path:` entries when set —
  ## no store discovery, each entry must be an existing directory.

# ---------------------------------------------------------------------------
# d2-agent subject dep resolution (pure scanning/selection)
# ---------------------------------------------------------------------------

func depImportTokenSplits(c: char): bool {.raises: [].} =
  c in {' ', '\t', ',', '[', ']', '(', ')', ';', '#'}

func importStatementTokens*(source: string): seq[string] {.raises: [].} =
  ## Tokens of every import/from/export statement line, multi-line lists
  ## included (`import` alone or a trailing ',' continues the list —
  ## nim-toml-serialization reader.nim imports exactly this way). Comments
  ## ('#') are cut, so prose mentioning package names never matches. This is
  ## the static discriminator between a stamped subject whose import closure
  ## needs external dep roots and a self-contained one (unit-test fixtures,
  ## collateral harnesses) that must stay zero-diff.
  result = @[]
  var inList = false
  for raw in source.splitLines():
    var t = raw.strip()
    if t.len == 0:
      continue
    let hashIdx = t.find('#')
    if hashIdx >= 0:
      t = t[0 ..< hashIdx].strip()
      if t.len == 0:
        continue
    if inList or t.startsWith("import ") or t.startsWith("from ") or
        t.startsWith("export "):
      var tok = ""
      for c in t & " ":
        if depImportTokenSplits(c):
          if tok.len > 0:
            result.add(tok)
            tok = ""
        else:
          tok.add(c)
      inList = t.endsWith(",")
    elif t == "import" or t == "from" or t == "export":
      inList = true  # bare keyword — the token list continues on the next lines

func tokenNamesPackage*(tok, name: string): bool {.raises: [].} =
  ## `stew` / `stew/enums` / `stew/[enums, objects]` — the token begins with
  ## the package name at a token boundary (splitting already guarantees the
  ## left boundary; `toml_serialization/lexer` can never match
  ## `serialization/`).
  tok == name or tok.startsWith(name & "/")

func sourceNamesDepPackages*(source: string): bool {.raises: [].} =
  ## True when any import/from/export statement names one of
  ## D2AgentSubjectDepPackages.
  let toks = importStatementTokens(source)
  for name in D2AgentSubjectDepPackages:
    for tok in toks:
      if tokenNamesPackage(tok, name):
        return true
  false

func parseNimblePkgDirName*(dirName: string): Option[(string, string)] {.
    raises: [].} =
  ## `<name>-<version>[-<hash>]` — the nimble store layout (pkgs2/pkgs). The
  ## name is everything before the first '-' followed by a digit; the version
  ## ends at the next '-' (the content hash is excluded). Name-anchored, so
  ## `json_serialization-0.2.9-…` parses as name `json_serialization` and
  ## never collides with `serialization`.
  for i in 1 ..< dirName.len:
    if dirName[i] == '-' and i + 1 < dirName.len and dirName[i + 1] in
        {'0'..'9'}:
      let rest = dirName[i + 1 .. ^1]
      var version = rest
      let dash = rest.find('-')
      if dash >= 0:
        version = rest[0 ..< dash]
      return some((dirName[0 ..< i], version))
  none((string, string))

func versionRank*(version: string): Option[int64] {.raises: [].} =
  ## Deterministic ordering rank: the digit groups concatenated and read as
  ## one number ("0.5.4" → 054, "051" → 51 — the pkgcache flattened form
  ## compares equal to its dotted form). No digits → none (sorts lowest).
  var acc: int64 = 0
  var anyDigit = false
  for c in version:
    if c in {'0'..'9'}:
      anyDigit = true
      acc = acc * 10 + (ord(c) - ord('0'))
  if anyDigit:
    some(acc)
  else:
    none(int64)

func pkgcacheDirNamesPackage*(dirName, name: string): bool {.raises: [].} =
  ## pkgcache layout `githubcom_<vendor><repo>_<ver>[_<hash>]` — the package
  ## name appears as `nim<name>` inside the flattened vendor/repo slug
  ## (`githubcom_statusimnimstew_020` → stew). Requiring the `nim` marker
  ## keeps `githubcom_statusimnimjsonserialization_029` from matching
  ## `serialization`.
  let marker = "nim" & name
  var idx = dirName.find(marker)
  while idx >= 0:
    let after = idx + marker.len
    if after >= dirName.len or dirName[after] == '_':
      return true
    idx = dirName.find(marker, after)
  false

func pkgcacheVersionAfter*(dirName, name: string): string {.raises: [].} =
  ## The flattened version token following the matched `nim<name>` marker
  ## (`…nimstew_020_79e4…` → "020"); "" when absent.
  let marker = "nim" & name
  let idx = dirName.find(marker)
  if idx < 0:
    return ""
  let after = idx + marker.len
  if after < dirName.len and dirName[after] == '_':
    var endIdx = dirName.find('_', after + 1)
    if endIdx < 0:
      endIdx = dirName.len
    return dirName[after + 1 ..< endIdx]
  ""

func newestPkgDir*(candidates: seq[(string, string, string)]): Option[string] {.
    raises: [].} =
  ## Newest-wins selection over (dirPath, dirName, version) candidates: max
  ## by (versionRank, dirName) — dirName is the deterministic tie-break when
  ## two checkouts share a version. Empty input → none.
  if candidates.len == 0:
    return none(string)
  var bestPath = ""
  var bestRank = none(int64)
  var bestName = ""
  for (path, dirName, version) in candidates:
    let rank = versionRank(version)
    let better = if bestPath.len == 0: true
                 elif rank.isNone: false
                 elif bestRank.isNone: true
                 else: rank.get > bestRank.get or
                       (rank.get == bestRank.get and dirName > bestName)
    if better:
      bestPath = path
      bestRank = rank
      bestName = dirName
  some(bestPath)

# ---------------------------------------------------------------------------
# Concrete property evaluation (pure — fail-closed to none(...))
# ---------------------------------------------------------------------------

func evalConcreteBinOp*(op: BinOpKind; lv, rv: ConcreteValue): Option[ConcreteValue] {.raises: [].} =
  ## bv64 binop semantics over concrete values — bit-exact wraparound; div/rem
  ## are guarded (zero divisor → none: fail closed, never guess).
  case op
  of boAdd:
    if lv.kind == ckInt: some(ConcreteValue(kind: ckInt, i: lv.i +% rv.i)) else: none(ConcreteValue)
  of boSub:
    if lv.kind == ckInt: some(ConcreteValue(kind: ckInt, i: lv.i -% rv.i)) else: none(ConcreteValue)
  of boMul:
    if lv.kind == ckInt: some(ConcreteValue(kind: ckInt, i: lv.i *% rv.i)) else: none(ConcreteValue)
  of boDiv:
    if lv.kind == ckInt and rv.i != 0: some(ConcreteValue(kind: ckInt, i: lv.i div rv.i)) else: none(ConcreteValue)
  of boRem:
    if lv.kind == ckInt and rv.i != 0: some(ConcreteValue(kind: ckInt, i: lv.i mod rv.i)) else: none(ConcreteValue)
  of boRemU:
    if lv.kind == ckInt and rv.i != 0:
      let u = cast[uint64](lv.i) mod cast[uint64](rv.i)
      some(ConcreteValue(kind: ckInt, i: cast[int64](u)))
    else:
      none(ConcreteValue)
  of boLt:
    if lv.kind == ckInt: some(ConcreteValue(kind: ckBool, b: lv.i < rv.i)) else: none(ConcreteValue)
  of boLtU:
    if lv.kind == ckInt:
      let lu = cast[uint64](lv.i)
      let ru = cast[uint64](rv.i)
      some(ConcreteValue(kind: ckBool, b: lu < ru))
    else:
      none(ConcreteValue)
  of boLe:
    if lv.kind == ckInt: some(ConcreteValue(kind: ckBool, b: lv.i <= rv.i)) else: none(ConcreteValue)
  of boGt:
    if lv.kind == ckInt: some(ConcreteValue(kind: ckBool, b: lv.i > rv.i)) else: none(ConcreteValue)
  of boGe:
    if lv.kind == ckInt: some(ConcreteValue(kind: ckBool, b: lv.i >= rv.i)) else: none(ConcreteValue)
  of boEq:
    if lv.kind == rv.kind:
      let eq = if lv.kind == ckInt: lv.i == rv.i else: lv.b == rv.b
      some(ConcreteValue(kind: ckBool, b: eq))
    else:
      # v1.4 Bool 0/1 embed: bool and int share ONE bv64 value domain (the
      # same domain the SMT lowering compares), so a bool equals an int
      # exactly when the int is its 0/1 bit pattern. Any other int is not a
      # bool encoding — fail closed.
      var b: bool
      var i: int64
      if lv.kind == ckBool:
        b = lv.b
        i = rv.i
      else:
        b = rv.b
        i = lv.i
      if i == 0 or i == 1:
        some(ConcreteValue(kind: ckBool, b: b == (i == 1)))
      else:
        none(ConcreteValue)
  of boAnd:
    if lv.kind == ckBool and rv.kind == ckBool:
      some(ConcreteValue(kind: ckBool, b: lv.b and rv.b))
    else:
      none(ConcreteValue)
  of boOr:
    if lv.kind == ckBool and rv.kind == ckBool:
      some(ConcreteValue(kind: ckBool, b: lv.b or rv.b))
    else:
      none(ConcreteValue)
  of boShl, boShr, boUnsupported:
    none(ConcreteValue)  # shifts are unsupported in SemanticProfileV1 — fail closed

func evalConcreteUnaryOp*(op: UnaryOpKind; av: ConcreteValue): Option[ConcreteValue] {.raises: [].} =
  ## bv64 unary semantics over a concrete value.
  case op
  of uoNot:
    if av.kind == ckBool: some(ConcreteValue(kind: ckBool, b: not av.b)) else: none(ConcreteValue)
  of uoBvNot:
    if av.kind == ckInt: some(ConcreteValue(kind: ckInt, i: not av.i)) else: none(ConcreteValue)
  of uoBvNeg:
    if av.kind == ckInt: some(ConcreteValue(kind: ckInt, i: 0'i64 -% av.i)) else: none(ConcreteValue)

func evalConcreteIr*(e: IRExpr; env: Table[string, ConcreteValue];
                     u64Ctx: bool = false): Option[ConcreteValue] {.raises: [].} =
  ## Evaluate an IRExpr over concrete bv64 values. Supports the certified
  ## subset (literals, vars, let, if, casts, bv arithmetic/comparison/logic).
  ## Anything outside the subset — calls, loops, shifts, floats, strings —
  ## evaluates to none(...): the caller must fail closed, never guess.
  ## `u64Ctx` mirrors irExprToSmt's width-64 lowering context: comparisons
  ## inside a subtree carrying a u64-domain literal compare as UNSIGNED
  ## bit patterns (bvult/bvule — the concrete replay must agree with the
  ## SMT lowering it replays, not with the signed policy).
  if e == nil:
    return none(ConcreteValue)
  case e.kind
  of irLit:
    # Two-part literal form: nonzero `litU64` ⟺ u64-domain active — the
    # exact bit pattern enters the env (int64 holds patterns, not meanings).
    some(ConcreteValue(kind: ckInt,
         i: if e.litU64 != 0'u64: cast[int64](e.litU64) else: e.litVal))
  of irVar:
    if env.hasKey(e.varName):
      let v = env.getOrDefault(e.varName)
      some(v)
    else:
      none(ConcreteValue)
  of irLet:
    var inner = env
    let v = evalConcreteIr(e.letVal, env, u64Ctx)
    if v.isNone:
      return none(ConcreteValue)
    inner[e.letName] = v.get
    evalConcreteIr(e.letBody, inner, u64Ctx)
  of irIf:
    let c = evalConcreteIr(e.ifCond, env, u64Ctx)
    if c.isNone or c.get.kind != ckBool:
      return none(ConcreteValue)
    if c.get.b:
      evalConcreteIr(e.ifThen, env, u64Ctx)
    else:
      evalConcreteIr(e.ifElse, env, u64Ctx)
  of irCast:
    evalConcreteIr(e.castExpr, env, u64Ctx)
  of irBinOp:
    let childCtx = u64Ctx or containsU64Lit(e)
    let l = evalConcreteIr(e.binLhs, env, childCtx)
    let r = evalConcreteIr(e.binRhs, env, childCtx)
    if l.isNone or r.isNone:
      return none(ConcreteValue)
    if e.binOp == boLtU:
      # Operator-resident unsigned order — NO containsU64Lit heuristic (the
      # legacy channel stays boLt-only); the replay must agree with the
      # bvult SMT lowering for boLtU unconditionally.
      if l.get.kind == ckInt and r.get.kind == ckInt:
        let lu = cast[uint64](l.get.i)
        let ru = cast[uint64](r.get.i)
        return some(ConcreteValue(kind: ckBool, b: lu < ru))
      return none(ConcreteValue)
    if childCtx and e.binOp in {boLt, boLe, boGt, boGe}:
      let lu = cast[uint64](l.get.i)
      let ru = cast[uint64](r.get.i)
      let b = case e.binOp
              of boLt: lu < ru
              of boLe: lu <= ru
              of boGt: lu > ru
              of boGe: lu >= ru
              else: false
      return some(ConcreteValue(kind: ckBool, b: b))
    evalConcreteBinOp(e.binOp, l.get, r.get)
  of irUnaryOp:
    let a = evalConcreteIr(e.unaryArg, env)
    if a.isNone:
      return none(ConcreteValue)
    evalConcreteUnaryOp(e.unaryOp, a.get)
  of irCall, irRecCall, irLoop, irCase, irStringLit, irFloatLit:
    none(ConcreteValue)  # outside the concrete-evaluable subset

func evaluatePostconditions*(posts: seq[IRExpr]; env: Table[string, ConcreteValue]): Option[bool] {.raises: [].} =
  ## Conjunction of all postcondition conjuncts over the concrete env.
  ## none(...) when any conjunct is not concretely evaluable (fail-closed).
  if posts.len == 0:
    return none(bool)
  for pc in posts:
    let v = evalConcreteIr(pc, env)
    if v.isNone or v.get.kind != ckBool:
      return none(bool)
    if not v.get.b:
      return some(false)
  some(true)

func parseConcreteLiteral*(lit: string): Option[ConcreteValue] {.raises: [].} =
  ## Parse a Nim source literal produced by bindingToNimLiteral/modelToTestInputs
  ## ("42", "-7", "18446744073709551615", "true", "false") into a ConcreteValue.
  ## Decimal magnitudes accumulate over the FULL unsigned domain: a value in
  ## [2^63, 2^64−1] stores its exact bit pattern (never a truncated signed
  ## reinterpretation); ≥ 2^64 is outside the representable domain — fail
  ## closed to none.
  let t = lit.strip()
  if t == "true":
    return some(ConcreteValue(kind: ckBool, b: true))
  if t == "false":
    return some(ConcreteValue(kind: ckBool, b: false))
  if t.len == 0:
    return none(ConcreteValue)
  var digits = t
  var neg = false
  if digits[0] == '-':
    neg = true
    digits = digits[1 .. ^1]
  if digits.len == 0 or digits.len > 20 or not digits.allCharsInSet({'0'..'9'}):
    return none(ConcreteValue)
  var acc: uint64 = 0
  for ch in digits:
    let d = uint64(ch.ord - '0'.ord)
    if acc > (uint64.high - d) div 10:
      return none(ConcreteValue)  # magnitude ≥ 2^64 — unrepresentable
    acc = acc * 10 + d
  if neg:
    if acc > uint64(int64.high) + 1:
      return none(ConcreteValue)
    if acc == uint64(int64.high) + 1:
      return some(ConcreteValue(kind: ckInt, i: int64.low))
    return some(ConcreteValue(kind: ckInt, i: -cast[int64](acc)))
  some(ConcreteValue(kind: ckInt, i: cast[int64](acc)))

func decideReplayVerdict*(harnessRan: bool; propertyHolds: Option[bool]): ReplayVerdict {.raises: [].} =
  ## Agreement = the pinned real toolchain reproduced the violation:
  ## property evaluated on the OBSERVED result and found false.
  ## true (holds) → the solver model is contradicted → rvDisagree.
  ## Anything unevaluable → rvUnavailable. Callers treat every non-Agree
  ## outcome as cvUnresolved fail-closed (promotion authority unchanged).
  if not harnessRan:
    return rvUnavailable
  if propertyHolds.isNone:
    return rvUnavailable
  if propertyHolds.get:
    rvDisagree
  else:
    rvAgree

func extractObservedResult(output: string): Option[string] {.raises: [].} =
  ## Value echoed between the harness markers ("" marker lines excluded).
  let lines = output.splitLines()
  var inBlock = false
  for line in lines:
    let t = line.strip()
    if t == ReplayBeginMarker:
      inBlock = true
      continue
    if t == ReplayEndMarker:
      if inBlock:
        return none(string)  # no value line between markers
      continue
    if inBlock and t.len > 0:
      return some(t)
  none(string)

# ---------------------------------------------------------------------------
# PROPOSITION_DISPROVED payload projection (pure)
# ---------------------------------------------------------------------------

func counterexampleBindingsPayload*(bindings: seq[ModelBinding]): seq[string] {.raises: [].} =
  ## Exact solver assignment as certificate strings: "name=value" with the
  ## BitVec64 hex rendered as decimal (z3BvHexToI64) — deterministic order is
  ## the parser's emission order.
  result = @[]
  for b in bindings:
    var value = b.value
    if b.value.len >= 18 and b.value[0] == '#' and b.value[1] == 'x':
      value = $z3BvHexToI64(b.value)
    result.add(b.name & "=" & value)

func inputLiteralsPayload*(paramNames: seq[string]; literals: seq[string]): seq[string] {.raises: [].} =
  ## "input.<param>=<nimLiteral>" — the exact replay input (PROPOSITION_DISPROVED element 2).
  result = @[]
  let n = min(paramNames.len, literals.len)
  for i in 0 ..< n:
    result.add("input." & paramNames[i] & "=" & literals[i])

func replayRecordPayload*(record: ReplayRecord): seq[string] {.raises: [].} =
  ## Replay record folds (PROPOSITION_DISPROVED element 4): subject binding + GateEnvLock
  ## triple + hostPlatform + outcome. Signed wholesale with the certificate
  ## payload — no separate signature (Ed25519 signs the full cert JSON).
  result = @[]
  result.add("replay.verdict=" & $record.verdict)
  result.add("replay.exitCode=" & $record.exitCode)
  result.add("replay.subjectGitRef=" & record.subjectGitRef)
  result.add("replay.treeMerkle=" & record.subjectTreeMerkle)
  result.add("replay.moduleSha256=" & record.moduleSha256)
  result.add("replay.moduleSha256AfterRun=" & record.moduleSha256AfterRun)
  result.add("replay.worktreeStable=" & $record.worktreeStable)
  result.add("replay.subjectInputsPre=" & record.subjectInputsPre)
  result.add("replay.subjectInputsPost=" & record.subjectInputsPost)
  result.add("replay.repoFootprintPre=" & record.repoFootprintPre)
  result.add("replay.repoFootprintPost=" & record.repoFootprintPost)
  result.add("replay.nimVersion=" & record.nimVersion)
  result.add("replay.nimHash=" & record.nimHash)
  result.add("replay.stdlibHash=" & record.stdlibHash)
  result.add("replay.hostPlatform=" & record.hostPlatform)
  if record.diagnostics.len > 0:
    result.add("replay.diagnostics=" & record.diagnostics.replace('\n', ' '))

# ---------------------------------------------------------------------------
# Harness synthesis (pure string building)
# ---------------------------------------------------------------------------

func renderReplayHarness*(moduleName: string; funcName: string; inputLiterals: seq[string];
                          callExpr: string = ""): string {.raises: [].} =
  ## The wrapper body: splices the subject module (resolved via `--path:` flags,
  ## never written), calls the subject function with the exact model input,
  ## and echoes the observed result between markers the adapter parses.
  ## `include` (not `import`) is load-bearing: self-kernel collateral entries
  ## are mostly PRIVATE symbols (`func f(...)` without the `*` export marker)
  ## that `import` can never expose — the plain harness would fail to compile
  ## with "undeclared identifier" for every one of them (Q6). `include` rides
  ## the same module search paths and keeps the splice read-only. Relative
  ## imports inside the spliced file resolve against the SPLICED file's
  ## directory (verified against Nim 2.2.10 — replay_harness_config_quirks.md
  ## Q6), so `--path:<moduleDir>` anchors the subject's own import chain.
  ## `callExpr` (S6 β-composite replay) replaces the plain `funcName(args)`
  ## call when the claimed function is a synthesis over subject symbols that
  ## does not itself exist in the subject module.
  var args = ""
  for i, lit in inputLiterals:
    if i > 0:
      args.add(", ")
    args.add(lit)
  let echoed = if callExpr.len > 0: "$" & callExpr
               else: "$" & funcName & "(" & args & ")"
  "include " & moduleName & "\n" &
  "echo \"" & ReplayBeginMarker & "\"\n" &
  "echo " & echoed & "\n" &
  "echo \"" & ReplayEndMarker & "\"\n"

# ---------------------------------------------------------------------------
# Worktree-stability predicate v2 (pure assembly — unit-tested; DEBT#505
# dry-duplicate of the Rust adapter's same-named assembly — keep in tandem)
# ---------------------------------------------------------------------------

func subjectInputsDigestFrom*(entries: seq[tuple[relPath, fileSha: string]]): string {.
    raises: [].} =
  ## The (b) subject-inputs digest: "relPath:fileSha256\n" lines sorted by
  ## relPath and hashed WHOLE. Pure over the already-measured pairs — the
  ## I/O boundary runs `git ls-files --full-name --cached --others
  ## --exclude-standard` over the subject input root and hashes each file.
  ## An added entry, a removed entry, a renamed path (relPath moves) and a
  ## content-only change (fileSha moves) each move this digest — which is
  ## how a run-made overwrite of a pre-existing UNTRACKED file is detected
  ## even though the status line and the tracked diff never move.
  var ordered = entries
  ordered.sort(proc (a, b: tuple[relPath, fileSha: string]): int =
    if a.relPath < b.relPath: -1
    elif b.relPath < a.relPath: 1
    else: 0)
  var acc = ""
  for e in ordered:
    acc.add(e.relPath & ":" & e.fileSha & "\n")
  sha256Hex(acc)

func combineFootprintDigest*(statusSha, trackedDiffSha: string): string {.
    raises: [].} =
  ## The (c)+(d) repo-footprint fold: sha256 over the two component digests
  ## in FIXED order (status, tracked diff). The components are measured
  ## separately — `git status --porcelain --untracked-files=all` (the -uall
  ## fold is required: the default collapses untracked directories, hiding
  ## run-made files) and `git diff HEAD --no-color --no-renames
  ## --no-ext-diff` (tracked content) — so neither can mask the other.
  sha256Hex("status=" & statusSha & ";tracked=" & trackedDiffSha)

func worktreeStableFrom*(moduleShaPre, moduleShaPost, subjectInputsPre,
                         subjectInputsPost, repoFootprintPre,
                         repoFootprintPost: string): bool {.raises: [].} =
  ## Predicate v2 — the G2 condition "the subject tree is unchanged across
  ## the run" (replay_evidence_policy.md §4) as RELATIVE pre/post equality
  ## over (a) the subject module sha256, (b) the subject-inputs digest and
  ## (c)+(d) the combined repo footprint. Pre-existing worktree noise (a
  ## stale build stamp, untracked files) is present on BOTH sides of every
  ## comparison and can never break the seal; only drift the run itself
  ## made moves one side. This is a redefinition of what counts as drift,
  ## NOT a path exemption — nothing is ignored.
  moduleShaPre == moduleShaPost and
  subjectInputsPre == subjectInputsPost and
  repoFootprintPre == repoFootprintPost

# ---------------------------------------------------------------------------
# I/O boundary — measurements and subject binding
# ---------------------------------------------------------------------------

proc measuredFileSha256(path: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## sha256 of file bytes ("" when unreadable) — mirrors precompile_gates
  ## fileSha256 measurement semantics without importing the cli layer.
  try:
    if not fileExists(path):
      return ""
    sha256Hex(readFile(path))
  except CatchableError:
    ""

proc gitCapture(args: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Read-only git query output ("" on failure). Never mutates the subject.
  try:
    let (outp, code) = execCmdEx("git " & args, options = {poStdErrToStdOut, poUsePath})
    if code == 0:
      outp.strip()
    else:
      ""
  except CatchableError:
    ""

proc subjectRepoRootFor(modulePath: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Git worktree root containing the subject module ("" when not a repo).
  let dir = if dirExists(modulePath): modulePath else: modulePath.parentDir()
  gitCapture("-C \"" & dir & "\" rev-parse --show-toplevel")

proc measureSubjectInputsDigest(repoRoot, subjectInputRoot: string): string {.
    raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## (b): `git ls-files --full-name --cached --others --exclude-standard`
  ## over the subject input root (read-only), each listed file hashed,
  ## assembled by the pure `subjectInputsDigestFrom` (relpath-sorted,
  ## whole-digest sha256). Never mutates the subject. The Nim subject input
  ## root is the MODULE'S PARENT DIRECTORY (Nim subject convention — no
  ## crate manifest walk; the Rust twin discovers a Cargo.toml root).
  let listing = gitCapture("-C \"" & repoRoot &
    "\" ls-files --full-name --cached --others --exclude-standard -- \"" &
    subjectInputRoot & "\"")
  var entries: seq[tuple[relPath, fileSha: string]] = @[]
  for rel in listing.splitLines():
    let t = rel.strip()
    if t.len == 0:
      continue
    entries.add((t, measuredFileSha256(joinPath(repoRoot, t))))
  subjectInputsDigestFrom(entries)

proc measureRepoFootprintDigest(repoRoot: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## (c)+(d): the repo status output (`status --porcelain
  ## --untracked-files=all` — -uall so run-made files inside untracked
  ## directories stay visible) and the tracked-content diff output
  ## (`diff HEAD --no-color --no-renames --no-ext-diff`), hashed separately
  ## and combined in fixed order by `combineFootprintDigest`. Read-only.
  let statusOut = gitCapture("-C \"" & repoRoot &
    "\" status --porcelain --untracked-files=all")
  let diffOut = gitCapture("-C \"" & repoRoot &
    "\" diff HEAD --no-color --no-renames --no-ext-diff")
  combineFootprintDigest(sha256Hex(statusOut), sha256Hex(diffOut))

proc nimToolchainFingerprint(): tuple[nimExe, nimVersion, nimHash, stdlibHash: string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## GateEnvLock triple measured exactly like precompile_gates.buildCurrentFingerprint:
  ## `nim --version` first line, sha256 of the nim binary, sha256 of
  ## <nimDir>/lib/system.nim.
  var nimExe = ""
  try:
    nimExe = findExe("nim")
  except CatchableError:
    nimExe = ""  # axiom:best-effort(absent nim is recorded as the GateEnvLock diagnostic, never a silent pass)
  if nimExe.len == 0:
    return ("", "", "", "")
  var versionLine = ""
  try:
    let (outp, code) = execCmdEx("\"" & nimExe & "\" --version", options = {poStdErrToStdOut, poUsePath})
    if code == 0:
      let lines = outp.splitLines()
      if lines.len > 0:
        versionLine = lines[0].strip()
  except CatchableError:
    discard  # axiom:best-effort(empty nimVersion fold is the recorded GateEnvLock diagnostic, never a silent pass)
  (nimExe, versionLine, measuredFileSha256(nimExe),
   measuredFileSha256(nimExe.parentDir() / "lib" / "system.nim"))

proc stateTmpBase(): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Harness scratch root: $AXIOM_STATE_DIR/.axiom/tmp/replay, CWD-relative
  ## fallback (subject tree is never written — Zero-Footprint Integrity).
  let sr = getEnv("AXIOM_STATE_DIR", "").strip()
  if sr.len > 0:
    sr / ".axiom" / "tmp" / "replay"
  else:
    try:
      getCurrentDir() / ".axiom" / "tmp" / "replay"
    except CatchableError:
      ".axiom" / "tmp" / "replay"

proc ceReplayModulePath*(subjectRepoRoot, sourcePath: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Resolve the subject module file for the replay adapter: absolute as-is;
  ## otherwise subjectRepoRoot-joined (the external-subject root), then the
  ## Axiom repo root (self-kernel collateral entries carry repo-relative
  ## sourcePaths that live in the ANALYSIS process's repo, not in the
  ## `--project` subject root), then CWD-relative. The adapter fail-closes
  ## when the resolved path does not exist.
  if sourcePath.len == 0:
    return ""
  if isAbsolute(sourcePath):
    return sourcePath
  if subjectRepoRoot.len > 0:
    let rooted = joinPath(subjectRepoRoot, sourcePath)
    if fileExists(rooted):
      return rooted
  let axiomRooted = joinPath(findRepoRoot(), sourcePath)
  if fileExists(axiomRooted):
    return axiomRooted
  var cwd = ""
  try:
    cwd = getCurrentDir()
  except CatchableError:
    cwd = "."
  let cwdJoined = joinPath(cwd, sourcePath)
  if fileExists(cwdJoined):
    return cwdJoined
  joinPath(subjectRepoRoot, sourcePath)

# ---------------------------------------------------------------------------
# d2-agent subject dep resolution (I/O boundary — store discovery + subject scan)
# ---------------------------------------------------------------------------

proc nimbleStoreRoots*(): seq[string] {.
    raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Nimble store roots searched in fixed priority order — pkgs2 (nimble 2.x
  ## installed packages, `<name>-<ver>-<hash>` layout) is authoritative;
  ## pkgcache (git checkouts, flattened `githubcom_*` slugs) and the classic
  ## pkgs/ layout are fallbacks. Absent roots are skipped (best-effort
  ## discovery; a fully absent store surfaces as the fail-closed missing
  ## diagnostic, never a silent pass).
  let base = try:
    getHomeDir() / ".nimble"
  except CatchableError:
    return @[]
  for store in ["pkgs2", "pkgcache", "pkgs"]:
    let dir = base / store
    try:
      if dirExists(dir):
        result.add(dir)
    except CatchableError:
      discard  # axiom:best-effort(an unreadable store root contributes no candidates — a fully absent store surfaces as the fail-closed missing diagnostic in resolveNimblePackageRoots, never a silent pass)

proc storePackageCandidates*(store, name: string): seq[(string, string, string)] {.
    raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Candidate (dirPath, dirName, version) entries for `name` among the
  ## immediate children of one store root — pkgs2/pkgs layout via
  ## parseNimblePkgDirName, pkgcache layout via pkgcacheDirNamesPackage.
  result = @[]
  try:
    for kind, dirPath in walkDir(store):
      if kind != pcDir:
        continue
      let dirName = splitFile(dirPath).name
      let parsed = parseNimblePkgDirName(dirName)
      if parsed.isSome and parsed.get[0] == name:
        result.add((dirPath, dirName, parsed.get[1]))
      elif pkgcacheDirNamesPackage(dirName, name):
        result.add((dirPath, dirName, pkgcacheVersionAfter(dirName, name)))
  except CatchableError:
    discard  # axiom:best-effort(unreadable store root yields no candidates — the missing-package diagnostic downstream is the fail-closed record, never a silent pass)

proc pkgRootProvidesModule*(root, name: string): bool {.
    raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The root actually provides the package's top module (`<name>/` dir or
  ## `<name>.nim`) — guards against cache/checkout dirs that carry the name
  ## but no module.
  try:
    dirExists(root / name) or fileExists(root / name & ".nim")
  except CatchableError:
    false

proc resolveNimblePackageRootsFrom*(names: seq[string]; stores: seq[string]): tuple[paths: seq[string]; missing: seq[string]] {.
    raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## resolveNimblePackageRoots over an explicit store list (the testable
  ## core; the store discovery is the only difference).
  result.paths = @[]
  result.missing = @[]
  for name in names:
    var candidates: seq[(string, string, string)] = @[]
    for store in stores:
      candidates.add(storePackageCandidates(store, name))
    let picked = newestPkgDir(candidates)
    if picked.isSome and pkgRootProvidesModule(picked.get, name):
      if picked.get notin result.paths:
        result.paths.add(picked.get)
    else:
      result.missing.add(name)

proc resolveNimblePackageRoots*(names: seq[string]): tuple[paths: seq[string]; missing: seq[string]] {.
    raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Resolve each named package to ONE root dir from the local nimble store
  ## (newest version wins, deterministic tie-break), validating that the
  ## root provides the package's top module. Names absent from every store
  ## root come back in `missing` — the caller fails closed with a diagnostic
  ## that names them.
  resolveNimblePackageRootsFrom(names, nimbleStoreRoots())

proc depPathEnvOverride*(): tuple[paths: seq[string]; error: string] {.
    raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## `AXIOM_REPLAY_DEP_PATHS` (design (b) override): ':'-separated package
  ## roots used verbatim — no store discovery. Unset/empty → no override.
  ## A non-directory entry fails closed with a diagnostic naming it.
  result.paths = @[]
  result.error = ""
  var raw = ""
  try:
    raw = getEnv(ReplayDepPathsEnvVar, "").strip()
  except CatchableError:
    raw = ""
  if raw.len == 0:
    return
  for entry in raw.split(':'):
    let p = entry.strip()
    if p.len == 0:
      continue
    var ok = false
    try:
      ok = dirExists(p)
    except CatchableError:
      ok = false
    if not ok:
      return (@[], ReplayDepPathsEnvVar & " entry is not a directory: " & p)
    if p notin result.paths:
      result.paths.add(p)

proc subjectTreeNeedsDepRoots*(repoRoot: string): bool {.
    raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Static discriminator: does any .nim file in the subject tree's
  ## import/from/export statements name one of D2AgentSubjectDepPackages?
  ## Self-contained stamped subjects (unit-test fixtures, collateral
  ## harnesses) stay zero-diff; a tree that names the stack gets the dep
  ## roots. Unreadable files contribute no signal — the replay still fails
  ## closed later if the deps were genuinely required.
  if repoRoot.len == 0:
    return false
  try:
    for file in walkDirRec(repoRoot, relative = false):
      if splitFile(file).ext != ".nim":
        continue
      if sourceNamesDepPackages(readFile(file)):
        return true
  except CatchableError:
    discard  # axiom:best-effort(scan failure contributes no dep signal — the replay still fails closed later if the deps were genuinely required (harness compile), and AXIOM_REPLAY_DEP_PATHS is the explicit pin)
  false

proc resolveD2AgentDepSearchPaths*(repoRoot: string): tuple[paths: seq[string]; error: string] {.
    raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## The d2-agent replay binding's dep roots (design (a) + (b) override):
  ## `AXIOM_REPLAY_DEP_PATHS` wins wholesale when set; otherwise the dep
  ## roots are resolved from the nimble store ONLY when the subject tree
  ## actually names the dependency stack (self-contained stamped subjects —
  ## fixtures and collateral harnesses — keep the existing search paths,
  ## zero-diff). A named package missing from the store fails closed with a
  ## diagnostic listing what was searched.
  let ov = depPathEnvOverride()
  if ov.error.len > 0:
    return (@[], ov.error)
  if ov.paths.len > 0:
    return (ov.paths, "")
  if not subjectTreeNeedsDepRoots(repoRoot):
    return (@[], "")
  let resolved = resolveNimblePackageRoots(D2AgentSubjectDepPackages)
  if resolved.missing.len > 0:
    return (@[], "subject dep resolution failed: " & resolved.missing.join(", ") &
                 " not found in nimble store (searched: " &
                 nimbleStoreRoots().join(", ") & ")")
  (resolved.paths, "")

# ---------------------------------------------------------------------------
# Subject-repo compile roots (Q5 — skipped-config path injection)
# ---------------------------------------------------------------------------

func nimbleRequiresNames*(nimbleFileContent: string): seq[string] {.raises: [].} =
  ## Package names declared by a .nimble file's `requires "name <constraint>"`
  ## lines — the project's declarative dependency contract (Q5 SSOT; the
  ## config.nims inject list is a store-repair mirror, not the authority).
  ## The toolchain name `nim` is skipped (it is the compiler itself, never a
  ## nimble store package). Quoted segments only; comments (#) are cut; the
  ## name is the first whitespace token of each quoted segment
  ## (`requires "a", "b >= 1.0"` yields [a, b]).
  proc addName(names: var seq[string]; segment: string) {.raises: [].} =
    var tok = ""
    for c in segment & " ":
      if c in {' ', '\t'}:
        break
      tok.add(c)
    if tok.len > 0 and tok != "nim" and tok notin names:
      names.add(tok)
  result = @[]
  for raw in nimbleFileContent.splitLines():
    var t = raw.strip()
    if t.len == 0:
      continue
    let hashIdx = t.find('#')
    if hashIdx >= 0:
      t = t[0 ..< hashIdx].strip()
    if not t.startsWith("requires"):
      continue
    let rest = t["requires".len .. ^1]
    var seg = ""
    var inQuotes = false
    for c in rest:
      if c == '"':
        if inQuotes and seg.len > 0:
          result.addName(seg)
          seg = ""
        inQuotes = not inQuotes
        continue
      if inQuotes:
        seg.add(c)
    if inQuotes and seg.len > 0:
      result.addName(seg)

proc subjectRepoDepSearchPaths*(repoRoot, nimExe: string): seq[string] {.
    raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Extra `--path:` entries a plain harness compile needs to resolve a
  ## self-repo subject's import closure WITHOUT any config file evaluation
  ## (Q1/Q3 skip them by design, so the repo's own injections are lost):
  ##   1. the Nim toolchain root ( `<nimExe>/../../` when it carries the
  ##      compiler sources) — in-repo kernel modules import `compiler/*`;
  ##      derived from the MEASURED nim binary, never from a hardcoded home;
  ##   2. the subject repo's nimble `requires` roots from the local store —
  ##      best-effort: an unresolved name is skipped here and the harness
  ##      compile's own "cannot open file" error remains the fail-closed
  ##      diagnostic (never guessed, never defaulted).
  ## Appended AFTER the subject paths (subject tree keeps search priority).
  ## The d2-agent stamped-template path never calls this (its dep roots have
  ## their own resolution design) — its compile command stays byte-identical.
  result = @[]
  if nimExe.len > 0:
    let toolchainRoot = nimExe.parentDir().parentDir()
    try:
      if dirExists(toolchainRoot / "compiler") and toolchainRoot notin result:
        result.add(toolchainRoot)
    except CatchableError:
      discard  # axiom:best-effort(absent toolchain root contributes no path — the compile's error stays the diagnostic)
  if repoRoot.len == 0:
    return
  var nimbleFile = ""
  try:
    for kind, path in walkDir(repoRoot):
      if kind == pcFile and splitFile(path).ext == ".nimble":
        nimbleFile = path
        break
  except CatchableError:
    return  # axiom:best-effort(unreadable repo root → no dep signal; the compile's error stays the diagnostic)
  if nimbleFile.len == 0:
    return
  var content = ""
  try:
    content = readFile(nimbleFile)
  except CatchableError:
    return  # axiom:best-effort(unreadable nimble file → no dep signal; the compile's error stays the diagnostic)
  let resolved = resolveNimblePackageRoots(nimbleRequiresNames(content))
  for p in resolved.paths:
    if p notin result:
      result.add(p)

# ---------------------------------------------------------------------------
# I/O boundary — the adapter execution (staged)
# ---------------------------------------------------------------------------

proc bindSubjectIntegrity(cfg: ReplayConfig; record: var ReplayRecord): tuple[repoRoot: string; error: string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## ① Subject integrity binding — measured before anything runs. Folds the
  ## exact-commit identity (gitRef + tree OID), the pre-run module hash, and
  ## the predicate-v2 pre side: the subject-inputs digest (b) and the
  ## combined repo-footprint digest (c)+(d). Returns ("", error) on the
  ## first unverifiable step; (repoRoot, "") when the subject is bound. The
  ## repo root is discovered from the SUBJECT MODULE's git toplevel — an
  ## external `--project` run proves self-kernel collateral whose modules
  ## live in the Axiom repo, and the identity folds, the worktree-stability
  ## checks, and the harness compile roots must all describe THAT repo, not
  ## the caller's analysis root. `cfg.subjectRepoRoot` stays the fallback
  ## (fixtures, discovery-resistant layouts).
  if not fileExists(cfg.subjectModulePath):
    return ("", "subject module not found: " & cfg.subjectModulePath)
  record.moduleSha256 = measuredFileSha256(cfg.subjectModulePath)
  if record.moduleSha256.len == 0:
    return ("", "subject module unreadable")
  let repoRoot = block:
    var discovered = subjectRepoRootFor(cfg.subjectModulePath)
    if discovered.len == 0:
      discovered = cfg.subjectRepoRoot
    discovered
  if repoRoot.len == 0:
    return ("", "subject repo root not discoverable (exact-commit binding required)")
  record.subjectGitRef = gitCapture("-C \"" & repoRoot & "\" rev-parse HEAD")
  record.subjectTreeMerkle = gitCapture("-C \"" & repoRoot & "\" rev-parse HEAD^{tree}")
  if record.subjectGitRef.len == 0 or record.subjectTreeMerkle.len == 0:
    return ("", "subject git identity unavailable (rev-parse failed)")
  record.subjectInputsPre = measureSubjectInputsDigest(
    repoRoot, cfg.subjectModulePath.parentDir())
  record.repoFootprintPre = measureRepoFootprintDigest(repoRoot)
  (repoRoot, "")

func buildHarnessCmd*(nimExe, moduleDir, repoRoot, harnessDir, harnessPath: string;
                      depSearchPaths: seq[string]): string {.raises: [].} =
  ## The replay compile command (pure — unit-tested). The subject module is
  ## imported via compile-time `--path:` flags only; `depSearchPaths` ride as
  ## additional `--path:` entries appended AFTER the subject paths (subject
  ## tree keeps search priority) and are empty for every non-d2-agent replay
  ## path.
  # Config isolation (replay_harness_config_quirks.md Q1+Q3 resolution): the
  # harness project file lives under the state tmp tree inside the repo tree,
  # so Nim's config resolution would walk its parent chain and evaluate the
  # repo's config.nims. Nim reads, in order: the user config
  # (--skipUserCfg), $parentDir/config.nims for ANY parent dir of the
  # project file's path (--skipParentCfg), then $projectDir/config.nims and
  # $project.nims (--skipProjCfg) — Nim 2.2.10 doc/nims.md (NimScript cfg
  # resolution) + doc/nimc.md "Configuration files". The harness needs none
  # of them: the subject module is imported via explicit --path: flags only.
  # Skipping the parent chain removes the repo config's cwd-relative
  # bootstrap from replay compiles — out-of-root cwd no longer breaks them
  # (Q1) and concurrent replays no longer race on its shared output (Q3).
  # The repo's own module roots ride as explicit --path flags (the same two
  # switches config.nims declares) so self-kernel collateral harnesses keep
  # resolving their import chain without any config evaluation.
  # Q4 (subject dep resolution): the subject's nimble dependency roots ride
  # as explicit --path flags too — Nim's lazy nimble-path discovery is
  # cwd-sensitive (a harness compile invoked with cwd inside the Axiom repo
  # cannot resolve `stew/enums` while the identical command from a neutral
  # cwd resolves it via ~/.nimble/pkgs2), so the d2-agent replay pins the
  # discovered roots explicitly instead of depending on that mechanism.
  var cmd = "\"" & nimExe & "\" c -r --hints:off --warnings:off" &
            " --skipParentCfg --skipUserCfg --skipProjCfg" &
            " --path:\"" & moduleDir & "\"" &
            " --path:\"" & repoRoot & "\"" &
            " --path:\"" & repoRoot / "src" & "\"" &
            " --path:\"" & repoRoot / "tools" & "\""
  for dep in depSearchPaths:
    cmd.add(" --path:\"" & dep & "\"")
  cmd.add(" --nimcache:\"" & (harnessDir / "nimcache") & "\"" &
          " -o:\"" & (harnessDir / "replay_harness_bin") & "\"" &
          " \"" & harnessPath & "\"")
  cmd

proc synthesizeAndRunHarness(cfg: ReplayConfig; record: var ReplayRecord; repoRoot: string): tuple[rawOutput: string; error: string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## ②③ Harness synthesis under the state tmp tree + `nim c -r` execution.
  ## The subject module is imported via compile-time `--path:` flags only —
  ## the subject tree is never written. Folds the GateEnvLock triple.
  # GateEnvLock toolchain fingerprint (recorded even when nim is missing —
  # the absent triple IS the diagnostic).
  let toolchain = nimToolchainFingerprint()
  record.nimVersion = toolchain.nimVersion
  record.nimHash = toolchain.nimHash
  record.stdlibHash = toolchain.stdlibHash
  if toolchain.nimExe.len == 0:
    return ("", "nim not found on PATH (GateEnvLock toolchain required)")
  let bindingSeed = cfg.funcName & "|" & cfg.subjectModulePath & "|" &
                    cfg.inputLiterals.join(",") & "|" & record.subjectGitRef
  let harnessDir = stateTmpBase() / sha256Hex(bindingSeed)[0 ..< 16]
  try:
    createDir(harnessDir)
  except CatchableError:
    return ("", "cannot create harness dir: " & harnessDir)
  record.harnessDir = harnessDir
  let moduleName = splitFile(cfg.subjectModulePath).name
  let harnessPath = harnessDir / "replay_harness.nim"
  let harnessBody = if cfg.harnessSource.len > 0: cfg.harnessSource
                    else: renderReplayHarness(moduleName, cfg.funcName,
                                              cfg.inputLiterals, cfg.callExpr)
  try:
    writeFile(harnessPath, harnessBody)
  except CatchableError as e:
    return ("", "cannot write harness: " & e.msg)
  let moduleDir = cfg.subjectModulePath.parentDir()
  # Q5: a plain harness (renderReplayHarness render — never the d2-agent
  # stamped template) compiles with all config files skipped, so the subject
  # repo's own path injections (nimble requires roots, Nim toolchain root for
  # `compiler/*` imports) must ride as explicit `--path:` entries. Appended
  # AFTER cfg.depSearchPaths (d2-agent roots, empty here) — the subject tree
  # keeps search priority in every case.
  var depPaths = cfg.depSearchPaths
  if cfg.harnessSource.len == 0:
    for p in subjectRepoDepSearchPaths(repoRoot, toolchain.nimExe):
      if p notin depPaths:
        depPaths.add(p)
  let cmd = buildHarnessCmd(toolchain.nimExe, moduleDir, repoRoot, harnessDir,
                            harnessPath, depPaths)
  try:
    let (outp, code) = execCmdEx(cmd, options = {poStdErrToStdOut, poUsePath})
    record.exitCode = code
    record.observedOutput = outp.strip()
    (outp, "")
  except CatchableError as e:
    record.observedOutput = ""
    ("", "harness execution failed: " & e.msg)

proc confirmPostRunIntegrity(cfg: ReplayConfig; record: var ReplayRecord; repoRoot: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## ④ Post-run subject integrity: the predicate-v2 worktree-stability
  ## decision (Zero-Footprint Integrity) plus the harness exit-code gate.
  ## The (b)(c)(d) post sides are re-measured here and compared against the
  ## bind-side pre captures — RELATIVE equality (G2 "unchanged across the
  ## run"); a repo-wide clean porcelain is NOT required, so pre-existing
  ## noise (stale build stamp, untracked files) never seals. "" when the
  ## observation is admissible; the failure diagnostic otherwise (verdict
  ## stays rvUnavailable).
  record.moduleSha256AfterRun = measuredFileSha256(cfg.subjectModulePath)
  record.subjectInputsPost = measureSubjectInputsDigest(
    repoRoot, cfg.subjectModulePath.parentDir())
  record.repoFootprintPost = measureRepoFootprintDigest(repoRoot)
  record.worktreeStable = worktreeStableFrom(
    record.moduleSha256, record.moduleSha256AfterRun,
    record.subjectInputsPre, record.subjectInputsPost,
    record.repoFootprintPre, record.repoFootprintPost)
  if record.exitCode != 0:
    return "harness nonzero exit " & $record.exitCode
  if not record.worktreeStable:
    return "subject tree drifted during replay (hash/porcelain mismatch)"
  ""

func decideReplayAgreement(cfg: ReplayConfig; rawOutput: string; record: var ReplayRecord) {.raises: [].} =
  ## Agreement decision — pure projection over the observation: the violated
  ## postconditions are re-evaluated concretely on the observed result.
  ## `propertyHolds == false` (violation reproduced) is the PROPOSITION_DISPROVED agreement.
  let observed = extractObservedResult(rawOutput)
  if observed.isNone:
    record.diagnostics = "harness output missing " & ReplayBeginMarker & "/" & ReplayEndMarker & " value"
    record.verdict = rvUnavailable
    return
  let paramCount = min(cfg.paramNames.len, cfg.inputLiterals.len)
  if paramCount != cfg.paramNames.len or paramCount != cfg.inputLiterals.len:
    record.diagnostics = "input/param arity mismatch"
    record.verdict = rvUnavailable
    return
  var env = initTable[string, ConcreteValue]()
  for i, lit in cfg.inputLiterals:
    let v = parseConcreteLiteral(lit)
    if v.isNone:
      record.diagnostics = "input literal unparsable: " & lit
      record.verdict = rvUnavailable
      return
    env[cfg.paramNames[i]] = v.get
  let observedVal = parseConcreteLiteral(observed.get)
  if observedVal.isNone:
    record.diagnostics = "observed result unparsable: " & observed.get
    record.verdict = rvUnavailable
    return
  env["result"] = observedVal.get
  let holds = evaluatePostconditions(cfg.postconditions, env)
  record.verdict = decideReplayVerdict(harnessRan = true, propertyHolds = holds)
  if record.verdict == rvUnavailable:
    record.diagnostics = "property not concretely evaluable (outside certified subset)"
  elif record.verdict == rvDisagree:
    record.diagnostics = "property holds on observed result — replay disagrees with solver model"

proc runCounterexampleReplay*(cfg: ReplayConfig): ReplayRecord {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Execute the replay harness for one confirmed counterexample.
  ## Observer-only: every failure mode lands in `rvUnavailable` +
  ## `diagnostics`; nothing is promoted here and nothing is written to the
  ## subject tree or the CAS.
  var record = ReplayRecord(
    verdict: rvUnavailable,
    exitCode: -1,
    hostPlatform: hostPlatformId,
    worktreeStable: false)
  let bound = bindSubjectIntegrity(cfg, record)
  if bound.error.len > 0:
    record.diagnostics = bound.error
    return record
  let ran = synthesizeAndRunHarness(cfg, record, bound.repoRoot)
  if ran.error.len > 0:
    record.diagnostics = ran.error
    return record
  let integrityError = confirmPostRunIntegrity(cfg, record, bound.repoRoot)
  if integrityError.len > 0:
    record.diagnostics = integrityError
    return record
  decideReplayAgreement(cfg, ran.rawOutput, record)
  record

func collectFreeNames(e: IRExpr; bound: HashSet[string]): HashSet[string] {.
    raises: [].} =
  ## Free variable names of `e` relative to `bound` — let/loop binders shadow
  ## in their bodies, case branches do not bind (patterns are int64 literals).
  if e == nil: return
  case e.kind
  of irLit, irFloatLit, irStringLit: discard
  of irVar:
    if not (e.varName in bound):
      result.incl(e.varName)
  of irLet:
    for n in collectFreeNames(e.letVal, bound): result.incl(n)
    var boundInner = bound
    boundInner.incl(e.letName)
    for n in collectFreeNames(e.letBody, boundInner): result.incl(n)
  of irIf:
    for n in collectFreeNames(e.ifCond, bound): result.incl(n)
    for n in collectFreeNames(e.ifThen, bound): result.incl(n)
    for n in collectFreeNames(e.ifElse, bound): result.incl(n)
  of irCase:
    for n in collectFreeNames(e.caseScrutinee, bound): result.incl(n)
    for br in e.caseBranches:
      for n in collectFreeNames(br.body, bound): result.incl(n)
    if e.caseDefault != nil:
      for n in collectFreeNames(e.caseDefault, bound): result.incl(n)
  of irCall:
    for a in e.callArgs:
      for n in collectFreeNames(a, bound): result.incl(n)
  of irBinOp:
    for n in collectFreeNames(e.binLhs, bound): result.incl(n)
    for n in collectFreeNames(e.binRhs, bound): result.incl(n)
  of irUnaryOp:
    for n in collectFreeNames(e.unaryArg, bound): result.incl(n)
  of irRecCall:
    for a in e.recArgs:
      for n in collectFreeNames(a, bound): result.incl(n)
  of irLoop:
    for i in e.loopInits:
      for n in collectFreeNames(i, bound): result.incl(n)
    var boundInner = bound
    for v in e.loopVars: boundInner.incl(v)
    for n in collectFreeNames(e.loopCond, boundInner): result.incl(n)
    if e.loopStep != nil:
      for n in collectFreeNames(e.loopStep, boundInner): result.incl(n)
    for n in collectFreeNames(e.loopBody, boundInner): result.incl(n)
    for inv in e.loopInvariants:
      for n in collectFreeNames(inv, boundInner): result.incl(n)
    if e.loopVariant != nil:
      for n in collectFreeNames(e.loopVariant, boundInner): result.incl(n)
  of irCast:
    for n in collectFreeNames(e.castExpr, bound): result.incl(n)

func compositeReplayShape*(funcDef: IRFuncDef;
                           parseBound: SubjectParseBoundComponents): CompositeReplayShape {.
    raises: [].} =
  ## S6: derive the β-composite replay shape from the §2.1a composite
  ## parse-bound components (the measured originals + typedesc carrier) and
  ## the composite funcDef's value parameter (the one parameter the spliced
  ## body actually reads — the same single-referenced-param rule the
  ## synthesis enforces). All-empty result when the entry is not synthesized;
  ## a shape with an unmeasured carrier name is left incomplete and the
  ## caller fails closed (rvUnavailable), never guesses.
  ##
  ## S6 (buffer-binding slice): a SINGLE-ORIGIN claim carrier (the base32 rem /
  ## base36 buffer pattern — ONE measured original, empty ea2) replays against
  ## its one original symbol: the carrier's body IS that original's body and
  ## its claim binds the original's result, so the replay calls
  ## `outer(<carrier>, <valueLit>)` instead of the two-leg composition. The
  ## carrier name never exists in the subject module; only measured components
  ## are used, and an unmeasured one fails closed.
  if not parseBound.synthesizedComposite:
    return CompositeReplayShape()
  if parseBound.replayHarnessTemplate.len > 0:
    # d2-agent binding: the stamped template IS the harness — the replay
    # observes the ORIGINAL subject through its public API, not through a
    # composite call over subject symbols. Empty shape; the adapter renders
    # the template instead (replayConfirmedDisproof).
    return CompositeReplayShape()
  # The value parameter: the one parameter the body references (both shapes).
  let freeNames = collectFreeNames(funcDef.body, initHashSet[string]())
  var valueParam = ""
  for p in funcDef.params:
    if p.name in freeNames:
      if valueParam.len > 0:
        return CompositeReplayShape()  # multi-param body — not the synthesis shape
      valueParam = p.name
  if valueParam.len == 0:
    return CompositeReplayShape()
  if parseBound.claimCarrierSingleOrigin:
    if parseBound.measuredForFuncName.len == 0 or
       parseBound.compositeCarrierTypename.len == 0:
      return CompositeReplayShape()
    return CompositeReplayShape(
      outerSymbol: parseBound.measuredForFuncName,
      innerSymbol: "",
      carrierTypename: parseBound.compositeCarrierTypename,
      valueParam: valueParam)
  if parseBound.measuredForFuncName.len == 0 or
     parseBound.ea2MeasuredForFuncName.len == 0 or
     parseBound.compositeCarrierTypename.len == 0:
    return CompositeReplayShape()
  CompositeReplayShape(
    outerSymbol: parseBound.measuredForFuncName,
    innerSymbol: parseBound.ea2MeasuredForFuncName,
    carrierTypename: parseBound.compositeCarrierTypename,
    valueParam: valueParam)

func compositeCallExpr(shape: CompositeReplayShape; paramNames,
                       replayInputs: seq[string]; diagnostics: var string):
    string {.raises: [].} =
  ## S6: build the composite replay call expression —
  ## `outer(<carrier>, inner(<carrier>, <valueLit>))` for the two-leg
  ## composite, `outer(<carrier>, <valueLit>)` for a single-origin claim
  ## carrier (empty innerSymbol) — from the derived shape and the model
  ## bindings. Empty for a non-composite subject. An unbound value parameter
  ## writes the fail-closed rvUnavailable diagnostics and returns empty; the
  ## caller treats empty + composite shape as a stop.
  if shape.outerSymbol.len == 0:
    return ""
  var valueLit = ""
  for i, pn in paramNames:
    if pn == shape.valueParam:
      valueLit = replayInputs[i]
      break
  if valueLit.len == 0:
    diagnostics = "rvUnavailable:composite value parameter '" &
                  shape.valueParam & "' has no model binding"
    return ""
  if shape.innerSymbol.len == 0:
    return shape.outerSymbol & "(" & shape.carrierTypename & ", " & valueLit & ")"
  shape.outerSymbol & "(" & shape.carrierTypename & ", " &
    shape.innerSymbol & "(" & shape.carrierTypename & ", " & valueLit & "))"

func d2AgentReplayPostcondition(funcDef: IRFuncDef): Option[IRExpr] {.
    raises: [].} =
  ## The d2-agent binding's replay post: `result == <forbid>` — the observed
  ## raise-boolean must equal the adopted spec's required reject decision on
  ## the model byte. The forbid side is the spliced claim's RIGHT operand (the
  ## synthesis pins the claim shape `<carrier body> == <forbid>` — for the
  ## control carrier `<forbid> == <forbid>` — so the RHS is the spec side in
  ## both carriers); any other claim shape fails closed.
  if funcDef.postConditions.len != 1:
    return none(IRExpr)
  let claim = funcDef.postConditions[0]
  if claim == nil or claim.kind != irBinOp or claim.binOp != boEq:
    return none(IRExpr)
  if claim.binRhs == nil:
    return none(IRExpr)
  some(irEq(irVar("result", funcDef.retType), claim.binRhs))

proc replayConfirmedDisproof*(subjectRepoRoot: string; sourcePath: string;
                              funcDef: IRFuncDef; modelRaw: string;
                              parseBound: SubjectParseBoundComponents =
                                SubjectParseBoundComponents()):
    tuple[agreed: bool; payload: seq[string]; diagnostics: string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Single pipeline entry (S4-S5): replay one P4-confirmed disproof against
  ## the real subject module. `modelRaw` is the raw solver output that carried
  ## the `(get-model)` assignment (VerificationResult.model). Agreement
  ## returns the PROPOSITION_DISPROVED payload (exact input + propertyViolated + replay
  ## record folds); ANY other outcome returns agreed=false + diagnostics and
  ## the caller decides fail-closed cvUnresolved. Authority = 0 — this proc
  ## never mutates a verdict.
  ## S6: for a synthesized β-composite (parseBound.synthesizedComposite) the
  ## replay composes the two ORIGINAL subject symbols —
  ## `outer(<carrier>, inner(<carrier>, n))` — because the composite name
  ## never exists in the subject module. The carriers/origins come from the
  ## measured parse-bound components; anything unmeasured fails closed.
  result.agreed = false
  let bindings = parseModelBindings(modelRaw)
  # S4 exact-input discipline: modelToTestInputs fills type-default literals
  # for unbound parameters — replaying those would present a defaulted input
  # as the solver's counterexample. Fail closed unless the model binds every
  # subject parameter.
  for p in funcDef.params:
    var bound = false
    for b in bindings:
      if b.name == p.name:
        bound = true
        break
    if not bound:
      result.diagnostics = "rvUnavailable:model does not bind parameter '" &
                           p.name & "' (exact-input required)"
      return
  let replayInputs = modelToTestInputs(bindings, funcDef.params)
  var paramNames: seq[string] = @[]
  for p in funcDef.params:
    paramNames.add(p.name)
  # S6 composite replay shape (empty for non-composite subjects — zero-diff).
  let shape = compositeReplayShape(funcDef, parseBound)
  var callExpr = compositeCallExpr(shape, paramNames, replayInputs,
                                   result.diagnostics)
  if shape.outerSymbol.len > 0 and callExpr.len == 0:
    return  # fail closed: composite value parameter unbound (diagnostics set)
  # d2-agent binding: the stamped template IS the harness. The model's exact
  # byte literal renders into the <lit> slot; the replay post is
  # `result == <forbid>` over the OBSERVED raise-boolean (contract §replay —
  # the observation enters the agreement, so the decision is never a
  # model-only tautology). Anything off-shape fails closed.
  var harnessSource = ""
  var replayPosts = funcDef.postConditions
  var depSearchPaths: seq[string] = @[]
  if parseBound.replayHarnessTemplate.len > 0:
    if funcDef.params.len != 1:
      result.diagnostics = "rvUnavailable:d2-agent replay needs exactly one " &
                           "value parameter"
      return
    var valueLit = ""
    for i, pn in paramNames:
      if pn == funcDef.params[0].name:
        valueLit = replayInputs[i]
        break
    if valueLit.len == 0:
      result.diagnostics = "rvUnavailable:d2-agent model does not bind '" &
                           funcDef.params[0].name & "' (exact-input required)"
      return
    let post = d2AgentReplayPostcondition(funcDef)
    if post.isNone:
      result.diagnostics = "rvUnavailable:d2-agent claim shape is not " &
                           "'<carrier body> == <forbid>'"
      return
    harnessSource = parseBound.replayHarnessTemplate.replace(
      ReplayValuePlaceholder, valueLit)
    replayPosts = @[post.get]
    # Q4 dep roots (design (a)+(b)): the stamped harness imports the
    # subject's public API, whose import closure may reach the subject's
    # nimble dependency stack — resolution is env-override-first, then
    # nimble-store discovery gated on the subject tree actually naming the
    # stack. Missing packages fail closed here (the harness could not
    # compile anyway); the diagnostic rides the rvUnavailable path.
    let depRes = resolveD2AgentDepSearchPaths(subjectRepoRoot)
    if depRes.error.len > 0:
      result.diagnostics = "rvUnavailable:" & depRes.error
      return
    depSearchPaths = depRes.paths
  let cfg = ReplayConfig(
    subjectRepoRoot: subjectRepoRoot,
    subjectModulePath: ceReplayModulePath(subjectRepoRoot, sourcePath),
    funcName: funcDef.name,
    paramNames: paramNames,
    inputLiterals: replayInputs,
    postconditions: replayPosts,
    callExpr: callExpr,
    harnessSource: harnessSource,
    depSearchPaths: depSearchPaths)
  let replay = runCounterexampleReplay(cfg)
  if replay.verdict != rvAgree:
    result.diagnostics = $replay.verdict & ":" & replay.diagnostics
    return
  result.agreed = true
  var propertySmt = ""
  for pc in replayPosts:
    if pc == nil:
      continue
    let pcSmt = irExprToSmt(pc)
    propertySmt = if propertySmt.len == 0: pcSmt
                  else: "(and " & propertySmt & " " & pcSmt & ")"
  result.payload = inputLiteralsPayload(paramNames, replayInputs) &
                   @["propertyViolated=" & propertySmt] &
                   replayRecordPayload(replay)

{.pop.}
