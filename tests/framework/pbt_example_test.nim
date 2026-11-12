## tests/framework/pbt_example_test.nim
## Example usage of the PBT (Property-Based Testing) engine.
## Demonstrates how to write property tests using the existing engine.

import core/testing/pbt_engine
import std/unittest

suite "PBT Example Tests":
  
  test "Property: String reverse is involutive":
    ## Property: reverse(reverse(x)) == x
    let seed = 12345  # Deterministic seed for reproducibility
    
    proc generator(r: var Rand): string =
      genString(r, 0, 100)  # Generate strings of length 0-100
    
    proc predicate(x: string): bool =
      x.reversed().reversed() == x
    
    let result = checkProperty(seed, generator, predicate)
    check result.success == true
  
  test "Property: List length is preserved after sorting":
    ## Property: len(sort(x)) == len(x)
    let seed = 67890
    
    proc generator(r: var Rand): seq[int] =
      genSeq(r, genInt(r, -100, 100), 0, 50)
    
    proc predicate(x: seq[int]): bool =
      x.sorted().len == x.len
    
    let result = checkProperty(seed, generator, predicate)
    check result.success == true
  
  test "PBT with failing property (for demonstration)":
    ## This test shows how PBT reports failures
    let seed = 11111
    
    proc generator(r: var Rand): int =
      genInt(r, 0, 1000)
    
    proc predicate(x: int): bool =
      x mod 2 == 0  # Only even numbers (will fail for odd numbers)
    
    let result = checkProperty(seed, generator, predicate)
    # This will fail, but we catch the result
    check result.success == false
    echo "Failure correctly detected! Seed: ", result.failingSeed

# Usage instructions:
# Run with: nim c -r tests/framework/pbt_example_test.nim
# Reproduce failures: nim c -r tests/framework/pbt_example_test.nim --pbt-seed:<failingSeed>
