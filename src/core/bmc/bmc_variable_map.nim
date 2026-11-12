import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
## BMC Variable Map — SSA Normalization + Scope Context Stack
##
## Provides variable mapping between source code variables and Z3 internal
## variables, with SSA index canonicalization and lexical scoping support.
##
## Design: Layer 2 of the 3-Layer Deterministic Architecture.

import std/strutils  # find, contains
import core/types/results  # Result type usage

type
  VariableMapping* = object
    sourceName*: string        # Source code variable name (e.g., "idx", "counter")
    smtName*: string           # Z3 internal variable name (e.g., "x!0", "var0")
    ssaIndex*: int             # SSA index
    bmcStep*: int              # BMC step
    sourceLine*: int           # Source code line number
    sourceFile*: string        # Source file path
    scopeContext*: string      # Scope context (e.g., "loop_body", "if_then")

  VariableMapTable* = object
    mappings*: seq[VariableMapping]
    sourceFile*: string

  ScopeContextStack* = object
    stack*: seq[string]        # Scope context stack (parent scopes)
    currentScope*: string      # Current active scope (hierarchical path)
    scopeCounter*: int         # Sequential scope ID counter

func initScopeContextStack*(initialScope: string = "global"): ScopeContextStack =
  ## Initialize a scope context stack with an initial scope
  ScopeContextStack(stack: @[], currentScope: initialScope, scopeCounter: 0)

func pushScope*(ctx: var ScopeContextStack; scopeLabel: string) =
  ## Push a new scope onto the context stack with unique hierarchical ID.
  ## Generates "global.main.if_1.loop_2" style paths to prevent
  ## sibling scope name collisions (e.g., two independent if_then blocks).
  ctx.stack.add(ctx.currentScope)
  ctx.scopeCounter.inc
  ctx.currentScope = ctx.currentScope & "." & scopeLabel & "_" & $ctx.scopeCounter

func popScope*(ctx: var ScopeContextStack) =
  ## Pop the current scope and restore the parent scope
  if ctx.stack.len > 0:
    ctx.currentScope = ctx.stack[^1]
    ctx.stack.setLen(ctx.stack.len - 1)

func canonicalizeVariable*(smtName: string; varMap: VariableMapTable; 
                           scopeCtx: ScopeContextStack): string =
  ## SSA index canonicalization: Convert Z3 internal variable names to
  ## source code variable names using lexical scoping tree traversal.
  ##
  ## Traverses from innermost scope to outermost (parent) scopes to
  ## handle variable shadowing and scope visibility correctly.
  
  # 1. Search in current scope first
  for mapping in varMap.mappings:
    if mapping.smtName == smtName and mapping.scopeContext == scopeCtx.currentScope:
      return mapping.sourceName
      
  # 2. Traverse parent scopes in reverse order (nearest ancestor first)
  # This ensures proper lexical scoping and handles variable shadowing
  if scopeCtx.stack.len > 0:
    for k in countdown(scopeCtx.stack.len - 1, 0):
      let parentScope = scopeCtx.stack[k]
      for mapping in varMap.mappings:
        if mapping.smtName == smtName and mapping.scopeContext == parentScope:
          return mapping.sourceName
  
  # 3. No mapping found in any scope - strip SSA index for basic name
  # "x_ssa_4" → "x", "x!0" → "x"
  let bangIdx = smtName.find('!')
  if bangIdx > 0:
    return smtName[0 ..< bangIdx]
  
  let ssaIdx = smtName.find("_ssa_")
  if ssaIdx > 0:
    return smtName[0 ..< ssaIdx]
  
  # 4. Return as-is if no pattern matches
  return smtName

func addMapping*(varMap: var VariableMapTable; mapping: VariableMapping) =
  ## Add a variable mapping to the table
  varMap.mappings.add(mapping)

func findMapping*(varMap: VariableMapTable; smtName: string; 
                  scopeCtx: ScopeContextStack): Result[VariableMapping, string] =
  ## Find a variable mapping using lexical scoping traversal
  ## Returns the first matching mapping found in scope hierarchy
  
  # Search current scope
  for mapping in varMap.mappings:
    if mapping.smtName == smtName and mapping.scopeContext == scopeCtx.currentScope:
      return ok(mapping)
  
  # Search parent scopes
  if scopeCtx.stack.len > 0:
    for k in countdown(scopeCtx.stack.len - 1, 0):
      let parentScope = scopeCtx.stack[k]
      for mapping in varMap.mappings:
        if mapping.smtName == smtName and mapping.scopeContext == parentScope:
          return ok(mapping)
  
  err("No mapping found for: " & smtName)

func buildVariableMap*(config: object; sourceCode: string): VariableMapTable =
  ## Build a variable mapping table from BMC configuration and source code.
  ##
  ## This would analyze the source code to extract variable declarations
  ## and create mappings between source variables and SMT variables.
  ##
  ## Placeholder implementation - would be enhanced with actual AST analysis.
  VariableMapTable(mappings: @[], sourceFile: "")

func normalizeSSAIndices*(smtExpr: string; varMap: VariableMapTable; 
                         scopeCtx: ScopeContextStack): string =
  ## Normalize SSA indices in an SMT expression
  ## Replaces Z3 internal variable names with canonical source code names
  
  result = smtExpr
  # This would use the variable map to replace SSA-indexed variables
  # with their canonical source code names
  # Placeholder implementation

{.pop.}
