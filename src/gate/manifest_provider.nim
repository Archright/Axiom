import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## manifest_provider.nim — Virtual Manifest Provider (B2)
##
## Unified accessor interface for gate manifest data.
## Reads compile-time constants from gate_registry.nim (AllGateConfigs,
## AxiomManifestIndexContent) and provides runtime accessors that replace
## stale gate_manifest.json references.
##
## Consumers:
##   - Any file that previously read gate_manifest.json directly
##   - Tests that need manifest data
##   - Hash-based staleness detection

import gate/gate_contract
import generated/gate_registry
import core/crypto/hash_kernel
import std/[json, options]

const AxiomManifestIndexContent* = staticRead("src/gate/manifest.d/_index.json")
const AxiomManifestHash* = hash_kernel.sha256Hex(AxiomManifestIndexContent)
const AxiomManifestJsonData* = AxiomManifestIndexContent

proc getManifestHash*(): string =
  result = AxiomManifestHash

# ══════════════════════════════════════════════════════════════════════════════
# Compile-Time Accessors
# ══════════════════════════════════════════════════════════════════════════════

proc getGateManifestAsJson*(): string =
  ## Returns the full manifest as a JSON string (compile-time constant).
  ## Replaces: staticRead("gate_manifest.json")
  var root = newJObject()
  var gatesArr = newJArray()
  for gate in AllGateConfigs:
    var gateNode = newJObject()
    gateNode["id"] = newJString(gate.id)
    gateNode["name"] = newJString(gate.name)
    gatesArr.add(gateNode)
  root["gates"] = gatesArr
  result = $root

proc getGateManifestAsNode*(): JsonNode =
  ## Returns the manifest as a parsed JsonNode.
  ## Replaces: parseJson(readFile("gate_manifest.json"))
  result = parseJson(getGateManifestAsJson())

# ══════════════════════════════════════════════════════════════════════════════
# Runtime Accessors
# ══════════════════════════════════════════════════════════════════════════════

proc getGateById*(gateId: string): Option[GateConfig] =
  ## Returns a specific gate configuration by ID.
  ## Replaces: iterating over gate_manifest.json and matching "id" field.
  for gate in allGates():
    if gate.id == gateId:
      return some(gate)
  return none(GateConfig)

proc getGateIds*(): seq[string] =
  ## Returns all gate IDs as a string sequence.
  ## Replaces: parsing gate_manifest.json and extracting "id" fields.
  for gate in allGates():
    result.add(gate.id)

proc manifestExists*(): bool =
  ## Returns true if the manifest data is available.
  result = allGates().len > 0

proc manifestContentHash*(): string =
  ## Returns a hash of the manifest content for staleness detection.
  ## Replaces: readFile("gate_manifest.json") + SHA-256 hash
  let content = getGateManifestAsJson()
  result = hash_kernel.sha256Hex(content)

# ══════════════════════════════════════════════════════════════════════════════
# Backward-Compatible Accessors
# ══════════════════════════════════════════════════════════════════════════════

proc allGatesAsJson*(): string =
  ## Returns all gates as JSON string.
  ## Replaces: readFile("gate_manifest.json")
  result = getGateManifestAsJson()

proc allGateIds*(): seq[string] =
  ## Alias for getGateIds for backward compatibility.
  result = getGateIds()

# ══════════════════════════════════════════════════════════════════════════════
# ManifestProvider Protocol
# ══════════════════════════════════════════════════════════════════════════════

type ManifestProvider* = object
  getJson*: proc(): string
  getHash*: proc(): string
  exists*: proc(): bool

proc newManifestProvider*(): ManifestProvider =
  result.getJson = getGateManifestAsJson
  result.getHash = getManifestHash
  result.exists = manifestExists

proc getManifestData*(p: ManifestProvider): string =
  assert p.getJson != nil, "ManifestProvider not initialized — use newManifestProvider()"
  result = p.getJson()
