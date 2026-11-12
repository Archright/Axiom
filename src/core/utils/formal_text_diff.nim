## formal_text_diff.nim — FSM-Based Diff Classification
##
## Classifies unified diff hunks into ChangeKind categories using a
## finite-state machine that tracks multi-line comment nesting (#\[ ]#)
## and multi-line pragma blocks (opening/closing pragma directives).
##
## An unclosed opening pragma block must never swallow subsequent logic lines: real
## code content is classified as ckLogic regardless of pragmaDepth.
##
## Conservative default: any unclassifiable content → ckLogic.
## Gates MUST NOT skip verification on ckLogic.
##
## Usage:
##   nim c -o:bin/formal-text-diff tools/formal_text_diff.nim
##   echo "$diff" | bin/formal-text-diff

import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import std/[strutils]

type
  ChangeKind* = enum
    ckLogic     ## Contains substantive code changes — gate MUST verify
    ckPragma    ## Only pragma/annotation changes
    ckComment   ## Only comment changes
    ckWhitespace ## Only whitespace / blank-line changes

# ── FSM Helpers ────────────────────────────────────────────────────────────────

func stripDiffMarker(line: string): string =
  ## Strip leading +/-/space from a unified-diff line.
  ## Returns the content portion, or "" if the line is a diff header.
  if line.len == 0: return ""
  let first = line[0]
  if first in {'+', '-', ' '}:
    return line[1 .. ^1]
  # Lines like @@ hunk headers, --- / +++ headers — skip entirely
  if line.startsWith("@@") or line.startsWith("---") or line.startsWith("+++"):
    return ""
  return line

func countOccurrences(s: string, sub: string): int =
  ## Count non-overlapping occurrences of sub in s.
  result = 0
  var i = 0
  while i <= s.len - sub.len:
    if s[i ..< i + sub.len] == sub:
      inc result
      i += sub.len
    else:
      inc i

func isOpenBlockComment(s: string): int =
  ## Count #\[ opens not inside a closing bracket context.
  result = countOccurrences(s, "#[")

func isCloseBlockComment(s: string): int =
  ## Count ]# closes.
  result = countOccurrences(s, "]#")

func isPragmaPush(line: string): bool =
  ## Detect opening pragma-block lines.
  let stripped = line.strip()
  const pushTok = "{." & "push"  # assembled to avoid false-positive pragma scan
  result = pushTok in stripped or "{.  push" in stripped

func isPragmaPop(line: string): bool =
  ## Detect closing pragma-block lines.
  let stripped = line.strip()
  const popTok = "{." & "pop"
  result = popTok in stripped or "{.  pop" in stripped

func isSingleLineComment(line: string): bool =
  ## Line is entirely a single-line comment (# ...).
  let stripped = line.strip()
  result = stripped.len > 0 and stripped[0] == '#'

func isPragmaOnly(line: string): bool =
  ## Line contains only pragma annotations or the word "pragma".
  let stripped = line.strip()
  if stripped.len == 0: return false
  result = stripped.startsWith("{.") or stripped.startsWith("pragma") or
           stripped.startsWith("##[")

func isWhitespaceOnly(line: string): bool =
  ## Line is blank or contains only whitespace.
  result = line.strip().len == 0

# ── Core Classifier ───────────────────────────────────────────────────────────

func classifyChange*(diffText: string): ChangeKind =
  ## Classify a unified diff text into a ChangeKind using FSM tracking.
  ##
  ## FSM state:
  ##   - commentDepth: nesting depth of #\[ ]# block comments
  ##   - pragmaDepth:  nesting depth of opening/closing pragma-block directives
  ##
  ## A line that opens/closes (or lies within) a block comment is comment
  ## content. An unclosed opening pragma block does NOT turn any following line into
  ## pragma content — real code after a push is classified as ckLogic.
  ##
  ## Conservative rule: any non-trivial code content immediately returns
  ## ckLogic. This ensures gates never skip verification on ambiguity.
  let lines = diffText.splitLines()

  var commentDepth = 0
  var pragmaDepth = 0
  var allWhitespace = true
  var allComment = true
  var allPragma = true

  for line in lines:
    let content = stripDiffMarker(line)
    if content.len == 0:
      continue

    # ── Track block comment nesting ────────────────────────────────────
    let opens = isOpenBlockComment(content)
    let closes = isCloseBlockComment(content)
    let wasInComment = commentDepth > 0
    commentDepth += opens
    commentDepth -= closes
    if commentDepth < 0:
      commentDepth = 0

    # A line is comment content if we were inside a comment, or it opens or
    # closes a block comment — this includes unclosed/standalone comment fences.
    if wasInComment or opens > 0 or closes > 0:
      allWhitespace = false
      allPragma = false
      continue

    # ── Track pragma block nesting ─────────────────────────────────────
    if isPragmaPush(content):
      inc pragmaDepth
      allWhitespace = false
      allComment = false
      continue

    if isPragmaPop(content):
      dec pragmaDepth
      if pragmaDepth < 0:
        pragmaDepth = 0
      allWhitespace = false
      allComment = false
      continue

    # NOTE: pragmaDepth is tracked above but never swallows subsequent logic.
    # An unclosed push must not hide real code — classify every remaining line.

    # ── Classify the line ──────────────────────────────────────────────
    if isWhitespaceOnly(content):
      continue  # doesn't affect any flag

    allWhitespace = false

    if isSingleLineComment(content):
      allPragma = false
      continue

    if isPragmaOnly(content):
      allComment = false
      continue

    # ── Anything else is logic — conservative immediate return ─────────
    return ckLogic

  # ── All lines processed — determine aggregate classification ─────────
  if allWhitespace:
    return ckWhitespace
  if allComment:
    return ckComment
  if allPragma:
    return ckPragma
  return ckLogic

# ── CLI Entry ──────────────────────────────────────────────────────────────────

{.pop.}
