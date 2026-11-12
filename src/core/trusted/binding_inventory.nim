import core/trusted/layer_declaration
axiomLayer "trusted.core.binding-inventory"

## binding_inventory.nim — WP4-j.2 lock 21: independent source binding observer.
##
## Observes binding-bearing constructs in RAW NimNode / RAW PNode trees without
## translating, without type inference, without any semantic conversion.
##
## Independence contract (lock 21): this module MUST NOT reuse any traversal
## logic from ast_to_ir.nim (the translator G). The witness exists precisely to
## catch losses the translator makes — if both used the same walk, a lost
## binding would be lost twice and self-certification would reappear.
## (De Bruijn criterion structure: trusted observer separate from producer.)
##
## Observation universe (binding-witness.v1 scope contract):
##   B = B_params ∪ B_locals ∪ B_loop
## Binding-bearing constructs inside opaque constructs (template/macro/
## iterator/converter bodies, block/when/static) are NOT observed — the
## construct itself is recorded as an opaque boundary and never entered.
## opaqueExpansionStatus beyond this contract is the next WP's capability.

{.push raises: [].}

import std/macros
import std/strutils
import std/sequtils
import std/tables
import compiler/ast
import core/crypto/hash_kernel

func stripGensymLoc*(s: string): string =
  ## Strip Nim gensym suffix (everything after a backtick).
  ## Local implementation — MUST NOT reuse the translator's stripGensym
  ## (lock 21: independent observer, no shared traversal/symbol logic).
  if '`' in s: s.split('`')[0]
  else: s

type
  BindingKind* = enum
    bkLet, bkVar, bkConst, bkParam, bkLoopVar, bkOpaque

  BindingWitness* = object
    scopePath*: string
    bindingKind*: string      ## "let"|"var"|"const"|"param"|"loopVar"|"opaque:<kind>"
    localOccurrence*: int
    name*: string
    lineHint*: int = 0
    opaque*: bool = false

  InstantiationWitness* = object
    callSite*: string               ## line hint of the call site
    calleeSymbol*: string           ## e.g. "getBitsBE"
    actualArgs*: seq[string]        ## ident names of actual args (child[1..])
    formalNames*: seq[string]       ## formal param names (value + type params)
    formalTypedesc*: seq[bool]      ## true where formal is typedesc (type[T])
    positionalRelation*: seq[int]   ## formal index per actual (empty if count mismatch)
    concreteTypeArgument*: string   ## the actual arg mapped to a typedesc formal
    modulePath*: string
    occurrenceRef*: string          ## sha256Hex(modulePath & ":" & callSite & ":" & calleeSymbol & ":" & concreteTypeArgument)

  BindingInventory* = object
    witnesses*: seq[BindingWitness]
    opaqueBoundaries*: seq[string]  ## observed opaque construct kinds (deduped)
    instantiationWitnesses*: seq[InstantiationWitness]  ## WP4-j.4 template instantiation witnesses

func kindNameOf(n: NimNode): string =
  ## Human-readable kind tag for a NimNode (deterministic).
  $n.kind

func kindNameOf(p: PNode): string =
  ## Human-readable kind tag for a PNode (deterministic).
  $p.kind

func lineOf(n: NimNode): int =
  try:
    int(n.lineInfoObj.line)
  except CatchableError:
    0

func lineOf(p: PNode): int =
  try:
    int(p.info.line)
  except CatchableError:
    0

func identNameNim(n: NimNode): string =
  ## Best-effort name extraction from a NimNode ident position.
  case n.kind
  of nnkIdent, nnkSym:
    result = n.strVal
  of nnkPostfix:
    result = if n.len >= 2: identNameNim(n[1]) else: ""
  of nnkAccQuoted:
    var acc = ""
    for i in 0 ..< n.len:
      acc.add($n[i])
    result = acc
  else:
    result = ""

func identNameP(p: PNode): string =
  ## Best-effort name extraction from a PNode ident position.
  case p.kind
  of nkIdent:
    result = p.ident.s
  of nkSym:
    result = p.sym.name.s
  of nkPostfix:
    result = if p.len >= 2: identNameP(p[1]) else: ""
  of nkAccQuoted:
    var acc = ""
    for i in 0 ..< p.len:
      acc.add(identNameP(p[i]))
    result = acc
  of nkStrLit:
    result = p.strVal
  else:
    result = ""

func isTypedescNim(n: NimNode): bool =
  ## Check whether a NimNode type node is a typedesc (type[T]).
  if n.kind == nnkBracketExpr and n.len >= 1 and n[0].kind == nnkIdent:
    n[0].strVal == "type"
  else:
    false

func isTypedescP(p: PNode): bool =
  ## Check whether a PNode type node is a typedesc (type[T]).
  if p.kind == nkBracketExpr and p.len >= 1 and p[0].kind == nkIdent:
    p[0].ident.s == "type"
  else:
    false

func formalParamsNim(def: NimNode): (seq[string], seq[bool]) =
  ## Collect formal param names + typedesc flags from a NimNode func/proc def.
  ## Value params from nkFormalParams children[1..]; type params from nkGenericParams.
  var names: seq[string]
  var td: seq[bool]
  # genericParams (type params) — typically at child index 1.
  if def.len > 1 and def[1].kind == nnkGenericParams:
    for i in 0 ..< def[1].len:
      let d = def[1][i]
      if d.kind == nnkIdentDefs and d.len >= 2:
        names.add identNameNim(d[0])
        td.add isTypedescNim(d[1])
  # formalParams at child index 3; params are children[1..] (child[0] is return type).
  if def.len > 3 and def[3].kind == nnkFormalParams:
    for i in 1 ..< def[3].len:
      let d = def[3][i]
      if d.kind == nnkIdentDefs and d.len >= 3:
        names.add identNameNim(d[0])
        td.add isTypedescNim(d[1])
  result = (names, td)

func formalParamsP(p: PNode): (seq[string], seq[bool]) =
  ## Collect formal param names + typedesc flags from a PNode func/proc def.
  var names: seq[string]
  var td: seq[bool]
  if p.len > 1 and p[1].kind == nkGenericParams:
    for i in 0 ..< p[1].len:
      let d = p[1][i]
      if d.kind == nkIdentDefs and d.len >= 2:
        names.add identNameP(d[0])
        td.add isTypedescP(d[1])
  if p.len > 3 and p[3].kind == nkFormalParams:
    for i in 1 ..< p[3].len:
      let d = p[3][i]
      if d.kind == nkIdentDefs and d.len >= 3:
        names.add identNameP(d[0])
        td.add isTypedescP(d[1])
  result = (names, td)

# ── NimNode observer ───────────────────────────────────────────

func findFuncDefParamsNim(root: NimNode): Table[string, (seq[string], seq[bool])] =
  ## Non-recursive collection of func/proc def formal params by name.
  ## Stops at opaque boundaries (no body entry).
  var stack: seq[NimNode] = @[root]
  while stack.len > 0:
    let n = stack.pop()
    if n.isNil: continue
    case n.kind
    of nnkFuncDef, nnkProcDef:
      let name = identNameNim(n[0])
      result[name] = formalParamsNim(n)
    of nnkTemplateDef, nnkMacroDef, nnkIteratorDef, nnkConverterDef,
       nnkBlockStmt, nnkBlockExpr, nnkWhenStmt, nnkStaticStmt,
       nnkImportStmt, nnkExportStmt, nnkTypeSection:
      discard  # opaque — do not enter for funcDef collection
    else:
      for i in 0 ..< n.len:
        stack.add(n[i])

func observeTemplateInstantiationsNim(root: NimNode;
    funcDefs: Table[string, (seq[string], seq[bool])];
    modulePath: string; inv: var BindingInventory) =
  ## Walk to find nnkTemplateDef nodes; for each, inspect the nkStmtList
  ## body's DIRECT children for nnkCall only (1-depth; no body expansion).
  var stack: seq[NimNode] = @[root]
  while stack.len > 0:
    let n = stack.pop()
    if n.isNil: continue
    if n.kind == nnkTemplateDef:
      # Find the body (nkStmtList) and its direct nkCall children.
      for i in 0 ..< n.len:
        if n[i].kind == nnkStmtList:
          for j in 0 ..< n[i].len:
            let call = n[i][j]
            if call.kind != nnkCall or call.len < 1: continue
            let callee = identNameNim(call[0])
            let actuals = (1 ..< call.len).mapIt(identNameNim(call[it]))
            let entry = funcDefs.getOrDefault(callee)
            let formalNames = entry[0]
            let formalTypedesc = entry[1]
            # concreteTypeArgument: actual mapped to a typedesc formal.
            var concreteTypeArgument = ""
            for k, isTd in formalTypedesc:
              if isTd and k < actuals.len:
                concreteTypeArgument = actuals[k]
            let positionalRelation = if actuals.len == formalNames.len:
              toSeq(0 ..< actuals.len)
            else:
              @[]
            let callSite = $lineOf(n)
            let witness = InstantiationWitness(
              callSite: callSite,
              calleeSymbol: callee,
              actualArgs: actuals,
              formalNames: formalNames,
              formalTypedesc: formalTypedesc,
              positionalRelation: positionalRelation,
              concreteTypeArgument: concreteTypeArgument,
              modulePath: modulePath,
              occurrenceRef: sha256Hex(modulePath & ":" & callSite & ":" & callee & ":" & concreteTypeArgument))
            inv.instantiationWitnesses.add(witness)
          break
      # Do NOT recurse into template body (1-depth opaque contract).
    elif n.kind notin {nnkTemplateDef, nnkMacroDef, nnkIteratorDef, nnkConverterDef,
       nnkBlockStmt, nnkBlockExpr, nnkWhenStmt, nnkStaticStmt,
       nnkImportStmt, nnkExportStmt, nnkTypeSection}:
      for i in 0 ..< n.len:
        stack.add(n[i])

func findFuncDefParamsP(root: PNode): Table[string, (seq[string], seq[bool])] =
  ## Non-recursive collection of func/proc def formal params by name (PNode).
  var stack: seq[PNode] = @[root]
  while stack.len > 0:
    let n = stack.pop()
    if n.isNil: continue
    if n.kind in {nkEmpty, nkIdent, nkSym, nkCharLit,
                  nkIntLit..nkInt64Lit, nkUIntLit..nkUInt64Lit,
                  nkFloatLit..nkFloat128Lit, nkStrLit, nkRStrLit,
                  nkTripleStrLit, nkNilLit}:
      continue
    case n.kind
    of nkFuncDef, nkProcDef:
      let name = identNameP(n[0])
      result[name] = formalParamsP(n)
    of nkTemplateDef, nkMacroDef, nkIteratorDef, nkConverterDef,
       nkBlockStmt, nkBlockExpr, nkWhenStmt, nkStaticStmt,
       nkImportStmt, nkExportStmt, nkTypeSection:
      discard
    else:
      for i in 0 ..< n.len:
        if not n[i].isNil:
          stack.add(n[i])

func observeTemplateInstantiationsP(root: PNode;
    funcDefs: Table[string, (seq[string], seq[bool])];
    modulePath: string; inv: var BindingInventory) =
  var stack: seq[PNode] = @[root]
  while stack.len > 0:
    let n = stack.pop()
    if n.isNil: continue
    if n.kind in {nkEmpty, nkIdent, nkSym, nkCharLit,
                  nkIntLit..nkInt64Lit, nkUIntLit..nkUInt64Lit,
                  nkFloatLit..nkFloat128Lit, nkStrLit, nkRStrLit,
                  nkTripleStrLit, nkNilLit}:
      continue
    if n.kind == nkTemplateDef:
      for i in 0 ..< n.len:
        if n[i].kind == nkStmtList:
          for j in 0 ..< n[i].len:
            let call = n[i][j]
            if call.kind != nkCall or call.len < 1: continue
            let callee = identNameP(call[0])
            let actuals = (0 ..< call.len - 1).mapIt(identNameP(call[it + 1]))
            let entry = funcDefs.getOrDefault(callee)
            let formalNames = entry[0]
            let formalTypedesc = entry[1]
            var concreteTypeArgument = ""
            for k, isTd in formalTypedesc:
              if isTd and k < actuals.len:
                concreteTypeArgument = actuals[k]
            let callSite = $lineOf(n)
            let witness = InstantiationWitness(
              callSite: callSite,
              calleeSymbol: callee,
              actualArgs: actuals,
              formalNames: formalNames,
              formalTypedesc: formalTypedesc,
              positionalRelation: if actuals.len == formalNames.len: toSeq(0 ..< actuals.len) else: @[],
              concreteTypeArgument: concreteTypeArgument,
              modulePath: modulePath,
              occurrenceRef: sha256Hex(modulePath & ":" & callSite & ":" & callee & ":" & concreteTypeArgument))
            inv.instantiationWitnesses.add(witness)
          break
    elif n.kind notin {nkTemplateDef, nkMacroDef, nkIteratorDef, nkConverterDef,
       nkBlockStmt, nkBlockExpr, nkWhenStmt, nkStaticStmt,
       nkImportStmt, nkExportStmt, nkTypeSection}:
      for i in 0 ..< n.len:
        if not n[i].isNil:
          stack.add(n[i])

func observeInstantiations*(def: PNode; modulePath: string; inv: var BindingInventory) =
  ## WP4-j.4: observe template instantiation calls in a raw PNode tree.
  let funcDefs = findFuncDefParamsP(def)
  observeTemplateInstantiationsP(def, funcDefs, modulePath, inv)

# ── NimNode observer ──────────────────────────────────────────────

func observeNim(n: NimNode; scopePath: string; inv: var BindingInventory) =
  ## Recursive RAW observation. Never translates; opaque constructs are
  ## recorded as boundaries and never entered.
  case n.kind
  of nnkLetSection:
    var occ = 0
    for i in 0 ..< n.len:
      let identDefs = n[i]
      if identDefs.kind == nnkIdentDefs and identDefs.len >= 3:
        for j in 0 ..< identDefs.len - 2:
          inv.witnesses.add(BindingWitness(
            scopePath: scopePath, bindingKind: "let",
            localOccurrence: occ, name: stripGensymLoc(identNameNim(identDefs[j])),
            lineHint: lineOf(identDefs), opaque: false))
          inc occ
    for i in 0 ..< n.len:
      for j in 2 ..< n[i].len:
        observeNim(n[i][j], scopePath & "/val[" & $i & "]", inv)
  of nnkVarSection:
    var occ = 0
    for i in 0 ..< n.len:
      let identDefs = n[i]
      if identDefs.kind == nnkIdentDefs and identDefs.len >= 3:
        for j in 0 ..< identDefs.len - 2:
          inv.witnesses.add(BindingWitness(
            scopePath: scopePath, bindingKind: "var",
            localOccurrence: occ, name: stripGensymLoc(identNameNim(identDefs[j])),
            lineHint: lineOf(identDefs), opaque: false))
          inc occ
    for i in 0 ..< n.len:
      for j in 2 ..< n[i].len:
        observeNim(n[i][j], scopePath & "/val[" & $i & "]", inv)
  of nnkConstSection:
    var occ = 0
    for i in 0 ..< n.len:
      let identDefs = n[i]
      # NOTE: const sections contain nnkConstDef nodes (not nnkIdentDefs).
      if identDefs.kind in {nnkIdentDefs, nnkConstDef} and identDefs.len >= 3:
        for j in 0 ..< identDefs.len - 2:
          inv.witnesses.add(BindingWitness(
            scopePath: scopePath, bindingKind: "const",
            localOccurrence: occ, name: stripGensymLoc(identNameNim(identDefs[j])),
            lineHint: lineOf(identDefs), opaque: false))
          inc occ
    for i in 0 ..< n.len:
      for j in 2 ..< n[i].len:
        observeNim(n[i][j], scopePath & "/val[" & $i & "]", inv)
  of nnkFormalParams:
    var occ = 0
    for i in 1 ..< n.len:
      let identDefs = n[i]
      if identDefs.kind == nnkIdentDefs and identDefs.len >= 3:
        for j in 0 ..< identDefs.len - 2:
          inv.witnesses.add(BindingWitness(
            scopePath: scopePath, bindingKind: "param",
            localOccurrence: occ, name: stripGensymLoc(identNameNim(identDefs[j])),
            lineHint: lineOf(identDefs), opaque: false))
          inc occ
  of nnkForStmt:
    # loop variables: child[0] is nnkIdent or nnkVarTuple
    var occ = 0
    if n[0].kind == nnkIdent:
      inv.witnesses.add(BindingWitness(
        scopePath: scopePath, bindingKind: "loopVar",
        localOccurrence: occ, name: stripGensymLoc(identNameNim(n[0])),
        lineHint: lineOf(n), opaque: false))
      inc occ
    elif n[0].kind == nnkVarTuple:
      for i in 0 ..< n[0].len:
        inv.witnesses.add(BindingWitness(
          scopePath: scopePath, bindingKind: "loopVar",
          localOccurrence: occ, name: stripGensymLoc(identNameNim(n[0][i])),
          lineHint: lineOf(n), opaque: false))
        inc occ
    if n.len >= 3:
      observeNim(n[2], scopePath & "/forbody", inv)
  of nnkTemplateDef, nnkMacroDef, nnkIteratorDef, nnkConverterDef,
     nnkBlockStmt, nnkBlockExpr, nnkWhenStmt, nnkStaticStmt,
     nnkImportStmt, nnkExportStmt, nnkTypeSection:
    # Opaque boundary: observed, never entered, never interpreted.
    # NOTE: nnkWhenExp does not exist in NimNodeKind (PNode-only kind).
    let tag = "opaque:" & kindNameOf(n)
    inv.opaqueBoundaries.add(tag)
    inv.witnesses.add(BindingWitness(
      scopePath: scopePath, bindingKind: tag,
      localOccurrence: 0, name: "", lineHint: lineOf(n), opaque: true))
  else:
    # Recurse into children — the observer must see the WHOLE tree.
    for i in 0 ..< n.len:
      observeNim(n[i], scopePath & "/" & kindNameOf(n) & "[" & $i & "]", inv)

func observeP(p: PNode; scopePath: string; inv: var BindingInventory) =
  ## Recursive RAW observation for the runtime PNode path.
  case p.kind
  of nkLetSection:
    var occ = 0
    for i in 0 ..< p.len:
      let identDefs = p[i]
      if identDefs.kind == nkIdentDefs and identDefs.len >= 3:
        for j in 0 ..< identDefs.len - 2:
          inv.witnesses.add(BindingWitness(
            scopePath: scopePath, bindingKind: "let",
            localOccurrence: occ, name: stripGensymLoc(identNameP(identDefs[j])),
            lineHint: lineOf(identDefs), opaque: false))
          inc occ
    for i in 0 ..< p.len:
      for j in 2 ..< p[i].len:
        observeP(p[i][j], scopePath & "/val[" & $i & "]", inv)
  of nkVarSection:
    var occ = 0
    for i in 0 ..< p.len:
      let identDefs = p[i]
      if identDefs.kind == nkIdentDefs and identDefs.len >= 3:
        for j in 0 ..< identDefs.len - 2:
          inv.witnesses.add(BindingWitness(
            scopePath: scopePath, bindingKind: "var",
            localOccurrence: occ, name: stripGensymLoc(identNameP(identDefs[j])),
            lineHint: lineOf(identDefs), opaque: false))
          inc occ
    for i in 0 ..< p.len:
      for j in 2 ..< p[i].len:
        observeP(p[i][j], scopePath & "/val[" & $i & "]", inv)
  of nkConstSection:
    var occ = 0
    for i in 0 ..< p.len:
      let identDefs = p[i]
      # NOTE: const sections contain nkConstDef nodes (not nkIdentDefs).
      if identDefs.kind in {nkIdentDefs, nkConstDef} and identDefs.len >= 3:
        for j in 0 ..< identDefs.len - 2:
          inv.witnesses.add(BindingWitness(
            scopePath: scopePath, bindingKind: "const",
            localOccurrence: occ, name: stripGensymLoc(identNameP(identDefs[j])),
            lineHint: lineOf(identDefs), opaque: false))
          inc occ
    for i in 0 ..< p.len:
      for j in 2 ..< p[i].len:
        observeP(p[i][j], scopePath & "/val[" & $i & "]", inv)
  of nkFormalParams:
    var occ = 0
    for i in 1 ..< p.len:
      let identDefs = p[i]
      if identDefs.kind == nkIdentDefs and identDefs.len >= 3:
        for j in 0 ..< identDefs.len - 2:
          inv.witnesses.add(BindingWitness(
            scopePath: scopePath, bindingKind: "param",
            localOccurrence: occ, name: stripGensymLoc(identNameP(identDefs[j])),
            lineHint: lineOf(identDefs), opaque: false))
          inc occ
  of nkForStmt:
    var occ = 0
    if p[0].kind == nkIdent:
      inv.witnesses.add(BindingWitness(
        scopePath: scopePath, bindingKind: "loopVar",
        localOccurrence: occ, name: stripGensymLoc(identNameP(p[0])),
        lineHint: lineOf(p), opaque: false))
      inc occ
    elif p[0].kind == nkVarTuple:
      for i in 0 ..< p[0].len:
        inv.witnesses.add(BindingWitness(
          scopePath: scopePath, bindingKind: "loopVar",
          localOccurrence: occ, name: stripGensymLoc(identNameP(p[0][i])),
          lineHint: lineOf(p), opaque: false))
        inc occ
    if p.len >= 3:
      observeP(p[2], scopePath & "/forbody", inv)
  of nkTemplateDef, nkMacroDef, nkIteratorDef, nkConverterDef,
     nkBlockStmt, nkBlockExpr, nkWhenStmt, nkStaticStmt,
     nkImportStmt, nkExportStmt, nkTypeSection:
    let tag = "opaque:" & kindNameOf(p)
    inv.opaqueBoundaries.add(tag)
    inv.witnesses.add(BindingWitness(
      scopePath: scopePath, bindingKind: tag,
      localOccurrence: 0, name: "", lineHint: lineOf(p), opaque: true))
  else:
    # Atom kinds (ident/sym/literals) have no `sons` — touching p.len raises
    # FieldDefect on them (compiler/ast.nim len() contract). Guard by kind,
    # mirroring pnode_to_canon's atom guard (but with independent logic).
    if p.kind notin {nkEmpty, nkIdent, nkSym, nkCharLit,
                     nkIntLit..nkInt64Lit, nkUIntLit..nkUInt64Lit,
                     nkFloatLit..nkFloat128Lit,
                     nkStrLit, nkRStrLit, nkTripleStrLit, nkNilLit}:
      for i in 0 ..< p.len:
        if not p[i].isNil:
          observeP(p[i], scopePath & "/" & kindNameOf(p) & "[" & $i & "]", inv)

# ── Entry points ──────────────────────────────────────────────────

func inventoryFromNimNode*(def: NimNode; funcName: string): BindingInventory =
  ## Observe binding-bearing constructs in a raw proc/func NimNode.
  ## Independent of the translator: no shared traversal, no translation.
  if def.kind notin {nnkProcDef, nnkFuncDef}:
    return
  observeNim(def, "func[" & funcName & "]", result)

func inventoryFromPNode*(pn: PNode; funcName: string): BindingInventory =
  ## Observe binding-bearing constructs in a raw proc/func PNode.
  if pn.kind notin {nkProcDef, nkFuncDef}:
    return
  observeP(pn, "func[" & funcName & "]", result)

{.pop.}
