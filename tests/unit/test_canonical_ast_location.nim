## S1 test: CanonNode sourceSpanRef — provenance without semantic impact
## Verifies that toCanon fills sourceSpanRef from real AST nodes and leaves
## synthetic nodes with an empty span.  No semantic comparison is affected.

import std/macros
import shared/canonical_ast

# ---------------------------------------------------------------------------
# Macro harness: runs toCanon + assertions at compile time
# Fails compilation (via error()) if any assertion is violated.
# Only uses built-in string ops (len, [], ==) — no strutils needed.
# ---------------------------------------------------------------------------

macro s1VerifyRealProcSpan*(): untyped =
  let tree = quote do:
    proc hello(): string =
      "world"

  let c = toCanon(tree)

  # Check sourceSpanRef is non-empty
  if c.sourceSpanRef.len == 0:
    error("toCanon on a real proc node must populate sourceSpanRef", tree)

  # Check it ends with "nnkProcDef" by comparing last chars
  let kindSuffix = "nnkProcDef"
  if c.sourceSpanRef.len < kindSuffix.len:
    error("sourceSpanRef too short to contain nnkProcDef suffix", tree)

  var match = true
  for i in 0 ..< kindSuffix.len:
    let expectedIdx = c.sourceSpanRef.len - kindSuffix.len + i
    if c.sourceSpanRef[expectedIdx] != kindSuffix[i]:
      match = false
      break

  if not match:
    error("sourceSpanRef must end with nnkProcDef kind label", tree)

  result = newNimNode(nnkStmtList)

s1VerifyRealProcSpan()

# ---------------------------------------------------------------------------
# Test 2: synthetic node (parseStmt of empty string — no file, no location)
# yields empty sourceSpanRef
# ---------------------------------------------------------------------------
# Nim 2.2.10 quirk: newNimNode(nnkEmpty) inside a macro gets the VM's
# creation-site line info (file/line/col of the macro body), so it is NOT
# a valid "no-location" probe; parseStmt("") produces filename=='' which
# formatSourceSpan treats as no location info.

macro s1VerifySyntheticSpan*(): untyped =
  let synth = parseStmt("")
  let c = toCanon(synth)

  if c.sourceSpanRef.len != 0:
    error("toCanon on a synthetic node must yield empty sourceSpanRef", synth)

  result = newNimNode(nnkStmtList)

s1VerifySyntheticSpan()

# ---------------------------------------------------------------------------
# Test 3: semantic fields deterministic regardless of sourceSpanRef
# ---------------------------------------------------------------------------

macro s1VerifySemanticDeterminism*(): untyped =
  let c1 = toCanon(quote do: 42)
  let c2 = toCanon(quote do: 42)

  if c1.kind != c2.kind:
    error("kind must match deterministically", quote do: 42)
  if c1.intVal != c2.intVal:
    error("intVal must match deterministically", quote do: 42)

  discard c1.sourceSpanRef
  discard c2.sourceSpanRef

  result = newNimNode(nnkStmtList)

s1VerifySemanticDeterminism()

# ---------------------------------------------------------------------------
# Test 4: children of a real node carry sourceSpanRef
# ---------------------------------------------------------------------------

macro s1VerifyChildSpans*(): untyped =
  let c = toCanon(quote do:
    proc add(a: int, b: int): int =
      a + b
  )

  if c.children.len == 0:
    error("proc node must have children", quote do:
      proc add(a: int, b: int): int =
        a + b
    )

  var foundNonEmptyChildSpan = false
  for child in c.children:
    if child.sourceSpanRef.len > 0:
      foundNonEmptyChildSpan = true

  if not foundNonEmptyChildSpan:
    error("at least one child of a real proc node must carry a non-empty sourceSpanRef", quote do:
      proc add(a: int, b: int): int =
        a + b
    )

  result = newNimNode(nnkStmtList)

s1VerifyChildSpans()

echo "S1 sourceSpanRef tests passed."
