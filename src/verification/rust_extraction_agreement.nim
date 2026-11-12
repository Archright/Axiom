import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Rust Extraction Agreement — the INV-4 differential for the Rust subject
## path (feat/rust-subject-v1), mirroring
## src/verification/extraction_agreement.nim.
##
## Per-run differential (contract §4.1, INV-4 —
## docs/spec/certification_continuity_contract.md:249, the different-language
## OR different-derivation clause; SHARED INPUT is allowed — the Nim path
## already shares one canonical between both legs):
##   Rust shared canonical (src/core/trusted/rust_canonical.nim)
##     →(b) rust wire (src/verification/rust_ast_wire.nim)
##     →(c) Lean reference extractor (proofs/IR/RustReferenceExtractor.lean,
##          hand-written from IRExpr + its OWN wire decoder — NOT derived
##          from the Nim leg) → IR_Lean bytes
##   Rust canonical →(a) Nim derivation (rustCanonicalToIr, THIS module) →
##     IR_Nim bytes (ir_binary_codec.serializeIRExprAligned)
##   IR_Nim == IR_Lean byte-for-byte ELSE FAIL CLOSED (no seal).
##
## Verdicts: the EXISTING ea* vocabulary is REUSED
## (verification/extraction_agreement.ExtractionAgreementVerdict — no new
## enum, no new gate, no new authority):
##   eaAgree          — byte-equal serialized IR (the only evidence-carrying
##                      verdict)
##   eaMismatch       — both legs produced IR, bytes differ (fail-closed)
##   eaUnsupported    — the wire codec rejected a canonical node outside the
##                      closed 11-kind grammar (fail-closed, never skip), or
##                      the reference extractor rejected the wire (exit 1)
##   eaReferenceError — Lean worker unavailable (exit -2), worker IO failure
##                      (exit 2), or no output file
##   eaInternalError  — invalid canonical, wire round-trip failure, Nim-leg
##                      derivation failure, or worker timeout/start failure
##
## Worker channel: the rust wire and the IR output travel via temp FILES —
## only quoted paths appear on argv (QUIRK(quirk#runGitEx-argv-flattening);
## docs/spec/merge_materializer_quirks.md §2). Default worker is the Lean
## source run by the pinned toolchain
## (`lake env lean --run IR/RustReferenceExtractor.lean`, cwd =
## <repoRoot>/proofs); `AXIOM_RUSTCHECK_CMD` or the explicit argument
## override it with a prebuilt binary.

import std/options
import std/os
import core/axiom_pragmas
import core/crypto/hash_kernel
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/rust_canonical
import core/utils/repo_root
import infrastructure/ir_binary_codec
import infrastructure/process_utils
import verification/extraction_agreement
import verification/rust_ast_wire

axiomIoBoundary()

# ---------------------------------------------------------------------------
# (a) Nim leg — Rust canonical → Axiom IR (own derivation, Rust grammar)
# ---------------------------------------------------------------------------

type
  RustIrDerivation* = object
    ok*: bool
    body*: IRExpr
    error*: string

  RustTypeEnv = seq[tuple[name: string, ty: RustType]]

func rustIrType*(t: RustType): IRType {.raises: [].} =
  ## Rust type → IR type. Width-uniform lifting (docs/spec/
  ## rust_certified_subset.md §1): Axiom IR has the single machine-integer
  ## representation irtBitVec64, so u8/u32 BOTH map to bitVec64; the subject
  ## width stays preserved in the canonical/wire (explicit widthBits +
  ## signedness) and re-enters verification as range preconditions in specs,
  ## never as an IR construct. bool is embedded as the Int 0/1 value domain
  ## (v1.3 bool-expression row): the IR keeps ONE value sort, the bool
  ## parameter's range precondition `0 ≤ p ∧ p < 2` restores its domain, and
  ## a bool-typed expression used as a value is coerced with
  ## `ite(prop, 1, 0)` — the same embedding the Lean renderer and the SMT
  ## lowerer consume.
  case t.kind
  of rtyInt: irTypeBitVec64()
  of rtyBool: irTypeBitVec64()

func envLookup(env: RustTypeEnv; name: string): tuple[found: bool, ty: RustType] {.raises: [].} =
  for entry in env:
    if entry.name == name:
      return (true, entry.ty)
  (false, RustType(kind: rtyInt, widthBits: 8, signedness: rsgUnsigned))

func okIr(e: IRExpr): RustIrDerivation {.inline.} =
  RustIrDerivation(ok: true, body: e, error: "")

func failIr(msg: string): RustIrDerivation {.inline.} =
  RustIrDerivation(ok: false, body: nil, error: msg)

func irLitRust(v: int64): IRExpr {.raises: [].} =
  IRExpr(kind: irLit, litVal: v, typ: irTypeBitVec64())

func irVarRust(name: string; ty: IRType): IRExpr {.raises: [].} =
  IRExpr(kind: irVar, varName: name, varType: ty, typ: ty)

func irBinOpRust(op: BinOpKind; l, r: IRExpr): IRExpr {.raises: [].} =
  ## Smart-constructor typ discipline (recomputeTyp equivalence): comparisons
  ## and boolean combinators are irtBool, arithmetic takes the lhs type.
  let t = case op
          of boEq, boLt, boLtU, boAnd, boOr: irTypeBool()
          else: l.typ
  IRExpr(kind: irBinOp, binOp: op, binLhs: l, binRhs: r, typ: t)

func irLetRust(name: string; v, body: IRExpr): IRExpr {.raises: [].} =
  ## let-binding, isCompileTime=false (irLet tag 0x04 on the IR wire).
  IRExpr(kind: irLet, letName: name, letVal: v, letBody: body,
         isCompileTime: false, typ: body.typ)

func operandExpr(env: RustTypeEnv; op: RustOperand): tuple[ok: bool, expr: IRExpr, ty: RustType, err: string] {.raises: [].} =
  ## Operand → IR. Copy and Move are reads of the same value: memory
  ## discipline (borrow/drop order) has NO IR image — both legs decode them
  ## to the identical irVar (documented closed decision, not a default).
  case op.kind
  of ropCopy, ropMove:
    let (found, ty) = envLookup(env, op.place)
    if not found:
      return (false, nil, ty, "reference to unbound place '" & op.place & "'")
    (true, irVarRust(op.place, rustIrType(ty)), ty, "")
  of ropConstant:
    ## The disjoint two-part literal split (rust_canonical u64DomainLow): the
    ## u64-domain carrier [2^63, 2^64−1] rides litU64, the signed carrier
    ## [−2^63, 2^63−1] rides litVal — the Lean extractor decodes the identical
    ## split, so byte agreement requires the same IR image here.
    (true, if op.valueU64 != 0'u64: irLitU64(op.valueU64)
           else: irLitRust(op.value), op.ty, "")

func asBoolProp(e: IRExpr; ty: RustType; isProp: bool): IRExpr {.raises: [].} =
  ## Coerce a bool-typed VALUE (Int 0/1) to a Prop (`e = 1`). A node that is
  ## already a Prop (comparison / boolean combinator) passes through. This is
  ## the single coercion rule both INV-4 legs implement.
  if ty.kind == rtyBool and not isProp:
    irBinOpRust(boEq, e, irLitRust(1))
  else:
    e

func exprToIr(env: RustTypeEnv; e: RustExpr):
    tuple[ok: bool, expr: IRExpr, ty: RustType, isProp: bool, err: string] {.
    raises: [].} =
  ## Collapsed expression tree → IR. `isProp` distinguishes a Prop-valued
  ## bool node (comparison/combinator) from a bool VALUE (operand/ite, Int
  ## 0/1). The distinction is what makes the coercion explicit and identical
  ## on both legs.
  if e == nil:
    return (false, nil, rustBoolType(), false, "nil expression node")
  case e.kind
  of rexOperand:
    let o = operandExpr(env, e.operand)
    if not o.ok:
      return (false, nil, o.ty, false, o.err)
    (true, o.expr, o.ty, false, "")
  of rexBinaryOp:
    let l = exprToIr(env, e.lhs)
    if not l.ok: return l
    let r = exprToIr(env, e.rhs)
    if not r.ok: return r
    case e.form
    of rboEq, rboLt:
      let op = if e.form == rboEq: boEq else: boLt
      (true, irBinOpRust(op, l.expr, r.expr), rustBoolType(), true, "")
    of rboAnd, rboOr:
      let op = if e.form == rboAnd: boAnd else: boOr
      let lp = asBoolProp(l.expr, l.ty, l.isProp)
      let rp = asBoolProp(r.expr, r.ty, r.isProp)
      (true, irBinOpRust(op, lp, rp), rustBoolType(), true, "")
  of rexIte:
    let c = exprToIr(env, e.cond)
    if not c.ok: return c
    let t = exprToIr(env, e.thenExpr)
    if not t.ok: return t
    let el = exprToIr(env, e.elseExpr)
    if not el.ok: return el
    if c.ty.kind != rtyBool:
      return (false, nil, t.ty, false, "ite condition is not bool-typed")
    if t.ty.kind != el.ty.kind:
      return (false, nil, t.ty, false, "ite branch type mismatch")
    let cond = asBoolProp(c.expr, c.ty, c.isProp)
    # Bool branches are VALUES (0/1); int branches are values. A Prop branch
    # is coerced to its 0/1 value so the ite stays single-sorted.
    let tv = if t.ty.kind == rtyBool and t.isProp:
               IRExpr(kind: irIf, ifCond: t.expr, ifThen: irLitRust(1),
                      ifElse: irLitRust(0), typ: irTypeBitVec64())
             else: t.expr
    let ev = if el.ty.kind == rtyBool and el.isProp:
               IRExpr(kind: irIf, ifCond: el.expr, ifThen: irLitRust(1),
                      ifElse: irLitRust(0), typ: irTypeBitVec64())
             else: el.expr
    (true, IRExpr(kind: irIf, ifCond: cond, ifThen: tv, ifElse: ev,
                  typ: tv.typ), t.ty, false, "")

func rvalueExpr(env: RustTypeEnv; rv: RustRvalue): tuple[ok: bool, expr: IRExpr, ty: RustType, err: string] {.raises: [].} =
  ## Rvalue → IR + result type.
  ##   Use          → the operand's expression
  ##   BinaryOp(Eq) → irBinOp(boEq, l, r); result bool
  ##   AddChecked   → irBinOp(boAdd, l, r); result = lhs type. The checked
  ##                  operation form is preserved by the canonical/wire tag;
  ##                  its overflow→Panic edge is the tool-layer failureMode
  ##                  fact, NOT program semantics — the value path is plain
  ##                  BV64 add, and overflow-reachable inputs are outside the
  ##                  certified domain (rust_certified_subset §1/§3).
  case rv.kind
  of rrvUse:
    operandExpr(env, rv.operand)
  of rrvBinaryOp:
    let l = operandExpr(env, rv.lhs)
    if not l.ok: return l
    let r = operandExpr(env, rv.rhs)
    if not r.ok: return r
    (true, irBinOpRust(boEq, l.expr, r.expr),
     RustType(kind: rtyBool, widthBits: 1, signedness: rsgUnsigned), "")
  of rrvAddChecked:
    let l = operandExpr(env, rv.addLhs)
    if not l.ok: return l
    let r = operandExpr(env, rv.addRhs)
    if not r.ok: return r
    (true, irBinOpRust(boAdd, l.expr, r.expr), l.ty, "")
  of rrvExpr:
    let e = exprToIr(env, rv.expr)
    if not e.ok:
      return (false, nil, e.ty, e.err)
    (true, e.expr, e.ty, "")

func rustCanonicalToIr*(c: RustCanonical): RustIrDerivation {.raises: [].} =
  ## Derive the function body IRExpr from the shared canonical (Nim leg).
  ## Closed decisions, mirrored EXACTLY by the Lean reference extractor:
  ##   StorageLive / StorageDead — memory bookkeeping, no IR image (decoded,
  ##     checked, emitted as nothing — explicit, both legs identical)
  ##   Panic — the divergence target of AddChecked; carries no value into the
  ##     body expression, and the verified domain excludes overflow
  ##     reachability (§3 coincidence-domain) → no IR image on the value path
  ##   Assign(dest == returnPlace) → sets the body expression (single
  ##     assignment; re-assignment fails)
  ##   Assign(other) → appends a let-binding (single assignment; v1 places
  ##     are SSA-fresh, measured probe shape)
  ##   Return — exactly one, LAST statement (validateRustCanonical enforces);
  ##     the body expression MUST have been assigned
  ##   Bindings fold outermost-first in statement order (first binding is the
  ##     outermost let), matching the Nim-path fold discipline.
  let v = validateRustCanonical(c)
  if v != rceNone:
    return failIr("canonical failed validation: " & rustCanonicalErrorReason(v))
  var env: RustTypeEnv = @[]
  for p in c.params:
    env.add((name: p.name, ty: p.ty))
  var bindings: seq[tuple[name: string, val: IRExpr]] = @[]
  var hasBody = false
  var bodyExpr: IRExpr = nil
  for i in 0 ..< c.body.len:
    let s = c.body[i]
    case s.kind
    of rskStorageLive, rskStorageDead, rskPanic:
      discard  # documented no-ops — see function docstring
    of rskReturn:
      if i != c.body.len - 1:
        return failIr("Return before end of body (straight-line v1 only)")
    of rskAssign:
      let rv = rvalueExpr(env, s.rvalue)
      if not rv.ok:
        return failIr(rv.err)
      if s.dest == c.returnPlace:
        if hasBody:
          return failIr("re-assignment of return place '" & s.dest & "'")
        hasBody = true
        bodyExpr = rv.expr
      else:
        if envLookup(env, s.dest).found:
          return failIr("re-assignment of place '" & s.dest & "' (v1 is single-assignment)")
        env.add((name: s.dest, ty: rv.ty))
        bindings.add((name: s.dest, val: rv.expr))
  if not hasBody:
    return failIr("return place '" & c.returnPlace & "' never assigned")
  # v1.3 bool-expression row: the IR keeps one value sort. A bool return
  # whose body is a Prop (comparison/combinator) is embedded as the Int 0/1
  # value `ite(prop, 1, 0)` — the SAME expression the spec post's bool RHS
  # lowers to, so the rendered theorem closes by unfold+omega.
  var bodyValue = bodyExpr
  if c.retType.kind == rtyBool and bodyValue != nil and
      bodyValue.typ != nil and bodyValue.typ.kind == irtBool:
    bodyValue = IRExpr(kind: irIf, ifCond: bodyValue,
                       ifThen: irLitRust(1), ifElse: irLitRust(0),
                       typ: irTypeBitVec64())
  var bodyAcc = bodyValue
  for i in countdown(bindings.len - 1, 0):
    bodyAcc = irLetRust(bindings[i].name, bindings[i].val, bodyAcc)
  okIr(bodyAcc)

# ---------------------------------------------------------------------------
# SSA let-inlining (Rust derivation shapes) + source-level-name funcDef
# ---------------------------------------------------------------------------

func substVar(e: IRExpr; name: string; value: IRExpr): IRExpr {.raises: [].} =
  ## Replace every free occurrence of the variable `name` by `value`.
  ## `irLet` with the same binder SHADOWS the substitution: its body is kept
  ## (the let's value is still substituted). Rebuilds preserve each node's
  ## construction-time `typ` — the substitution changes no types.
  if e.isNil:
    return e
  case e.kind
  of irLit:
    e
  of irVar:
    if e.varName == name: value else: e
  of irLet:
    let val = substVar(e.letVal, name, value)
    if e.letName == name:
      IRExpr(kind: irLet, letName: e.letName, letVal: val, letBody: e.letBody,
             isCompileTime: e.isCompileTime, typ: e.typ)
    else:
      IRExpr(kind: irLet, letName: e.letName, letVal: val,
             letBody: substVar(e.letBody, name, value),
             isCompileTime: e.isCompileTime, typ: e.typ)
  of irIf:
    IRExpr(kind: irIf, ifCond: substVar(e.ifCond, name, value),
           ifThen: substVar(e.ifThen, name, value),
           ifElse: substVar(e.ifElse, name, value), typ: e.typ)
  of irUnaryOp:
    IRExpr(kind: irUnaryOp, unaryOp: e.unaryOp,
           unaryArg: substVar(e.unaryArg, name, value), typ: e.typ)
  of irBinOp:
    IRExpr(kind: irBinOp, binOp: e.binOp,
           binLhs: substVar(e.binLhs, name, value),
           binRhs: substVar(e.binRhs, name, value), typ: e.typ)
  else:
    # irFloatLit / irCase / irCall / irRecCall / irLoop / irStringLit /
    # irCast — outside the Rust straight-line derivation, kept verbatim
    # (the bounded-subset lowering downstream fails closed on them).
    e

func inlineLets*(e: IRExpr): IRExpr {.raises: [].} =
  ## Inline every `irLet` binding into its body (SSA: each binder is assigned
  ## exactly once, so substitution is unambiguous and terminating). The
  ## result is let-free for any `rustCanonicalToIr` derivation.
  if e.isNil:
    return e
  case e.kind
  of irLet:
    let val = inlineLets(e.letVal)
    inlineLets(substVar(e.letBody, e.letName, val))
  of irIf:
    IRExpr(kind: irIf, ifCond: inlineLets(e.ifCond),
           ifThen: inlineLets(e.ifThen), ifElse: inlineLets(e.ifElse),
           typ: e.typ)
  of irUnaryOp:
    IRExpr(kind: irUnaryOp, unaryOp: e.unaryOp,
           unaryArg: inlineLets(e.unaryArg), typ: e.typ)
  of irBinOp:
    IRExpr(kind: irBinOp, binOp: e.binOp, binLhs: inlineLets(e.binLhs),
           binRhs: inlineLets(e.binRhs), typ: e.typ)
  else:
    e

func rustGuardWidthBound(widthBits: int): Option[int64] {.raises: [].} =
  ## 2^widthBits for the closed width set (8/32); none marks "not
  ## representable" — for width 64 no 2^64 bound exists in the int64 literal
  ## domain (the width-64 forms bound at 2^64−1 instead, a different shape).
  ## The render-side twin is rust_obligation_render.widthBound. Duplicated,
  ## not imported: the render module sits ABOVE this one in the import graph
  ## (it imports us).
  case widthBits
  of 8: some(256'i64)
  of 32: some(4294967296'i64)
  else: none(int64)

func rustTypeRangePred(paramName: string; ty: RustType): IRExpr {.raises: [].} =
  ## Type-derived range `0 ≤ p ∧ p < 2^width` — the render-side twin is
  ## rust_obligation_render.rustTypeRangePrecondition; plain IRExpr here
  ## because the origin-carrying RustWidthPrecondition record lives above
  ## this module.
  ## Width-64 (v1.2): the two-part literal form carries the 2^64−1 ceiling,
  ## so the hypothesis is the honest FULL range
  ## `0 ≤ p ∧ p ≤ 18446744073709551615` again — the v1.1 lower-bound-only
  ## shape (which proved a stronger, vacuously-falsifying statement above
  ## 2^64−1) is retired with the wall that forced it.
  let bv = irTypeBitVec64()
  if ty.widthBits == 64:
    return irAnd(irLe(irLit(0), irVar(paramName, bv)),
                 irLe(irVar(paramName, bv), irLitU64(u64DomainHigh)))
  irAnd(irLe(irLit(0), irVar(paramName, bv)),
        irLt(irVar(paramName, bv),
             irLit(rustGuardWidthBound(ty.widthBits).get(0'i64))))

func rustBoolRangePred(paramName: string): IRExpr {.raises: [].} =
  ## The bool parameter's domain in the Int 0/1 embedding: `0 ≤ p ∧ p < 2`.
  ## Signed/unsigned comparisons coincide on this domain, so the existing
  ## `boLt` lowering is exact.
  let bv = irTypeBitVec64()
  irAnd(irLe(irLit(0), irVar(paramName, bv)),
        irLt(irVar(paramName, bv), irLit(2)))

proc rustCanonicalToIrFuncDef*(canonical: RustCanonical; post: IRExpr;
                               preExtra: seq[IRExpr] = @[]): IRFuncDef {.
    raises: [].} =
  ## The canonical as a source-level-name IRFuncDef for SMT counterexample
  ## queries (guard attempts + declared-lane confirmation). Params keep the
  ## SOURCE-LEVEL names — Z3 model bindings match by name and the replay
  ## exact-input gate is name-based (rust_replay_adapter.nim:603). Body is
  ## the let-inlined Nim-leg derivation; preconditions are the type ranges
  ## per int param ∪ preExtra (the theorem-hypothesis domain — a SAT model
  ## is in-domain by construction); postconditions = @[post]. `irFuncDef`
  ## sets no pre/post — assigned after construction (the spike S5 pattern,
  ## tmp/guard_spike/s5_smt.nim:12-15).
  let derivation = rustCanonicalToIr(canonical)
  if not derivation.ok:
    # Unreachable post-eaAgree (the differential proves the Nim leg); the
    # documented failure sentinel is the empty name (axiom_ir.nim:670-672)
    # and the stub body keeps any downstream traversal non-nil.
    return irFuncDef("", @[], rustIrType(canonical.retType), irLit(0))
  var params: seq[(string, IRType)] = @[]
  var pres: seq[IRExpr] = @[]
  for p in canonical.params:
    params.add((p.name, rustIrType(p.ty)))
    if p.ty.kind == rtyInt and (rustGuardWidthBound(p.ty.widthBits).isSome or
                                p.ty.widthBits == 64):
      pres.add(rustTypeRangePred(p.name, p.ty))
    elif p.ty.kind == rtyBool:
      pres.add(rustBoolRangePred(p.name))
  for pre in preExtra:
    if pre != nil:
      pres.add(pre)
  var f = irFuncDef(canonical.funcName, params, rustIrType(canonical.retType),
                    inlineLets(derivation.body))
  f.preConditions = pres
  if post != nil:
    f.postConditions = @[post]
  f

# ---------------------------------------------------------------------------
# (c) Lean reference-extractor leg (worker channel)
# ---------------------------------------------------------------------------

func bytesToStr(bytes: openArray[byte]): string {.raises: [].} =
  result = newString(bytes.len)
  for i in 0 ..< bytes.len:
    result[i] = char(bytes[i])

proc runRustReferenceExtractorOnWire*(
  wireBytes: seq[byte];
  rcheckExe: string = "";
  projectRoot: string = "";
  timeoutMs: int = 60_000
): tuple[exitCode: int, output: string, outBytes: seq[byte]] {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## (c) Reference-extractor leg: write the rust wire to a temp FILE, invoke
  ## the Lean reference extractor (`--ast <file> --out <file>`; temp-FILE
  ## channel for BOTH payloads — QUIRK(quirk#runGitEx-argv-flattening)), read
  ## the IR output. exitCode: -2 = worker unavailable, -1 = timeout / failed
  ## to start, 0 = OK, 1 = extraction failure (unsupported/malformed),
  ## 2 = worker IO failure. outBytes empty on any non-zero exit.
  result = (exitCode: -1, output: "", outBytes: @[])
  let root = if projectRoot.len > 0: projectRoot else: resolveRepoRoot()
  var cmd: string = ""
  if rcheckExe.len > 0:
    cmd = rcheckExe
  elif getEnv("AXIOM_RUSTCHECK_CMD", "").len > 0:
    cmd = getEnv("AXIOM_RUSTCHECK_CMD", "")
  else:
    let leanSource = root / "proofs" / "IR" / "RustReferenceExtractor.lean"
    if not fileExists(leanSource):
      # Sentinel -2: worker unavailable (distinct from timeout -1).
      result.exitCode = -2
      result.output = "RustReferenceExtractor.lean not found: " & leanSource
      return
    # Run by the pinned toolchain from the proofs/ project root (lake needs
    # its lakefile directory to resolve IR/*.olean; the .lean path is
    # relative to it).
    cmd = "lake env lean --run IR/RustReferenceExtractor.lean"
  var payload = bytesToStr(wireBytes)
  var astPath = ""
  var outPath = ""
  try:
    astPath = getTempDir() / ("axiom_rustwire_" & sha256Hex(payload) & ".bin")
    outPath = getTempDir() / ("axiom_irlean_rust_" & sha256Hex(payload) & ".bin")
    writeFile(astPath, payload)
    let (output, code) = execCmdWithTimeout(
      cmd & " --ast " & quoteShell(astPath) & " --out " &
      quoteShell(outPath), workingDir = root / "proofs",
      timeoutMs = timeoutMs)
    result.output = output
    result.exitCode = code
    if code == 0 and fileExists(outPath):
      let text = readFile(outPath)
      var bytes: seq[byte] = @[]
      for i in 0 ..< text.len:
        bytes.add(byte(text[i]))
      result.outBytes = bytes
  except CatchableError:
    result.output = "RustReferenceExtractor invocation failed"
  finally:
    if astPath.len > 0:
      try: removeFile(astPath)
      except CatchableError: discard # axiom:best-effort(ioboundary catch) temp cleanup
    if outPath.len > 0:
      try: removeFile(outPath)
      except CatchableError: discard # axiom:best-effort(ioboundary catch) temp cleanup

# ---------------------------------------------------------------------------
# (a)+(b)+(c)+(d) — the differential driver
# ---------------------------------------------------------------------------

proc runRustExtractionAgreement*(
  canon: RustCanonical;
  rcheckExe: string = "";
  projectRoot: string = "";
  timeoutMs: int = 60_000
): ExtractionAgreementResult {.
  raises: [CatchableError], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Full per-run differential for ONE Rust function (INV-4). Steps:
  ## (validation) closed-grammar + structural validation;
  ## (b) wire the canonical (unsupported → eaUnsupported) + round-trip
  ##     consistency of OUR codec (failure → eaInternalError);
  ## (a) Nim derivation → IR_Nim bytes; (c) Lean reference via the worker;
  ## (d) byte-compare (eaAgree ONLY on byte equality). Fail-closed at every
  ## step — nothing but eaAgree seals.
  result = ExtractionAgreementResult(verdict: eaInternalError, reason: "",
                                     nimDigest: "", leanDigest: "")
  let v = validateRustCanonical(canon)
  if v != rceNone:
    result.reason = "invalid canonical: " & rustCanonicalErrorReason(v)
    return
  let wire = serializeCanonicalWire(canon)
  if not wire.ok:
    result.verdict = eaUnsupported
    result.reason = "unsupported canonical content (" & wire.kindName & ") " &
      "outside the certified-subset wire set"
    return
  let decoded = deserializeCanonicalWire(wire.bytes)
  if not decoded.ok:
    result.reason = "our codec produced a wire our own decoder rejects (" &
      decoded.kindName & ") — fail-closed"
    return
  let reencoded = serializeCanonicalWire(decoded.canonical)
  if not reencoded.ok or reencoded.bytes != wire.bytes:
    result.reason = "wire round-trip is not byte-stable — fail-closed"
    return
  let nimLeg = rustCanonicalToIr(canon)
  if not nimLeg.ok:
    result.reason = "Nim derivation failed: " & nimLeg.error
    return
  let nimBytes = serializeIRExprAligned(nimLeg.body)
  if nimBytes.len == 0:
    result.reason = "Nim derivation produced no serialized IR"
    return
  result.nimDigest = sha256Hex(bytesToStr(nimBytes))
  let lean = runRustReferenceExtractorOnWire(wire.bytes, rcheckExe,
                                             projectRoot, timeoutMs)
  if lean.exitCode == -2:
    result.verdict = eaReferenceError
    result.reason = "reference extractor unavailable: " & lean.output
    return
  if lean.exitCode == -1:
    result.reason = "rust reference extractor timed out or failed to start: " &
      lean.output
    return
  if lean.exitCode == 2:
    result.verdict = eaReferenceError
    result.reason = "reference extractor IO failure: " & lean.output
    return
  if lean.exitCode != 0:
    result.verdict = eaUnsupported
    result.reason = "reference extractor rejected the wire (unsupported " &
      "construct or malformed bytes): " & lean.output
    return
  if lean.outBytes.len == 0:
    result.verdict = eaReferenceError
    result.reason = "reference extractor produced no output file"
    return
  result.leanDigest = sha256Hex(bytesToStr(lean.outBytes))
  result.verdict = compareSerializedIR(nimBytes, lean.outBytes)
  result.reason = agreementVerdictReason(result.verdict)

{.pop.}
