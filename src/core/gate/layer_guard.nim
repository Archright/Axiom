import core/trusted/layer_declaration
axiomLayer "domain"
import core/trusted/axiom_pragmas
{.push raises: [].}
# axiomIoBoundary
## layer_guard.nim — Compile-time Poison Pill
##
## AGENTS.md §1.2: Domain (src/core/) MUST NOT import Infrastructure (verification/),
## Presentation (cli/), or Gate (gate/) layers. This module enforces that boundary
## at compile time using the `{.error.}` pragma.
##
## **Mechanism**: Each symbol below is a stub declaration marked with `{.error.}`.
## If any module in `src/core/` imports this guard AND attempts to use one of
## these symbols (directly or via transitive import from the forbidden layer),
## the compiler emits a hard error. No runtime cost — purely compile-time.
##
## **Composition Root Exemption**: `src/cli/main.nim` (the Composition Root /
## gateway_main equivalent) is the ONLY module that may import across layers.
## It wires Domain → Infrastructure → Presentation. It MUST NOT import this guard.
##
## **Usage**: Import this module in any `src/core/` module to opt into layer
## boundary enforcement:
##
##   import core/gate/layer_guard  # activates compile-time boundary check
##
## **Adding new guards**: When a new symbol from a forbidden layer is discovered
## being used in src/core/, add a stub here with an appropriate error message
## referencing the AGENTS.md section.

# ============================================================================
# Gate Layer (src/gate/) — L0 Orchestrator, L1 Meta, L2 Functional
# AGENTS.md §1.2: Gate layer is Infrastructure. Domain MUST NOT import it.
# ============================================================================

type
  GateConfig* {.error: "AGENTS.md §1.2: Domain (core/) MUST NOT use gate/GateConfig. Gate types belong to Infrastructure layer.".} = object
    ## Poison stub for gate_types.GateConfig. Real definition in src/gate/gate_types.nim.

  GateStage* {.error: "AGENTS.md §1.2: Domain (core/) MUST NOT use gate/GateStage. Gate enums belong to Infrastructure layer.".} = enum
    ## Poison stub for gate_types.GateStage. Real definition in src/gate/gate_types.nim.
    gsPoisonDummy

  GateLayer* {.error: "AGENTS.md §1.2: Domain (core/) MUST NOT use gate/GateLayer. Gate enums belong to Infrastructure layer.".} = enum
    ## Poison stub for gate_types.GateLayer. Real definition in src/gate/gate_types.nim.
    glPoisonDummy

  GateWeight* {.error: "AGENTS.md §1.2: Domain (core/) MUST NOT use gate/GateWeight. Gate enums belong to Infrastructure layer.".} = enum
    ## Poison stub for gate_types.GateWeight. Real definition in src/gate/gate_types.nim.
    gwPoisonDummy

  GateResult* {.error: "AGENTS.md §1.2: Domain (core/) MUST NOT use gate/GateResult. Gate types belong to Infrastructure layer.".} = object
    ## Poison stub for gate_types.GateResult. Real definition in src/gate/gate_types.nim.

  GateRunner* {.error: "AGENTS.md §1.2: Domain (core/) MUST NOT use gate/GateRunner. Gate types belong to Infrastructure layer.".} = object
    ## Poison stub for gate_types.GateRunner. Real definition in src/gate/gate_types.nim.

  GateRunMode* {.error: "AGENTS.md §1.2: Domain (core/) MUST NOT use gate/GateRunMode. Gate enums belong to Infrastructure layer.".} = enum
    ## Poison stub for gate_types.GateRunMode. Real definition in src/gate/gate_types.nim.
    grmPoisonDummy

func gate_hook*() {.error: "AGENTS.md §1.2: Domain (core/) MUST NOT call gate_hook. Gate orchestration belongs to Infrastructure layer.".} =
  ## Poison stub for gate_hook.runPreCommit/runPrePush orchestrator.

func dispatchGate*() {.error: "AGENTS.md §1.2: Domain (core/) MUST NOT call dispatchGate. Gate dispatch belongs to Infrastructure layer.".} =
  ## Poison stub for gate dispatch entry point.

func runGateHook*() {.error: "AGENTS.md §1.2: Domain (core/) MUST NOT call runGateHook. Gate orchestration belongs to Infrastructure layer.".} =
  ## Poison stub for gate_hook.runGateHook.

func runBatch*() {.error: "AGENTS.md §1.2: Domain (core/) MUST NOT call gate/runBatch. Batch execution belongs to Infrastructure layer.".} =
  ## Poison stub for gate runners.runBatch.

func allGates*() {.error: "AGENTS.md §1.2: Domain (core/) MUST NOT call gate/allGates. Gate registry belongs to Infrastructure layer.".} =
  ## Poison stub for gate_list.allGates.

func shouldRun*() {.error: "AGENTS.md §1.2: Domain (core/) MUST NOT call gate/shouldRun. Gate scheduling belongs to Infrastructure layer.".} =
  ## Poison stub for gate_utils.shouldRun.


# ============================================================================
# CLI Layer (src/cli/) — Presentation
# AGENTS.md §1.2: CLI is Presentation. Domain MUST NOT import it.
# ============================================================================

func runMain*(args: seq[string]) {.error: "AGENTS.md §1.2: Domain (core/) MUST NOT call cli/runMain. CLI entry points belong to Presentation layer.".} =
  ## Poison stub for cli/main.runMain.

func runReportCli*(args: seq[string]) {.error: "AGENTS.md §1.2: Domain (core/) MUST NOT call cli/runReportCli. CLI commands belong to Presentation layer.".} =
  ## Poison stub for report_cli.runReportCli.

proc runAxiomEngineCli*() {.error: "AGENTS.md §1.2: Domain (core/) MUST NOT call cli/runAxiomEngineCli. CLI commands belong to Presentation layer.", axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Poison stub for axiom_engine.runAxiomEngineCli.

func runCli*() {.error: "AGENTS.md §1.2: Domain (core/) MUST NOT call cli/runCli. CLI dispatch belongs to Presentation layer.".} =
  ## Poison stub for main.runCli.


# ============================================================================
# Verification Layer (src/verification/) — Infrastructure
# AGENTS.md §1.2: Verification is Infrastructure. Domain MUST NOT import it.
# Exception: solver/provers.nim MAY be used in Composition Root only.
# ============================================================================

type
  LeanLspClient* {.error: "AGENTS.md §1.2: Domain (core/) MUST NOT use verification/LeanLspClient. LSP clients belong to Infrastructure layer.".} = ref object
    ## Poison stub for lean_lsp.LeanLspClient. Real definition in src/verification/lean_lsp.nim.

  LeanLspClientPool* {.error: "AGENTS.md §1.2: Domain (core/) MUST NOT use verification/LeanLspClientPool. LSP pools belong to Infrastructure layer.".} = object
    ## Poison stub for lean_lsp.LeanLspClientPool.

proc z3ExecPersistent*(query: string; timeoutMs: int; desiredWorkers: int = 1) {.error: "AGENTS.md §1.2: Domain (core/) MUST NOT call verification/z3ExecPersistent. Z3 pool belongs to Infrastructure layer.", axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Poison stub for z3_pool.z3ExecPersistent. Real definition in src/verification/solver/z3_pool.nim.

func proveWithFixedpoint*() {.error: "AGENTS.md §1.2: Domain (core/) MUST NOT call verification/proveWithFixedpoint. Fixed-point engine belongs to Infrastructure layer.".} =
  ## Poison stub for fixedpoint_engine.proveWithFixedpoint.

{.pop}
