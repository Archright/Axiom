/-
  RustReferenceExtractor — Rust certified-subset canonical wire →
  AxiomIR.IRExpr reference extractor (feat/rust-subject-v1, INV-4 leg 2).

  INDEPENDENCE CLAIM (INV-4 — docs/spec/certification_continuity_contract.md
  §5, :249):
  This module is a HAND-WRITTEN Lean 4 implementation of the Rust
  certified-subset extraction rules. It is NOT codegen'd from, copy-derived
  from, or sharing a generator with the Nim leg
  (src/verification/rust_extraction_agreement.nim rustCanonicalToIr):
    * different language — Lean 4 vs Nim;
    * independent derivation — it was written from the IRExpr definition
      (IR/AxiomIRExpr.lean) and this author's own reading of the Rust
      certified subset (docs/spec/rust_certified_subset.md §1) and of the
      rust wire format documented in src/verification/rust_ast_wire.nim,
      NOT from the Nim leg's source. It decodes the rust wire with its OWN
      small decoder and re-serializes the produced IRExpr with its OWN
      encoder in the 8-byte-aligned IR binary format.
  This is deliberately NOT a lean4lean-style derivation (contract §8.3 —
  same-generator outputs are not independent evidence). Any divergence from
  the Nim leg on the certified subset MUST surface as a byte mismatch in the
  per-run differential (rust_extraction_agreement.nim → eaMismatch /
  eaReferenceError), never as a silent agreement.

  SUPPORTED SUBSET — exactly the measured 11-node grammar (the closed tag
  table of src/verification/rust_ast_wire.nim; anything else is a hard
  decode/extraction failure, exit 1):
    statements  StorageLive (0x11), StorageDead (0x12), Assign (0x13),
                Return (0x14), Panic (0x15)
    rvalues     Use (0x21), BinaryOp (0x22, form 1=Eq, 2=Lt, 3=And, 4=Or),
                AddChecked (0x23), Expr (0x24 — recursive tree: Operand
                0x25, BinaryOp 0x26, Ite 0x27)
    operands    Copy (0x31), Move (0x32), Constant (0x33, v2 payload:
                uint64 value-bits + uint64 domain code [0 = signed int64
                reading, 1 = unsigned u64, admitted only for bits ≥ 2^63] +
                type)
    types       0x41 + kind + width + signedness; the closed set accepts
                ONLY int/8/unsigned, int/32/unsigned, int/64/unsigned,
                bool/1/unsigned
    document    magic 0xA1, version 3, modulePath, sourceIdentity, funcName,
                returnPlace, failureMode (0 = noneObserved, 1 =
                panicOnOverflowObserved), params, retType, body

  CLOSED DERIVATION DECISIONS (documented at the wire codec; BOTH legs must
  implement them identically — divergence here is the differential's
  purpose):
    Copy / Move — reads of the same value; memory discipline has no IR
      image; both decode to the identical irVar of the place's type.
    StorageLive / StorageDead — memory bookkeeping; decoded, checked,
      emitted as nothing.
    Panic — the divergence target of AddChecked; no value image on the body
      path. The verified domain excludes overflow reachability
      (rust_certified_subset §3 coincidence-domain), and failureMode is a
      TOOL-LAYER observation (rustc/Charon, this build profile), NOT a
      program-meaning claim (ADR-0030 D2: fsObserved cap /
      fingerprint→evidence only). Neither carries into the IR.
    AddChecked — the checked-add operation FORM (preserved by the wire tag);
      its value path is plain BV64 add (width-uniform lifting — Axiom IR has
      only irtBitVec64; u8/u32 width re-enters verification as range
      preconditions in specs, never as an IR construct).
    Assign(dest = returnPlace) → sets the body expression (single
      assignment); Assign(other) → appends a let-binding (single
      assignment, SSA-fresh places); bindings fold outermost-first in
      statement order; Return must be exactly the LAST statement and the
      return place MUST have been assigned; a reference to an unbound place
      is a hard failure (no default type guessing).

  EXIT CODES (worker contract, shared with ircheck):
    0 = wire decoded + extraction succeeded + IR encoded, output written
    1 = decode/extraction/encoding failure (unsupported node, malformed
        wire, unsupported IR) — fail-closed, never a fabricated pass
    2 = input unreadable / output unwritable
-/

import IR.AxiomIRExpr
import Lean

open AxiomIR

namespace AxiomRustRef

-- ══════════════════════════════════════════════════════════════════════════
-- Decoded wire shapes (own reading of rust_ast_wire.nim's tag table)
-- ══════════════════════════════════════════════════════════════════════════

inductive RType where
  | int (width : Nat) (signed : Bool)
  | boolT
  deriving BEq, Repr, Inhabited

inductive ROperand where
  | copy (place : String)
  | move (place : String)
  | constant (value : Int) (ty : RType)
  deriving BEq, Repr, Inhabited

inductive RBinOpForm where
  | eq
  | lt
  | and_
  | or_
  deriving BEq, Repr, Inhabited

/-- Recursive expression tree (wire tag 0x24 payload) — the Switch collapse's
    only carrier of nested boolean structure. Types are reconstructed by the
    derivation, never stored. -/
inductive RExpr where
  | operand (op : ROperand)
  | binaryOp (form : RBinOpForm) (lhs : RExpr) (rhs : RExpr)
  | ite (cond : RExpr) (thenE : RExpr) (elseE : RExpr)
  deriving BEq, Repr, Inhabited

inductive RRvalue where
  | use (op : ROperand)
  | binaryOp (form : RBinOpForm) (lhs : ROperand) (rhs : ROperand)
  | addChecked (lhs : ROperand) (rhs : ROperand)
  | expr (e : RExpr)
  deriving BEq, Repr, Inhabited

inductive RStmt where
  | storageLive (place : String)
  | storageDead (place : String)
  | assign (dest : String) (rv : RRvalue)
  | returnStmt
  | panic
  deriving BEq, Repr, Inhabited

structure RFunc where
  modulePath : String
  sourceIdentity : String
  funcName : String
  returnPlace : String
  /-- TOOL-LAYER observation (rustc/Charon, this build profile) — NOT a
      program-meaning claim; never carries into the IR (ADR-0030 D2). -/
  failurePanicOnOverflowObserved : Bool
  params : List (String × RType)
  retType : RType
  body : List RStmt
  deriving BEq, Repr, Inhabited

/-- Closed type set: int/8/unsigned, int/32/unsigned, bool/1/unsigned,
    plus the full-domain row int/64/unsigned (usize on x86_64 — v1.2
    retired the width-64 admission wall: the two-part IR literal form
    carries ≥ 2^63 values and the no-overflow obligation discharges in
    the equivalent closed form `lhs + rhs ≤ 2^64−1`).
    Everything else → none (fail-closed, never widened). -/
def rtypeSupported : RType → Bool
  | .int w s => (w == 8 || w == 32 || w == 64) && !s
  | .boolT => true

-- ══════════════════════════════════════════════════════════════════════════
-- Independent wire decoder (8-byte aligned; own reading of the layout doc)
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

private def readTag (data : ByteArray) (offset : Nat) : Option (UInt64 × Nat) :=
  readU64 data offset

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

private def readRType (data : ByteArray) (offset : Nat) : Option (RType × Nat) :=
  match readTag data offset with
  | none => none
  | some (tag, off0) =>
    if tag != 0x41 then none
    else
      match readU64 data off0 with
      | none => none
      | some (kindCode, off1) =>
        match readU64 data off1 with
        | none => none
        | some (width, off2) =>
          match readU64 data off2 with
          | none => none
          | some (sgCode, off3) =>
            let t : Option RType :=
              match kindCode, sgCode with
              | 0, 0 => some (RType.int width.toNat false)
              | 0, 1 => some (RType.int width.toNat true)
              | 1, 0 => some RType.boolT
              | _, _ => none
            match t with
            | none => none
            | some ty => if rtypeSupported ty then some (ty, off3) else none

private def readROperand (data : ByteArray) (offset : Nat) : Option (ROperand × Nat) :=
  match readTag data offset with
  | none => none
  | some (tag, off0) =>
    match tag with
    -- 0x31 Copy: String place
    | 0x31 =>
        match readString data off0 with
        | some (p, off1) => if p.isEmpty then none else some (ROperand.copy p, off1)
        | none => none
    -- 0x32 Move: String place
    | 0x32 =>
        match readString data off0 with
        | some (p, off1) => if p.isEmpty then none else some (ROperand.move p, off1)
        | none => none
    -- 0x33 Constant: uint64 value-bits + uint64 domain code + type (v2).
    -- Domain 0 = the exact two's-complement int64 reading of the bits;
    -- domain 1 = the unsigned u64 value, admitted ONLY for bits ≥ 2^63
    -- (the disjoint two-part domain — the Nim codec enforces the same
    -- bound in both directions). `UInt64.toNat` is exact for all u64, so
    -- the unlimited `Int` operand value carries ≥ 2^63 exactly.
    | 0x33 =>
        match readU64 data off0 with
        | none => none
        | some (raw, off1) =>
          match readU64 data off1 with
          | none => none
          | some (domainCode, off2) =>
            if domainCode == 0 then
              match readRType data off2 with
              | some (ty, off3) =>
                some (ROperand.constant (Int64.ofUInt64 raw).toInt ty, off3)
              | none => none
            else if domainCode == 1 then
              if raw < 0x8000000000000000 then none
              else
                match readRType data off2 with
                | some (ty, off3) =>
                  some (ROperand.constant raw.toNat ty, off3)
                | none => none
            else none
    -- every other tag → outside the certified subset (fail-closed)
    | _ => none

private partial def readRExpr (data : ByteArray) (offset : Nat) : Option (RExpr × Nat) :=
  match readTag data offset with
  | none => none
  | some (tag, off0) =>
    match tag with
    -- 0x25 Operand
    | 0x25 =>
        match readROperand data off0 with
        | some (op, off1) => some (RExpr.operand op, off1)
        | none => none
    -- 0x26 BinaryOp: UInt64 form (1=Eq, 2=Lt, 3=And, 4=Or) + expr + expr
    | 0x26 =>
        match readU64 data off0 with
        | none => none
        | some (formCode, off1) =>
          let form : Option RBinOpForm :=
            match formCode with
            | 1 => some RBinOpForm.eq
            | 2 => some RBinOpForm.lt
            | 3 => some RBinOpForm.and_
            | 4 => some RBinOpForm.or_
            | _ => none
          match form with
          | none => none
          | some f =>
            match readRExpr data off1 with
            | none => none
            | some (l, off2) =>
              match readRExpr data off2 with
              | some (r, off3) => some (RExpr.binaryOp f l r, off3)
              | none => none
    -- 0x27 Ite: cond + then + else
    | 0x27 =>
        match readRExpr data off0 with
        | none => none
        | some (c, off1) =>
          match readRExpr data off1 with
          | none => none
          | some (t, off2) =>
            match readRExpr data off2 with
            | some (e, off3) => some (RExpr.ite c t e, off3)
            | none => none
    | _ => none

private def readRRvalue (data : ByteArray) (offset : Nat) : Option (RRvalue × Nat) :=
  match readTag data offset with
  | none => none
  | some (tag, off0) =>
    match tag with
    -- 0x21 Use: operand
    | 0x21 =>
        match readROperand data off0 with
        | some (op, off1) => some (RRvalue.use op, off1)
        | none => none
    -- 0x22 BinaryOp: UInt64 form (1=Eq, 2=Lt, 3=And, 4=Or) + operand lhs +
    -- operand rhs
    | 0x22 =>
        match readU64 data off0 with
        | none => none
        | some (formCode, off1) =>
          let form : Option RBinOpForm :=
            match formCode with
            | 1 => some RBinOpForm.eq
            | 2 => some RBinOpForm.lt
            | 3 => some RBinOpForm.and_
            | 4 => some RBinOpForm.or_
            | _ => none
          match form with
          | none => none
          | some f =>
            match readROperand data off1 with
            | none => none
            | some (l, off2) =>
              match readROperand data off2 with
              | some (r, off3) => some (RRvalue.binaryOp f l r, off3)
              | none => none
    -- 0x23 AddChecked: operand lhs + operand rhs
    | 0x23 =>
        match readROperand data off0 with
        | none => none
        | some (l, off1) =>
          match readROperand data off1 with
          | some (r, off2) => some (RRvalue.addChecked l r, off2)
          | none => none
    -- 0x24 Expr: recursive expression tree
    | 0x24 =>
        match readRExpr data off0 with
        | some (e, off1) => some (RRvalue.expr e, off1)
        | none => none
    | _ => none

private def readRStmt (data : ByteArray) (offset : Nat) : Option (RStmt × Nat) :=
  match readTag data offset with
  | none => none
  | some (tag, off0) =>
    match tag with
    -- 0x11 StorageLive: String place
    | 0x11 =>
        match readString data off0 with
        | some (p, off1) => if p.isEmpty then none else some (RStmt.storageLive p, off1)
        | none => none
    -- 0x12 StorageDead: String place
    | 0x12 =>
        match readString data off0 with
        | some (p, off1) => if p.isEmpty then none else some (RStmt.storageDead p, off1)
        | none => none
    -- 0x13 Assign: String dest + rvalue
    | 0x13 =>
        match readString data off0 with
        | none => none
        | some (d, off1) =>
          if d.isEmpty then none
          else
            match readRRvalue data off1 with
            | some (rv, off2) => some (RStmt.assign d rv, off2)
            | none => none
    -- 0x14 Return
    | 0x14 => some (RStmt.returnStmt, off0)
    -- 0x15 Panic
    | 0x15 => some (RStmt.panic, off0)
    | _ => none

/-- Decode the full wire document: magic 0xA1, uint64 version (=3),
    modulePath, sourceIdentity, funcName, returnPlace, failureMode,
    paramCount × (name + type), retType, body (count + stmts).
    Trailing bytes and an empty body are hard failures. -/
private def readRFuncDoc (data : ByteArray) : Option RFunc := do
  let (tag, off1) ← readTag data 0
  if tag != 0xA1 then none
  let (ver, off2) ← readU64 data off1
  if ver != 3 then none
  let (modulePath, off3) ← readString data off2
  if modulePath.isEmpty then none
  let (sourceIdentity, off4) ← readString data off3
  if sourceIdentity.isEmpty then none
  let (funcName, off5) ← readString data off4
  if funcName.isEmpty then none
  let (returnPlace, off6) ← readString data off5
  if returnPlace.isEmpty then none
  let (fmCode, off7) ← readU64 data off6
  let failureObserved : Option Bool :=
    match fmCode with
    | 0 => some false
    | 1 => some true
    | _ => none
  let failureObserved ← failureObserved
  let (paramCount, off8) ← readU64 data off7
  let (params, off9) ← readParams data paramCount.toNat off8 []
  let (retType, off10) ← readRType data off9
  let (bodyTag, off11) ← readTag data off10
  if bodyTag != 0x10 then none
  let (stmtCount, off12) ← readU64 data off11
  if stmtCount == 0 then none
  let (body, off13) ← readStmts data stmtCount.toNat off12 []
  if off13 != data.size then none
  some { modulePath := modulePath, sourceIdentity := sourceIdentity,
         funcName := funcName, returnPlace := returnPlace,
         failurePanicOnOverflowObserved := failureObserved,
         params := params, retType := retType, body := body }
where
  readParams : ByteArray → Nat → Nat → List (String × RType) →
      Option (List (String × RType) × Nat)
    | _, 0, offset, acc => some (acc.reverse, offset)
    | data, n + 1, offset, acc =>
        match readString data offset with
        | none => none
        | some (name, off1) =>
          if name.isEmpty then none
          else
            match readRType data off1 with
            | some (ty, off2) => readParams data n off2 ((name, ty) :: acc)
            | none => none

  readStmts : ByteArray → Nat → Nat → List RStmt → Option (List RStmt × Nat)
    | _, 0, offset, acc => some (acc.reverse, offset)
    | data, n + 1, offset, acc =>
        match readRStmt data offset with
        | some (s, off1) => readStmts data n off1 (s :: acc)
        | none => none

-- ══════════════════════════════════════════════════════════════════════════
-- Certified-subset extraction rules (OWN reading — see header)
-- ══════════════════════════════════════════════════════════════════════════

abbrev REnv := List (String × RType)

private def envLookup : REnv → String → Option RType
  | [], _ => none
  | (n, t) :: rest, name => if n == name then some t else envLookup rest name

/-- Width-uniform lifting: Axiom IR has only irtBitVec64 for machine
    integers; the u8/u32 width stays in the canonical and re-enters
    verification as range preconditions in specs. Bool is the Int 0/1
    embedding (v1.3 bool-expression row) — the same value sort as ints. -/
private def irTypeOf : RType → IRType
  | .int _ _ => IRType.bitVec64
  | .boolT => IRType.bitVec64

/-- Operand → IR + the operand's canonical type.
    Copy and Move are reads of the same value — identical irVar. -/
private def operandExpr (env : REnv) : ROperand → Option (IRExpr × RType)
  | .copy p =>
      match envLookup env p with
      | some t => some (IRExpr.var_ p (irTypeOf t), t)
      | none => none
  | .move p =>
      match envLookup env p with
      | some t => some (IRExpr.var_ p (irTypeOf t), t)
      | none => none
  | .constant v t => some (IRExpr.lit v, t)

/-- Bool value → Prop coercion: a bool-typed VALUE (Int 0/1) becomes
    `e = 1`; a node already known to be a Prop passes through. The single
    coercion rule both INV-4 legs implement. -/
private def asBoolProp (e : IRExpr) (ty : RType) (isProp : Bool) : IRExpr :=
  if ty == RType.boolT && !isProp then
    IRExpr.binOp BinOp.eq e (IRExpr.lit 1)
  else e

private def sameRTypeKind (a b : RType) : Bool :=
  match a, b with
  | .int _ _, .int _ _ => true
  | .boolT, .boolT => true
  | _, _ => false

/-- Collapsed expression tree → IR + type + isProp. `isProp` distinguishes a
    Prop-valued bool node (comparison/combinator) from a bool VALUE
    (operand/ite, Int 0/1). -/
private def exprToIR (env : REnv) : RExpr → Option (IRExpr × RType × Bool)
  | .operand op =>
      match operandExpr env op with
      | some (e, t) => some (e, t, false)
      | none => none
  | .binaryOp form l r =>
      match exprToIR env l with
      | none => none
      | some (le, lt, lp) =>
        match exprToIR env r with
        | none => none
        | some (re, rt, rp) =>
          match form with
          | .eq => some (IRExpr.binOp BinOp.eq le re, RType.boolT, true)
          | .lt => some (IRExpr.binOp BinOp.lt le re, RType.boolT, true)
          | .and_ =>
              some (IRExpr.binOp BinOp.and_ (asBoolProp le lt lp)
                      (asBoolProp re rt rp), RType.boolT, true)
          | .or_ =>
              some (IRExpr.binOp BinOp.or_ (asBoolProp le lt lp)
                      (asBoolProp re rt rp), RType.boolT, true)
  | .ite c t e =>
      match exprToIR env c with
      | none => none
      | some (ce, ct, cp) =>
        match exprToIR env t with
        | none => none
        | some (te, tt, tp) =>
          match exprToIR env e with
          | none => none
          | some (ee, et, ep) =>
            if ct != RType.boolT then none
            else if !sameRTypeKind tt et then none
            else
              let cond := asBoolProp ce ct cp
              let tv := if tt == RType.boolT && tp then
                          IRExpr.ifThenElse te (IRExpr.lit 1) (IRExpr.lit 0)
                        else te
              let ev := if et == RType.boolT && ep then
                          IRExpr.ifThenElse ee (IRExpr.lit 1) (IRExpr.lit 0)
                        else ee
              some (IRExpr.ifThenElse cond tv ev, tt, false)

/-- Rvalue → IR + result type.
    BinaryOp(Eq/Lt) → binOp, result bool (a Prop).
    BinaryOp(And/Or) → binOp on the Prop forms of both operands, result bool.
    Expr → the collapsed tree (see exprToIR).
    AddChecked → binOp add on the value path, result = lhs type; the
    overflow→Panic edge is the tool-layer failureMode fact, not program
    semantics (overflow-reachable inputs are outside the certified domain). -/
private def rvalueExpr (env : REnv) : RRvalue → Option (IRExpr × RType)
  | .use op => operandExpr env op
  | .binaryOp form l r =>
      match operandExpr env l with
      | none => none
      | some (le, lt) =>
        match operandExpr env r with
        | none => none
        | some (re, rt) =>
          match form with
          | .eq => some (IRExpr.binOp BinOp.eq le re, RType.boolT)
          | .lt => some (IRExpr.binOp BinOp.lt le re, RType.boolT)
          | .and_ =>
              some (IRExpr.binOp BinOp.and_ (asBoolProp le lt false)
                      (asBoolProp re rt false), RType.boolT)
          | .or_ =>
              some (IRExpr.binOp BinOp.or_ (asBoolProp le lt false)
                      (asBoolProp re rt false), RType.boolT)
  | .addChecked l r =>
      match operandExpr env l with
      | none => none
      | some (le, lt) =>
        match operandExpr env r with
        | none => none
        | some (re, _) => some (IRExpr.binOp BinOp.add le re, lt)
  | .expr e =>
      match exprToIR env e with
      | none => none
      | some (ie, it, _) => some (ie, it)

/-- Bindings fold outermost-first in statement order (first binding = the
    outermost let), matching the wire codec's documented fold discipline. -/
private def wrapBindings (bindings : List (String × IRExpr)) (body : IRExpr) : IRExpr :=
  bindings.foldr (fun (n, v) rest => IRExpr.letIn n v rest false) body

/-- Statement walk: accumulate let-bindings in statement order, keep the
    return-place assignment as the body expression. Single-assignment is
    enforced (SSA-fresh places); Return must be the LAST statement; Panic
    and the storage markers have no value-IR image. -/
private partial def convertStmts (returnPlace : String) (env : REnv)
    (bindings : List (String × IRExpr)) (bodyO : Option IRExpr) :
    List RStmt → Option (List (String × IRExpr) × Option IRExpr)
  | [] => some (bindings, bodyO)
  | s :: rest =>
      match s with
      | .storageLive _ => convertStmts returnPlace env bindings bodyO rest
      | .storageDead _ => convertStmts returnPlace env bindings bodyO rest
      | .panic => convertStmts returnPlace env bindings bodyO rest
      | .returnStmt =>
          if rest.isEmpty then some (bindings, bodyO)
          else none
      | .assign dest rv =>
          match rvalueExpr env rv with
          | none => none
          | some (ve, vt) =>
            if dest == returnPlace then
              match bodyO with
              | some _ => none  -- re-assignment of the return place
              | none => convertStmts returnPlace env bindings (some ve) rest
            else
              match envLookup env dest with
              | some _ => none  -- re-assignment of a local (v1 is SSA-fresh)
              | none =>
                convertStmts returnPlace (env ++ [(dest, vt)]) (bindings ++ [(dest, ve)]) bodyO rest

/-- Func extraction: params seed the type env; the return place MUST have
    been assigned (no lit-0 default — fail-closed). A bool return whose body
    is a Prop is embedded as the Int 0/1 value `ite(prop, 1, 0)` — the SAME
    expression the Nim leg derives and the spec post's bool RHS lowers to. -/
private def extractFunc : RFunc → Option (String × IRExpr)
  | f =>
      match convertStmts f.returnPlace f.params [] none f.body with
      | some (bindings, some body) =>
          let bodyValue :=
            if f.retType == RType.boolT then
              IRExpr.ifThenElse body (IRExpr.lit 1) (IRExpr.lit 0)
            else body
          some (f.funcName, wrapBindings bindings bodyValue)
      | _ => none

-- ══════════════════════════════════════════════════════════════════════════
-- Independent IR binary encoder (own 8-byte-aligned IR wire, matching
-- src/infrastructure/ir_binary_codec.nim byte-for-byte on the subset)
-- ══════════════════════════════════════════════════════════════════════════

namespace RefEncoder

private def emptyBA : ByteArray :=
  "".toUTF8

/-- Bytes must be pushed directly, never round-tripped through a Unicode
    char (a ≥0x80 byte via String.singleton would emit a 2-byte UTF-8
    sequence and corrupt the wire). -/
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

/-- Literal payload encoding, byte-exact with ir_binary_codec.nim:
    the SIGNED domain [−2^63, 2^63) travels under tag 0x01 as the exact
    two's-complement int64 bits; the u64 domain [2^63, 2^64) travels under
    tag 0x0F as the raw uint64 bits. `v` outside [−2^63, 2^64) → none
    (fail-closed — the silent `Int64.ofInt` truncation is retired: a
    truncated wire would disagree with the Nim leg instead of failing). -/
private def putLitPayload (v : Int) : Option (UInt8 × ByteArray) :=
  if v < -9223372036854775808 then none
  else if v >= 18446744073709551616 then none
  else if v < 9223372036854775808 then
    some (0x01, putU64 (Int64.toUInt64 (Int64.ofInt v)) emptyBA)
  else
    -- v ∈ [2^63, 2^64): `UInt64.ofNat` is modulo-2^64, and the guard makes
    -- the wrap a no-op — the raw bits are exact.
    some (0x0F, putU64 (UInt64.ofNat v.toNat) emptyBA)

private def putString (s : String) (buf : ByteArray) : ByteArray :=
  let raw := s.toUTF8
  ((putU64 (UInt64.ofNat raw.size) emptyBA) ++ raw ++ zeros (align8w raw.size - raw.size)) ++ buf

private def putTag (tag : UInt8) (buf : ByteArray) : ByteArray :=
  let body := b1 tag ++ zeros 7 ++ buf
  body ++ zeros (align8w body.size - body.size)

private def encodeIRType : IRType → Option ByteArray
  | .bitVec64 => some (putTag 0x01 emptyBA)
  | .bool => some (putTag 0x02 emptyBA)
  -- list/string/enum/variant: outside the Rust certified subset
  | _ => none

/-- Nim BinOpKind ordinals (axiom_ir.nim): boAdd = 0, boLt = 9, boAnd = 13,
    boOr = 14, boEq = 15. The Rust subset produces only these forms. -/
private def binOpNum : BinOp → Option UInt64
  | .add => some 0
  | .lt => some 9
  | .and_ => some 13
  | .or_ => some 14
  | .eq => some 15
  | _ => none

private partial def encodeIR : IRExpr → Option ByteArray
  | .lit v =>
      match putLitPayload v with
      | none => none
      | some (tag, payload) => some (putTag tag payload)
  | .var_ name ty =>
      match encodeIRType ty with
      | none => none
      | some tb => some (putTag 0x03 ((putString name emptyBA) ++ tb))
  | .letIn name val body false =>
      match encodeIR val with
      | none => none
      | some vb =>
        match encodeIR body with
        | none => none
        | some bb => some (putTag 0x04 (putString name (vb ++ bb)))
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
  -- floatLit, compile-time let, case, call, unaryOp, recCall, loop,
  -- stringLit, cast: outside the Rust certified subset (fail-closed)
  | _ => none

end RefEncoder

/-- Encode an extracted IRExpr to the IR binary wire (8-byte aligned).
    `none` → the IR contains a construct outside the certified subset. -/
private def encodeIRToBytes (ir : IRExpr) : Option ByteArray :=
  RefEncoder.encodeIR ir

-- ══════════════════════════════════════════════════════════════════════════
-- IO entry — `RustReferenceExtractor.lean --ast <file> --out <file>`
-- (run by the differential via `lake env lean --run`, cwd = repo root)
-- ══════════════════════════════════════════════════════════════════════════

/-- Worker mode: decode the rust wire from `astPath`, extract the function's
    IRExpr, encode it to the IR binary wire, write to `outPath`.
    Exit codes: 0 OK · 1 decode/extract/encode failure · 2 IO failure.
    Fail-closed: any unsupported node or malformed byte is a hard failure. -/
def extractIRFile (astPath : String) (outPath : String) : IO UInt32 := do
  let astBytes ← try
    IO.FS.readBinFile (System.FilePath.mk astPath)
  catch _ =>
    IO.eprint s!"RustReferenceExtractor: cannot read {astPath}\n"
    return (2 : UInt32)
  match readRFuncDoc astBytes with
  | none =>
      IO.eprint "RustReferenceExtractor: FAIL (malformed rust wire or unsupported node kind)\n"
      return (1 : UInt32)
  | some f =>
    match extractFunc f with
    | none =>
        IO.eprint "RustReferenceExtractor: FAIL (unsupported construct in certified-subset extraction)\n"
        return (1 : UInt32)
    | some (_name, ir) =>
      match encodeIRToBytes ir with
      | none =>
          IO.eprint "RustReferenceExtractor: FAIL (IR contains a construct outside the certified subset)\n"
          return (1 : UInt32)
      | some outBytes =>
        try
          IO.FS.writeBinFile (System.FilePath.mk outPath) outBytes
        catch _ =>
          IO.eprint s!"RustReferenceExtractor: cannot write {outPath}\n"
          return (2 : UInt32)
        IO.print "RustReferenceExtractor: OK\n"
        return (0 : UInt32)

end AxiomRustRef

/-- Entry point: `--ast <wire.bin> --out <ir.bin>` (argv[0] may be present
    or absent depending on the launcher). Top-level `main` — `lean --run`
    resolves it in the root namespace (Lake lean_exe contract). -/
def main (args : List String) : IO UInt32 := do
  match args with
  | ["--ast", astPath, "--out", outPath] => AxiomRustRef.extractIRFile astPath outPath
  | [_prog, "--ast", astPath, "--out", outPath] => AxiomRustRef.extractIRFile astPath outPath
  | _ =>
    IO.eprint "Usage: lean --run RustReferenceExtractor.lean --ast <rustwire.bin> --out <ir.bin>\n"
    return (1 : UInt32)
