# axiom:gate-registry

## gate_registry.nim — Core types for gate execution (GateContext, GateRunner, GateSpec).
##
## Provides:
##   - GateSpec type with id, dependsOn, runner fields
##   - GateContext type for gate execution context
##   - GateRunner proc type for gate implementation signatures

type
  ## GateContext provides execution context for gate runners.
  GateContext* = object
    repoRoot*: string           ## Repository root directory
    stagedFiles*: seq[string]   ## Files staged for commit

  ## GateRunner is the proc type for gate implementations.
  ## {.gcsafe.} ensures thread-safe execution in concurrent contexts.
  ## {.raises: [].} ensures deterministic exception-free execution (static-first).
  GateRunner* = proc(ctx: GateContext): bool {.nimcall, gcsafe, raises: [].}

  ## GateSpec defines a gate's metadata and implementation reference.
  GateSpec* = object
    id*: string            ## Unique gate identifier
    dependsOn*: seq[string]  ## Gate IDs this gate depends on (DAG edges)
    runner*: GateRunner    ## Gate implementation proc
