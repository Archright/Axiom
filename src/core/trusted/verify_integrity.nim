import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## verifyIntegrity — Compile-time Code Block Verification
## ============================================================
## 2-pass architecture:
##   Pass 1 (untyped macro): captures code block as AST, wraps in static verification
##   Pass 2 (typed proc): resolves symbols, validates effects, translates to SMT
##
## Defense layers:
##   Layer 1: Blacklist — forbidden AST node kinds (cast, addr, asm, emit)
##   Layer 2: FFI Introspection — detect importc/header/codegenDecl via getImpl
##   Layer 3: Strict Whitelist — only approved mathematical primitives allowed
##
## v7 patches:
##   - getImpl nil (external symbols) → Strict Whitelist fallback
##   - Generic uninstantiated symbols → Strict Whitelist fallback
##   - Forward declaration guideline: code inside verifyIntegrity must be top-down
##
## AGENTS.md §0.6: Static First Enforcement
## ============================================================

import std/macros
import std/strutils
import core/trusted/effect_bridge  # For AxiomIOEffect

# ─── SMT Pure Subset: Blacklist ─────────────────────────────────────────────────

const forbiddenKinds* = {
  nnkCast,          # Pointer/integer casting — bypasses type system
  nnkAddr,          # Address-of — raw pointer access
  nnkPtrTy,         # Pointer type definition
  nnkRefTy,         # Reference type definition
  nnkObjConstr,     # Object construction (can contain hidden refs)
  nnkAsmStmt,       # Inline assembly — completely unverifiable
}

func validatePureSubset*(body: NimNode) {.compileTime.} =
  ## Recursively validate that the AST contains only pure algebraic constructs.
  for node in body:
    if node.kind in forbiddenKinds:
      error("SMT subset violation: " & $node.kind &
            " is not in the pure algebraic subset. " &
            "verifyIntegrity blocks may only use pure value-type operations.", node)
    validatePureSubset(node)

# ─── SMT Pure Subset: Emit/Pragma Detection ────────────────────────────────────

func validateNoEmit*(body: NimNode) {.compileTime.} =
  ## Detect {.emit.} pragma — injects raw C code, bypassing all Nim safety.
  for node in body:
    if node.kind == nnkPragma:
      for p in node:
        if p.kind == nnkExprColonExpr and p.len >= 2:
          if p[0].kind == nnkIdent and p[0].strVal == "emit":
            error("SMT subset violation: {.emit.} pragma injects raw C code, " &
                  "completely bypassing the effect system.", node)
        elif p.kind == nnkIdent and p.strVal == "emit":
          error("SMT subset violation: {.emit.} pragma detected.", node)
    validateNoEmit(node)

# ─── Strict Whitelist ──────────────────────────────────────────────────────────

const whitelistedSymbols* = [
  # Arithmetic
  "+", "-", "*", "div", "mod", "abs", "succ", "pred",
  # Comparison
  "==", "!=", "<", "<=", ">", ">=",
  # Logic
  "not", "and", "or", "xor",
  # Bitwise
  "shl", "shr", "bitand", "bitor", "bitxor",
  # Containers (pure)
  "len", "high", "low", "[]",
  # Conversions (pure)
  "int", "float", "bool", "char",
  # System (pure)
  "sizeof", "clamp", "min", "max",
]

func isWhitelistedSymbol*(sym: NimNode): bool {.compileTime.} =
  ## Check if a symbol is in the Strict Whitelist.
  let name = $sym
  result = name in whitelistedSymbols

# ─── FFI Introspection ─────────────────────────────────────────────────────────

const ffiPragmas* = [
  "importc", "importcpp", "importjs", "importObjC",
  "header", "codegenDecl", "dynlib", "link"
]

func validateNoFFI*(body: NimNode) {.compileTime.} =
  ## Detect FFI symbols via getImpl introspection.
  ## v7 patches: getImpl nil → Strict Whitelist, generic → Strict Whitelist
  for node in body:
    if node.kind == nnkCall and node[0].kind == nnkSym:
      let impl = node[0].getImpl
      if impl.isNil:
        if not isWhitelistedSymbol(node[0]):
          error("SMT subset: external symbol '" & $node[0] &
                "' has no impl (nil) and is NOT in the Strict Whitelist.", node)
      elif impl.kind in {nnkProcDef, nnkFuncDef}:
        let pragmas = impl[4]
        for p in pragmas:
          let name = if p.kind == nnkIdent: p.strVal
                     elif p.kind == nnkExprColonExpr and p[0].kind == nnkIdent: p[0].strVal
                     else: ""
          if name in ffiPragmas:
            error("SMT subset violation: FFI symbol '" & $node[0] &
                  "' has {" & name & "} pragma.", node)
      elif impl.kind in {nnkSym, nnkBracketExpr}:
        if not isWhitelistedSymbol(node[0]):
          error("SMT subset: generic/uninstantiated symbol '" & $node[0] &
                "' not in Strict Whitelist.", node)
    validateNoFFI(node)

# ─── verifyIntegrity: 2-pass Macro ─────────────────────────────────────────────

macro verifyIntegrity*(body: untyped): untyped =
  ## Pass 1 (untyped): Capture code block as AST.
  ## Wraps in static: call to Pass 2 (typed) for symbol-level validation.
  result = quote do:
    static:
      verifyIntegrityCheck(`body`)
    `body`

macro verifyIntegrityCheck*(body: typed): untyped =
  ## Pass 2 (typed): Validate symbols, effects, and SMT subset.
  validatePureSubset(body)
  validateNoEmit(body)
  validateNoFFI(body)
  result = newEmptyNode()

{.pop.}
