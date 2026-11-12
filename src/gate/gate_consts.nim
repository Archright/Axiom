import core/trusted/layer_declaration
axiomLayer "gate"
import std/staticos
import std/tables
when staticFileExists("src/core/trusted/layer_rules.nim"):
  import core/trusted/layer_rules
  # ALL symbols consumed from module MUST live inside this block
  export layer_rules.LayerRule, layer_rules.DebtBudget
  export layer_rules.LayerRules, layer_rules.DebtBudgets
  const HasLayerRules* = true
else:
  const HasLayerRules* = false

const InternalPaths*: array[32, string] = [
  "core/types/", "core/verified_axioms_catalog_parts/",
  "core/io_utils_isolation", "core/verified_axioms/",
  "core/the_judge_query_parts/",
  "core/bmc/", "core/solver/", "core/encoding/", "core/logic/",
  "core/orchestrator/", "core/session/", "core/sorter/",
  "core/vault/", "core/gateway/", "core/topology/",
  "core/policy/", "core/identity/", "core/contracts/",
  "core/type_system/", "core/diagnostics/", "core/sync/",
  "core/profiles/", "core/json/", "core/utils/", "core/file/",
  "core/io/", "core/proof/", "core/integrity/", "core/trusted/",
  "core/parsers/", "core/spec/", "core/schema/",
]
let hubMapping*: Table[string, seq[string]] = {
  "src/core/verified_axioms/verified_axioms.nim": @["core/verified_axioms_catalog_parts/", "core/verified_axioms/"],
  "src/core/utils/io_utils.nim": @["core/io_utils_isolation"],
  # The proof-universe lock gate must reuse the canonical lock-identity predicate
  # (verifyProofUniverseLock) so the gate's runtime check is byte-for-byte the same
  # computation used by `ax vkd sync` / lock commitment. Replicating the Merkle
  # recomputation in the gate would risk drift from the SSOT. Exact-file scope only.
  "src/gate/runners/proof_universe_lock_gate.nim": @["core/proof/"],
  # Temporary exemptions for upper layers

  "src/cli/": @["core/gateway/", "core/logic/", "core/solver/", "core/types/", "core/orchestrator/",
               "core/proof/", "core/bmc/", "core/diagnostics/", "core/topology/", "core/sorter/",
               "core/json/", "core/vault/", "core/session/", "core/encoding/", "core/sync/",
               "core/identity/", "core/contracts/", "core/type_system/", "core/profiles/",
               "core/utils/", "core/file/", "core/io/", "core/integrity/", "core/trusted/",
               "core/parsers/", "core/spec/", "core/policy/"],
  "src/mcp/": @["core/gateway/", "core/logic/", "core/solver/", "core/types/", "core/orchestrator/",
               "core/proof/", "core/bmc/", "core/diagnostics/", "core/topology/", "core/sorter/",
               "core/json/", "core/vault/", "core/session/", "core/encoding/", "core/sync/",
               "core/identity/", "core/contracts/", "core/type_system/", "core/profiles/",
               "core/utils/", "core/file/", "core/io/", "core/integrity/", "core/trusted/",
               "core/parsers/", "core/spec/", "core/policy/"],
  "src/verification/": @["core/gateway/", "core/logic/", "core/solver/", "core/types/", "core/orchestrator/",
                        "core/proof/", "core/bmc/", "core/diagnostics/", "core/topology/", "core/sorter/",
                        "core/json/", "core/vault/", "core/session/", "core/encoding/", "core/sync/",
                        "core/identity/", "core/contracts/", "core/type_system/", "core/profiles/",
                        "core/utils/", "core/file/", "core/io/", "core/integrity/", "core/trusted/",
                        "core/parsers/", "core/spec/", "core/policy/",
                        "core/verified_axioms_catalog_parts/", "core/verified_axioms/"],
  "src/sieve/": @["core/sorter/", "core/topology/", "core/parsers/"],
  "src/api/": @["core/orchestrator/", "core/sorter/", "core/types/"],
  "src/gate/": @["core/parsers/", "core/types/", "core/solver/", "core/json/", "core/trusted/"],
  "src/frontend/": @["core/types/"],
  "src/engine/": @["core/gateway/", "core/proof/", "core/solver/", "core/types/", "core/trusted/"],
  "tools/": @["core/types/", "core/trusted/", "gate/gate_types", "gate/topology_spec", "gate/framework/topology_types", "verification/lean_repl_bridge", "verification/router"],
  "src/personas/": @["core/contracts/", "core/types/"],
  "src/infrastructure/": @["core/contracts/", "core/topology/", "core/trusted/"],
}.toTable

# LayerRule, DebtBudget, LayerRules, DebtBudgets
# are conditionally re-exported from core/trusted/layer_rules (see above).
