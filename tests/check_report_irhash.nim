import core/axiom_pragmas
import std/tables

# Simulate what ax report does
generateAxiomInit()
initRegistryLookup()

echo "=== Registry Check ==="
echo "Total entries: ", runtimeAxiomRegistry.len
var withHash = 0
var withoutHash = 0
for entry in runtimeAxiomRegistry:
  if entry.irHash.len > 0:
    inc withHash
  else:
    inc withoutHash
echo "With irHash: ", withHash
echo "Without irHash: ", withoutHash

# Show first 5 entries
echo ""
echo "=== First 5 entries ==="
for i, entry in runtimeAxiomRegistry:
  if i < 5:
    let hashPreview = if entry.irHash.len > 0: entry.irHash[0..min(19, entry.irHash.len-1)] else: "(empty)"
    echo entry.name, " | irHash: ", hashPreview, " | isKernel: ", entry.isKernel
