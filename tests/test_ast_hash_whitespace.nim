## test_ast_hash_whitespace.nim — Verify AST hash is whitespace-invariant
import std/[strutils, os]
import core/ast_hash

proc main() =
  echo "=== AST Hash Whitespace Invariance Test ==="
  echo ""

  # Test 1: Same code, different operator spacing (single-line)
  let sourceA = "let x = 1 + 2"
  let sourceB = "let x=1+2"

  let hashA = computeAstHash(sourceA)
  let hashB = computeAstHash(sourceB)

  echo "Test 1: Same code, different operator spacing"
  echo "  Source A: ", repr(sourceA)
  echo "  Source B: ", repr(sourceB)
  echo "  Hash A: ", $hashA
  echo "  Hash B: ", $hashB
  if hashA == hashB:
    echo "  PASS: Hashes match"
  else:
    echo "  FAIL: Hashes differ"
  echo ""

  # Test 2: Different code should produce different hashes
  let sourceC = "proc foo(): int = result = 42"
  let sourceD = "proc bar(): int = result = 99"

  let hashC = computeAstHash(sourceC)
  let hashD = computeAstHash(sourceD)

  echo "Test 2: Different code should differ"
  echo "  Source C: ", repr(sourceC)
  echo "  Source D: ", repr(sourceD)
  echo "  Hash C: ", $hashC
  echo "  Hash D: ", $hashD
  if hashC != hashD:
    echo "  PASS: Hashes differ"
  else:
    echo "  FAIL: Hashes are identical (collision)"
  echo ""

  # Test 3: Determinism — same source always produces same hash
  let sourceE = "type MyType = object\n  x: int\n  y: string"
  let hashE1 = computeAstHash(sourceE)
  let hashE2 = computeAstHash(sourceE)
  let hashE3 = computeAstHash(sourceE)

  echo "Test 3: Determinism (same source, three calls)"
  echo "  Source: ", repr(sourceE)
  echo "  Hash 1: ", $hashE1
  echo "  Hash 2: ", $hashE2
  echo "  Hash 3: ", $hashE3
  if hashE1 == hashE2 and hashE2 == hashE3:
    echo "  PASS: All hashes identical"
  else:
    echo "  FAIL: Hashes differ across calls"
  echo ""

  # Test 4: Empty vs whitespace-only (fallback to content hash)
  let sourceF = ""
  let sourceG = "   \n\n   "

  let hashF = computeAstHash(sourceF)
  let hashG = computeAstHash(sourceG)

  echo "Test 4: Empty vs whitespace-only"
  echo "  Source F (empty): ", repr(sourceF)
  echo "  Source G (whitespace): ", repr(sourceG)
  echo "  Hash F: ", $hashF
  echo "  Hash G: ", $hashG
  if hashF == hashG:
    echo "  PASS: Both fall back to content hash"
  else:
    echo "  INFO: Different fallback behavior"
  echo ""

  # Test 5: Parse actual project file
  let projectFile = getCurrentDir() / "src/core/parser_utils.nim"
  if fileExists(projectFile):
    let fileContent = readFile(projectFile)
    let hash1 = computeAstHash(fileContent)
    
    # Read again and verify determinism
    let fileContent2 = readFile(projectFile)
    let hash2 = computeAstHash(fileContent2)
    
    echo "Test 5: Actual project file (" & extractFilename(projectFile) & ")"
    echo "  File size: ", fileContent.len, " bytes"
    echo "  Hash 1: ", $hash1
    echo "  Hash 2: ", $hash2
    if hash1 == hash2:
      echo "  PASS: File hashes match (deterministic)"
    else:
      echo "  FAIL: File hashes differ"
  else:
    echo "Test 5: SKIPPED (file not found: " & projectFile & ")"
  echo ""

  echo "=== Test Complete ==="

main()
