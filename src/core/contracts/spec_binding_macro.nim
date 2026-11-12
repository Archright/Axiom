import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## Design-by-Contract macros for Layer 2 of the 3-Layer Contract Architecture.
##
## Provides `requires` and `ensures` macros for compile-time-enforceable
## preconditions and postconditions, plus `contractProc` for full proc wrapping.
## Checks run in non-release builds only (zero runtime cost in production).
##
## Also provides `{.spec("ID").} pragma for spec-code binding verification:
##   - Reads docs/spec/three_tier_contract_architecture.md at compile time
##   - Verifies spec ID exists in the document table
##   - Fails compilation if spec ID is missing (prevents doc-code drift)

import std/[macros, strutils, os, json]

# ---------------------------------------------------------------------------
# Spec Registry — Single source of truth for spec IDs
# ---------------------------------------------------------------------------

const RepoRootAnchor = currentSourcePath().parentDir().parentDir().parentDir().parentDir()
  ## repo-root anchor: currentSourcePath() → src/core/contracts/spec_binding_macro.nim;
  ## 4×parentDir = repo root. `staticRead` resolves relative to the directory of
  ## the file containing the call first, then falls back to the import/search
  ## paths — CWD is never consulted (Nim 2.2.10 `compiler/vmdeps.nim` `opSlurp`;
  ## Q-009 in docs/spec/nim_2_2_10_stdlib_quirks.md). An absolute anchor is the
  ## only machine-independent form: it is returned as-is by `findFile`
  ## (`compiler/options.nim:928-932`), while a relative literal depends on the
  ## module's layout depth and a wrong-depth one needs a machine-local symlink.

const RegistryPath = RepoRootAnchor / "docs/spec/spec_registry.json"
static:
  if not fileExists(RegistryPath):
    error("Spec registry file missing: " & RegistryPath)
  else:
    let registry = parseJson(staticRead(RegistryPath))
    when not defined(release):
      discard registry

# ---------------------------------------------------------------------------
# Spec-Code Binding — Compile-time document synchronization
# ---------------------------------------------------------------------------

const
  SpecDocPath = RepoRootAnchor / "docs/spec/three_tier_contract_architecture.md"
  SpecDocContent = staticRead(SpecDocPath)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro spec*(id: static string, node: untyped): untyped =
  ## Spec-code binding pragma — verifies spec ID exists in docs at compile time.
  ## Prevents documentation drift by failing compilation if ID is missing.
  ##
  ## id: spec ID to look up in the document table
  ## node: AST node that the pragma is attached to (auto-passed by compiler)

  let specId = id
  let formattedCell = "| " & specId & " |"

  # Cell-level strict matching prevents substring false positives
  if formattedCell notin SpecDocContent:
    error(
      "\n[FAIL] [COMPILER-SPEC-DRIFT] Spec ID '" & specId & "' is missing in docs!\n" &
      "   ACTION: Add '| " & specId & " | ... |' to the specification table in docs.\n"
    )

  # Return the original AST node unchanged (preserves type definition)
  result = node

# ---------------------------------------------------------------------------
# Contract macros (existing)
# ---------------------------------------------------------------------------

## Module-level contract scope usage:

## Module-level contract scope usage:
##
##   {.push contractProc.}
##   proc add*(a: Matrix; b: Matrix): Matrix = ...
##   proc multiply*(a: Matrix; b: Matrix): Matrix = ...
##   {.pop.}
##
## This tells `ax prove` to extract contracts from all procs in this module.
## Individual `{.requires.}` / `{.ensures.}` pragmas still take precedence.

var contractScopeDepth* {.compileTime.}: int = 0

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
template contractProc* {.pragma.}

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro contractScope*(body: untyped): untyped =
  ## Module-level contract scope.
  ## When used as `{.push contractProc.}`, all procs in scope get contract enforcement.
  result = body

proc isContractScopeActive*(): bool {.compileTime.} =
  ## Checks if we're inside a `{.push contractProc.}` scope.
  contractScopeDepth > 0

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro constructor*(body: untyped): untyped =
  result = body

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro requires*(cond: typed, msg: static string = ""): untyped =
  result = quote do:
    when not defined(release):
      if not `cond`:
        raise newException(AssertionDefect,
          "Precondition failed: " & `msg`)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro ensures*(cond: typed, msg: static string = ""): untyped =
  result = quote do:
    when not defined(release):
      defer:
        if not `cond`:
          raise newException(AssertionDefect,
            "Postcondition failed: " & `msg`)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro contractProc*(procDef: untyped): untyped =
  var node = procDef
  if node.kind == nnkStmtList and node.len == 1:
    node = node[0]
  if node.kind != nnkProcDef:
    error("contractProc requires a proc definition, got " & $node.kind, node)
  let nameNode = node[0]
  let params = node[3]
  var pragmas = node[4]
  var body = node[6]

  if pragmas.kind == nnkPragma and pragmas.len == 0:
    pragmas = newEmptyNode()

  var isConstructor = false
  if pragmas.kind == nnkPragma:
    for i in 0..<pragmas.len:
      if pragmas[i].kind == nnkIdent and eqIdent(pragmas[i], "constructor"):
        isConstructor = true
        break

  if isConstructor:
    var i = 0
    while i < pragmas.len:
      if pragmas[i].kind == nnkIdent and eqIdent(pragmas[i], "constructor"):
        pragmas.del(i)
        break
      inc i

  var requiresNodes: seq[NimNode]
  var ensuresNodes: seq[NimNode]

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
  template extractContractPragmas(pragmaList: NimNode) =
    if pragmaList.kind == nnkPragma:
      var i = 0
      while i < pragmaList.len:
        let p = pragmaList[i]
        if p.kind == nnkExprColonExpr and p.len >= 2:
          let key = p[0]
          if key.kind == nnkIdent:
            if key.eqIdent("requires"):
              requiresNodes.add(p[1])
              pragmaList.del(i)
              continue
            elif key.eqIdent("ensures"):
              ensuresNodes.add(p[1])
              pragmaList.del(i)
              continue
        inc i

  extractContractPragmas(pragmas)

  var newBody = newStmtList()

  if not isConstructor:
    for req in requiresNodes:
      newBody.add(quote do:
        when not defined(release):
          if not `req`:
            raise newException(AssertionDefect,
              "Precondition failed"))
  newBody.add(body)

  for ens in ensuresNodes:
    newBody.add(quote do:
      when not defined(release):
        defer:
          if not `ens`:
            raise newException(AssertionDefect,
              "Postcondition failed"))

  var paramChildren: seq[NimNode]
  for i in 0..<params.len:
    paramChildren.add(params[i])

  let pragmaArg = if pragmas.len == 0: newEmptyNode() else: pragmas

  result = newProc(nameNode, paramChildren, newBody, nnkProcDef, pragmaArg)

{.pop.}
