import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}
## Normalized Content Hash — tree-sitter-free change detection
##
## Strips comments, normalizes whitespace, and computes SHA-256 to produce
## a deterministic hash that is invariant under cosmetic changes (comments,
## indentation, trailing whitespace). Used by invalidation_trigger.nim to
## detect whether two source versions are semantically identical without
## requiring tree-sitter parsing.
##
## Algorithm:
##   1. Remove single-line comments (# ...) outside strings/chars
##   2. Remove multi-line comment blocks #[ ... ]# outside strings/chars
##   3. Normalize line endings (\r\n -> \n, \r -> \n)
##   4. Collapse runs of horizontal whitespace (spaces/tabs) to single space
##   5. Strip leading/trailing blank lines per line
##   6. Compute SHA-256 of normalized content

import core/crypto/hash_kernel

func isInStringOrChar*(source: string; idx: int): bool {.raises: [].} =
  ## Check if position idx falls inside a string literal or character literal.
  ## Walkes from the start of source to idx with proper escape handling.
  if idx <= 0 or idx >= source.len: return false
  var i = 0
  var inString = false
  var inChar = false
  var escaped = false
  while i < idx:
    let c = source[i]
    if escaped:
      escaped = false
      inc i
      continue
    case c
    of '\\':
      if inString or inChar:
        escaped = true
    of '"':
      if not inChar:
        inString = not inString
    of '\'':
      if not inString:
        inChar = not inChar
    else:
      discard
    inc i
  inString or inChar

func stripComments*(source: string): string {.raises: [].} =
  ## Remove Nim-style comments (# single-line, #[ ... ]# multi-line)
  ## that appear outside string and character literals.
  ## Handles: raw strings r"...", R"..."; triple-quoted strings """...""";
  ## and nested block comments #[ ... #[ ... ]# ... ]#.
  ## Preserves line structure (replaces comment chars with spaces).
  result = newStringOfCap(source.len)
  var i = 0
  var inChar = false
  var inString = false
  var escaped = false
  var inTripleStr = false
  var inRawString = false
  var nestedCommentDepth = 0

  while i < source.len:
    let c = source[i]

    if nestedCommentDepth > 0:
      if c == '#' and i + 1 < source.len and source[i + 1] == ']':
        dec nestedCommentDepth
        result.add(' ')
        inc i
        if i < source.len and source[i] == '#':
          inc i
      elif c == '#' and i + 1 < source.len and source[i + 1] == '[':
        inc nestedCommentDepth
        result.add(' ')
        inc i
        inc i
      else:
        result.add(' ')
        inc i
      continue

    if escaped:
      escaped = false
      result.add(c)
      inc i
      continue

    case c
    of '\\':
      if (inChar or inString) and not inTripleStr and not inRawString:
        escaped = true
        result.add(c)
      else:
        result.add(c)
      inc i
    of '\'':
      if inTripleStr or inRawString:
        result.add(c)
      else:
        inChar = not inChar
        result.add(c)
      inc i
    of '"':
      if inTripleStr:
        if i + 1 < source.len and source[i + 1] == '"':
          if i + 2 < source.len and source[i + 2] == '"':
            inTripleStr = false
            result.add('\"')
            result.add('\"')
            result.add('\"')
            inc i
            inc i
            inc i
          else:
            result.add('\"')
            inc i
        else:
          result.add('\"')
          inc i
      elif inRawString:
        result.add(c)
        inc i
      else:
        if i + 1 < source.len and source[i + 1] == '"':
          if i + 2 < source.len and source[i + 2] == '"':
            # Opening triple-quoted string: `"""` occupies exactly i, i+1, i+2.
            # The character at i+3 is string content — it must NOT gate the open,
            # or a `"""abc"""` literal leaves i unchanged and spins forever.
            inTripleStr = true
            result.add('\"')
            result.add('\"')
            result.add('\"')
            inc i
            inc i
            inc i
          else:
            result.add('\"')
            inc i
        elif i + 1 < source.len and (source[i + 1] == 'r' or source[i + 1] == 'R') and i + 2 < source.len and source[i + 2] == '"':
          result.add('r')
          result.add('\"')
          inc i
          inRawString = true
        elif i + 1 < source.len and source[i + 1] == '"':
          inString = not inString
          result.add('\"')
          inc i
        else:
          inString = not inString
          result.add(c)
          inc i
    of '#':
      if inChar or inString or inTripleStr or inRawString:
        result.add(c)
        inc i
      elif i + 1 < source.len and source[i + 1] == '[':
        if i + 2 < source.len and source[i + 1] == '[' and source[i + 2] == '#':
          nestedCommentDepth = 1
          result.add(' ')
          inc i
          inc i
          inc i
        else:
          nestedCommentDepth = 1
          result.add(' ')
          inc i
          inc i
      elif i + 1 < source.len and source[i + 1] == '#':
        while i < source.len and source[i] != '\n':
          result.add(' ')
          inc i
        if i < source.len and source[i] == '\n':
          result.add('\n')
          inc i
      else:
        while i < source.len and source[i] != '\n':
          result.add(' ')
          inc i
        if i < source.len and source[i] == '\n':
          result.add('\n')
          inc i
    of '\r':
      result.add('\n')
      inc i
    of '\n':
      result.add('\n')
      inc i
    else:
      result.add(c)
      inc i

func normalizeWhitespace*(source: string): string {.raises: [].} =
  ## Normalize whitespace in source text:
  ##   - Convert \r\n and \r to \n
  ##   - Collapse runs of spaces/tabs on each line to single space
  ##   - Strip trailing whitespace from each line
  ##   - Preserve line structure
  result = newStringOfCap(source.len)
  var i = 0
  var atLineStart = true
  var collectingSpace = false

  while i < source.len:
    let c = source[i]
    case c
    of '\r', '\n':
      if c == '\r' and i + 1 < source.len and source[i + 1] == '\n':
        inc i
      if result.len > 0 and result[result.len - 1] == '\n':
        inc i
        continue
      if collectingSpace:
        result.add(' ')
        collectingSpace = false
      while result.len > 0 and result[result.len - 1] == ' ':
        result.setLen(result.len - 1)
      result.add('\n')
      atLineStart = true
      inc i
    of ' ', '\t':
      if not atLineStart or not collectingSpace:
        collectingSpace = true
      inc i
    else:
      if collectingSpace:
        result.add(' ')
        collectingSpace = false
      result.add(c)
      atLineStart = false
      inc i

  if collectingSpace:
    result.add(' ')
  if result.len > 0 and result[result.len - 1] == ' ':
    result.setLen(result.len - 1)

func normalizedContent*(source: string): string {.raises: [].} =
  ## Full normalization pipeline: strip comments, then normalize whitespace.
  ## Deterministic: same semantic content always produces identical output.
  let commented = stripComments(source)
  normalizeWhitespace(commented)

proc normalizedContentHash*(source: string): string {.raises: [].} =
  ## Compute SHA-256 hash of normalized content.
  ## Returns empty string for empty input.
  ## Invariant: normalizedContentHash(a) == normalizedContentHash(b)
  ## iff a and b have the same semantics (ignoring comments/whitespace).
  let normed = normalizedContent(source)
  if normed.len == 0:
    result = ""
  else:
    result = computeContentHash(normed)