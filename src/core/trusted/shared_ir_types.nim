import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## Shared IR Types — DSL-generated types for shared memory IPC.
##
## Uses the `defineIR` macro from ir_def.nim to generate both Nim packed
## objects and Lean 4 structures from a single source of truth.
## The Lean file is generated at compile time to proofs/Generated/SharedIRHeader.lean.

import ir_def

defineIR "SharedIRHeader":
  struct SharedIRHeader {.packed.}:
    magic: uint32
    version: uint32
    headerSize: uint32
    status: int32
    irOffset: uint64
    irSize: uint64
    resultOffset: uint64
    resultSize: uint64
    padding: array[16, byte]

{.pop.}
