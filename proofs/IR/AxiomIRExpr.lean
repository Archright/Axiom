/-
  Axiom Core IR — Lean 4 inductive representation.
  Mirrors src/core/trusted/axiom_ir.nim 1:1.
  Used by MetaCheckIR.lean for kernel type checking.
-/

namespace AxiomIR

-- IR Type System
inductive IRType where
  | bitVec64 : IRType
  | bool : IRType
  | list : IRType → IRType
  | string : IRType
  deriving BEq, Repr, Inhabited

-- Binary Operations
inductive BinOp where
  | add | sub | mul | div | rem
  | lt | le | gt | ge
  | and_ | or_ | eq | ltU
  deriving BEq, Repr, Inhabited

-- Unary Operations
inductive UnaryOp where
  | not_ | bvNot | bvNeg
  deriving BEq, Repr, Inhabited

-- Loop Kinds
inductive LoopKind where
  | for_ | while_
  deriving BEq, Repr, Inhabited

-- Mutual block: IRExpr and CaseBranch reference each other
mutual
  -- Case Branch
  structure CaseBranch where
    pattern : Int
    body : IRExpr

  -- IR Expression (mutual with CaseBranch)
  inductive IRExpr where
    | lit (val : Int) : IRExpr
    | floatLit (val : Float) : IRExpr
    | var_ (name : String) (typ : IRType) : IRExpr
    | letIn (name : String) (val : IRExpr) (body : IRExpr) (isCompileTime : Bool) : IRExpr
    | ifThenElse (cond : IRExpr) (thenE : IRExpr) (elseE : IRExpr) : IRExpr
    | case_ (scrutinee : IRExpr) (branches : List CaseBranch) (default_ : Option IRExpr) : IRExpr
    | call (name : String) (args : List IRExpr) : IRExpr
    | binOp (op : BinOp) (lhs : IRExpr) (rhs : IRExpr) : IRExpr
    | unaryOp (op : UnaryOp) (operand : IRExpr) : IRExpr
    | recCall (args : List IRExpr) : IRExpr
    | loop (kind : LoopKind) (vars : List String) (inits : List IRExpr) (cond : IRExpr) (step : Option IRExpr) (body : IRExpr) (invariants : List IRExpr) (variant_ : Option IRExpr) : IRExpr
    | stringLit (val : String) : IRExpr
    | cast (expr : IRExpr) (fromTy : IRType) (toTy : IRType) : IRExpr
end

-- Derive instances for mutual types outside the mutual block
deriving instance BEq for CaseBranch
deriving instance Repr for CaseBranch
deriving instance BEq for IRExpr
deriving instance Repr for IRExpr

-- Manual Inhabited instances for mutual types
instance : Inhabited CaseBranch where
  default := { pattern := 0, body := IRExpr.lit 0 }

instance : Inhabited IRExpr where
  default := IRExpr.lit 0

-- Function Parameter
structure IRFuncParam where
  name : String
  ty : IRType
  constraint : Option IRExpr := none
  deriving BEq, Repr, Inhabited

-- Function Definition
structure IRFuncDef where
  name : String
  params : List IRFuncParam
  retType : IRType
  body : IRExpr
  isRecursive : Bool
  preConditions : List IRExpr := []
  deriving BEq, Repr, Inhabited

-- SMT-LIB2 AST (structural, not string)
inductive SmtExpr where
  | const_ (name : String) : SmtExpr
  | app (op : String) (args : List SmtExpr) : SmtExpr
  | quantifier (kind : String) (vars : List (String × IRType)) (body : SmtExpr) : SmtExpr
  deriving BEq, Repr, Inhabited

-- ══════════════════════════════════════════════════════════════════════════════
-- Binary Codec — Deserialize IRExpr from 8-byte aligned wire format.
-- Symmetric with src/infrastructure/ir_binary_codec.nim
--
-- Wire format summary (all fields at 8-byte boundaries):
--   Tag:     1 byte tag + 7 padding = 8 bytes
--   UInt64:  8 bytes little-endian
--   Int64:   8 bytes little-endian (cast from UInt64)
--   Float64: 8 bytes little-endian (cast from UInt64 bits)
--   String:  UInt64 length + raw bytes + padding to 8-byte boundary
--   Seq:     UInt64 count + aligned elements
--
-- Tag encoding (from ir_binary_codec.nim):
--   0x00 = nil     0x01 = irLit      0x02 = irFloatLit  0x03 = irVar
--   0x04 = irLet   0x05 = irIf       0x06 = irCase      0x07 = irCall
--   0x08 = irBinOp 0x09 = irUnaryOp  0x0A = irRecCall   0x0B = irLoop
--   0x0C = irStringLit  0x0D = irCast  0x0E = irLet (isCompileTime=true, CLET)
--   0x0F = irLitU64 (8-byte LE direct uint64 — the u64-domain two-part
--          form; a value ≥ 2^63 travels ONLY under 0x0F, never reinterpreted
--          through the signed 0x01 tag. Payload < 2^63 → decode error:
--          the disjoint-domain invariant is enforced both directions.)
--
-- IRType tags:
--   0x00 = nil  0x01 = bitVec64  0x02 = bool  0x03 = list  0x04 = string
-- ══════════════════════════════════════════════════════════════════════════════

namespace BinaryCodec

-- ─── Alignment ───

def align8 (n : Nat) : Nat :=
  (n + 7) / 8 * 8

-- ─── Primitive read helpers ───
-- All return Option (value × newOffset). Offset is aligned before each read.

private def readUInt64Aligned (data : ByteArray) (offset : Nat) : Option (UInt64 × Nat) :=
  let base := align8 offset
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

private def readUInt32Aligned (data : ByteArray) (offset : Nat) : Option (UInt32 × Nat) :=
  let base := align8 offset
  if base + 8 > data.size then none
  else
    let s := data.extract base (base + 8)
    let val := (s.get! 0).toUInt32
           ||| ((s.get! 1).toUInt32 <<< 8)
           ||| ((s.get! 2).toUInt32 <<< 16)
           ||| ((s.get! 3).toUInt32 <<< 24)
    some (val, base + 8)

private def readInt64Aligned (data : ByteArray) (offset : Nat) : Option (Int × Nat) :=
  match readUInt64Aligned data offset with
  | some (u, off) => some ((Int64.ofUInt64 u).toInt, off)
  | none => none

private def readFloat64Aligned (data : ByteArray) (offset : Nat) : Option (Float × Nat) :=
  match readUInt64Aligned data offset with
  | some (u, off) => some (Float.ofBits u, off)
  | none => none

private def readTag (data : ByteArray) (offset : Nat) : Option (UInt8 × Nat) :=
  let base := align8 offset
  if base + 8 > data.size then none
  else some (data.get! base, base + 8)

private def readStringAligned (data : ByteArray) (offset : Nat) : Option (String × Nat) :=
  match readUInt64Aligned data offset with
  | none => none
  | some (lenU64, dataStart) =>
    let len := lenU64.toNat
    if dataStart + len > data.size then none
    else
      let s := data.extract dataStart (dataStart + len)
      let chars := (List.range len).map (fun i => Char.ofUInt8 (s.get! i))
      let newOffset := align8 (dataStart + len)
      some (String.ofList chars, newOffset)

-- ─── IRType deserialization (self-recursive for list element types) ───

private partial def readIRType (data : ByteArray) (offset : Nat) : Option (IRType × Nat) :=
  match readTag data offset with
  | none => none
  | some (tag, off) =>
    match tag with
    | 0x00 => some (IRType.bitVec64, off)   -- nil sentinel → Inhabited default
    | 0x01 => some (IRType.bitVec64, off)
    | 0x02 => some (IRType.bool, off)
    | 0x03 =>
      match readIRType data off with
      | some (elem, off2) => some (IRType.list elem, off2)
      | none => none
    | 0x04 => some (IRType.string, off)
    | _ => none

-- ─── Enum ordinal mappings ───
-- Must match the Nim enum ordinals used by ir_binary_codec.nim

private def binOpOfOrdinal (u : UInt64) : Option BinOp :=
  match u.toNat with
  | 0  => some BinOp.add
  | 1  => some BinOp.sub
  | 2  => some BinOp.mul
  | 3  => some BinOp.div
  | 4  => some BinOp.rem
  | 5  => some BinOp.lt
  | 6  => some BinOp.le
  | 7  => some BinOp.gt
  | 8  => some BinOp.ge
  | 9  => some BinOp.and_
  | 10 => some BinOp.or_
  | 11 => some BinOp.eq
  -- 16 = Nim BinOpKind boLtU (ir_binary_codec.nim wire ordinal). The 5..11
  -- arms are Lean-constructor ordinals, not Nim wire ordinals — pre-existing
  -- stale-table defect (documented, not repaired in this slice).
  | 16 => some BinOp.ltU
  | _  => none

private def unaryOpOfOrdinal (u : UInt64) : Option UnaryOp :=
  match u.toNat with
  | 0 => some UnaryOp.not_
  | 1 => some UnaryOp.bvNot
  | 2 => some UnaryOp.bvNeg
  | _ => none

private def loopKindOfOrdinal (u : UInt64) : Option LoopKind :=
  match u.toNat with
  | 0 => some LoopKind.for_
  | 1 => some LoopKind.while_
  | _ => none

-- ─── String list reading (standalone) ───

private partial def readStringList (data : ByteArray) (offset : Nat) : Option (List String × Nat) :=
  match readUInt64Aligned data offset with
  | none => none
  | some (countU64, afterCount) =>
    let count := countU64.toNat
    let rec go : Nat → Nat → List String → Option (List String × Nat)
      | 0, off, acc => some (acc.reverse, off)
      | n + 1, off, acc =>
        match readStringAligned data off with
        | some (s, off2) => go n off2 (s :: acc)
        | none => none
    go count afterCount []

-- ─── IRExpr deserialization (mutual recursion block) ───
-- Internal decode result: Option (Option IRExpr × Nat)
--   none           → error (malformed data or bounds violation)
--   some (none, _) → nil sentinel decoded (valid for Option IRExpr fields)
--   some (some e, _) → valid expression decoded

mutual
  -- Decode an IRExpr that must be non-nil.
  -- Returns none on nil sentinel or error.
  private partial def decodeNonNil (data : ByteArray) (offset : Nat) : Option (IRExpr × Nat) :=
    match decodeIRExprAt data offset with
    | some (some e, off) => some (e, off)
    | _ => none

  -- Read a single CaseBranch: Int64(pattern) + IRExpr(body)
  private partial def readCaseBranch (data : ByteArray) (offset : Nat) : Option (CaseBranch × Nat) :=
    match readInt64Aligned data offset with
    | none => none
    | some (pattern, off1) =>
      match decodeNonNil data off1 with
      | some (body, off2) => some ({ pattern := pattern, body := body }, off2)
      | none => none

  -- Read a sequence of CaseBranch (remaining count already consumed).
  private partial def readCaseBranchSeq (data : ByteArray) (remaining : Nat) (offset : Nat) : Option (List CaseBranch × Nat) :=
    match remaining with
    | 0 => some ([], offset)
    | n + 1 =>
      match readCaseBranch data offset with
      | some (br, off) =>
        match readCaseBranchSeq data n off with
        | some (rest, finalOff) => some (br :: rest, finalOff)
        | none => none
      | none => none

  -- Read a sequence of IRExpr (remaining count already consumed).
  private partial def readIRExprSeq (data : ByteArray) (remaining : Nat) (offset : Nat) : Option (List IRExpr × Nat) :=
    match remaining with
    | 0 => some ([], offset)
    | n + 1 =>
      match decodeIRExprAt data offset with
      | some (some e, off) =>
        match readIRExprSeq data n off with
        | some (rest, finalOff) => some (e :: rest, finalOff)
        | _ => none
      | _ => none

  -- Main recursive IRExpr decoder.
  -- Reads one complete IRExpr at `offset`, returning it wrapped in Option
  -- (none for nil sentinel, some for a real expression).
  private partial def decodeIRExprAt (data : ByteArray) (offset : Nat) : Option (Option IRExpr × Nat) :=
    match readTag data offset with
    | none => none
    | some (tag, off) =>
      match tag with
      -- 0x00 = nil sentinel
      | 0x00 => some (none, off)

      -- 0x01 = irLit → lit: Int64 (SIGNED domain only — values ≥ 2^63
      -- travel exclusively under the 0x0F irLitU64 tag; a 0x01 payload is
      -- the exact two's-complement int64 reading, by codec contract)
      | 0x01 =>
        match readInt64Aligned data off with
        | some (val, off2) => some (some (IRExpr.lit val), off2)
        | none => none

      -- 0x0F = irLitU64 → lit: UInt64 (the u64 domain [2^63, 2^64−1],
      -- byte-exact with ir_binary_codec.nim: 8-byte LE direct uint64).
      -- Payload < 2^63 violates the disjoint two-part domain → none
      -- (fail-closed — never a silent signed reinterpretation).
      | 0x0F =>
        match readUInt64Aligned data off with
        | some (val, off2) =>
          if val < 0x8000000000000000 then none
          else some (some (IRExpr.lit val.toNat), off2)
        | none => none

      -- 0x02 = irFloatLit → floatLit: Float64
      | 0x02 =>
        match readFloat64Aligned data off with
        | some (val, off2) => some (some (IRExpr.floatLit val), off2)
        | none => none

      -- 0x03 = irVar → var_: String(name) + IRType
      | 0x03 =>
        match readStringAligned data off with
        | none => none
        | some (name, off2) =>
          match readIRType data off2 with
          | some (ty, off3) => some (some (IRExpr.var_ name ty), off3)
          | none => none

      -- 0x04 = irLet (isCompileTime=false) → letIn: String(name) + IRExpr(val) + IRExpr(body) + Bool
      | 0x04 =>
        match readStringAligned data off with
        | none => none
        | some (name, off2) =>
          match decodeNonNil data off2 with
          | none => none
          | some (valExpr, off3) =>
            match decodeNonNil data off3 with
            | some (bodyExpr, off4) => some (some (IRExpr.letIn name valExpr bodyExpr false), off4)
            | none => none

      -- 0x0E = irLet (isCompileTime=true, CLET) → letIn: String(name) + IRExpr(val) + IRExpr(body) + Bool
      | 0x0E =>
        match readStringAligned data off with
        | none => none
        | some (name, off2) =>
          match decodeNonNil data off2 with
          | none => none
          | some (valExpr, off3) =>
            match decodeNonNil data off3 with
            | some (bodyExpr, off4) => some (some (IRExpr.letIn name valExpr bodyExpr true), off4)
            | none => none

      -- 0x05 = irIf → ifThenElse: IRExpr(cond) + IRExpr(then) + IRExpr(else)
      | 0x05 =>
        match decodeNonNil data off with
        | none => none
        | some (cond, off2) =>
          match decodeNonNil data off2 with
          | none => none
          | some (thenE, off3) =>
            match decodeNonNil data off3 with
            | some (elseE, off4) => some (some (IRExpr.ifThenElse cond thenE elseE), off4)
            | none => none

      -- 0x06 = irCase → case_:
      --   IRExpr(scrutinee) + UInt64(branchCount) + CaseBranch[count] + IRExpr(default)
      | 0x06 =>
        match decodeNonNil data off with
        | none => none
        | some (scrutinee, off2) =>
          match readUInt64Aligned data off2 with
          | none => none
          | some (branchCountU64, off3) =>
            match readCaseBranchSeq data branchCountU64.toNat off3 with
            | none => none
            | some (branches, off4) =>
              match decodeIRExprAt data off4 with
              | some (default_, off5) =>
                some (some (IRExpr.case_ scrutinee branches default_), off5)
              | none => none

      -- 0x07 = irCall → call: String(name) + UInt64(count) + IRExpr[count]
      | 0x07 =>
        match readStringAligned data off with
        | none => none
        | some (name, off2) =>
          match readUInt64Aligned data off2 with
          | none => none
          | some (countU64, off3) =>
            match readIRExprSeq data countU64.toNat off3 with
            | some (args, off4) => some (some (IRExpr.call name args), off4)
            | none => none

      -- 0x08 = irBinOp → binOp: UInt64(op) + IRExpr(lhs) + IRExpr(rhs)
      | 0x08 =>
        match readUInt64Aligned data off with
        | none => none
        | some (opU64, off2) =>
          match binOpOfOrdinal opU64 with
          | none => none
          | some op =>
            match decodeNonNil data off2 with
            | none => none
            | some (lhs, off3) =>
              match decodeNonNil data off3 with
              | some (rhs, off4) => some (some (IRExpr.binOp op lhs rhs), off4)
              | none => none

      -- 0x09 = irUnaryOp → unaryOp: UInt64(op) + IRExpr(operand)
      | 0x09 =>
        match readUInt64Aligned data off with
        | none => none
        | some (opU64, off2) =>
          match unaryOpOfOrdinal opU64 with
          | none => none
          | some op =>
            match decodeNonNil data off2 with
            | some (operand, off3) => some (some (IRExpr.unaryOp op operand), off3)
            | none => none

      -- 0x0A = irRecCall → recCall: UInt64(count) + IRExpr[count]
      | 0x0A =>
        match readUInt64Aligned data off with
        | none => none
        | some (countU64, off2) =>
          match readIRExprSeq data countU64.toNat off2 with
          | some (args, off3) => some (some (IRExpr.recCall args), off3)
          | none => none

      -- 0x0B = irLoop → loop:
      --   UInt64(loopKind) + StringSeq(vars) + IRExprSeq(inits)
      --   + IRExpr(cond) + IRExpr?(step) + IRExpr(body)
      --   + IRExprSeq(invariants) + IRExpr?(variant)
      | 0x0B =>
        match readUInt64Aligned data off with
        | none => none
        | some (lkU64, off2) =>
          match loopKindOfOrdinal lkU64 with
          | none => none
          | some kind =>
            match readStringList data off2 with
            | none => none
            | some (vars, off3) =>
              match readUInt64Aligned data off3 with
              | none => none
              | some (initCountU64, off4) =>
                match readIRExprSeq data initCountU64.toNat off4 with
                | none => none
                | some (inits, off5) =>
                  match decodeNonNil data off5 with
                  | none => none
                  | some (cond, off6) =>
                    match decodeIRExprAt data off6 with
                    | none => none
                    | some (step, off7) =>
                      match decodeNonNil data off7 with
                      | none => none
                      | some (body, off8) =>
                        match readUInt64Aligned data off8 with
                        | none => none
                        | some (invCountU64, off9) =>
                          match readIRExprSeq data invCountU64.toNat off9 with
                          | none => none
                          | some (invariants, off10) =>
                            match decodeIRExprAt data off10 with
                            | some (variant_, off11) =>
                              some (some (IRExpr.loop kind vars inits cond step body invariants variant_), off11)
                            | none => none

      -- 0x0C = irStringLit → stringLit: String(val)
      | 0x0C =>
        match readStringAligned data off with
        | some (val, off2) => some (some (IRExpr.stringLit val), off2)
        | none => none

      -- 0x0D = irCast → cast: IRExpr(expr) + IRType(fromTy) + IRType(toTy)
      -- Mirrors ir_binary_codec.nim: writeTag(0x0D) + serializeIRExprAligned(castExpr)
      --   + serializeIRTypeAligned(castFrom) + serializeIRTypeAligned(castTo)
      | 0x0D =>
        match decodeNonNil data off with
        | none => none
        | some (expr, off2) =>
          match readIRType data off2 with
          | none => none
          | some (fromTy, off3) =>
            match readIRType data off3 with
            | some (toTy, off4) => some (some (IRExpr.cast expr fromTy toTy), off4)
            | none => none

      -- Invalid tag → error
      | _ => none

end

end BinaryCodec

-- Public entry point
/-- Deserialize an IRExpr from a byte array in the 8-byte aligned wire format.
    Returns `none` on empty input, nil sentinel, or any validation failure
    (bounds violation, invalid tag, alignment error, missing fields, excess bytes).
    Exactly symmetric with `ir_binary_codec.nim` `deserializeIRExprAligned`. -/
def deserializeIRExpr (data : ByteArray) : Option IRExpr := do
  let (optExpr, _) ← BinaryCodec.decodeIRExprAt data 0
  optExpr

end AxiomIR
