/-
  ReferenceExtractor — certified-subset AST → AxiomIR.IRExpr reference extractor
  (certification-continuity Phase 3.75 — Tier 2 extraction agreement).

  INDEPENDENCE CLAIM (INV-4 — docs/spec/certification_continuity_contract.md
  §5/§8.3):
  This module is a HAND-WRITTEN Lean 4 implementation of the certified-subset
  extraction rules. It is NOT codegen'd from, copy-derived from, or sharing a
  generator with src/core/trusted/ast_to_ir.nim:
    * different language — Lean 4 vs Nim;
    * independent derivation — it was written from the IRExpr definition
      (IR/AxiomIRExpr.lean) and this author's own reading of the certified
      subset (contract §1 "Certified subset of Nim": canonical-serializable,
      loss-free IR lowering), NOT from ast_to_ir.nim's source. It decodes the
      AST wire (src/verification/ast_wire.nim, wire format documented there)
      with its OWN small decoder — the existing AxiomIR.BinaryCodec decodes
      IRExpr, not AST, so this decoder is new and independent — and
      re-serializes the produced IRExpr with its OWN encoder in the
      8-byte-aligned IR binary format.
  This is deliberately NOT a lean4lean-style derivation: lean4lean is "derived
  directly from the C++ kernel implementation… not really an independent
  implementation" (contract §8.3 — exactly the failure mode INV-4 forbids:
  same-generator outputs are not independent evidence). Any divergence from
  Nim on the certified subset MUST surface as a byte mismatch in the per-run
  differential (extraction_agreement.nim → EA_MISMATCH / EA_REFERENCE_ERROR),
  never as a silent agreement.

  SUPPORTED SUBSET (matches ast_wire.nim's wire kinds — anything else is a
  hard decode/extraction failure, exit 1):
    int literals (all widths, one unified Int), char literals, nil (→ lit 0),
    identifiers (vars), infix operators + - * / div % mod < <= > >= == and or
    (Nim spellings), prefix operators - (bvNeg) and not (not_), calls
    (irCall; self-name → irRecCall), let/var/const single-name bindings,
    assignment-to-identifier (name "result" → body expression), return
    statements, single-branch early-return if statements, function defs with
    formal params (int-family/bool/string type names only).

  EXIT CODES (worker contract, shared with ircheck --check-file):
    0 = AST decoded + extraction succeeded + IR encoded, output written
    1 = decode/extraction/encoding failure (unsupported node, malformed wire,
        unsupported IR) — fail-closed, never a fabricated pass
    2 = input unreadable / output unwritable
-/

import IR.AxiomIRExpr
import Lean

open AxiomIR

namespace AxiomRef

-- ══════════════════════════════════════════════════════════════════════════
-- Wire AST (decoded shape of src/verification/ast_wire.nim's binary format)
-- ══════════════════════════════════════════════════════════════════════════

inductive WAst where
  | funcDef (name : String) (params : List (String × String)) (body : WAst)
  | stmtList (stmts : List WAst)
  | bindSection (isCompileTime : Bool) (binds : List (String × WAst))
  | asgn (name : String) (value : WAst)
  | returnStmt (value : WAst)
  | ifStmt (cond : WAst) (retVal : WAst) (rest : WAst)
  | intLit (val : Int)
  | ident (name : String)
  | infix (op : String) (lhs : WAst) (rhs : WAst)
  | prefix (op : String) (arg : WAst)
  | call (name : String) (args : List WAst)
  | nilLit
  deriving BEq, Repr, Inhabited

-- ══════════════════════════════════════════════════════════════════════════
-- Independent wire decoder (8-byte aligned; own reading of ast_wire.nim)
-- ══════════════════════════════════════════════════════════════════════════

private def align8w (n : Nat) : Nat :=
  (n + 7) / 8 * 8

private def readU64 (data : ByteArray) (offset : Nat) : Option (UInt64 × Nat) :=
  let base := align8w offset
  if base + 8 > data.size then none
  else
    let s := data.extract base (base + 8)
    let val := (s.get! 0).toUInt64
           ||| ((s.get! 1).toUInt64 <<< 8)
           ||| ((s.get! 2).toUInt64 <<< 16)
           ||| ((s.get! 3).toUInt64 <<< 24)
           ||| ((s.get! 4).toUInt64 <<< 32)
           ||| ((s.get! 5).toUInt64 <<< 40)
           ||| ((s.get! 6).toUInt64 <<< 48)
           ||| ((s.get! 7).toUInt64 <<< 56)
    some (val, base + 8)

private def readI64 (data : ByteArray) (offset : Nat) : Option (Int × Nat) :=
  match readU64 data offset with
  | some (u, off) => some ((Int64.ofUInt64 u).toInt, off)
  | none => none

private def readTag (data : ByteArray) (offset : Nat) : Option (UInt8 × Nat) :=
  let base := align8w offset
  if base + 8 > data.size then none
  else some (data.get! base, base + 8)

private def readString (data : ByteArray) (offset : Nat) : Option (String × Nat) :=
  match readU64 data offset with
  | none => none
  | some (lenU64, dataStart) =>
    let len := lenU64.toNat
    if dataStart + len > data.size then none
    else
      let s := data.extract dataStart (dataStart + len)
      let chars := (List.range len).map (fun i => Char.ofUInt8 (s.get! i))
      some (String.ofList chars, align8w (dataStart + len))

-- Mutually recursive: WAst decoding (nodes contain nodes, lists of nodes).
mutual
  private partial def readWAst : ByteArray → Nat → Option (WAst × Nat)
    | data, offset =>
      match readTag data offset with
      | none => none
      | some (tag, off0) =>
        match tag with
        -- 0x11 funcDef: String name, UInt64 paramCount, (String name, String type)*, node body
        | 0x11 =>
            match readString data off0 with
            | none => none
            | some (name, off1) =>
              match readU64 data off1 with
              | none => none
              | some (countU64, off2) =>
                match readStrPairs data countU64.toNat off2 with
                | none => none
                | some (params, off3) =>
                  match readWAst data off3 with
                  | none => none
                  | some (body, off4) => some (WAst.funcDef name params body, off4)
        -- 0x12 stmtList: UInt64 count, node*
        | 0x12 =>
            match readU64 data off0 with
            | none => none
            | some (countU64, off1) =>
              match readNodeList data countU64.toNat off1 with
              | none => none
              | some (stmts, off2) => some (WAst.stmtList stmts, off2)
        -- 0x13/0x14/0x15 bind sections: UInt64 count, (String name, node value)*
        | 0x13 => readBindSection false data off0
        | 0x14 => readBindSection false data off0
        | 0x15 => readBindSection true data off0
        -- 0x16 asgn: String name, node value
        | 0x16 =>
            match readString data off0 with
            | none => none
            | some (name, off1) =>
              match readWAst data off1 with
              | none => none
              | some (value, off2) => some (WAst.asgn name value, off2)
        -- 0x17 returnStmt: node value
        | 0x17 =>
            match readWAst data off0 with
            | none => none
            | some (value, off1) => some (WAst.returnStmt value, off1)
        -- 0x18 ifStmt (early return): node cond, node retVal, node rest
        | 0x18 =>
            match readWAst data off0 with
            | none => none
            | some (cond, off1) =>
              match readWAst data off1 with
              | none => none
              | some (retVal, off2) =>
                match readWAst data off2 with
                | none => none
                | some (rest, off3) => some (WAst.ifStmt cond retVal rest, off3)
        -- 0x1C intLit: Int64
        | 0x1C =>
            match readI64 data off0 with
            | some (v, off1) => some (WAst.intLit v, off1)
            | none => none
        -- 0x1D ident: String
        | 0x1D =>
            match readString data off0 with
            | some (name, off1) => some (WAst.ident name, off1)
            | none => none
        -- 0x1E infix: String op, node lhs, node rhs
        | 0x1E =>
            match readString data off0 with
            | none => none
            | some (op, off1) =>
              match readWAst data off1 with
              | none => none
              | some (lhs, off2) =>
                match readWAst data off2 with
                | none => none
                | some (rhs, off3) => some (WAst.infix op lhs rhs, off3)
        -- 0x1F prefix: String op, node arg
        | 0x1F =>
            match readString data off0 with
            | none => none
            | some (op, off1) =>
              match readWAst data off1 with
              | none => none
              | some (arg, off2) => some (WAst.prefix op arg, off2)
        -- 0x20 call: String name, UInt64 count, node*
        | 0x20 =>
            match readString data off0 with
            | none => none
            | some (name, off1) =>
              match readU64 data off1 with
              | none => none
              | some (countU64, off2) =>
                match readNodeList data countU64.toNat off2 with
                | none => none
                | some (args, off3) => some (WAst.call name args, off3)
        -- 0x21 charLit: Int64
        | 0x21 =>
            match readI64 data off0 with
            | some (v, off1) => some (WAst.intLit v, off1)
            | none => none
        -- 0x22 nilLit
        | 0x22 => some (WAst.nilLit, off0)
        -- 0x19/0x1A/0x1B (if-expression branches) and every other tag:
        -- outside the certified subset → hard failure (fail-closed)
        | _ => none
  where
    readStrPairs : ByteArray → Nat → Nat → Option (List (String × String) × Nat)
    | _, 0, offset => some ([], offset)
    | data, n + 1, offset =>
        match readString data offset with
        | none => none
        | some (n1, off1) =>
          match readString data off1 with
          | none => none
          | some (t1, off2) =>
            match readStrPairs data n off2 with
            | some (rest, off3) => some ((n1, t1) :: rest, off3)
            | none => none

    readNodeList : ByteArray → Nat → Nat → Option (List WAst × Nat)
    | _, 0, offset => some ([], offset)
    | data, n + 1, offset =>
        match readWAst data offset with
        | none => none
        | some (w, off1) =>
          match readNodeList data n off1 with
          | some (rest, off2) => some (w :: rest, off2)
          | none => none

    readBindSection : Bool → ByteArray → Nat → Option (WAst × Nat)
    | ct, data, offset =>
        match readU64 data offset with
        | none => none
        | some (countU64, off1) =>
          match readBinds data countU64.toNat off1 with
          | some (binds, off2) => some (WAst.bindSection ct binds, off2)
          | none => none

    readBinds : ByteArray → Nat → Nat → Option (List (String × WAst) × Nat)
    | _, 0, offset => some ([], offset)
    | data, n + 1, offset =>
        match readString data offset with
        | none => none
        | some (name, off1) =>
          match readWAst data off1 with
          | none => none
          | some (value, off2) =>
            match readBinds data n off2 with
            | some (rest, off3) => some ((name, value) :: rest, off3)
            | none => none
end

/-- Decode the full wire document: magic 0xA0, uint64 version (=1), root node. -/
private def readWireAST (data : ByteArray) : Option WAst := do
  let (tag, off1) ← readTag data 0
  if tag ≠ 0xA0 then none
  let (ver, off2) ← readU64 data off1
  if ver ≠ 1 then none
  let (w, _) ← readWAst data off2
  pure w

-- ══════════════════════════════════════════════════════════════════════════
-- Certified-subset extraction rules (OWN reading — see header)
-- ══════════════════════════════════════════════════════════════════════════

/-- Type-name mapping: bool → IRType.bool, string → IRType.string, the int
    family and everything else → IRType.bitVec64 (the canonical extractor's
    default; seq/array/list-typed params are outside the certified subset and
    are rejected at the wire level). -/
private def typeOfName (t : String) : IRType :=
  match t with
  | "bool" => IRType.bool
  | "string" => IRType.string
  | _ => IRType.bitVec64

/-- Nim operator spelling → IR BinOp. Operators outside the certified table
    (%% shl shr and anything else) → none (fail-closed). -/
private def binOpOfOp (op : String) : Option BinOp :=
  match op with
  | "+" => some BinOp.add
  | "-" => some BinOp.sub
  | "*" => some BinOp.mul
  | "/" => some BinOp.div
  | "div" => some BinOp.div
  | "%" => some BinOp.rem
  | "mod" => some BinOp.rem
  | "<" => some BinOp.lt
  | "<=" => some BinOp.le
  | ">" => some BinOp.gt
  | ">=" => some BinOp.ge
  | "==" => some BinOp.eq
  | "and" => some BinOp.and_
  | "or" => some BinOp.or_
  | _ => none

/-- Prefix operator spelling → IR UnaryOp. -/
private def unOpOfOp (op : String) : Option UnaryOp :=
  match op with
  | "not" => some UnaryOp.not_
  | "-" => some UnaryOp.bvNeg
  | _ => none

private def bindLookup (env : List (String × IRType)) (name : String) : IRType :=
  match env.lookup name with
  | some t => t
  | none => IRType.bitVec64

/-- IR type of an extracted expression, mirroring the Nim smart constructors'
    typ propagation (needed ONLY to reproduce the and/or operand coercion:
    irBinOp wraps BitVec64-typed operands of and/or in irCall("opCastToBool")). -/
private def typOfIR : IRExpr → Option IRType
  | .lit _ => some IRType.bitVec64
  | .var_ _ t => some t
  | .letIn _ _ b _ => typOfIR b
  | .ifThenElse _ t _ => typOfIR t
  | .binOp op _ _ =>
      match op with
      | .lt | .le | .gt | .ge | .eq | .and_ | .or_ => some IRType.bool
      | _ => none  -- arithmetic: the lhs type (unreachable in wrap decisions)
  | .unaryOp op _a =>
      match op with
      | .not_ => some IRType.bool
      | _ => none
  | .call "opCastToBool" _ => some IRType.bool
  | .call _ _ => none  -- plain calls carry no type (nil) in the subset
  | .recCall _ => some IRType.bitVec64
  | .stringLit _ => some IRType.string
  | _ => none

/-- and/or operand coercion: BitVec64-typed operands are wrapped in
    opCastToBool exactly as the Nim irBinOp smart constructor does; every
    other operand passes through unchanged. -/
private def coerceAndOrOperand (e : IRExpr) : IRExpr :=
  match typOfIR e with
  | some IRType.bitVec64 => IRExpr.call "opCastToBool" [e]
  | _ => e

-- Expression extraction. Statements and the func-def root in expression
-- slots are malformed wire → none (fail-closed).
private partial def extractExpr (env : List (String × IRType)) (fnName : String) : WAst → Option IRExpr
  | .intLit v => some (IRExpr.lit v)
  | .ident name => some (IRExpr.var_ name (bindLookup env name))
  | .infix op l r =>
      match binOpOfOp op with
      | none => none
      | some b =>
        match extractExpr env fnName l with
        | none => none
        | some le =>
          match extractExpr env fnName r with
          | none => none
          | some re =>
            let le' := if b == BinOp.and_ || b == BinOp.or_ then coerceAndOrOperand le else le
            let re' := if b == BinOp.and_ || b == BinOp.or_ then coerceAndOrOperand re else re
            some (IRExpr.binOp b le' re')
  | .prefix op arg =>
      match unOpOfOp op with
      | none => none
      | some u =>
        match extractExpr env fnName arg with
        | none => none
        | some ae => some (IRExpr.unaryOp u ae)
  | .call name args =>
      match args.mapM (extractExpr env fnName) with
      | none => none
      | some argEs =>
        if name == fnName then some (IRExpr.recCall argEs)
        else some (IRExpr.call name argEs)
  | .nilLit => some (IRExpr.lit 0)
  | _ => none

private def wrapBindings (acc : List (String × IRExpr × Bool)) (body : IRExpr) : IRExpr :=
  acc.foldr (fun (n, v, ct) rest => IRExpr.letIn n v rest ct) body

-- Statement conversion: accumulate bindings in statement order, keep the
-- LAST body expression, fold bindings outermost-first (let a in let b in e).
-- An early-return if (cond, retVal, rest) becomes
--   irIf(cond, retVal, convert rest with FRESH bindings)
-- wrapped by the bindings accumulated so far — the canonical extractor's
-- convertBodyFromCanon(stmts, i + 1) semantics as this extractor reads them.
private partial def convertStmtsCore (env : List (String × IRType)) (fnName : String)
    : List WAst → List (String × IRExpr × Bool) → Option IRExpr → Option IRExpr
  | [], acc, bodyO => some (wrapBindings acc (match bodyO with | some b => b | none => IRExpr.lit 0))
  | s :: rest, acc, bodyO =>
      match s with
      | .bindSection ct binds =>
          let
            rec foldBinds : List (String × WAst) → List (String × IRExpr × Bool) →
                Option (List (String × IRExpr × Bool))
            | [], acc2 => some acc2
            | (nm, v) :: rest, acc2 =>
                match extractExpr env fnName v with
                | none => none
                | some ve => foldBinds rest (acc2 ++ [(nm, ve, ct)])
          match foldBinds binds acc with
          | some acc' => convertStmtsCore env fnName rest acc' bodyO
          | none => none
      | .asgn name value =>
          match extractExpr env fnName value with
          | none => none
          | some ve =>
            if name == "result" then
              convertStmtsCore env fnName rest acc (some ve)
            else
              convertStmtsCore env fnName rest (acc ++ [(name, ve, false)]) bodyO
      | .returnStmt value =>
          match extractExpr env fnName value with
          | none => none
          | some ve => convertStmtsCore env fnName rest acc (some ve)
      | .ifStmt cond retVal restNode =>
          match extractExpr env fnName cond with
          | none => none
          | some condE =>
            match extractExpr env fnName retVal with
            | none => none
            | some retE =>
              match restNode with
              | .stmtList restStmts =>
                match convertStmtsCore env fnName restStmts [] none with
                | none => none
                | some elseE =>
                  some (wrapBindings acc (IRExpr.ifThenElse condE retE elseE))
              | _ => none
      -- Bare expression statement → the running body expression (the
      -- canonical extractor's "last statement wins" behaviour; the wire
      -- carries only supported expression nodes here).
      | other =>
          match extractExpr env fnName other with
          | none => none
          | some e => convertStmtsCore env fnName rest acc (some e)
  where
    -- (no polymorphic helpers — partial defs must stay monomorphic)

-- Func-def extraction: params → type env; body must be a stmtList root.
private partial def extractFuncDef : WAst → Option (String × IRExpr)
  | .funcDef name params body =>
      let env := params.map (fun (n, t) => (n, typeOfName t))
      match body with
      | .stmtList stmts =>
          match convertStmtsCore env name stmts [] none with
          | some ir => some (name, ir)
          | none => none
      | _ => none
  | _ => none

-- ══════════════════════════════════════════════════════════════════════════
-- Independent IR binary encoder (own 8-byte-aligned IR wire, matching
-- src/infrastructure/ir_binary_codec.nim byte-for-byte on the subset)
-- ══════════════════════════════════════════════════════════════════════════

namespace RefEncoder

private def emptyBA : ByteArray :=
  "".toUTF8

-- Byte-safe single-byte builder: `String.singleton (Char.ofUInt8 b) |>.toUTF8`
-- would emit a 2-byte UTF-8 sequence for b ≥ 0x80 (e.g. 0xB3 → C2 B3), which
-- corrupts the IR wire (observed: intLit 179 encoded as [1][46018][0] instead
-- of [1][179] — 0xB3C2 = the UTF-8 bytes of U+00B3). Bytes must be pushed
-- directly, never round-tripped through a Unicode char.
private def b1 (b : UInt8) : ByteArray :=
  ByteArray.empty.push b

private def zeros (n : Nat) : ByteArray :=
  (List.range n).foldl (fun acc _ => acc ++ b1 0) emptyBA

private def padTo8 (len : Nat) (buf : ByteArray) : ByteArray :=
  buf ++ zeros (align8w len - len)

private def u8lo (v : UInt64) : UInt8 :=
  UInt8.ofNatClamp ((v &&& 255).toNat)

private def putU64 (v : UInt64) (buf : ByteArray) : ByteArray :=
  buf ++ (List.range 8).foldl
    (fun acc k => acc ++ b1 (u8lo (v >>> ((8 * k).toUInt64))))
    emptyBA

private def putI64 (v : Int) (buf : ByteArray) : ByteArray :=
  putU64 (Int64.toUInt64 (Int64.ofInt v)) buf

private def putString (s : String) (buf : ByteArray) : ByteArray :=
  let raw := s.toUTF8
  ((putU64 (UInt64.ofNat raw.size) emptyBA) ++ raw ++ zeros (align8w raw.size - raw.size)) ++ buf

private def putTag (tag : UInt8) (buf : ByteArray) : ByteArray :=
  let body := b1 tag ++ zeros 7 ++ buf
  body ++ zeros (align8w body.size - body.size)

private partial def encodeIRType : IRType → Option ByteArray
  | .bitVec64 => some (putTag 0x01 emptyBA)
  | .bool => some (putTag 0x02 emptyBA)
  | .string => some (putTag 0x04 emptyBA)
  | .list elem =>
      match encodeIRType elem with
      | none => none
      | some e => some (putTag 0x03 emptyBA ++ e)

private partial def binOpNum : BinOp → Option UInt64
  -- Nim enum ordinals (axiom_ir.nim BinOpKind): 0 add, 1 sub, 2 mul,
  -- 3 div, 4 rem, 9 lt, 10 le, 11 gt, 12 ge, 13 and_, 14 or_, 15 eq,
  -- 16 ltU.
  | .add => some 0
  | .sub => some 1
  | .mul => some 2
  | .div => some 3
  | .rem => some 4
  | .lt => some 9
  | .le => some 10
  | .gt => some 11
  | .ge => some 12
  | .and_ => some 13
  | .or_ => some 14
  | .eq => some 15
  | .ltU => some 16

private partial def unaryOpNum : UnaryOp → Option UInt64
  | .not_ => some 0
  | .bvNot => some 1
  | .bvNeg => some 2

mutual
  private partial def encodeArgs : List IRExpr → Option ByteArray
    | [] => some emptyBA
    | x :: xs =>
        match encodeIR x with
        | none => none
        | some b =>
          match encodeArgs xs with
          | some r => some (b ++ r)
          | none => none

  private partial def encodeIR : IRExpr → Option ByteArray
    | .lit v => some (putTag 0x01 (putI64 v emptyBA))
    | .var_ name ty =>
        match encodeIRType ty with
        | none => none
        | some tb => some (putTag 0x03 ((putString name emptyBA) ++ tb))
    | .letIn name val body ct =>
        match encodeIR val with
        | none => none
        | some vb =>
          match encodeIR body with
          | none => none
          | some bb =>
            let tag := if ct then 0x0E else 0x04
            some (putTag tag (putString name (vb ++ bb)))
    | .ifThenElse cond thenE elseE =>
        match encodeIR cond with
        | none => none
        | some cb =>
          match encodeIR thenE with
          | none => none
          | some tb =>
            match encodeIR elseE with
            | none => none
            | some eb => some (putTag 0x05 (cb ++ tb ++ eb))
    | .call name args =>
        match encodeArgs args with
        | none => none
        | some ab => some (putTag 0x07 (putString name ((putU64 (UInt64.ofNat args.length) emptyBA) ++ ab)))
    | .binOp op lhs rhs =>
        match binOpNum op with
        | none => none
        | some on =>
          match encodeIR lhs with
          | none => none
          | some lb =>
            match encodeIR rhs with
            | none => none
            | some rb => some (putTag 0x08 ((putU64 on emptyBA) ++ lb ++ rb))
    | .unaryOp op operand =>
        match unaryOpNum op with
        | none => none
        | some on =>
          match encodeIR operand with
          | none => none
          | some ob => some (putTag 0x09 ((putU64 on emptyBA) ++ ob))
    | .recCall args =>
        match encodeArgs args with
        | none => none
        | some ab => some (putTag 0x0A ((putU64 (UInt64.ofNat args.length) emptyBA) ++ ab))
    -- floatLit, case_, loop, stringLit, cast: outside the certified subset
    | _ => none
end

end RefEncoder

/-- Encode an extracted IRExpr to the IR binary wire (8-byte aligned).
    `none` → the IR contains a construct outside the certified subset. -/
private def encodeIRToBytes (ir : IRExpr) : Option ByteArray :=
  RefEncoder.encodeIR ir

-- ══════════════════════════════════════════════════════════════════════════
-- IO entry — `ircheck extract --ast <file> --out <file>`
-- ══════════════════════════════════════════════════════════════════════════

/-- Worker mode: decode the AST wire from `astPath`, extract the function's
    IRExpr, encode it to the IR binary wire, write to `outPath`.
    Exit codes: 0 OK · 1 decode/extract/encode failure · 2 IO failure.
    Fail-closed: any unsupported node or malformed byte is a hard failure. -/
def extractIRFile (astPath : String) (outPath : String) : IO UInt32 := do
  let astBytes ← try
    IO.FS.readBinFile (System.FilePath.mk astPath)
  catch _ =>
    IO.eprint s!"ReferenceExtractor: cannot read {astPath}\n"
    return (2 : UInt32)
  match readWireAST astBytes with
  | none =>
      IO.eprint "ReferenceExtractor: FAIL (malformed AST wire or unsupported node kind)\n"
      return (1 : UInt32)
  | some w =>
    match extractFuncDef w with
    | none =>
        IO.eprint "ReferenceExtractor: FAIL (unsupported construct in certified-subset extraction)\n"
        return (1 : UInt32)
    | some (_name, ir) =>
      match encodeIRToBytes ir with
      | none =>
          IO.eprint "ReferenceExtractor: FAIL (IR contains a construct outside the certified subset)\n"
          return (1 : UInt32)
      | some outBytes =>
        try
          IO.FS.writeBinFile (System.FilePath.mk outPath) outBytes
        catch _ =>
          IO.eprint s!"ReferenceExtractor: cannot write {outPath}\n"
          return (2 : UInt32)
        IO.print "ReferenceExtractor: OK\n"
        return (0 : UInt32)

end AxiomRef