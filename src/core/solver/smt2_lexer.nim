import core/trusted/layer_declaration
axiomLayer "domain"
import core/crypto/hash_kernel
{.push raises: [].}

## SMT-LIB2 Standard Lexer
##
## Formal tokenizer following the SMT-LIB2 standard specification.
## Handles all edge cases that break ad-hoc parenthesis-depth parsers:
## - Quoted Symbols (|...|): identifiers with special characters
## - String Literals ("..."): with escape sequences (\\, \")
## - Comments (;): line-end, ignored
## - Keywords (:named, :precision, etc.)
## - Numerals (integer literals)
##
## Design: State machine based on the SMT-LIB2 v2.6 grammar:
##   <token> ::= <spec_constant> | <symbol> | <keyword>
##   <spec_constant> ::= <numeral> | <decimal> | <hexadecimal> | <binary> | <string>
##   <symbol> ::= <simple_symbol> | <quoted_symbol>
##   <simple_symbol> ::= <non_digit_char>+
##   <quoted_symbol> ::= |<any char except |\>|
##   <string> ::= "<any char except "\">"
##   <keyword> ::= :<simple_symbol>
##
## Reference: SMT-LIB Standard v2.6, Section 3.1 "Lexical Structure"
##
## User refinement (Plan v3 Phase B): "정식 렉서(Lexer) 기반 토큰화 —
## Quoted Symbol과 주석이 섞인 복잡한 S-expression을 안전하게 분리할 수 있습니다."

import std/[strutils, tables, hashes, algorithm]

type
  TokenKind* = enum
    tkLParen        ## (
    tkRParen        ## )
    tkSymbol        ## General identifier: x, Int, Bool, +, >=, is_int
    tkQuotedSymbol  ## |...| — identifiers with special chars
    tkString        ## "..." — string literal (escape sequences supported)
    tkKeyword       ## :... — keyword (:named, :precision, :depth)
    tkNumeral       ## Integer literal: 0, 42, -1
    tkComment       ## ; ... — line comment (consumed but not emitted)

  Token* = object
    kind*: TokenKind
    literal*: string   ## Raw text (without delimiters for strings/quoted)
    line*: int
    col*: int

  LexerState = enum
    lsNormal       ## Default state
    lsString       ## Inside "..."
    lsStringEscape ## After \ inside "..."
    lsQuoted       ## Inside |...|
    lsComment      ## After ; until newline

  SExprKind* = enum
    seAtom   ## Leaf node (symbol, string, numeral, keyword)
    seList   ## Parenthesized list

  SExprNode* = object
    ## Parsed S-expression tree node.
    case kind*: SExprKind
    of seAtom:
      value*: string
      atomKind*: TokenKind
    of seList:
      children*: seq[SExprNode]

# --- Token construction ---

func classifyToken(literal: string): TokenKind {.noSideEffect.} =
  ## Classify a raw token string into its kind.
  if literal.len == 0: return tkSymbol
  if literal[0] == ':': return tkKeyword
  if literal[0] in {'0'..'9'} or
     (literal.len > 1 and literal[0] == '-' and literal[1] in {'0'..'9'}):
    return tkNumeral
  return tkSymbol

func makeToken(literal: string; line, col: int): Token {.noSideEffect.} =
  Token(
    kind: classifyToken(literal),
    literal: literal,
    line: line,
    col: col
  )

# --- Main lexer ---

func tokenizeSmt2*(input: string): seq[Token] {.noSideEffect.} =
  ## SMT-LIB2 standard lexer.
  ##
  ## Converts raw SMT-LIB2 text into a token stream.
  ## Quoted Symbols (|...|), Comments (;), String Literals ("...")
  ## are all handled correctly — parenthesis depth is never corrupted.
  ##
  ## Example:
  ##   tokenizeSmt2("(assert (= msg \"error (unexpected)\")) ; comment")
  ##   → [LParen, Symbol("assert"), LParen, Symbol("="), Symbol("msg"),
  ##      String("error (unexpected)"), RParen, RParen]
  result = @[]
  var state = lsNormal
  var current = ""
  var line = 1
  var col = 1
  var tokenStartLine = 1
  var tokenStartCol = 1

  for c in input:
    case state
    of lsNormal:
      if c == '(':
        if current.len > 0:
          result.add(makeToken(current, tokenStartLine, tokenStartCol))
          current = ""
        result.add(Token(kind: tkLParen, literal: "(", line: line, col: col))
      elif c == ')':
        if current.len > 0:
          result.add(makeToken(current, tokenStartLine, tokenStartCol))
          current = ""
        result.add(Token(kind: tkRParen, literal: ")", line: line, col: col))
      elif c == '"':
        if current.len > 0:
          result.add(makeToken(current, tokenStartLine, tokenStartCol))
          current = ""
        tokenStartLine = line
        tokenStartCol = col
        state = lsString
      elif c == '|':
        if current.len > 0:
          result.add(makeToken(current, tokenStartLine, tokenStartCol))
          current = ""
        tokenStartLine = line
        tokenStartCol = col
        state = lsQuoted
      elif c == ';':
        if current.len > 0:
          result.add(makeToken(current, tokenStartLine, tokenStartCol))
          current = ""
        state = lsComment
      elif c in {' ', '\t', '\r'}:
        if current.len > 0:
          result.add(makeToken(current, tokenStartLine, tokenStartCol))
          current = ""
      elif c == '\n':
        if current.len > 0:
          result.add(makeToken(current, tokenStartLine, tokenStartCol))
          current = ""
        line += 1; col = 1; continue
      else:
        if current.len == 0:
          tokenStartLine = line
          tokenStartCol = col
        current.add(c)

    of lsString:
      if c == '\\':
        current.add(c)
        state = lsStringEscape
      elif c == '"':
        result.add(Token(kind: tkString, literal: current,
          line: tokenStartLine, col: tokenStartCol))
        current = ""
        state = lsNormal
      else:
        current.add(c)

    of lsStringEscape:
      current.add(c)
      state = lsString

    of lsQuoted:
      if c == '|':
        result.add(Token(kind: tkQuotedSymbol, literal: current,
          line: tokenStartLine, col: tokenStartCol))
        current = ""
        state = lsNormal
      else:
        current.add(c)

    of lsComment:
      if c == '\n':
        state = lsNormal
      # Comments are consumed — not added to token stream

    if c == '\n':
      line += 1; col = 1
    else:
      col += 1

  # Flush remaining token
  if current.len > 0:
    result.add(makeToken(current, tokenStartLine, tokenStartCol))

# --- S-expression parser (lexer-based) ---

func parseSExprImpl(tokens: seq[Token]; pos: var int): SExprNode {.noSideEffect.} =
  ## Recursive descent parser for S-expressions.
  ## Operates on token stream — paren depth is never corrupted by
  ## quoted symbols, strings, or comments.
  if pos >= tokens.len:
    return SExprNode(kind: seAtom, value: "", atomKind: tkSymbol)

  let tok = tokens[pos]

  case tok.kind
  of tkLParen:
    pos += 1
    var children: seq[SExprNode] = @[]
    while pos < tokens.len and tokens[pos].kind != tkRParen:
      children.add(parseSExprImpl(tokens, pos))
    if pos < tokens.len:
      pos += 1  # consume RParen
    return SExprNode(kind: seList, children: children)

  of tkRParen:
    # Stray RParen — skip
    pos += 1
    return SExprNode(kind: seAtom, value: ")", atomKind: tkRParen)

  of tkSymbol, tkQuotedSymbol, tkString, tkKeyword, tkNumeral:
    pos += 1
    return SExprNode(kind: seAtom, value: tok.literal, atomKind: tok.kind)

  of tkComment:
    # Should not appear (consumed by lexer), but handle gracefully
    pos += 1
    return parseSExprImpl(tokens, pos)

func parseSExpr*(tokens: seq[Token]): SExprNode {.noSideEffect.} =
  ## Parse a token stream into an S-expression tree.
  ## Returns the first complete S-expression found.
  var pos = 0
  parseSExprImpl(tokens, pos)

func parseSExprAll*(tokens: seq[Token]): seq[SExprNode] {.noSideEffect.} =
  ## Parse all S-expressions from a token stream.
  var pos = 0
  while pos < tokens.len:
    result.add(parseSExprImpl(tokens, pos))

# --- S-expression to canonical string ---

func canonicalString*(node: SExprNode): string {.noSideEffect.} =
  ## Convert an S-expression node to its canonical string representation.
  ## Used for alpha-equivalence comparison and hashing.
  case node.kind
  of seAtom:
    return node.value
  of seList:
    result = "("
    for i, child in node.children:
      if i > 0: result.add(" ")
      result.add(canonicalString(child))
    result.add(")")

# --- Commutative canonical ordering ---

const CommutativeOps* = ["and", "or", "+", "*", "=", "!="]

func canonicalizeCommutative*(node: SExprNode): SExprNode {.noSideEffect.} =
  ## Normalize commutative operators by sorting arguments lexicographically.
  ## (and B A) → (and A B)
  ## (or (> x 0) (< y 10)) → (or (< y 10) (> x 0))
  ## (+ y x) → (+ x y)
  ##
  ## This ensures that semantically equivalent expressions with different
  ## argument ordering produce the same canonical form.
  case node.kind
  of seAtom:
    return node
  of seList:
    var children: seq[SExprNode] = @[]
    for child in node.children:
      children.add(canonicalizeCommutative(child))

    if children.len >= 3:
      let op = children[0]
      if op.kind == seAtom and op.value in CommutativeOps:
        var args = children[1..^1]
        # Sort by canonical string representation
        args.sort(proc (a, b: SExprNode): int =
          cmp(canonicalString(a), canonicalString(b))
        )
        return SExprNode(kind: seList, children: @[op] & args)

    return SExprNode(kind: seList, children: children)

# --- Alpha-renaming (de Bruijn-style) ---

func collectVariables*(node: SExprNode;
    env: var Table[string, int]; nextIdx: var int) {.noSideEffect.} =
  ## Collect variable names and assign de Bruijn indices.
  case node.kind
  of seAtom:
    # Skip operators, constants, and keywords
    if node.atomKind == tkSymbol and
       node.value notin ["true", "false", "not", "and", "or", "=>",
                         "=", "<", ">", "<=", ">=", "+", "-", "*", "div", "mod",
                         "Int", "Bool", "Real", "BitVec"]:
      if node.value notin env:
        env[node.value] = nextIdx
        nextIdx += 1
  of seList:
    for child in node.children:
      collectVariables(child, env, nextIdx)

func alphaRename*(node: SExprNode;
    env: Table[string, int]; nextIdx: int): string {.noSideEffect.} =
  ## Alpha-rename variables to structural indices (de Bruijn style).
  ## (>= x 0) → (>= v0 0)
  ## Same variable always gets the same index within a scope.
  ##
  ## This makes vcHash stable across Z3's internal variable naming changes.
  case node.kind
  of seAtom:
    let idx = env.getOrDefault(node.value, -1)
    if idx >= 0:
      return "v" & $idx
    return node.value
  of seList:
    result = "("
    for i, child in node.children:
      if i > 0: result.add(" ")
      result.add(alphaRename(child, env, nextIdx))
    result.add(")")

func alphaRename*(node: SExprNode): string {.noSideEffect.} =
  ## Convenience wrapper: collect variables then rename.
  var env = initTable[string, int]()
  var nextIdx = 0
  collectVariables(node, env, nextIdx)
  alphaRename(node, env, nextIdx)

# --- Goal extraction from Z3 tactic output ---

func extractGoalExpressions*(tacticOutput: string): seq[string] {.noSideEffect.} =
  ## Extract goal expressions from Z3 `(apply ...)` tactic output.
  ## Strips metadata lines (:precision, :depth) and returns only
  ## the mathematical expressions.
  ##
  ## Input format:
  ##   (goals
  ##     (goal
  ##       (not (<= x 0))
  ##       (= y (+ 2 x))
  ##       :precision precise :depth 3)
  ##   )
  ##
  ## Output: @["(not (<= x 0))", "(= y (+ 2 x))"]
  let tokens = tokenizeSmt2(tacticOutput)
  let trees = parseSExprAll(tokens)

  result = @[]
  for tree in trees:
    if tree.kind == seList and tree.children.len > 0:
      # Look for (goals (goal ...))
      let head = tree.children[0]
      if head.kind == seAtom and head.value == "goals":
        for child in tree.children[1..^1]:
          if child.kind == seList and child.children.len > 0:
            let goalHead = child.children[0]
            if goalHead.kind == seAtom and goalHead.value == "goal":
              # Extract non-keyword children
              for expr in child.children[1..^1]:
                if expr.kind == seAtom and expr.atomKind == tkKeyword:
                  continue  # Skip :precision, :depth, etc.
                if expr.kind == seList or
                   (expr.kind == seAtom and expr.atomKind != tkKeyword):
                  result.add(canonicalString(expr))

# --- Hashing with full canonicalization ---

func computeCanonicalFingerprint*(expressions: seq[string]): string {.noSideEffect.} =
  ## Compute a deterministic fingerprint from canonicalized goal expressions.
  ##
  ## Pipeline:
  ##   1. Parse each expression
  ##   2. Alpha-rename variables (de Bruijn indices)
  ##   3. Canonicalize commutative operators
  ##   4. Serialize to canonical string
  ##   5. Hash the combined result
  var canonicalExprs: seq[string] = @[]
  for expr in expressions:
    let tokens = tokenizeSmt2(expr)
    let tree = parseSExpr(tokens)
    let renamed = alphaRename(tree)
    let retokens = tokenizeSmt2(renamed)
    let retree = parseSExpr(retokens)
    let canonical = canonicalizeCommutative(retree)
    canonicalExprs.add(canonicalString(canonical))

  canonicalExprs.sort()
  let joined = canonicalExprs.join("\n")
  sha256Hex(joined)

{.pop.}
