import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## LLBC → shared Rust canonical PRODUCER (feat/rust-subject-v1).
##
## This is the missing link closed by this module: it parses a real Charon
## LLBC extraction (JSON, charon 0.1.281 measured — the probe
## axiom_rust_probe: add_u8 / add_u8_mutant / is_zero) and constructs
## `RustCanonical` values (src/core/trusted/rust_canonical.nim) for the
## CLOSED 11-kind grammar ONLY. Everything outside the closed grammar is
## REJECTED with an explicit error — never silently dropped, never widened:
##
##   accepted statement kinds  StorageLive, StorageDead, Assign, Return,
##                             Panic — plus Assert ONLY as the measured
##                             overflow check of the AddChecked collapse
##                             (see PendingAdd); a standalone Assert outside
##                             that pattern is rejected
##   accepted rvalue kinds     Use, BinaryOp — forms AddChecked and Eq ONLY
##   accepted operand kinds    Copy, Move (plain Local places; Move
##                             Projection only inside the AddChecked
##                             collapse), Const
##   accepted types            u8 (8, unsigned), u32 (32, unsigned),
##                             bool (1, unsigned) — via LLBC type interning
##                             {"Deduplicated": id} / {"Value": [id, ty]}
##
##   REJECTED (fail-closed)    every other statement kind (SwitchInt, Call,
##                             Loop, Drop, Abort, UnwindResume at body level,
##                             …), every other rvalue/operand kind, every
##                             other BinaryOp form, every other integer
##                             type/signedness, places with Projection outside
##                             the collapse pattern, generic/unsafe/variadic/
##                             non-Rust-ABI declarations, trait impl blocks and
##                             any Impl name-path kind other than a single
##                             InherentImplBlock (Q11), has_errors extractions,
##                             unresolvable interned ids.
##                             `rceUnsupportedGrammar` names the offending
##                             kind (→ eaUnsupported downstream);
##                             `rceMalformed` names the structural violation.
##
## FILE-TABLE PRE-VALIDATION (Phase 1-A input contract). BEFORE any
## consumption, `validateLlbcFileTable` enforces the files[] contract
## reject-not-skip (ids present/non-negative/unique; subject-crate entries
## sole-key `Local`, non-empty subject-relative POSIX paths without `..`/`.`
## /empty segments, unique paths, embedded `contents`; foreign-crate
## `contents` never read). A violation is a WHOLE-document
## `rceMalformed` failure with the reason prefix "LLBC files table
## pre-validation failed:" — stronger than (and prior to) any per-function
## span failure. The validated local file table (id + relPath + contents) is
## the value reused by the rust subject input contract
## (verification/rust_input_contract.nim); the subject crate is
## discriminated by `crate_name == translated.crate_name` (foreign-crate
## files also serialize under the `Local` tag, measured on the probe).
##
## THE MEASURED CHECKED-ADD COLLAPSE. In the measured (overflow-checked)
## build profile, Charon lowers `a + b` on u8 into FOUR statements:
##   Assign(T, BinaryOp(AddChecked, o1, o2))                  # T : (u8, bool)
##   Assert(Move(Projection(T, Field 1)) == false,
##          on_failure: Panic, check_kind: Overflow(Add, …))
##   Assign(D, Use(Move(Projection(T, Field 0))))             # value half
## The canonical collapses this into ONE statement
## `Assign(D, rrvAddChecked(o1, o2))` and records the Assert's
## `on_failure: Panic` as `failureMode = rfmPanicOnOverflowObserved` — a
## TOOL-LAYER observation, NOT a program-meaning claim (ADR-0030 D2). The
## collapse is strict: the Assert must IMMEDIATELY follow the tuple Assign
## and the Field-0 extraction must IMMEDIATELY follow the Assert; any other
## statement interleaved is rejected. Re-assignment of any emitted place is
## rejected (v1 places are SSA-fresh, measured probe shape).
##
## QUIRK NOTES (Charon 0.1.281 JSON serializer; the full docs/spec quirks
## entries are docs/spec/llbc_quirks.md Q1–Q12):
##   1. The constant operand serializes as "Const", not "Constant" (the
##      canonical enum is ropConstant); both spellings are accepted so a
##      serializer rename in either direction stays within the grammar.
##   2. Interning is document-order streaming: {"Value": [id, payload]}
##      defines, {"Deduplicated": id} references the latest definition.
##      Charon uses SEPARATE id spaces (types / constants / spans / layout
##      expressions) with overlapping ids — e.g. the probe's bool is TYPE
##      id 6 while const id 6 is the literal 1. Constants and types are
##      therefore collected into SEPARATE maps (payload JArray → constant
##      intern, payload JObject without "data" → type intern, with "data" →
##      span intern, ignored). Within the type map, layout-expression
##      payloads from type_decls can shadow type payloads; the measured
##      document defines type-space ids (4=u8, 5=(u8,bool), 6=bool) inside
##      fun_decls, i.e. AFTER type_decls, so the latest definition at
##      reference time is the type-space one. A payload that resolves to a
##      non-type shape fails closed at use with a naming reason.
##   3. Span interning: body/statement spans are {"Value": [id, {data: …}]}
##      while item spans are inline {"Untagged": {data: …}} — both shapes
##      are accepted; the data payload is identical.
##   4. Place projections: Charon's NonEmptyVec serializes a ONE-element
##      projection list as the element itself (an object) — the measured
##      collapse shapes are {"Projection": [base, {"Field": [null, F]}]}.
##      A one-element array form is also accepted; longer chains fail
##      closed (no multi-field projection is representable in v1).
##   5. (Q11) An inherent-impl method's item_meta.name carries the impl
##      block as a path ELEMENT — [Ident(crate), Ident(module),
##      {Impl: {Ty: {kind: "InherentImplBlock", skip_binder: <type ref>}}},
##      Ident(method)] — and the owner resolves through the SAME type intern
##      table (skip_binder {"Deduplicated": vid} → {"Adt": {"id": N}} →
##      type_decls[N].item_meta.name). A scalar owner (a primitive type,
##      not an Adt) has NO nominal path: the decl is unaddressable by
##      structured name and the enumeration skips it (never invented).
##   6. (Q12) Layout expressions live ONLY under the "layout" key and reuse
##      the {"Value": [id, payload]} form with ids that COLLIDE with the
##      type space — the collector never descends into a "layout" key
##      (measured: the impl-probe's u8 — type id 0 — is shadowed by a Dog
##      layout "Constant" at the same id; the earlier probe healed this only
##      by accident of document order).
##
## BOUNDARY HONESTY: a RustCanonical produced here is still only an
## extraction artifact. The AxiomTrustBoundary rows
## (src/core/trusted/trust_boundary.nim) stay `exists: false` until this
## producer is wired into a LIVE run (docs/spec/rust_certified_subset.md §2).

import std/[json, strutils, tables]
import core/axiom_pragmas
import core/crypto/hash_kernel
import core/trusted/rust_canonical
import core/types/results

type
  LlbcFile* = object
    ## parseLlbcFile outcome — `root` is a parsed LLBC document iff `ok`.
    ok*: bool
    root*: JsonNode
    reason*: string

  LlbcToCanonicalResult* = object
    ## Producer outcome for ONE function declaration. `error` REUSES the
    ## existing `RustCanonicalError` vocabulary (no new enum, no new gate,
    ## no new authority): rceNone iff ok; rceUnsupportedGrammar = a node/
    ## type/operation outside the closed grammar (→ eaUnsupported
    ## downstream); rceMalformed = structural violation of the measured
    ## shape. `reason` names the offending node.
    ok*: bool
    canonical*: RustCanonical
    error*: RustCanonicalError
    reason*: string

  Err = tuple[err: RustCanonicalError, reason: string]

  LlbcInternTables = object
    ## Document-order streaming interning (see QUIRK NOTE 2).
    types: Table[int, JsonNode]
    consts: Table[int, tuple[kind: JsonNode, ty: JsonNode]]

  LlbcDeclCtx = object
    interns: LlbcInternTables
    files: seq[tuple[id: int, name: string]]
    typeDecls: JsonNode
      ## translated.type_decls (the Adt registry — owner resolution for the
      ## structured names; the array INDEX is the Adt id, cross-checked
      ## against the entry's own def_id, Q11)
    ownerTypes: Table[int, JsonNode]
      ## (Q11) The impl-OWNER type definitions, collected from
      ## translated.item_names ONLY — the name-path intern list serialized
      ## before type_decls/fun_decls, whose Value pairs are the FIRST
      ## serialization of the owner types. The general intern table is NOT
      ## usable here: Adt.generics.trait_refs payloads ({"kind": …}) reuse
      ## the Value form with ids that collide with the type space (measured:
      ## the impl-probe's Adt ids 1/2 are shadowed by Sized/MetaSized
      ## trait-ref payloads inside fun_decls locals) — see Q12.

  LlbcFileTableEntry* = object
    ## One VALIDATED subject-crate entry of `translated.files[]` — the
    ## measured charon 0.1.281 shape: local crate entries embed the full
    ## source text (`contents` byte-identical to disk, measured sha256
    ## match). LLBC carries NO hash fields — content identity comes only
    ## from hashing `contents` at contract time.
    id*: int              ## entry id — the span `file_id` key
    relPath*: string      ## subject-relative POSIX path (`name.Local`)
    contents*: string     ## embedded full source text (never null/missing)

  LlbcEmbeddedEntry* = object
    ## One VALIDATED subject-crate files[] entry whose name.Local is an
    ## ABSOLUTE path with embedded contents — §6d `embeddedContentAttested`:
    ## content-attested ONLY (the text rustc read at translation time; charon
    ## applies no path/crate filter to contents). NO generation-provenance
    ## claim: charon's FileName has no "generated" variant (Virtual/Local/
    ## NotReal — measured pin 79801650), so an absolute Local path evidences
    ## only "outside the extraction cwd". Not a subject source: excluded from
    ## the disk-set equivalence, never registered in buildDeclCtx (span
    ## resolution for its id stays fail-closed).
    index*: int            ## files[] array position (== FileId: charon's
                           ## IndexVec push_with assigns sequential ids)
    rawPath*: string       ## the verbatim absolute path — IN-MEMORY ONLY
                           ## (D3: run-relative, never recorded in any sidecar
                           ## or identity field; used for the duplicate check)
    crateName*: string     ## the entry's crate_name (== subject crate by the
                           ## classification rule)
    contentSha256*: string ## sha256Hex of the embedded contents string

  LlbcFileTableResult* = object
    ## validateLlbcFileTable outcome — the distinct input-contract error for
    ## the file table (a WHOLE-document failure, stronger than a per-function
    ## span failure). `ok` iff every files[] rule held; `reason` names the
    ## violated rule and the offending entry, "" iff ok.
    ok*: bool
    entries*: seq[LlbcFileTableEntry]  ## subject-crate entries, document order
    embedded*: seq[LlbcEmbeddedEntry]
      ## the §6d embeddedContentAttested entries, document order (empty when
      ## none)
    reason*: string
    rejection*: RustFileTableRejection
      ## the FIRST entry-level violation's structured producer facts
      ## (`rule == ""` for document-level failures and for ok — entry-level
      ## facts do not exist there). Verdict and reason are UNCHANGED by this
      ## record: it is the §6c v2 production-time rejection binding.

  RustFileTableRejection* = object
    ## Producer-owned structured facts about the FIRST files-table rule
    ## violation, captured at the validator's own violation point (§6c v2,
    ## productization_contract.md). Pure measurement exposure of what the
    ## validator already knows when it builds the reason string — the
    ## rejection verdict and reason text are unchanged. `rawPath` is
    ## run-relative location data: it may ONLY live in the §6c sidecar's
    ## binding section, never inside a compared identity field or a payload.
    rule*: string           ## stable rule tag; "" = no structured rejection
    index*: int             ## offending files[] index
    crateName*: string      ## offending entry crate_name, "" when absent
    rawPath*: string        ## offending name.Local verbatim, "" when absent
    contentSha256*: string  ## sha256 of the entry's embedded contents, ""
                            ## when absent or not a string

  PendingAdd = object
    ## Checked-add collapse state machine (see module docstring).
    active: bool         # tuple Assign consumed — Assert must come next
    assertSeen: bool     # Assert consumed — Field-0 extraction must come next
    tupleLocal: int
    op1, op2: RustOperand

  StmtWalker = object
    ## Walking state for one function body (explicit, no closures over var).
    localNames: Table[int, string]
    interns: LlbcInternTables
    c: RustCanonical
    pending: PendingAdd
    assigned: seq[string]

# ---------------------------------------------------------------------------
# raise-free JsonNode accessors — nil-guarded everywhere; never index or
# take a case-branch field of a node without checking its kind first
# ---------------------------------------------------------------------------

func jField(n: JsonNode; key: string): JsonNode {.inline.} =
  if n.isNil or n.kind != JObject: return nil
  n.fields.getOrDefault(key)

func jAt(n: JsonNode; i: int): JsonNode {.inline.} =
  if n.isNil or n.kind != JArray: return nil
  if i < 0 or i >= n.elems.len: return nil
  n.elems[i]

func jStr(n: JsonNode; default: string = ""): string {.inline.} =
  if n.isNil or n.kind != JString: default else: n.str

func jIdx(n: JsonNode): int {.inline.} =
  ## JInt payload as index/id; -1 signals "not an integer" (never a valid
  ## LLBC local index or intern id).
  if n.isNil or n.kind != JInt: -1 else: n.num.int

func isBool(n: JsonNode; v: bool): bool {.inline.} =
  not n.isNil and n.kind == JBool and n.bval == v

func soleKey(n: JsonNode): string =
  ## The single key of a tagged-union JSON object; "" when not exactly one.
  if n.isNil or n.kind != JObject or n.fields.len != 1: return ""
  for k, _ in n.fields:
    return k
  ""

func okErr(): Err {.inline.} = (rceNone, "")
func unsupported(reason: string): Err {.inline.} = (rceUnsupportedGrammar, reason)
func malformed(reason: string): Err {.inline.} = (rceMalformed, reason)

func shapeName(n: JsonNode): string =
  ## Compact shape descriptor for rejection reasons — names the offender
  ## without dumping the payload.
  if n.isNil: "absent"
  else:
    case n.kind
    of JObject: "'" & soleKey(n) & "'"
    of JString: "'" & n.str & "'"
    of JArray: "array"
    of JInt: "integer " & $n.num
    of JFloat: "float"
    of JBool: "bool"
    of JNull: "null"

# ---------------------------------------------------------------------------
# document-order intern collection (QUIRK NOTE 2)
# ---------------------------------------------------------------------------

func looksLikeTyPayload(payload: JsonNode): bool =
  ## The LLBC Value/Deduplicated id space is SHARED across interned entity
  ## kinds in charon 0.1.281 (measured on the serde_json extraction: Ty id 83
  ## = Bool and TraitRef id 83 both serialize as {"Value": [83, …]}). A type
  ## intern is registered ONLY from a payload whose single tag is a Ty
  ## variant — the shape discriminator that keeps TraitRef/Span/other
  ## entities from shadowing the type table ("latest wins" is safe only
  ## WITHIN the Ty space).
  if payload.isNil or payload.kind != JObject or payload.fields.len != 1:
    return false
  for k, _ in payload.fields:
    return k in ["Scalar", "Adt", "TypeVar", "Literal", "Never", "Ref",
                 "RawPtr", "TraitType", "DynTrait", "Arrow", "Error"]
  false

func collectInterns(n: JsonNode; t: var LlbcInternTables) =
  ## Register every {"Value": [id, payload]} definition in document order:
  ##   payload JArray               → constant intern  ([kindExpr, tyRef])
  ##   payload JObject with "data"  → span intern (ignored)
  ##   other payload JObject        → type intern
  ## Latest definition wins. The "layout" key is NEVER descended into (Q12):
  ## layout expressions are a SEPARATE id space serialized in the same
  ## Value/Deduplicated form, and conflating them shadows real type and
  ## constant definitions (measured: the impl-probe's u8 — type id 0 — is
  ## shadowed by a Dog layout "Constant" at the same id).
  if n.isNil: return
  case n.kind
  of JObject:
    if n.fields.len == 1 and n.fields.hasKey("Value"):
      let v = jField(n, "Value")
      if v.kind == JArray and v.elems.len == 2 and v.elems[0].kind == JInt:
        let id = v.elems[0].num.int
        let payload = v.elems[1]
        if payload.kind == JArray and payload.elems.len == 2:
          t.consts[id] = (payload.elems[0], payload.elems[1])
        elif payload.kind == JObject and looksLikeTyPayload(payload):
          t.types[id] = payload
    for k, _ in n.fields:
      if k == "layout":
        continue
      collectInterns(jField(n, k), t)
  of JArray:
    for i in 0 ..< n.elems.len:
      collectInterns(n.elems[i], t)
  else:
    discard

# ---------------------------------------------------------------------------
# type resolution — the closed v1 type set ONLY
# ---------------------------------------------------------------------------

func decodeTypePayload(payload: JsonNode): tuple[e: Err, ty: RustType] =
  ## Closed set: {"Scalar": {"Integer": {"Unsigned": "U8"|"U32"|"U64"}}} and
  ## {"Scalar": "Bool"} (measured bool shape). U64 is the v1.2 full-domain
  ## row (usize on the pinned x86_64 target) — params/returns/constants are
  ## admitted over [0, 2^64−1] and plain '+' is admitted where the no-overflow
  ## obligation `lhs+rhs ≤ 18446744073709551615` is discharged (§1 v1.2).
  ## Everything else → unsupported, naming the offending shape.
  if payload.isNil or payload.kind != JObject:
    return (unsupported("type shape " & shapeName(payload) &
      " outside the closed v1 set (u8/u32/u64/bool only)"), rustU8Type())
  let scalar = jField(payload, "Scalar")
  if scalar.isNil:
    return (unsupported("type shape " & shapeName(payload) &
      " outside the closed v1 set (u8/u32/u64/bool only)"), rustU8Type())
  if scalar.kind == JString:
    if scalar.str == "Bool":
      return (okErr(), rustBoolType())
    return (unsupported("scalar type '" & scalar.str &
      "' outside the closed v1 set"), rustU8Type())
  let integer = jField(scalar, "Integer")
  if integer.isNil or integer.kind != JObject:
    return (unsupported("scalar shape " & shapeName(scalar) &
      " outside the closed v1 set"), rustU8Type())
  let unsigned = jField(integer, "Unsigned")
  if unsigned.isNil or unsigned.kind != JString:
    return (unsupported("integer scalar " & shapeName(integer) &
      " outside the closed v1 set (unsigned u8/u32/u64 only)"), rustU8Type())
  case unsigned.str
  of "U8": (okErr(), rustU8Type())
  of "U32": (okErr(), rustU32Type())
  of "U64": (okErr(), rustU64Type())
  else:
    (unsupported("integer type '" & unsigned.str &
      "' outside the closed v1 set (u8/u32/u64 only)"), rustU8Type())

func decodeTypeRef(tref: JsonNode; interns: LlbcInternTables):
    tuple[e: Err, ty: RustType] =
  ## A type REFERENCE: inline definition {"Value": [id, payload]} or
  ## interned {"Deduplicated": id}. Unresolvable id → malformed (fail-closed).
  if tref.isNil:
    return (malformed("missing type reference"), rustU8Type())
  if tref.kind == JObject and tref.fields.len == 1 and
      tref.fields.hasKey("Deduplicated"):
    let id = jIdx(jField(tref, "Deduplicated"))
    if id < 0:
      return (malformed("malformed Deduplicated type id " &
        shapeName(jField(tref, "Deduplicated"))), rustU8Type())
    let payloadNode = interns.types.getOrDefault(id)
    if payloadNode.isNil:
      return (malformed("unresolved interned type id " & $id &
        " (no prior {\"Value\": [id, ty]} definition)"), rustU8Type())
    return decodeTypePayload(payloadNode)
  if tref.kind == JObject and tref.fields.len == 1 and
      tref.fields.hasKey("Value"):
    let v = jField(tref, "Value")
    if v.kind == JArray and v.elems.len == 2:
      return decodeTypePayload(v.elems[1])
    return (malformed("malformed inline type reference " & shapeName(v)),
            rustU8Type())
  # A bare type payload where a reference was expected — decode it directly
  # (tolerates inline types without interning), still closed-set only.
  decodeTypePayload(tref)

# ---------------------------------------------------------------------------
# operand decoding — Copy / Move / Const ONLY. The collapse pattern's
# Move-Projection shapes are matched structurally by matchMoveProjField
# before decodeOperand is consulted.
# ---------------------------------------------------------------------------

func parseUintText(s: string): Result[uint64, string] =
  ## ASCII decimal → uint64 over the FULL u64 domain [0, 2^64−1]. Errors are
  ## value-space-separated (Result — the -1 sentinel is retired): the 20-digit
  ## cap bounds the input, the accumulator refuses overflow past uint64.high
  ## (any literal > 2^64−1), and the caller range-checks against the resolved
  ## type width (`value ≥ 2^width` → malformed).
  if s.len == 0:
    return err("empty integer literal '" & s & "'")
  if s.len > 20:
    return err("integer literal exceeds the 20-digit cap: '" & s & "'")
  var acc: uint64 = 0
  for ch in s:
    if ch < '0' or ch > '9':
      return err("malformed integer literal '" & s & "'")
    let d = uint64(ch.ord - '0'.ord)
    if acc > (high(uint64) - d) div 10:
      return err("integer literal exceeds u64 range: '" & s & "'")
    acc = acc * 10 + d
  ok(acc)

func decodeConstOperand(payload: JsonNode; interns: LlbcInternTables):
    tuple[e: Err, op: RustOperand] =
  ## {"Value": [id, [kindExpr, tyRef]]} or {"Deduplicated": id} →
  ## ropConstant. Accepted kinds: {"Integer": {"Unsigned":
  ## ["U8"|"U32"|"U64", "<decimal>"]}} and {"Bool": true|false}. The literal
  ## must be within the resolved type's range (`value ≥ 2^width` → malformed,
  ## full u64 range check included); type/width mismatch → malformed.
  ## Literals ≥ 2^63 travel in the u64-domain representation (`valueU64`) —
  ## never reinterpreted into the signed `value`.
  let bad = RustOperand(kind: ropConstant, value: 0, ty: rustU8Type())
  var kindExpr, tyRef: JsonNode
  if payload.kind == JObject and payload.fields.len == 1 and
      payload.fields.hasKey("Deduplicated"):
    let id = jIdx(jField(payload, "Deduplicated"))
    if id < 0:
      return (malformed("malformed Deduplicated constant id"), bad)
    let entry = interns.consts.getOrDefault(id)
    if entry.kind.isNil:
      return (malformed("unresolved interned constant id " & $id), bad)
    kindExpr = entry.kind
    tyRef = entry.ty
  elif payload.kind == JObject and payload.fields.len == 1 and
      payload.fields.hasKey("Value"):
    let v = jField(payload, "Value")
    if v.kind != JArray or v.elems.len != 2 or
        v.elems[1].kind != JArray or v.elems[1].elems.len != 2:
      return (malformed("malformed constant payload " & shapeName(v)), bad)
    kindExpr = v.elems[1].elems[0]
    tyRef = v.elems[1].elems[1]
  else:
    return (malformed("constant operand shape " & shapeName(payload)), bad)
  let (tyErr, ty) = decodeTypeRef(tyRef, interns)
  if tyErr.err != rceNone:
    return (tyErr, bad)
  if kindExpr.isNil or kindExpr.kind != JObject or kindExpr.fields.len != 1:
    return (malformed("constant kind shape " & shapeName(kindExpr)), bad)
  let integer = jField(kindExpr, "Integer")
  if not integer.isNil:
    if integer.isNil or integer.kind != JObject or integer.fields.len != 1:
      return (malformed("integer constant shape " & shapeName(integer)), bad)
    let unsigned = jField(integer, "Unsigned")
    if unsigned.isNil or unsigned.kind != JArray or unsigned.elems.len != 2:
      return (malformed("integer constant shape " & shapeName(unsigned) &
        " (expected [ty, literal])"), bad)
    let tyTag = jStr(unsigned.elems[0], "")
    let parsed = parseUintText(jStr(unsigned.elems[1], ""))
    if parsed.isErr:
      return (malformed(parsed.error), bad)
    let value = parsed.get
    if tyTag != "U8" and tyTag != "U32" and tyTag != "U64":
      return (unsupported("integer constant type '" & tyTag &
        "' outside the closed v1 set (u8/u32/u64 only)"), bad)
    let width: int = if tyTag == "U8": 8 elif tyTag == "U64": 64 else: 32
    if ty.kind != rtyInt or ty.widthBits != width or
        ty.signedness != rsgUnsigned:
      return (malformed("integer constant typed " & tyTag &
        " but its interned type is not u" & $width), bad)
    let inRange = case width
                  of 8: value < 256'u64
                  of 32: value < 4294967296'u64
                  else: true  # width 64 — the FULL u64 domain [0, 2^64−1]
    if not inRange:
      return (malformed("integer constant " & $value &
        " out of range for u" & $width), bad)
    if value >= u64DomainLow:
      return (okErr(), RustOperand(kind: ropConstant, valueU64: value, ty: ty))
    return (okErr(), RustOperand(kind: ropConstant,
      value: cast[int64](value), ty: ty))
  let b = jField(kindExpr, "Bool")
  if not b.isNil:
    if not isBool(b, true) and not isBool(b, false):
      return (malformed("bool constant shape " & shapeName(b)), bad)
    if ty.kind != rtyBool:
      return (malformed("bool constant with non-bool interned type"), bad)
    let value: int64 = if b.bval: 1 else: 0
    return (okErr(), RustOperand(kind: ropConstant, value: value, ty: ty))
  (unsupported("constant kind " & shapeName(kindExpr) &
    " outside the closed v1 set (integer/bool literals only)"), bad)

func matchMoveProjField(op: JsonNode; tupleLocal, fieldIdx: int): bool =
  ## Structural matcher for the collapse pattern's operands:
  ## {"Move": {"kind": {"Projection": [{"kind": {"Local": T}, …},
  ##                                   {"Field": [null, F]}]}, …}}
  ## QUIRK NOTE: Charon's NonEmptyVec serializes a ONE-element projection
  ## list as the element itself (an object), not as an array — the measured
  ## shape. A one-element array is also accepted; anything else fails.
  func oneField(elem: JsonNode): bool =
    if elem.isNil or soleKey(elem) != "Field": return false
    let field = jField(elem, "Field")
    if field.kind != JArray or field.elems.len != 2: return false
    field.elems[0].kind == JNull and jIdx(field.elems[1]) == fieldIdx
  if op.isNil or op.kind != JObject or op.fields.len != 1: return false
  if not op.fields.hasKey("Move"): return false
  let mv = jField(op, "Move")
  if mv.isNil or mv.kind != JObject: return false
  let placeKind = jField(mv, "kind")
  if placeKind.isNil or placeKind.kind != JObject or
      placeKind.fields.len != 1 or not placeKind.fields.hasKey("Projection"):
    return false
  let proj = jField(placeKind, "Projection")
  if proj.kind != JArray or proj.elems.len != 2: return false
  let baseKind = jField(proj.elems[0], "kind")
  let baseLocal = jField(baseKind, "Local")
  if baseKind.isNil or baseKind.kind != JObject or
      baseKind.fields.len != 1 or baseLocal.isNil:
    return false
  if jIdx(baseLocal) != tupleLocal: return false
  let projections = proj.elems[1]
  if projections.kind == JObject:
    # NonEmptyVec single-element form (measured)
    oneField(projections)
  elif projections.kind == JArray and projections.elems.len == 1:
    oneField(projections.elems[0])
  else:
    false

func plainPlace(place: JsonNode; localNames: Table[int, string]):
    tuple[e: Err, name: string] =
  ## A place whose kind is exactly {"Local": n} → its canonical name
  ## (source name for named locals, `_N` LLBC shape for anonymous ones).
  ## Projection/deref/index places outside the collapse pattern → unsupported.
  if place.isNil or place.kind != JObject:
    return (malformed("malformed place " & shapeName(place)), "")
  let kindNode = jField(place, "kind")
  if kindNode.isNil or kindNode.kind != JObject or kindNode.fields.len != 1:
    return (malformed("malformed place kind " & shapeName(kindNode)), "")
  if not kindNode.fields.hasKey("Local"):
    return (unsupported("place kind " & shapeName(kindNode) &
      " outside the closed v1 grammar (plain locals only outside the " &
      "checked-add pattern)"), "")
  let idx = jIdx(jField(kindNode, "Local"))
  let name = localNames.getOrDefault(idx, "")
  if idx < 0 or name.len == 0:
    return (malformed("reference to unknown local index " & $idx), "")
  (okErr(), name)

func decodeOperand(op: JsonNode; localNames: Table[int, string];
                   interns: LlbcInternTables): tuple[e: Err, o: RustOperand] =
  ## Copy / Move (plain Local) / Const operands ONLY.
  let bad = RustOperand(kind: ropCopy, place: "")
  if op.isNil or op.kind != JObject or op.fields.len != 1:
    return (malformed("malformed operand " & shapeName(op)), bad)
  let key = soleKey(op)
  let operandPayload = jField(op, key)
  case key
  of "Copy", "Move":
    let (e, name) = plainPlace(operandPayload, localNames)
    if e.err != rceNone: return (e, bad)
    if key == "Copy":
      (okErr(), RustOperand(kind: ropCopy, place: name))
    else:
      (okErr(), RustOperand(kind: ropMove, place: name))
  of "Const", "Constant":
    decodeConstOperand(operandPayload, interns)
  else:
    (unsupported("operand kind '" & key &
      "' outside the closed v1 grammar (Copy/Move/Const only)"), bad)

# ---------------------------------------------------------------------------
# function-level decoding
# ---------------------------------------------------------------------------

func decodeNamePath(name: JsonNode):
    tuple[e: Err, modulePath, funcName: string] =
  ## item_meta.name: [{Ident: [seg, disambiguator}, …] with at most ONE
  ## {Impl: {Ty: {kind: "InherentImplBlock", …}}} element (Q11). The LAST
  ## segment is the function name; the Ident segments BEFORE it joined with
  ## `::` are the module path (for an impl method: the impl block's own
  ## module — the canonical records the DECL's measured module and method
  ## names; the owner participates in the STRUCTURED match key only, see
  ## llbcFunDeclNamePaths). A non-InherentImplBlock Impl kind (trait impl
  ## blocks), more than one Impl element, an Impl element as the LAST
  ## element (no method name), and any other path element (Builtin, …) →
  ## unsupported.
  if name.isNil or name.kind != JArray or name.elems.len < 2:
    return (malformed("item_meta.name must be an Ident path of length >= 2"),
            "", "")
  var segs: seq[string] = @[]
  var implCount = 0
  for i in 0 ..< name.elems.len:
    let elem = name.elems[i]
    let key = soleKey(elem)
    if key == "Impl":
      inc implCount
      if implCount > 1:
        return (unsupported("name path with more than one Impl element " &
          "outside the closed v1 grammar (a single inherent impl block only)"),
          "", "")
      if i == name.elems.len - 1:
        return (malformed("name path ending with an Impl element (no method " &
          "name)"), "", "")
      let ty = jField(jField(elem, "Impl"), "Ty")
      if ty.isNil or ty.kind != JObject:
        return (malformed("Impl path element without a Ty object"), "", "")
      let implKind = jStr(jField(ty, "kind"), "")
      if implKind != "InherentImplBlock":
        return (unsupported("impl block kind '" & implKind &
          "' outside the closed v1 grammar (InherentImplBlock only)"), "", "")
      continue
    if key != "Ident":
      return (unsupported("name path element " & shapeName(elem) &
        " outside the closed v1 grammar (Ident paths with at most one " &
        "inherent Impl block)"), "", "")
    let ident = jField(elem, "Ident")
    if ident.kind != JArray or ident.elems.len != 2 or
        ident.elems[0].kind != JString or ident.elems[0].str.len == 0:
      return (malformed("malformed Ident path element"), "", "")
    segs.add(ident.elems[0].str)
  if segs.len < 2:
    return (malformed("item_meta.name must carry a module segment and a " &
      "function name"), "", "")
  (okErr(), segs[0 ..< segs.len - 1].join("::"), segs[segs.len - 1])

# ---------------------------------------------------------------------------
# structured names (Q11) — the ADDRESSABLE identity of a fun_decl
# ---------------------------------------------------------------------------

func implOwnerNominalPath(implElem: JsonNode; ctx: LlbcDeclCtx):
    tuple[e: Err, ownerPath: string] =
  ## (Q11) The inherent-impl block's OWNER type as a nominal path: the
  ## Impl element's Ty.skip_binder type reference resolves through the SAME
  ## type intern table as signature types ({"Deduplicated": vid} → the
  ## table's {"Value": [vid, payload]} definition), the payload must be an
  ## Adt, and type_decls[Adt.id].item_meta.name (cross-checked: def_id ==
  ## array index, measured on every document) is the owner's Ident path.
  ## A primitive/scalar owner has no nominal path → unsupported
  ## (unaddressable — never invented as "<impl u8>" or similar).
  let impl = jField(implElem, "Impl")
  let ty = jField(impl, "Ty")
  if ty.isNil or ty.kind != JObject:
    return (malformed("Impl path element without a Ty object"), "")
  let implKind = jStr(jField(ty, "kind"), "")
  if implKind != "InherentImplBlock":
    return (unsupported("impl block kind '" & implKind &
      "' outside the closed v1 grammar (InherentImplBlock only)"), "")
  let sb = jField(ty, "skip_binder")
  var payload: JsonNode = nil
  if not sb.isNil and sb.kind == JObject and sb.fields.len == 1:
    if sb.fields.hasKey("Deduplicated"):
      let vid = jIdx(jField(sb, "Deduplicated"))
      if vid < 0:
        return (malformed("malformed Deduplicated owner type id"), "")
      payload = ctx.ownerTypes.getOrDefault(vid)
      if payload.isNil:
        return (malformed("unresolved impl-owner type id " & $vid &
          " (no item_names definition — Q11)"), "")
    elif sb.fields.hasKey("Value"):
      let v = jField(sb, "Value")
      if not v.isNil and v.kind == JArray and v.elems.len == 2:
        payload = v.elems[1]
  if payload.isNil or payload.kind != JObject:
    return (unsupported("impl owner type reference shape " & shapeName(sb) &
      " (a Deduplicated/Value type reference is required)"), "")
  let adt = jField(payload, "Adt")
  if adt.isNil or adt.kind != JObject:
    return (unsupported("impl owner type payload " & shapeName(payload) &
      " is not an Adt (primitive/scalar owners have no nominal path — " &
      "unaddressable, fail-closed)"), "")
  let adtId = jIdx(jField(adt, "id"))
  if adtId < 0:
    return (malformed("malformed Adt id in the impl owner type"), "")
  let tds = ctx.typeDecls
  if tds.isNil or tds.kind != JArray or adtId >= tds.elems.len:
    return (malformed("impl owner Adt id " & $adtId &
      " outside the type_decls range"), "")
  let td = tds.elems[adtId]
  if td.isNil or td.kind != JObject:
    return (malformed("type_decls[" & $adtId & "] is not an object"), "")
  let defId = jIdx(jField(td, "def_id"))
  if defId >= 0 and defId != adtId:
    return (malformed("type_decls[" & $adtId & "] carries def_id " & $defId &
      " != its array index (Q11 pin violated)"), "")
  let (oe, ownerModule, ownerLast) =
      decodeNamePath(jField(jField(td, "item_meta"), "name"))
  if oe.err != rceNone:
    return (oe, "")
  (okErr(), ownerModule & "::" & ownerLast)

func funDeclStructuredName(ctx: LlbcDeclCtx; fd: JsonNode):
    tuple[ok: bool, fullName: string] =
  ## (Q11/DEBT#510) The decl's structured match key — the addressable name
  ## `llbcFunDeclNamePaths` exposes and `llbcFunctionToCanonical` binds
  ## exactly:
  ##   - an all-Ident path: segments joined with "::" (the free-function
  ##     full name, unchanged);
  ##   - ONE InherentImplBlock Impl element at the PENULTIMATE position
  ##     (the measured shape): the owner's nominal Adt path + "::" + method
  ##     name — Rust's one-definition rule makes (owner, method) unique per
  ##     crate. The impl block's own module is NOT part of the key (it is
  ##     the canonical's modulePath — the decl's measured module).
  ## Any unresolvable shape (trait impl block, scalar owner, non-Ident
  ## element, Impl not penultimate, more than one Impl) → ok=false: the
  ## decl is UNADDRESSABLE, the enumeration skips it, and the producer's
  ## last-segment fallback still sees it (never silently dropped).
  let name = jField(jField(fd, "item_meta"), "name")
  if name.isNil or name.kind != JArray or name.elems.len == 0:
    return (false, "")
  var parts: seq[string] = @[]
  var implOwner = ""
  var implSeen = false
  for i in 0 ..< name.elems.len:
    let elem = name.elems[i]
    let key = soleKey(elem)
    if key == "Ident":
      let ident = jField(elem, "Ident")
      if ident.isNil or ident.kind != JArray or ident.elems.len != 2 or
          ident.elems[0].isNil or ident.elems[0].kind != JString or
          ident.elems[0].str.len == 0:
        return (false, "")
      parts.add(ident.elems[0].str)
    elif key == "Impl":
      if implSeen or i != name.elems.len - 2:
        return (false, "")
      implSeen = true
      let (oe, owner) = implOwnerNominalPath(elem, ctx)
      if oe.err != rceNone:
        return (false, "")
      implOwner = owner
    else:
      return (false, "")
  if parts.len == 0:
    return (false, "")
  if implSeen:
    return (true, implOwner & "::" & parts[parts.len - 1])
  (true, parts.join("::"))

func decodeSourceIdentity(span: JsonNode; ctx: LlbcDeclCtx):
    tuple[e: Err, identity: string] =
  ## item_meta.span → "file:begLine:begCol-endLine:endCol" over the crate's
  ## files table (property 5 provenance). Accepted span shapes:
  ## {"Untagged": {data: …}} (inline, measured on item_meta) and
  ## {"Value": [id, {data: …}]} (interned).
  if span.isNil or span.kind != JObject:
    return (malformed("missing item span"), "")
  var inner = span
  let vInner = jField(span, "Value")
  let untagged = jField(span, "Untagged")
  if not vInner.isNil:
    if vInner.kind != JArray or vInner.elems.len != 2:
      return (malformed("malformed interned span"), "")
    inner = vInner.elems[1]
  elif not untagged.isNil:
    inner = untagged
  let data = jField(inner, "data")
  if data.isNil:
    return (unsupported("span shape " & shapeName(span) &
      " outside the measured shapes (Untagged / Value-interned)"), "")
  let fileId = jIdx(jField(data, "file_id"))
  if fileId < 0:
    return (malformed("span without integer file_id"), "")
  var fileName = ""
  var found = false
  for f in ctx.files:
    if f.id == fileId:
      fileName = f.name
      found = true
  if not found or fileName.len == 0:
    return (malformed("span file_id " & $fileId &
      " not resolvable to a Local file name"), "")
  let bl = jIdx(jField(jField(data, "beg"), "line"))
  let bc = jIdx(jField(jField(data, "beg"), "col"))
  let el = jIdx(jField(jField(data, "end"), "line"))
  let ec = jIdx(jField(jField(data, "end"), "col"))
  if bl < 0 or bc < 0 or el < 0 or ec < 0:
    return (malformed("span beg/end without integer line/col"), "")
  (okErr(), fileName & ":" & $bl & ":" & $bc & "-" & $el & ":" & $ec)

func requireSignatureShape(sig: JsonNode): Err =
  ## Closed v1 declarations: safe, non-variadic, Rust ABI, monomorphic.
  if sig.isNil or sig.kind != JObject:
    return malformed("missing function signature")
  if not isBool(jField(sig, "is_unsafe"), false):
    return unsupported("unsafe function (or missing is_unsafe) outside " &
      "the closed v1 grammar")
  if jField(sig, "abi").isNil:
    return malformed("signature without abi")
  if jStr(jField(sig, "abi")) != "Rust":
    return unsupported("non-Rust ABI '" & jStr(jField(sig, "abi")) &
      "' outside the measured v1 surface")
  if not isBool(jField(sig, "is_variadic"), false):
    return unsupported("variadic function (or missing is_variadic) " &
      "outside the closed v1 grammar")
  okErr()

func requireMonomorphic(fd: JsonNode): Err =
  ## The generics table is a fun_decl-level member in the measured charon
  ## 0.1.281 shape (a sibling of `signature`, not a member of it). v1 is
  ## monomorphic: every entry array must be empty.
  let generics = jField(fd, "generics")
  if generics.isNil:
    return okErr()  # absent = monomorphic
  if generics.kind != JObject:
    return malformed("generics table is not an object")
  for k, v in generics.fields:
    if v.kind != JArray:
      return malformed("generics entry '" & k & "' is not an array")
    if v.elems.len > 0:
      return unsupported("generic parameter '" & k &
        "' outside the closed v1 grammar (monomorphic only)")
  okErr()

func buildLocalNames(locals: JsonNode; argCount: int):
    tuple[e: Err, names: Table[int, string], paramNames: seq[string]] =
  ## locals.locals → index → canonical place name. Locals 1..arg_count are
  ## the parameters and MUST carry their source names; the return place and
  ## anonymous temporaries use the LLBC `_N` shape.
  var names: Table[int, string]
  var paramNames: seq[string]
  let list = jField(locals, "locals")
  if locals.isNil or locals.kind != JObject or list.isNil or
      list.kind != JArray:
    return (malformed("body without locals list"), names, paramNames)
  for i in 0 ..< list.elems.len:
    let l = list.elems[i]
    let idx = jIdx(jField(l, "index"))
    if idx < 0:
      return (malformed("local without integer index"), names, paramNames)
    let nameNode = jField(l, "name")
    if nameNode.isNil or nameNode.kind == JNull:
      names[idx] = "_" & $idx
    elif nameNode.kind == JString and nameNode.str.len > 0:
      names[idx] = nameNode.str
    else:
      return (malformed("local " & $idx & " with malformed name"), names,
              paramNames)
  for p in 1 .. argCount:
    let pname = names.getOrDefault(p, "")
    if pname.len == 0:
      return (malformed("missing parameter local index " & $p), names,
              paramNames)
    paramNames.add(pname)
  if not names.hasKey(0):
    return (malformed("missing return-place local index 0"), names, paramNames)
  (okErr(), names, paramNames)

# ---------------------------------------------------------------------------
# body statement walk — the closed grammar + the checked-add collapse
# ---------------------------------------------------------------------------

func emitAssign(w: var StmtWalker; dest: string; rv: RustRvalue): Err =
  if dest in w.assigned:
    return malformed("re-assignment of place '" & dest &
      "' (v1 places are SSA-fresh, measured probe shape)")
  w.assigned.add(dest)
  w.c.body.add(RustStmt(kind: rskAssign, dest: dest, rvalue: rv))
  okErr()

func decodeAssign(w: var StmtWalker; destNode, rvNode: JsonNode): Err =
  let (de, dest) = plainPlace(destNode, w.localNames)
  if de.err != rceNone: return de
  if rvNode.isNil or rvNode.kind != JObject or rvNode.fields.len != 1:
    return malformed("malformed rvalue " & shapeName(rvNode))
  let rvKey = soleKey(rvNode)
  case rvKey
  of "Use":
    let payload = jField(rvNode, "Use")
    if payload.kind != JArray or payload.elems.len != 2:
      return malformed("malformed Use rvalue payload")
    let flag = payload.elems[1]
    if flag.kind != JString or (flag.str != "Yes" and flag.str != "No"):
      return unsupported("Use flag " & shapeName(flag) &
        " outside the measured shapes (Yes/No)")
    # Checked-add collapse: the Field-0 value extraction of the pending
    # tuple — exactly the statement that closes the pattern.
    if w.pending.active and w.pending.assertSeen and
        matchMoveProjField(payload.elems[0], w.pending.tupleLocal, 0):
      let saved1 = w.pending.op1
      let saved2 = w.pending.op2
      w.pending = PendingAdd()
      return emitAssign(w, dest, RustRvalue(kind: rrvAddChecked,
                                            addLhs: saved1, addRhs: saved2))
    if w.pending.active:
      return malformed("statement between the checked-add tuple assign " &
        "and its overflow assert/extraction")
    let (oe, op) = decodeOperand(payload.elems[0], w.localNames, w.interns)
    if oe.err != rceNone: return oe
    emitAssign(w, dest, RustRvalue(kind: rrvUse, operand: op))
  of "BinaryOp":
    if w.pending.active:
      return malformed("statement between the checked-add tuple assign " &
        "and its overflow assert/extraction")
    let payload = jField(rvNode, "BinaryOp")
    if payload.kind != JArray or payload.elems.len != 3:
      return malformed("malformed BinaryOp payload")
    let form = jStr(payload.elems[0], "")
    case form
    of "AddChecked":
      let (e1, op1) = decodeOperand(payload.elems[1], w.localNames, w.interns)
      if e1.err != rceNone: return e1
      let (e2, op2) = decodeOperand(payload.elems[2], w.localNames, w.interns)
      if e2.err != rceNone: return e2
      # The tuple local never becomes a canonical place; its Field-0
      # extraction destination is what gets emitted (with the Assert).
      let tupleIdx = jIdx(jField(jField(destNode, "kind"), "Local"))
      w.pending = PendingAdd(active: true, assertSeen: false,
                             tupleLocal: tupleIdx, op1: op1, op2: op2)
      okErr()
    of "Eq":
      let (e1, op1) = decodeOperand(payload.elems[1], w.localNames, w.interns)
      if e1.err != rceNone: return e1
      let (e2, op2) = decodeOperand(payload.elems[2], w.localNames, w.interns)
      if e2.err != rceNone: return e2
      emitAssign(w, dest, RustRvalue(kind: rrvBinaryOp, form: rboEq,
                                     lhs: op1, rhs: op2))
    else:
      unsupported("BinaryOp form '" & form &
        "' outside the closed v1 grammar (AddChecked and Eq only)")
  else:
    unsupported("rvalue kind '" & rvKey &
      "' outside the closed v1 grammar (Use/BinaryOp only)")

func decodeAssert(w: var StmtWalker; node: JsonNode): Err =
  ## The overflow check of the pending checked-add. Emits NO canonical
  ## statement; records the failureMode TOOL-LAYER fact.
  if not (w.pending.active and not w.pending.assertSeen):
    return unsupported("Assert outside the checked-add pattern " &
      "(the closed v1 grammar has no standalone assert)")
  let inner = jField(node, "assert")
  if inner.isNil or inner.kind != JObject:
    return malformed("Assert without assert payload")
  if not matchMoveProjField(jField(inner, "cond"), w.pending.tupleLocal, 1):
    return unsupported("Assert condition " & shapeName(jField(inner, "cond")) &
      " is not the checked-add overflow flag (Move Projection Field 1)")
  let expected = jField(inner, "expected")
  if not isBool(expected, false):
    return unsupported("Assert expected=" & shapeName(expected) &
      " outside the measured checked-add shape (== false)")
  let checkKind = jField(inner, "check_kind")
  let overflowOps = jField(checkKind, "Overflow")
  let firstOp = jAt(overflowOps, 0)
  if checkKind.isNil or overflowOps.isNil or overflowOps.kind != JArray or
      firstOp.isNil or firstOp.kind != JObject or
      not firstOp.fields.hasKey("Add"):
    return unsupported("Assert check_kind " & shapeName(checkKind) &
      " outside the measured checked-add shape (Overflow(Add, …))")
  let onFailure = jField(node, "on_failure")
  let panicPayload = jField(onFailure, "Panic")
  if onFailure.isNil or onFailure.kind != JObject or
      onFailure.fields.len != 1 or panicPayload.isNil or
      panicPayload.kind != JNull:
    return unsupported("on_failure " & shapeName(onFailure) &
      " outside the measured checked-add shape ({\"Panic\": null})")
  w.c.failureMode = rfmPanicOnOverflowObserved
  let onUnwind = jField(node, "on_unwind")
  if not onUnwind.isNil:
    let unwindSts = jField(onUnwind, "statements")
    if onUnwind.kind != JObject or unwindSts.isNil or unwindSts.kind != JArray:
      return malformed("malformed on_unwind block")
    for i in 0 ..< unwindSts.elems.len:
      let stKindNode = jField(unwindSts.elems[i], "kind")
      if stKindNode.isNil or stKindNode.kind != JString or
          stKindNode.str != "UnwindResume":
        return unsupported("unwind handler statement " &
          shapeName(stKindNode) &
          " outside the measured shape (UnwindResume only)")
  w.pending.assertSeen = true
  okErr()

func decodeOne(w: var StmtWalker; st: JsonNode): Err =
  let kindNode = jField(st, "kind")
  if kindNode.isNil:
    return malformed("statement without 'kind'")
  case kindNode.kind
  of JString:
    case kindNode.str
    of "Return":
      if w.pending.active:
        return malformed("Return inside an incomplete checked-add pattern")
      w.c.body.add(RustStmt(kind: rskReturn))
      okErr()
    of "Panic":
      if w.pending.active:
        return malformed("Panic inside an incomplete checked-add pattern")
      w.c.body.add(RustStmt(kind: rskPanic))
      okErr()
    else:
      unsupported("statement kind '" & kindNode.str &
        "' outside the closed v1 grammar")
  of JObject:
    if kindNode.fields.len != 1:
      return malformed("statement kind with multiple keys " &
        shapeName(kindNode))
    let key = soleKey(kindNode)
    case key
    of "StorageLive", "StorageDead":
      if w.pending.active:
        return malformed("statement between the checked-add tuple assign " &
          "and its overflow assert/extraction")
      let idx = jIdx(jField(kindNode, key))
      let placeName = w.localNames.getOrDefault(idx, "")
      if idx < 0 or placeName.len == 0:
        return malformed("malformed " & key & " on unknown local index " &
          $idx)
      if key == "StorageLive":
        w.c.body.add(RustStmt(kind: rskStorageLive, place: placeName))
      else:
        w.c.body.add(RustStmt(kind: rskStorageDead, place: placeName))
      okErr()
    of "Assign":
      let payload = jField(kindNode, "Assign")
      if payload.kind != JArray or payload.elems.len != 2:
        return malformed("malformed Assign payload")
      decodeAssign(w, payload.elems[0], payload.elems[1])
    of "Assert":
      decodeAssert(w, jField(kindNode, "Assert"))
    else:
      unsupported("statement kind '" & key &
        "' outside the closed v1 grammar (never silently dropped)")
  else:
    malformed("malformed statement kind " & shapeName(kindNode))

func walkStatements(sts: JsonNode; localNames: Table[int, string];
                    interns: LlbcInternTables; c: var RustCanonical): Err =
  ## Single pass over the body statements; runs the collapse state machine;
  ## rejects every unrecognized kind with a naming reason.
  if sts.isNil or sts.kind != JArray:
    return malformed("body without statements array")
  var w = StmtWalker(localNames: localNames, interns: interns, c: c,
                     pending: PendingAdd(), assigned: @[])
  for i in 0 ..< sts.elems.len:
    let e = decodeOne(w, sts.elems[i])
    if e.err != rceNone:
      c = w.c
      return e
  if w.pending.active:
    return malformed("checked-add pattern at end of body without its " &
      "overflow assert / value extraction")
  c = w.c
  okErr()

# ---------------------------------------------------------------------------
# boolean Switch collapse — recursive block evaluation (v1.3 row)
# ---------------------------------------------------------------------------
#
# MEASURED LLBC SHAPE (charon 0.1.281, serde_json::read::is_escape):
#   Switch := {"data": {"scrutinee": {"Value": operand},
#                       "branches": [[pattern, targetIdx], …],
#                       "fallback": fallbackIdx},
#              "branches": [{"statements": [...]}, …]}
#   A branch block that ends without Return falls through to the statement
#   AFTER the Switch in the parent block; Return is a statement and returns
#   the current return-place value. `&&`/`||` are lowered to nested Switches
#   (never BinaryOp), so the collapse is the ONLY carrier of their meaning.
#
# CLOSED COLLAPSE RULES (fail-closed, never widened):
#   - exactly ONE bool pattern per Switch (true or false); the fallback is
#     the other side. Integer/enum patterns → unsupported.
#   - ite(cond, true, e) → or(cond, e); ite(cond, e, false) → and(cond, e);
#     ite(cond, true, false) → cond. ite(cond, false, true) would need `not`
#     → unsupported (the closed subset has no negation node).
#   - a Return with no return-place assignment in scope is a POISON value
#     (nil): it is only an error if a reachable branch actually falls
#     through to it. Both branches returning values makes the poison tail
#     unreachable (the measured shape).
#   - Switch after a return-place assignment in the same block → unsupported
#     (the measured shape never does this; no silent guessing).

type
  CollapseEnvEntry = tuple[name: string, expr: RustExpr]

  CollapseCtx = object
    localNames: Table[int, string]
    interns: LlbcInternTables
    returnPlace: string

func cloneCollapseEnv(env: seq[CollapseEnvEntry]): seq[CollapseEnvEntry] =
  ## Fresh buffer — never share the seq storage between branch evaluations.
  result = newSeq[CollapseEnvEntry](env.len)
  for i in 0 ..< env.len:
    result[i] = env[i]

func collapseEnvFind(env: seq[CollapseEnvEntry]; name: string;
                     found: var bool): RustExpr =
  for e in env:
    if e.name == name:
      found = true
      return e.expr
  found = false
  nil

func isBoolConstExpr(e: RustExpr; v: bool): bool =
  if e == nil or e.kind != rexOperand: return false
  let op = e.operand
  if op.kind != ropConstant: return false
  if op.valueU64 != 0'u64: return false
  op.value == (if v: 1'i64 else: 0'i64)

func mkBoolConstExpr(v: bool): RustExpr =
  RustExpr(kind: rexOperand,
           operand: RustOperand(kind: ropConstant,
                                value: (if v: 1'i64 else: 0'i64),
                                ty: RustType(kind: rtyBool, widthBits: 1,
                                             signedness: rsgUnsigned)))

func mkBinaryExpr(f: RustBinOpForm; l, r: RustExpr): RustExpr =
  RustExpr(kind: rexBinaryOp, form: f, lhs: l, rhs: r)

func iteNormalize(cond, thenE, elseE: RustExpr): RustExpr =
  ## nil = the `not` form (outside the closed subset) — caller fails closed.
  if isBoolConstExpr(thenE, true) and isBoolConstExpr(elseE, false):
    return cond
  if isBoolConstExpr(thenE, true):
    return mkBinaryExpr(rboOr, cond, elseE)
  if isBoolConstExpr(elseE, false):
    return mkBinaryExpr(rboAnd, cond, thenE)
  if isBoolConstExpr(thenE, false) and isBoolConstExpr(elseE, true):
    return nil
  RustExpr(kind: rexIte, cond: cond, thenExpr: thenE, elseExpr: elseE)

func collapseOperandToExpr(ctx: CollapseCtx; op: RustOperand;
                           env: seq[CollapseEnvEntry]):
    tuple[e: Err, expr: RustExpr] =
  case op.kind
  of ropCopy, ropMove:
    var found = false
    let bound = collapseEnvFind(env, op.place, found)
    if not found:
      return (malformed("reference to unbound place '" & op.place & "'"), nil)
    (okErr(), bound)
  of ropConstant:
    (okErr(), RustExpr(kind: rexOperand, operand: op))

func decodeCollapseRvalue(ctx: CollapseCtx; rvNode: JsonNode;
                          env: seq[CollapseEnvEntry]):
    tuple[e: Err, expr: RustExpr] =
  if rvNode.isNil or rvNode.kind != JObject or rvNode.fields.len != 1:
    return (malformed("malformed rvalue " & shapeName(rvNode)), nil)
  let key = soleKey(rvNode)
  case key
  of "Use":
    let payload = jField(rvNode, "Use")
    if payload.kind != JArray or payload.elems.len != 2:
      return (malformed("malformed Use rvalue payload"), nil)
    let flag = payload.elems[1]
    if flag.kind != JString or (flag.str != "Yes" and flag.str != "No"):
      return (unsupported("Use flag " & shapeName(flag) &
        " outside the measured shapes (Yes/No)"), nil)
    let (oe, op) = decodeOperand(payload.elems[0], ctx.localNames, ctx.interns)
    if oe.err != rceNone: return (oe, nil)
    collapseOperandToExpr(ctx, op, env)
  of "BinaryOp":
    let payload = jField(rvNode, "BinaryOp")
    if payload.kind != JArray or payload.elems.len != 3:
      return (malformed("malformed BinaryOp payload"), nil)
    let form = jStr(payload.elems[0], "")
    if form != "Eq" and form != "Lt" and form != "And" and form != "Or":
      return (unsupported("BinaryOp form '" & form &
        "' outside the boolean Switch collapse (Eq/Lt/And/Or)"), nil)
    let rf = case form
             of "Eq": rboEq
             of "Lt": rboLt
             of "And": rboAnd
             else: rboOr
    let (e1, op1) = decodeOperand(payload.elems[1], ctx.localNames, ctx.interns)
    if e1.err != rceNone: return (e1, nil)
    let (e2, op2) = decodeOperand(payload.elems[2], ctx.localNames, ctx.interns)
    if e2.err != rceNone: return (e2, nil)
    let (l1, lx) = collapseOperandToExpr(ctx, op1, env)
    if l1.err != rceNone: return (l1, nil)
    let (l2, rx) = collapseOperandToExpr(ctx, op2, env)
    if l2.err != rceNone: return (l2, nil)
    (okErr(), mkBinaryExpr(rf, lx, rx))
  else:
    (unsupported("rvalue kind '" & key &
      "' outside the boolean Switch collapse (Use/BinaryOp only)"), nil)

func decodeBoolPattern(pat: JsonNode; interns: LlbcInternTables):
    tuple[e: Err, v: bool] =
  ## Bool patterns arrive as {"Deduplicated": id} into the const intern table
  ## (measured: 341 = false). Only Bool kinds are admitted.
  if pat.isNil or pat.kind != JObject or pat.fields.len != 1:
    return (malformed("malformed Switch pattern " & shapeName(pat)), false)
  var kindExpr: JsonNode
  if pat.fields.hasKey("Deduplicated"):
    let id = jIdx(jField(pat, "Deduplicated"))
    if id < 0:
      return (malformed("malformed Deduplicated pattern id"), false)
    let entry = interns.consts.getOrDefault(id)
    if entry.kind.isNil:
      return (malformed("unresolved interned pattern id " & $id), false)
    kindExpr = entry.kind
  elif pat.fields.hasKey("Value"):
    let v = jField(pat, "Value")
    if v.kind != JArray or v.elems.len != 2 or
        v.elems[1].kind != JArray or v.elems[1].elems.len != 2:
      return (malformed("malformed Switch pattern payload"), false)
    kindExpr = v.elems[1].elems[0]
  else:
    return (malformed("Switch pattern shape " & shapeName(pat)), false)
  let b = jField(kindExpr, "Bool")
  if b.isNil or (not isBool(b, true) and not isBool(b, false)):
    return (unsupported("Switch pattern kind " & shapeName(kindExpr) &
      " outside the boolean pattern set"), false)
  (okErr(), b.bval)

func evalCollapseBlock(ctx: CollapseCtx; stmts: JsonNode; start: int;
                       env: seq[CollapseEnvEntry]; cont: RustExpr;
                       err: var Err): RustExpr

func evalCollapseSwitch(ctx: CollapseCtx; sw: JsonNode;
                        env: seq[CollapseEnvEntry]; cont: RustExpr;
                        err: var Err): RustExpr =
  let data = jField(sw, "data")
  let branchBlocks = jField(sw, "branches")
  if data.isNil or data.kind != JObject or branchBlocks.isNil or
      branchBlocks.kind != JArray or branchBlocks.elems.len == 0:
    err = malformed("Switch without data/branches")
    return nil
  let scrutNode = jField(data, "scrutinee")
  let operandNode = jField(scrutNode, "Value")
  if operandNode.isNil:
    err = unsupported("Switch scrutinee form " & shapeName(scrutNode) &
      " (measured Value only)")
    return nil
  let (oe, op) = decodeOperand(operandNode, ctx.localNames, ctx.interns)
  if oe.err != rceNone:
    err = oe
    return nil
  let (se, scrExpr) = collapseOperandToExpr(ctx, op, env)
  if se.err != rceNone:
    err = se
    return nil
  let pairSeq = jField(data, "branches")
  if pairSeq.isNil or pairSeq.kind != JArray or pairSeq.elems.len != 1:
    err = unsupported("Switch with " &
      $(if pairSeq.isNil or pairSeq.kind != JArray: -1
        else: pairSeq.elems.len) &
      " patterns (the closed subset has ONE bool pattern per Switch)")
    return nil
  let pair = pairSeq.elems[0]
  if pair.kind != JArray or pair.elems.len != 2:
    err = malformed("malformed Switch branch pair")
    return nil
  let (pe, patVal) = decodeBoolPattern(pair.elems[0], ctx.interns)
  if pe.err != rceNone:
    err = pe
    return nil
  let targetIdx = jIdx(pair.elems[1])
  let fallbackIdx = jIdx(jField(data, "fallback"))
  if targetIdx < 0 or fallbackIdx < 0 or
      targetIdx >= branchBlocks.elems.len or
      fallbackIdx >= branchBlocks.elems.len:
    err = malformed("Switch target/fallback index out of range")
    return nil
  let targetStmts = jField(branchBlocks.elems[targetIdx], "statements")
  let fallbackStmts = jField(branchBlocks.elems[fallbackIdx], "statements")
  if targetStmts.isNil or targetStmts.kind != JArray or
      fallbackStmts.isNil or fallbackStmts.kind != JArray:
    err = malformed("Switch branch block without statements array")
    return nil
  let targetExpr = evalCollapseBlock(ctx, targetStmts, 0, env, cont, err)
  if err.err != rceNone: return nil
  let fallbackExpr = evalCollapseBlock(ctx, fallbackStmts, 0, env, cont, err)
  if err.err != rceNone: return nil
  if targetExpr == nil and fallbackExpr == nil:
    return nil  # both paths poison — the caller decides reachability
  if targetExpr == nil or fallbackExpr == nil:
    err = malformed("Switch branch falls through to an unset return place")
    return nil
  let thenE = if patVal: targetExpr else: fallbackExpr
  let elseE = if patVal: fallbackExpr else: targetExpr
  let r = iteNormalize(scrExpr, thenE, elseE)
  if r == nil:
    err = unsupported("Switch collapse would need `not` " &
      "(outside the closed subset)")
    return nil
  r

func evalCollapseBlock(ctx: CollapseCtx; stmts: JsonNode; start: int;
                       env: seq[CollapseEnvEntry]; cont: RustExpr;
                       err: var Err): RustExpr =
  ## Evaluate `stmts[start..]` to ONE expression. `cont` is the value of
  ## falling through the end of the block (nil = poison). A Return overrides
  ## `cont`; a Switch is terminal (its branches fall through to the tail).
  var e = cloneCollapseEnv(env)
  var ret: RustExpr = nil
  var retSeen = false
  var i = start
  while i < stmts.len:
    let st = stmts.elems[i]
    let kindNode = jField(st, "kind")
    if kindNode.isNil:
      err = malformed("statement without 'kind'")
      return nil
    if kindNode.kind == JString:
      case kindNode.str
      of "Return":
        if not retSeen:
          return nil  # poison — only an error if a reachable path uses it
        return ret
      of "Panic":
        err = unsupported("Panic inside the boolean Switch collapse")
        return nil
      else:
        err = unsupported("statement kind '" & kindNode.str &
          "' outside the boolean Switch collapse")
        return nil
    if kindNode.kind != JObject or kindNode.fields.len != 1:
      err = malformed("malformed statement kind " & shapeName(kindNode))
      return nil
    let key = soleKey(kindNode)
    case key
    of "StorageLive", "StorageDead":
      discard
    of "Assign":
      let payload = jField(kindNode, "Assign")
      if payload.kind != JArray or payload.elems.len != 2:
        err = malformed("malformed Assign payload")
        return nil
      let (de, dest) = plainPlace(payload.elems[0], ctx.localNames)
      if de.err != rceNone:
        err = de
        return nil
      let (re, expr) = decodeCollapseRvalue(ctx, payload.elems[1], e)
      if re.err != rceNone:
        err = re
        return nil
      if dest == ctx.returnPlace:
        if retSeen:
          err = malformed("re-assignment of return place '" & dest & "'")
          return nil
        ret = expr
        retSeen = true
      else:
        var found = false
        discard collapseEnvFind(e, dest, found)
        if found:
          err = malformed("re-assignment of place '" & dest & "'")
          return nil
        e.add((name: dest, expr: expr))
    of "Switch":
      if retSeen:
        err = unsupported("Switch after a return-place assignment in the " &
          "same block (outside the measured shape)")
        return nil
      let sw = jField(kindNode, "Switch")
      if sw.isNil or sw.kind != JObject:
        err = malformed("malformed Switch payload")
        return nil
      let contExpr = evalCollapseBlock(ctx, stmts, i + 1, e, cont, err)
      if err.err != rceNone: return nil
      return evalCollapseSwitch(ctx, sw, e, contExpr, err)
    of "Assert":
      err = unsupported("Assert outside the checked-add pattern " &
        "(boolean Switch collapse)")
      return nil
    else:
      err = unsupported("statement kind '" & key &
        "' outside the closed v1 grammar")
      return nil
    inc i
  if retSeen:
    # The block assigned the return place and falls through to the parent
    # tail. The measured tail is `… Return` (returns the current value), so
    # the branch value IS `ret`. A tail that independently produces a value
    # would make the fall-through ambiguous → fail closed.
    if cont != nil:
      err = malformed("return place assigned and then overwritten by an " &
        "independent continuation value")
      return nil
    return ret
  cont

func bodyHasSwitch(stmts: JsonNode): bool =
  ## Top-level scan: a Switch can only appear as a statement, and a nested
  ## Switch lives inside a Switch branch block — so a top-level hit is the
  ## complete discriminator between the straight-line and collapse paths.
  if stmts.isNil or stmts.kind != JArray: return false
  for st in stmts.elems:
    let kindNode = jField(st, "kind")
    if kindNode.isNil or kindNode.kind != JObject: continue
    if soleKey(kindNode) == "Switch":
      return true
  false

func collapseBody(ctx: CollapseCtx; stmts: JsonNode; params: seq[RustParam];
                  c: var RustCanonical): Err =
  ## Build the collapsed canonical body: one Assign(returnPlace,
  ## rrvExpr(tree)) + Return. The tree is the whole function meaning.
  var env: seq[CollapseEnvEntry] = @[]
  for p in params:
    env.add((name: p.name,
             expr: RustExpr(kind: rexOperand,
                            operand: RustOperand(kind: ropCopy,
                                                 place: p.name))))
  var err = okErr()
  let expr = evalCollapseBlock(ctx, stmts, 0, env, nil, err)
  if err.err != rceNone:
    return err
  if expr == nil:
    return malformed("boolean Switch collapse produced no return value")
  c.body.add(RustStmt(kind: rskAssign, dest: ctx.returnPlace,
                      rvalue: RustRvalue(kind: rrvExpr, expr: expr)))
  c.body.add(RustStmt(kind: rskReturn))
  okErr()

# ---------------------------------------------------------------------------
# declaration-level entry points
# ---------------------------------------------------------------------------

func extractFunDecl(ctx: LlbcDeclCtx; fd: JsonNode): LlbcToCanonicalResult =
  ## ONE fun_decl → RustCanonical (or an explicit fail-closed rejection).
  ## The five preserved properties are constructed explicitly:
  ##   1. funcName + params(ident, ty) + retType — item_meta.name +
  ##      signature.inputs/output (interning resolved)
  ##   2. widthBits + signedness                 — decodeTypeRef (closed set)
  ##   3. AddChecked form tag                    — rrvAddChecked (collapse)
  ##   4. failureMode (tool-layer)               — Assert on_failure Panic
  ##   5. modulePath / sourceIdentity            — item_meta.name / span
  result = LlbcToCanonicalResult(ok: false, error: rceMalformed, reason: "")
  if fd.isNil or fd.kind != JObject:
    result.reason = "fun_decl is not an object"
    return
  let meta = jField(fd, "item_meta")
  if meta.isNil or meta.kind != JObject:
    result.reason = "fun_decl without item_meta"
    return
  if isBool(jField(meta, "has_errors"), true):
    result.reason = "item_meta.has_errors is set — extraction is not " &
      "trustworthy (fail-closed)"
    return

  let (ne, modulePath, funcName) = decodeNamePath(jField(meta, "name"))
  if ne.err != rceNone:
    result.error = ne.err; result.reason = ne.reason; return

  let (se, sourceIdentity) = decodeSourceIdentity(jField(meta, "span"), ctx)
  if se.err != rceNone:
    result.error = se.err; result.reason = se.reason; return

  let sig = jField(fd, "signature")
  let sigShape = requireSignatureShape(sig)
  if sigShape.err != rceNone:
    result.error = sigShape.err; result.reason = sigShape.reason; return
  let mono = requireMonomorphic(fd)
  if mono.err != rceNone:
    result.error = mono.err; result.reason = mono.reason; return

  let bodyWrapper = jField(fd, "body")
  if bodyWrapper.isNil or bodyWrapper.kind != JObject or
      bodyWrapper.fields.len != 1 or
      not bodyWrapper.fields.hasKey("Structured"):
    result.error = rceUnsupportedGrammar
    result.reason = "body form " & shapeName(bodyWrapper) &
      " outside the closed v1 grammar (Structured bodies only)"
    return
  let structured = jField(bodyWrapper, "Structured")

  let localsNode = jField(structured, "locals")
  let argCount = jIdx(jField(localsNode, "arg_count"))
  if argCount < 0:
    result.reason = "locals without integer arg_count"
    return
  let (le, localNames, paramNames) = buildLocalNames(localsNode, argCount)
  if le.err != rceNone:
    result.error = le.err; result.reason = le.reason; return

  let inputs = jField(sig, "inputs")
  var inputCount = -1
  if not inputs.isNil and inputs.kind == JArray:
    inputCount = inputs.elems.len
  if inputCount != argCount:
    result.reason = "signature.inputs arity " & $inputCount &
      " != locals.arg_count " & $argCount
    return
  var params: seq[RustParam] = @[]
  for i in 0 ..< argCount:
    let (te, ty) = decodeTypeRef(inputs.elems[i], ctx.interns)
    if te.err != rceNone:
      result.error = te.err
      result.reason = "parameter " & paramNames[i] & ": " & te.reason
      return
    params.add(RustParam(name: paramNames[i], ty: ty))

  let (rte, retTy) = decodeTypeRef(jField(sig, "output"), ctx.interns)
  if rte.err != rceNone:
    result.error = rte.err; result.reason = "return type: " & rte.reason
    return

  let returnPlaceName = localNames.getOrDefault(0, "")
  if returnPlaceName.len == 0:
    result.reason = "missing return-place local index 0"
    return
  var c = RustCanonical(
    modulePath: modulePath,
    sourceIdentity: sourceIdentity,
    funcName: funcName,
    returnPlace: returnPlaceName,
    failureMode: rfmNoneObserved,
    params: params,
    retType: retTy,
    body: @[])

  let bodyStmts = jField(jField(structured, "body"), "statements")
  if bodyHasSwitch(bodyStmts):
    let cctx = CollapseCtx(localNames: localNames, interns: ctx.interns,
                           returnPlace: returnPlaceName)
    let collapseErr = collapseBody(cctx, bodyStmts, params, c)
    if collapseErr.err != rceNone:
      result.error = collapseErr.err
      result.reason = collapseErr.reason
      return
  else:
    let walkErr = walkStatements(bodyStmts, localNames, ctx.interns, c)
    if walkErr.err != rceNone:
      result.error = walkErr.err; result.reason = walkErr.reason; return

  let v = validateRustCanonical(c)
  if v != rceNone:
    result.error = v
    result.reason = "produced canonical failed validation: " &
      rustCanonicalErrorReason(v)
    return
  # The width-64 '+' wall (v1.1 boundary-type admission) is RETIRED in v1.2
  # (`work/u64-add-2026-11-02`): the IR literal two-part form carries values
  # ≥ 2^63 in the u64-domain representation and the no-overflow obligation
  # discharges in the equivalent form `lhs + rhs ≤ 18446744073709551615` —
  # the AddChecked collapse proceeds for width 64 exactly like u8/u32. The
  # exact refusal reason is preserved verbatim in `retiredWidth64WallReason`
  # (above) for regression tracking; the width-64 path no longer emits it.
  result.ok = true
  result.error = rceNone
  result.canonical = c

## The pre-v1.2 width-64 '+' refusal reason, preserved VERBATIM for
## regression tracking (docs/spec/rust_certified_subset.md §1): the width-64
## path no longer emits it, but the string must stay greppable so a
## regression back to the wall is machine-detectable.
const retiredWidth64WallReason* =
  "full-width '+' outside the closed v1 set: the no-overflow obligation " &
  "'lhs + rhs < 2^64' is unrepresentable in the IR literal domain (int64) — " &
  "u64 is boundary-type-only (fail-closed; wraparound/checked semantics are " &
  "the declared follow-up per docs/spec/rust_certified_subset.md §1)"

func validateLlbcFileTable*(root: JsonNode): LlbcFileTableResult =
  ## LLBC file-table PRE-VALIDATION (feat/rust-subject-v1 Phase 1-A) —
  ## reject-not-skip, run BEFORE anything consumes the LLBC. Enforces exactly
  ## these rules over `translated.files[]`; the FIRST violation fails the
  ## whole document with a reason naming the rule and the offending entry:
  ##   (1) `id` present, non-negative integer — every entry;
  ##   (2) subject-crate entries: `name` sole-key `Local` with a non-empty
  ##       string; (3) `id` unique across the whole table;
  ##   (4) `name.Local` values unique (literal equality — rule (5) already
  ##       pins the canonical POSIX form and D1 mandates no Unicode
  ##       normalization); (5) path grammar: `..` / `.` segments, empty
  ##       segments and non-POSIX separators are rejected — absolute paths
  ##       are NOT summarily rejected, they are the rule (7) classification
  ##       input; (6) subject-crate entries with null/missing `contents` →
  ##       reject; NON-subject-crate entries: `contents` is NEVER read
  ##       (documented policy — external crates contribute ids for span
  ##       resolution only); (7) §6d `embeddedContentAttested` — a
  ##       subject-crate entry whose `name.Local` is an ABSOLUTE path is
  ##       accepted, CONTENT-ATTESTED ONLY, when `contents` is a string:
  ##       recorded in `embedded` (index == FileId, verbatim path —
  ##       in-memory only, crate name, sha256 of contents) and EXCLUDED
  ##       from the returned entry list (not a subject source — outside the
  ##       disk-set equivalence, never in buildDeclCtx; span resolution for
  ##       its id stays fail-closed). Absolute + null/missing `contents`
  ##       keeps the pre-§6d rejection byte-identical (tag
  ##       `path_absolute`); a DUPLICATE absolute path among embedded
  ##       entries is a NEW rejection (`embedded_path_duplicate` — charon's
  ##       stable_id dedup makes it impossible in sound output, malformed
  ##       defense). NO generation-provenance claim: charon's FileName has
  ##       no "generated" variant (Virtual/Local/NotReal, pin 79801650) —
  ##       the absolute path evidences only "outside the extraction cwd".
  ## The subject crate is discriminated by `crate_name ==`
  ## `translated.crate_name` (MEASURED: foreign-crate files also serialize
  ## under the `Local` tag with absolute /rustc/... paths and null contents,
  ## so the tag alone cannot separate them).
  ## The returned entry list is the validated local file table reused by the
  ## rust subject input contract (verification/rust_input_contract.nim) and
  ## by buildDeclCtx — duplicate ids can no longer silently last-win at the
  ## span consumer, malformed entries can no longer be silently skipped.
  ## Entry-level violations additionally populate `rejection` — the
  ## structured producer facts of the FIRST violation (§6c v2 rejection
  ## binding); the reason string and the ok verdict are byte-identical to
  ## the pre-binding behavior.
  result.ok = false
  if root.isNil or root.kind != JObject:
    result.reason = "LLBC document is not a JSON object"
    return
  let translated = jField(root, "translated")
  if translated.isNil or translated.kind != JObject:
    result.reason = "LLBC document without 'translated'"
    return
  let crateName = jStr(jField(translated, "crate_name"))
  if crateName.len == 0:
    result.reason =
      "translated.crate_name missing or not a non-empty string — " &
      "the subject crate cannot be discriminated in the files table"
    return
  let files = jField(translated, "files")
  if files.isNil or files.kind != JArray:
    result.reason = "translated.files missing or not an array"
    return
  var seenIds: seq[int] = @[]
  template rejectEntry(ruleTag: string; idx: int; crate: string;
                       rawPathArg: string; contentsArg: JsonNode) =
    ## Record the structured producer facts of THIS violation, then fail the
    ## document exactly as before — the reason string and verdict are
    ## untouched (§6c v2: production-time rejection binding, judgment-invariant).
    block:
      let node: JsonNode = contentsArg
      result.rejection = RustFileTableRejection(
        rule: ruleTag, index: idx, crateName: crate, rawPath: rawPathArg,
        contentSha256: (if not node.isNil and node.kind == JString:
                          sha256Hex(node.str)
                        else: ""))
    return
  for i in 0 ..< files.elems.len:
    let f = files.elems[i]
    if f.isNil or f.kind != JObject:
      result.reason = "files[" & $i & "] is not a JSON object"
      rejectEntry("entry_not_object", i, "", "", nil)
    # Rule 1 — id present, non-negative integer.
    let idNode = jField(f, "id")
    if idNode.isNil or idNode.kind != JInt or idNode.num < 0:
      result.reason = "files[" & $i & "]: 'id' must be a present " &
        "non-negative integer (got " & shapeName(idNode) & ")"
      rejectEntry("id_invalid", i, "", "", nil)
    let id = idNode.num.int
    # Rule 3 — ids unique across the whole table.
    for prev in seenIds:
      if prev == id:
        result.reason = "files[" & $i & "]: duplicate file id " & $id &
          " (ids must be unique across the table)"
        rejectEntry("id_duplicate", i, "", "", nil)
    seenIds.add(id)
    let entryCrate = jStr(jField(f, "crate_name"))
    if entryCrate.len == 0:
      result.reason = "files[" & $i & "]: 'crate_name' missing or not a " &
        "non-empty string"
      rejectEntry("entry_crate_missing", i, "", "", nil)
    if entryCrate != crateName:
      # Foreign-crate entry — rule 6 policy: contents never read; only the
      # id rules above apply. It contributes nothing to the local table.
      continue
    # Subject-crate (local) entry — rules 2, 5, 4, 6 in grammar order.
    let nameNode = jField(f, "name")
    if soleKey(nameNode) != "Local":
      result.reason = "files[" & $i & "]: subject-crate entry name must be " &
        "sole-key 'Local' (got " & shapeName(nameNode) & ")"
      rejectEntry("name_not_local", i, entryCrate, "",
                  jField(f, "contents"))
    let relPath = jStr(jField(nameNode, "Local"))
    if relPath.len == 0:
      result.reason = "files[" & $i & "]: name.Local must be a non-empty string"
      rejectEntry("path_empty", i, entryCrate, "", jField(f, "contents"))
    # Rule 5 — subject-relative POSIX path grammar.
    if relPath.contains('\\'):
      result.reason = "files[" & $i & "]: non-POSIX separator in path '" &
        relPath & "'"
      rejectEntry("non_posix_separator", i, entryCrate, relPath,
                  jField(f, "contents"))
    if relPath.startsWith("/"):
      # §6d — subject-crate absolute-path entry: content-attested acceptance
      # (string contents) or the byte-identical §6c v2 rejection (otherwise).
      let absContents = jField(f, "contents")
      if not absContents.isNil and absContents.kind == JString:
        for prev in result.embedded:
          if prev.rawPath == relPath:
            result.reason = "files[" & $i & "]: duplicate absolute path '" &
              relPath & "' (embedded entries must be unique)"
            rejectEntry("embedded_path_duplicate", i, entryCrate, relPath,
                        absContents)
        result.embedded.add(LlbcEmbeddedEntry(
          index: i, rawPath: relPath, crateName: entryCrate,
          contentSha256: sha256Hex(absContents.str)))
        continue
      result.reason = "files[" & $i & "]: absolute path '" & relPath &
        "' (subject-relative POSIX path required)"
      rejectEntry("path_absolute", i, entryCrate, relPath,
                  jField(f, "contents"))
    for seg in relPath.split('/'):
      if seg.len == 0:
        result.reason = "files[" & $i & "]: empty path segment in '" &
          relPath & "'"
        rejectEntry("path_empty_segment", i, entryCrate, relPath,
                    jField(f, "contents"))
      if seg == "..":
        result.reason = "files[" & $i & "]: '..' segment in path '" &
          relPath & "'"
        rejectEntry("path_dotdot_segment", i, entryCrate, relPath,
                    jField(f, "contents"))
      if seg == ".":
        result.reason = "files[" & $i & "]: '.' segment in path '" &
          relPath & "'"
        rejectEntry("path_dot_segment", i, entryCrate, relPath,
                    jField(f, "contents"))
    # Rule 4 — Local paths unique (canonical form pinned by rule 5; D1
    # mandates no Unicode normalization, so literal equality is the rule).
    for prev in result.entries:
      if prev.relPath == relPath:
        result.reason = "files[" & $i & "]: duplicate Local path '" &
          relPath & "'"
        rejectEntry("path_duplicate", i, entryCrate, relPath,
                    jField(f, "contents"))
    # Rule 6 — a local entry must embed its source text (the empty string is
    # a present string: an empty .rs file hashes like any other).
    let contentsNode = jField(f, "contents")
    if contentsNode.isNil or contentsNode.kind != JString:
      result.reason = "files[" & $i & "]: subject-crate entry '" & relPath &
        "' must embed 'contents' as a string (got " &
        shapeName(contentsNode) & ")"
      rejectEntry("contents_missing", i, entryCrate, relPath, contentsNode)
    result.entries.add(LlbcFileTableEntry(
      id: id, relPath: relPath, contents: contentsNode.str))
  result.ok = true
  result.reason = ""

func buildDeclCtx(translated: JsonNode;
    localFiles: seq[LlbcFileTableEntry]): LlbcDeclCtx =
  ## Document-order intern collection over the whole translated subtree +
  ## the PRE-VALIDATED crate files table for span resolution (validate
  ## first — the consumer below never sees an unvalidated id/path) + the
  ## type_decls registry and the item_names-derived owner map for the
  ## structured-name owner resolution (Q11).
  var ctx: LlbcDeclCtx
  collectInterns(translated, ctx.interns)
  var ownerInterns: LlbcInternTables
  collectInterns(jField(translated, "item_names"), ownerInterns)
  ctx.ownerTypes = ownerInterns.types
  for e in localFiles:
    ctx.files.add((e.id, e.relPath))
  ctx.typeDecls = jField(translated, "type_decls")
  ctx

func funDecls(translated: JsonNode): JsonNode =
  jField(translated, "fun_decls")

func lastNameSegment(fd: JsonNode): string =
  ## The function's last Ident path segment, or "" when the path is absent
  ## or not all-Ident (Builtin etc.) — callers treat "" as unnameable.
  let name = jField(jField(fd, "item_meta"), "name")
  if name.isNil or name.kind != JArray or name.elems.len == 0:
    return ""
  let last = name.elems[name.elems.len - 1]
  if last.isNil or soleKey(last) != "Ident":
    return ""
  jStr(jAt(jField(last, "Ident"), 0))

func docHasErrors*(root: JsonNode): bool =
  ## Top-level `has_errors` — a failing extraction is never a candidate.
  isBool(jField(root, "has_errors"), true)

func hasStructuredBody(fd: JsonNode): bool =
  let bodyWrapper = jField(fd, "body")
  not bodyWrapper.isNil and bodyWrapper.kind == JObject and
    bodyWrapper.fields.hasKey("Structured")

type
  LlbcFunDeclNamePath* = object
    ## (Q11/DEBT#510) A fun_decl's ADDRESSABLE name: `fullName` — the
    ## structured match key the producer binds EXACTLY (free functions: the
    ## Ident-path join; inherent-impl methods: the owner's nominal Adt path
    ## + method) — and `lastSegment`, the bare word the ambiguity
    ## discipline refuses to resolve when more than one decl shares it.
    fullName*: string
    lastSegment*: string

proc llbcFunDeclNamePaths*(root: JsonNode): seq[LlbcFunDeclNamePath] {.
    raises: [].} =
  ## Every ADDRESSABLE fun_decl name, document order. A decl whose
  ## structured name is unresolvable (trait impl blocks, scalar/primitive
  ## owners — Q11 — non-Ident elements) is skipped: callers report what IS
  ## addressable, and the producer's last-segment fallback still sees every
  ## decl. Body form is NOT filtered here (extraction reports prototypes
  ## honestly — "extern prototype" is a measured reason, not a skip).
  result = @[]
  if root.isNil or root.kind != JObject: return
  let translated = jField(root, "translated")
  if translated.isNil or translated.kind != JObject: return
  let decls = funDecls(translated)
  if decls.isNil or decls.kind != JArray: return
  var ctx: LlbcDeclCtx
  ctx.typeDecls = jField(translated, "type_decls")
  var ownerInterns: LlbcInternTables
  collectInterns(jField(translated, "item_names"), ownerInterns)
  ctx.ownerTypes = ownerInterns.types
  collectInterns(translated, ctx.interns)
  for i in 0 ..< decls.elems.len:
    let fd = decls.elems[i]
    let s = funDeclStructuredName(ctx, fd)
    if not s.ok: continue
    let fn = lastNameSegment(fd)
    if fn.len == 0: continue
    result.add(LlbcFunDeclNamePath(fullName: s.fullName, lastSegment: fn))

func llbcFunctionNames*(root: JsonNode): seq[string] =
  ## Last-path name of every fun_decl carrying a Structured body, in
  ## document order. Declarations without a Structured body are not
  ## extractable and are NOT listed (llbcAllToCanonical reports them
  ## explicitly — nothing is silently dropped there).
  result = @[]
  if root.isNil or root.kind != JObject: return
  let decls = funDecls(jField(root, "translated"))
  if decls.isNil or decls.kind != JArray: return
  for i in 0 ..< decls.elems.len:
    let fd = decls.elems[i]
    if not hasStructuredBody(fd): continue
    let fn = lastNameSegment(fd)
    if fn.len > 0:
      result.add(fn)

proc llbcFunctionToCanonical*(root: JsonNode; funcName: string):
    LlbcToCanonicalResult =
  ## Extract ONE function into the shared canonical. TARGET RESOLUTION
  ## (DEBT#510 closure — the first document-order last-segment match is
  ## GONE, the producer binds the SELECTED decl):
  ##   1. an EXACT structured-name match (llbcFunDeclNamePaths' fullName)
  ##      selects that decl;
  ##   2. a bare LAST-SEGMENT match selects the decl ONLY when exactly one
  ##      fun_decl in the whole document carries that last segment — more
  ##      than one is an EXPLICIT Ambiguous rejection naming every
  ##      candidate (structured names where addressable), never a silent
  ##      first match;
  ##   3. otherwise NotFound.
  ## Fail-closed on every shape outside docs/spec/rust_certified_subset.md
  ## §1/§2.
  result = LlbcToCanonicalResult(ok: false, error: rceMalformed, reason: "")
  if root.isNil or root.kind != JObject:
    result.reason = "LLBC document is not a JSON object"
    return
  if docHasErrors(root):
    result.reason = "LLBC top-level has_errors is set (fail-closed)"
    return
  let translated = jField(root, "translated")
  if translated.isNil or translated.kind != JObject:
    result.reason = "LLBC document without 'translated'"
    return
  let decls = funDecls(translated)
  if decls.isNil or decls.kind != JArray:
    result.reason = "LLBC document without fun_decls"
    return
  # Input contract, file-table half: pre-validation BEFORE any consumption
  # (reject-not-skip; a violation is a whole-document failure, not a
  # per-function span failure).
  let ft = validateLlbcFileTable(root)
  if not ft.ok:
    result.error = rceMalformed
    result.reason = "LLBC files table pre-validation failed: " & ft.reason
    return
  let ctx = buildDeclCtx(translated, ft.entries)
  var exact: seq[int] = @[]
  var lastSeg: seq[int] = @[]
  var lastSegNames: seq[string] = @[]
  for i in 0 ..< decls.elems.len:
    let fd = decls.elems[i]
    let s = funDeclStructuredName(ctx, fd)
    if s.ok and s.fullName == funcName:
      exact.add(i)
    if lastNameSegment(fd) == funcName:
      lastSeg.add(i)
      lastSegNames.add(if s.ok: s.fullName
                       else: "<unaddressable decl " & $i & ">")
  var chosen = -1
  if exact.len == 1:
    chosen = exact[0]
  elif exact.len > 1:
    result.error = rceMalformed
    result.reason = "ambiguous target '" & funcName & "': " & $exact.len &
      " declarations share the structured name — a malformed document " &
      "(structured names are unique per crate)"
    return
  elif lastSeg.len == 1:
    chosen = lastSeg[0]
  elif lastSeg.len > 1:
    result.error = rceMalformed
    result.reason = "ambiguous target '" & funcName & "': " & $lastSeg.len &
      " declarations share the last name segment (" & lastSegNames.join(", ") &
      ") — use the structured full name (llbcFunDeclNamePaths); the first " &
      "document-order match is never taken silently (DEBT#510)"
    return
  else:
    result.reason = "function '" & funcName & "' not found in fun_decls"
    return
  let fd = decls.elems[chosen]
  if not hasStructuredBody(fd):
    result.reason = "function '" & funcName &
      "' has no Structured body (extern prototype — not extractable)"
    return
  return extractFunDecl(ctx, fd)

proc llbcAllToCanonical*(root: JsonNode): seq[LlbcToCanonicalResult] =
  ## EVERY fun_decl in document order — extraction result or explicit
  ## per-declaration failure. Nothing is silently dropped at declaration
  ## granularity (a prototype without a Structured body is reported, not
  ## skipped).
  result = @[]
  if root.isNil or root.kind != JObject:
    result.add(LlbcToCanonicalResult(ok: false, error: rceMalformed,
      reason: "LLBC document is not a JSON object"))
    return
  if docHasErrors(root):
    result.add(LlbcToCanonicalResult(ok: false, error: rceMalformed,
      reason: "LLBC top-level has_errors is set (fail-closed)"))
    return
  let translated = jField(root, "translated")
  if translated.isNil or translated.kind != JObject:
    result.add(LlbcToCanonicalResult(ok: false, error: rceMalformed,
      reason: "LLBC document without 'translated'"))
    return
  let decls = funDecls(translated)
  if decls.isNil or decls.kind != JArray:
    result.add(LlbcToCanonicalResult(ok: false, error: rceMalformed,
      reason: "LLBC document without fun_decls"))
    return
  let ft = validateLlbcFileTable(root)
  if not ft.ok:
    result.add(LlbcToCanonicalResult(ok: false, error: rceMalformed,
      reason: "LLBC files table pre-validation failed: " & ft.reason))
    return
  let ctx = buildDeclCtx(translated, ft.entries)
  for i in 0 ..< decls.elems.len:
    let fd = decls.elems[i]
    if not hasStructuredBody(fd):
      let fn = lastNameSegment(fd)
      let hint = if fn.len > 0: fn else: "<unnamed decl " & $i & ">"
      result.add(LlbcToCanonicalResult(ok: false,
        error: rceUnsupportedGrammar,
        reason: "declaration '" & hint &
        "' has no Structured body (extern prototype — not extractable)"))
      continue
    result.add(extractFunDecl(ctx, fd))

proc parseLlbcFile*(path: string): LlbcFile {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## I/O boundary: read + parse a Charon LLBC JSON file. Never raises — any
  ## read/parse failure is an explicit not-ok result.
  try:
    let text = readFile(path)
    LlbcFile(ok: true, root: parseJson(text), reason: "")
  except CatchableError as e:
    LlbcFile(ok: false, root: nil,
             reason: "cannot read/parse LLBC JSON '" & path & "': " & e.msg)

{.pop.}
