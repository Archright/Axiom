## SMT-LIB2 DFA Tokenizer — Phase 2 of Proof-Carrying Code architecture.
## Deterministic finite automaton for tokenizing SMT-LIB2 proof objects.
## No regex, no parseutils — pure character-by-character state machine.
## Validates size limits, nesting depth, and token size.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import proof_artifact_types

const
  WhitespaceChars = {' ', '\t', '\n', '\r'}
  SymbolStartChars = {
    'a'..'z', 'A'..'Z',
    '~', '!', '@', '$', '%', '^', '&', '*',
    '_', '-', '+', '=', '<', '>', '.', '?', '/'
  }
  SymbolContinuationChars = SymbolStartChars + {'0'..'9'}
  DigitChars = {'0'..'9'}

type
  DfaState = enum
    ## DFA states for SMT-LIB2 tokenization.
    dfaIdle
    dfaInSymbol
    dfaInString
    dfaInComment
    dfaInKeyword
    dfaInQuotedSymbol

  TokenKind* = enum
    tkOpenParen, tkCloseParen, tkSymbol, tkString, tkKeyword, tkNumeral, tkComment

  Token* = object
    kind*: TokenKind
    value*: string
    line*, col*: int

  ParseResult* = object
    case success*: bool
    of true:
      tokens*: seq[Token]
      maxDepth*: int
    of false:
      errorMsg*: string
      errorLine*, errorCol*: int

func classifySymbol(value: string): TokenKind {.raises: [].} =
  ## Classify a symbol token as numeral or generic symbol.
  ## Binary: b + {0,1}+   Hex: x + hex+   Decimal: digits+
  if value.len == 0:
    return tkSymbol
  if value[0] == 'b' and value.len > 1:
    var allBinary = true
    for j in 1 ..< value.len:
      if value[j] notin {'0', '1'}:
        allBinary = false
        break
    if allBinary:
      return tkNumeral
  if value[0] == 'x' and value.len > 1:
    var allHex = true
    for j in 1 ..< value.len:
      if value[j] notin {'0'..'9', 'a'..'f', 'A'..'F'}:
        allHex = false
        break
    if allHex:
      return tkNumeral
  if value[0] in DigitChars:
    var allDigits = true
    for j in 1 ..< value.len:
      if value[j] notin DigitChars:
        allDigits = false
        break
    if allDigits:
      return tkNumeral
  tkSymbol

func parseSmtLib2*(input: string): ParseResult {.raises: [].} =
  ## Tokenize SMT-LIB2 input using a DFA state machine.
  ## Rejects input exceeding MaxZ3ProofSize, tokens exceeding MaxTokenSize,
  ## and nesting depth exceeding MaxSmtNestingDepth.
  ## Returns ParseResult with tokens on success or error details on failure.

  # Size validation: reject immediately if input exceeds limit
  if input.len > MaxZ3ProofSize:
    return ParseResult(
      success: false,
      errorMsg: "Input exceeds MaxZ3ProofSize (" & $MaxZ3ProofSize & " bytes)",
      errorLine: 1, errorCol: 1
    )

  var
    tokens: seq[Token]
    state = dfaIdle
    line = 1
    col = 1
    maxDepth = 0
    currentDepth = 0
    tokenStartLine = 1
    tokenStartCol = 1
    buf: string
    i = 0

  template advanceChar() =
    if input[i] == '\n':
      inc line
      col = 1
    else:
      inc col
    inc i

  template emitError(msg: string): ParseResult =
    ParseResult(
      success: false,
      errorMsg: msg,
      errorLine: line,
      errorCol: col
    )

  while i < input.len:
    let ch = input[i]

    case state
    of dfaIdle:
      case ch
      of '(':
        inc currentDepth
        if currentDepth > maxDepth:
          maxDepth = currentDepth
        if currentDepth > MaxSmtNestingDepth:
          return emitError("Nesting depth exceeds MaxSmtNestingDepth (" &
                           $MaxSmtNestingDepth & ")")
        tokens.add(Token(kind: tkOpenParen, value: "(",
                         line: line, col: col))
        advanceChar()
      of ')':
        if currentDepth <= 0:
          return emitError("Unmatched closing parenthesis")
        dec currentDepth
        tokens.add(Token(kind: tkCloseParen, value: ")",
                         line: line, col: col))
        advanceChar()
      of '"':
        state = dfaInString
        tokenStartLine = line
        tokenStartCol = col
        buf = ""
        advanceChar()
      of ';':
        state = dfaInComment
        tokenStartLine = line
        tokenStartCol = col
        buf = ""
        advanceChar()
      of ':':
        state = dfaInKeyword
        tokenStartLine = line
        tokenStartCol = col
        buf = ":"
        advanceChar()
      of '|':
        state = dfaInQuotedSymbol
        tokenStartLine = line
        tokenStartCol = col
        buf = ""
        advanceChar()
      of WhitespaceChars:
        advanceChar()
      of SymbolStartChars:
        state = dfaInSymbol
        tokenStartLine = line
        tokenStartCol = col
        buf = ""
        buf.add(ch)
        advanceChar()
      of DigitChars:
        state = dfaInSymbol
        tokenStartLine = line
        tokenStartCol = col
        buf = ""
        buf.add(ch)
        advanceChar()
      else:
        return emitError("Unexpected character '" & ch & "'")

    of dfaInSymbol:
      if ch in SymbolContinuationChars:
        buf.add(ch)
        if buf.len > MaxTokenSize:
          return emitError("Token exceeds MaxTokenSize (" & $MaxTokenSize & ")")
        advanceChar()
      else:
        tokens.add(Token(kind: classifySymbol(buf), value: buf,
                         line: tokenStartLine, col: tokenStartCol))
        state = dfaIdle

    of dfaInString:
      if ch == '\\':
        advanceChar()
        if i < input.len:
          buf.add(input[i])
          advanceChar()
        else:
          return emitError("Unexpected end of input in string escape")
      elif ch == '"':
        tokens.add(Token(kind: tkString, value: buf,
                         line: tokenStartLine, col: tokenStartCol))
        state = dfaIdle
        advanceChar()
      else:
        buf.add(ch)
        if buf.len > MaxTokenSize:
          return emitError("String exceeds MaxTokenSize (" & $MaxTokenSize & ")")
        advanceChar()

    of dfaInComment:
      if ch == '\n':
        tokens.add(Token(kind: tkComment, value: buf,
                         line: tokenStartLine, col: tokenStartCol))
        state = dfaIdle
        advanceChar()
      else:
        buf.add(ch)
        advanceChar()

    of dfaInKeyword:
      if ch in SymbolContinuationChars:
        buf.add(ch)
        if buf.len > MaxTokenSize:
          return emitError("Keyword exceeds MaxTokenSize (" & $MaxTokenSize & ")")
        advanceChar()
      else:
        tokens.add(Token(kind: tkKeyword, value: buf,
                         line: tokenStartLine, col: tokenStartCol))
        state = dfaIdle

    of dfaInQuotedSymbol:
      if ch == '|':
        tokens.add(Token(kind: tkSymbol, value: buf,
                         line: tokenStartLine, col: tokenStartCol))
        state = dfaIdle
        advanceChar()
      else:
        buf.add(ch)
        if buf.len > MaxTokenSize:
          return emitError("Quoted symbol exceeds MaxTokenSize (" &
                           $MaxTokenSize & ")")
        advanceChar()

  # Flush any pending token at end of input
  case state
  of dfaInSymbol:
    tokens.add(Token(kind: classifySymbol(buf), value: buf,
                     line: tokenStartLine, col: tokenStartCol))
  of dfaInString:
    return emitError("Unterminated string starting at line " & $tokenStartLine)
  of dfaInComment:
    tokens.add(Token(kind: tkComment, value: buf,
                     line: tokenStartLine, col: tokenStartCol))
  of dfaInKeyword:
    tokens.add(Token(kind: tkKeyword, value: buf,
                     line: tokenStartLine, col: tokenStartCol))
  of dfaInQuotedSymbol:
    return emitError("Unterminated quoted symbol starting at line " &
                     $tokenStartLine)
  of dfaIdle:
    discard

  # Verify all parentheses are closed
  if currentDepth > 0:
    return emitError("Unclosed parenthesis (depth=" & $currentDepth & ")")

  ParseResult(
    success: true,
    tokens: tokens,
    maxDepth: maxDepth
  )
