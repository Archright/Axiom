import core/trusted/layer_declaration
import std/tables
import core/trusted/axiom_ir_types
axiomLayer "domain"
{.push raises: [].}

type
  SymbolOriginKind* = enum
    sokParam
    sokLet
    sokLoopState
    sokLoopIndex
    sokResult
    sokExitValue
    sokImplicit

  SymbolOrigin* = object
    kind*: SymbolOriginKind
    sourceId*: string

  SymbolEntry* = object
    name*: string
    origin*: SymbolOrigin
    irType*: IRType
    scope*: string

  SymbolTable* = object
    symbols*: seq[SymbolEntry]
    nameIndex*: Table[string, int]

func addSymbol*(st: var SymbolTable; name: string; origin: SymbolOrigin; irType: IRType; scope: string = "") =
  st.symbols.add(SymbolEntry(name: name, origin: origin, irType: irType, scope: scope))
  st.nameIndex[name] = st.symbols.len - 1

func hasSymbol*(st: SymbolTable; name: string): bool =
  st.nameIndex.hasKey(name)

func getSymbol*(st: SymbolTable; name: string): SymbolEntry =
  st.symbols[st.nameIndex.getOrDefault(name, -1)]

func allSymbols*(st: SymbolTable): seq[SymbolEntry] =
  st.symbols

func mergeSymbolTable*(st: var SymbolTable; other: SymbolTable) =
  for s in other.symbols:
    if not st.hasSymbol(s.name):
      st.addSymbol(s.name, s.origin, s.irType, s.scope)

{.pop.}