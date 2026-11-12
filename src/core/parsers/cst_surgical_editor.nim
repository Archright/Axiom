## Surgical Text Substitution — byte-offset based source code modification.
##
## Replaces body spans in-place using start_byte:end_byte offsets from tree-sitter.
## NO tree mutation, NO serialization — pure string surgery on original source.
## 100% formatting/comment preservation for non-targeted regions.

import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import std/algorithm

import cst_offset_extractor  # for ByteSpan

# ── Public API ────────────────────────────────────────────────────────────────

func surgicalReplaceBody*(source: string; bodySpan: ByteSpan;
                           stub: string = "  discard ## moved\n"): string {.
  raises: [].} =
  ## Replace bodySpan bytes in source with stub. Returns modified source.
  ##
  ## bodySpan: (start, end) from tree-sitter node
  ## stub: replacement text for the body region
  ##
  ## The region BEFORE bodySpan and AFTER bodySpan is 100% preserved.
  let before = source[0 ..< bodySpan.start.int]
  let after = source[bodySpan.`end`.int .. ^1]
  result = before & stub & after

func surgicalExtract*(source: string; fullSpan: ByteSpan): string {.
  raises: [].} =
  ## Extract text from source at fullSpan. Returns extracted text.
  ##
  ## fullSpan: (start, end) from tree-sitter node
  let s = fullSpan.start.int
  let e = fullSpan.`end`.int
  if s < 0 or e > source.len or s >= e:
    return ""
  source[s ..< e]

type
  SpanReplacement* = object
    ## A single replacement instruction: replace span with stub text.
    span*: ByteSpan
    stub*: string

func sortedDesc(replacements: var openArray[SpanReplacement]) =
  ## Sort replacements by start byte descending (in-place) to preserve offsets.
  func cmpSpan(a, b: SpanReplacement): int =
    if a.span.start > b.span.start: -1
    elif a.span.start < b.span.start: 1
    else: 0
  sort(replacements, cmpSpan)

func surgicalMultiReplace*(source: string;
                            replacements: openArray[SpanReplacement]): string {.
  raises: [].} =
  ## Apply multiple surgical replacements from end to start (to preserve offsets).
  ##
  ## replacements: array of SpanReplacement (span + stub_text)
  ## Sorted by start descending automatically so earlier offsets aren't invalidated.
  var editorResult = source
  # Copy to mutable local for sorting
  var reps = newSeq[SpanReplacement](replacements.len)
  for i, r in replacements:
    reps[i] = r
  sortedDesc(reps)
  for r in reps:
    let s = r.span.start.int
    let e = r.span.`end`.int
    if s < 0 or e > editorResult.len or s > e:
      continue
    editorResult = editorResult[0 ..< s] & r.stub & editorResult[e .. ^1]
  editorResult

{.pop.}
