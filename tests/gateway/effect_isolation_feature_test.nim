## Effect Isolation Feature Test — real BoundaryExtractor verification.
## Replaces the stub in tests/generated/effect_isolation_feature_test.nim.
## See tests/features/effect_isolation.feature for the specification.
##
## Contract: I/O functions get bcPartialHavoc (not bcIncompleteIO = "skip Z3 entirely").
## Snippet source causes regex fallback → ast_parse_failed_isolated injected.

import std/[unittest, strutils]
import core/boundary/boundary_extractor_part1
import core/boundary/boundary_extraction_types

func hasIsolationMarker(parts: seq[string]): bool {.raises: [].} =
  for part in parts:
    if "external_io_isolated" in part or "ast_parse_failed_isolated" in part:
      return true

suite "Effect Isolation — BoundaryExtractor":
  test "I/O function gets bcPartialHavoc (not bcIncompleteIO)":
    ## Scenario 1: I/O functions generate partial hints instead of none
    ## Given a Nim function containing writeFile
    ## When BoundaryExtractor analyzes the function
    ## Then completeness is bcPartialHavoc — Z3 havoc, not "skip entirely"
    const ioSource = """
proc legacySideEffect(data: string) {.raises: [].} =
  writeFile("/tmp/output.log", data)
"""
    let result = extractBoundaries("test::legacySideEffect", ioSource)
    check result.completeness == bcPartialHavoc
    check result.completeness != bcIncompleteIO
    # Verify some isolation marker exists in SMT or Lean parts
    check hasIsolationMarker(result.smtParts) or hasIsolationMarker(result.leanParts)

  test "Pure function gets bcPartialHavoc or bcComplete (not bcIncompleteIO)":
    ## Pure functions with no I/O should not be classified as bcIncompleteIO
    ## Note: snippet source triggers regex fallback → ast_parse_failed_isolated,
    ## so bcComplete is only achievable when tree-sitter parses the full source.
    const pureSource = """
func add(a, b: int): int = a + b
"""
    let result = extractBoundaries("test::add", pureSource)
    check result.completeness in {bcComplete, bcPartialHavoc}
    check result.completeness != bcIncompleteIO
