import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## DEBT#426: static-analyzer (declared in config/gates.json, entry tools/static_analyzer)
## exits 1 on ANY violation with no threshold/baseline/whitelist policy. Currently
## disabled in gates.json pending a fail-closed threshold policy.

## config_loader.nim — Centralized runtime configuration for gates.
##
## Loads config/gates.json and provides O(1) lookup via Table[string, GateRuntimeConfig].
## Falls back to all-enabled/Strict defaults if the file is missing or malformed.
## Generates a default config file on first run when it does not exist.
##
## Usage:
##   import gate/config_loader
##   let cfg = loadGateRuntimeConfig()
##   if cfg.isEnabled("documentation-first-gate"): echo "enabled"

import std/json
import std/os
import std/tables
import std/strformat
import core/utils/repo_root
import infrastructure/logger
import core/trusted/axiom_pragmas
const debtMarker426 {.axiomDebt: "DEBT#426".} = true

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  GateRuntimeConfig* = object
    enabled*: bool

  GateRuntimeCatalog* = ref object
    data*: Table[string, GateRuntimeConfig]

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

const DefaultEnabled* = true

func newGateRuntimeCatalog*(): GateRuntimeCatalog =
  result = GateRuntimeCatalog()
  result.data = initTable[string, GateRuntimeConfig]()

func isEmpty*(catalog: GateRuntimeCatalog): bool =
  catalog.data.len == 0

# ---------------------------------------------------------------------------
# Pure query functions (func) — no I/O, no exceptions
# ---------------------------------------------------------------------------

func isEnabled*(catalog: GateRuntimeCatalog, gateId: string): bool =
  ## Returns true if ``gateId`` is enabled in the catalog, or true if absent (default).
  if gateId in catalog.data:
    catalog.data[gateId].enabled
  else:
    DefaultEnabled

func contains*(catalog: GateRuntimeCatalog, gateId: string): bool =
  gateId in catalog.data

func allGateIds*(catalog: GateRuntimeCatalog): seq[string] =
  result = @[]
  for k in catalog.data.keys:
    result.add(k)

# ---------------------------------------------------------------------------
# JSON Parsing
# ---------------------------------------------------------------------------

proc parseGateEntry(node: JsonNode): GateRuntimeConfig {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Parse a single gate entry from JSON node with safe defaults.
  result.enabled = if node.hasKey("enabled"): node["enabled"].getBool() else: DefaultEnabled

proc buildCatalogFromJson*(node: JsonNode): GateRuntimeCatalog {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Build a GateRuntimeCatalog from the parsed JSON root node.
  result = newGateRuntimeCatalog()
  if not node.hasKey("gates") or node["gates"].kind != JObject:
    return
  let gatesObj = node["gates"]
  for key, val in gatesObj.pairs:
    try:
      result.data[key] = parseGateEntry(val)
    except CatchableError:
      logger.warn(&"[gate-config] Skipping malformed entry for gate: {key}")
  if result.data.len == 0 and node.hasKey("gates"):
    logger.error("[gate-config] FATAL: config/gates.json exists but parsed 0 gates. Check JSON schema or loader logic.")

# ---------------------------------------------------------------------------
# Default Config Generation
# ---------------------------------------------------------------------------

let allDefaultGates* = [
  "anti-theater-gate", "asset-hygiene-gate", "binary-artifact-gate",
  "binary-freshness-gate", "cli-build",
  "core-invariant-gate", "coverage-ratchet-gate",
  "debt-integrity-gate", "delegation-enforcer", "discarded-write-audit-gate",
  "doc-completeness-gate", "documentation-first-gate", "effect-inference-gate",
  "emergency-bypass-commit", "env-gate", "evidence-truth-boundary-gate", "external-cli-smoke", "gate-self-check",
  "gateway-test", "golden-master-gate", "hermetic-test-gate", "hotspot-gate",
  "immunity-gate", "import-encapsulation-gate", "integrity-test", "integrity-workflow",
  "intent-gate", "language-ban-gate", "layer-enforcement-gate", "lean-z3-consensus-gate",
  "manifest-consistency-gate", "mcp-tool-usage-gate",
  "monotonic-whitelist-gate", "nim-check", "policy-validator", "procedure-gate",
  "proof-universe-lock-gate", "quality-gate-runner", "release-version-gate",
  "reliability-gate", "sorry-audit-gate", "spec-binding-gate", "spec-presence-gate",
  "static-analyzer", "tcb-coverage-gate",
  "test-coverage-gate", "unstaged-guard", "verification-auditor"
]

proc generateDefaultConfig(root: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Generate default JSON config string for all known gates.
  result = "{\n"
  result.add("  \"phase3c\": true,\n")
  result.add("  \"gates\": {\n")
  let total = allDefaultGates.len
  for i, gid in allDefaultGates:
    let comma = if i < total - 1: "," else: ""
    result.add(&"    \"{gid}\": {{\"enabled\": true}}{comma}\n")
  result.add("  }\n")
  result.add("}\n")

proc ensureDefaultConfig(root: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## If config/gates.json does not exist, generate and write it.
  let configPath = root / "config" / "gates.json"
  if not fileExists(configPath):
    let content = generateDefaultConfig(root)
    writeFile(configPath, content)
    logger.info(&"[gate-config] Generated default config: {configPath}")

# ---------------------------------------------------------------------------
# Main Loader
# ---------------------------------------------------------------------------

proc loadGateRuntimeConfigFromRoot*(root: string): GateRuntimeCatalog {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Load and parse config/gates.json from the given project root.
  ## If the file is missing, generates a default one and returns all-defaults catalog.
  ## If parsing fails, falls back to all-defaults catalog.
  result = newGateRuntimeCatalog()

  # Ensure default config exists
  ensureDefaultConfig(root)

  let configPath = root / "config" / "gates.json"
  if not fileExists(configPath):
    logger.warn("[gate-config] Config file missing, using all-defaults catalog")
    return

  try:
    let content = readFile(configPath)
    let node = parseJson(content)

    # Validate phase3c marker
    if node.hasKey("phase3c") and node["phase3c"].getBool():
      result = buildCatalogFromJson(node)
      logger.info(&"[gate-config] Loaded {result.data.len} gate(s) from {configPath}")
    else:
      logger.warn("[gate-config] Missing or false phase3c marker, using all-defaults catalog")
  except ValueError:
    logger.warn(&"[gate-config] Failed to parse {configPath}, using all-defaults catalog")
  except CatchableError as e:
    logger.warn(&"[gate-config] Error loading {configPath}: {e.msg}, using all-defaults catalog")

proc loadGateRuntimeConfig*(): GateRuntimeCatalog =
  ## Load gate runtime config using auto-detected project root.
  let root = findRepoRoot()
  result = loadGateRuntimeConfigFromRoot(root)

when isMainModule:
  ## Excluded from aggregated nim check to avoid UnusedImport warnings.
  let cfg = loadGateRuntimeConfig()
  logger.info &"[gate-config] catalog has {cfg.data.len} entries"
