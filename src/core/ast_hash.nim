{.push raises: [].}
## ast_hash.nim — Deterministic AST-based source hashing via compiler parser
## Replaces tree-sitter CstAdapter with Nim compiler parser.
## Ignores whitespace/comments (structural hash only).
## Falls back to content hash if parsing fails.

import std/hashes
import core/parser_utils
import compiler/[ast, idents]

const SkipKinds: set[TNodeKind] = {}

func hashNode(n: PNode): Hash {.raises: [].} =
  ## Recursively hash AST node structure + semantic values.
  ## Whitespace/comments are lexer-level in Nim — never appear as AST nodes.
  if n == nil: return hash(0)
  if n.kind in SkipKinds:
    return hash(0)
  
  var h = hash(n.kind)
  
  # Leaf nodes with semantic values — hash them to differentiate content
  case n.kind
  of nkIdent:
    # Identifier nodes: hash(n.ident) is PIdent.h — the interned identifier
    # STRING hash (compiler/idents.nim "hash(x: PIdent) = x.h"). It is
    # content-based, not pointer identity, so hashes are stable across parse
    # sessions and across the shared (memoized) PNodes of parser_utils.
    h = h !& hash(n.ident)
  of nkCharLit..nkUInt64Lit:
    h = h !& hash(n.intVal)
  of nkFloatLit..nkFloat128Lit:
    h = h !& hash(n.floatVal)
  of nkStrLit..nkTripleStrLit:
    h = h !& hash(n.strVal)
  of nkSym:
    # Symbol nodes: hash the symbol name (PIdent) if present
    if not n.sym.isNil and not n.sym.name.isNil:
      h = h !& hash(n.sym.name)
  else:
    # Container nodes: hash child count then recurse
    var childCount = 0
    try:
      childCount = n.len
    except FieldDefect:
      childCount = 0
    h = h !& hash(childCount)
    
    for i in 0 ..< childCount:
      h = h !& hashNode(n[i])
  
  return h

proc computeAstHash*(source: string): Hash =
  ## Compute deterministic hash of source AST structure.
  ## Ignores whitespace/comments (structural hash only).
  ## Falls back to content hash if parsing fails.
  initParserUtils()
  let ast = parseStringAST(source)
  if ast.isNil:
    return hash(source)
  hashNode(ast)
