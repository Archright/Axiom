import core/axiom_pragmas
generateAxiomInit()
initRegistryLookup()
echo "Registry entries: ", runtimeAxiomRegistry.len
var irHashCount = 0
for entry in runtimeAxiomRegistry:
  if entry.irHash.len > 0:
    inc irHashCount
echo "Entries with irHash: ", irHashCount
echo "Entries without irHash: ", runtimeAxiomRegistry.len - irHashCount
for i, entry in runtimeAxiomRegistry:
  if i < 3:
    echo entry.name, " | irHash: ", entry.irHash[0..min(15, entry.irHash.len-1)], " | isKernel: ", entry.isKernel
