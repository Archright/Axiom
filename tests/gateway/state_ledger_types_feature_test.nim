## State Ledger Types Feature Test.
## Verifies the fixed-size binary layout types for cross-process pipeline state.
##
## Tests:
##   - LedgerStage enum values and ordinals
##   - LedgerGateResult enum values and ordinals
##   - LedgerMagic and LedgerVersion constants
##   - LedgerTotalSize matches expected 7528 bytes
##   - GateStateEntry accessor functions (isDeferred, setDeferred, clearDeferred)
##   - SubtreeRoot round-trip via reserved bytes

import std/[unittest]
import core/gate/state_ledger_types
import core/gate/hash_types
from core/gate/static_project_matrix import AxiomLedgerCap

suite "State Ledger Types — Enum Values":

  test "LedgerStage ordinals match specification":
    ## Given the LedgerStage enum
    ## When checked against the v27 binary layout spec
    ## Then ordinals are 0, 1, 2, 3
    check uint8(lsPreCommit) == 0'u8
    check uint8(lsPrePush) == 1'u8
    check uint8(lsManual) == 2'u8
    check uint8(lsCi) == 3'u8

  test "LedgerGateResult ordinals match specification":
    ## Given the LedgerGateResult enum
    ## When checked against the v27 binary layout spec
    ## Then ordinals are 0..4
    check uint8(lgrUnknown) == 0'u8
    check uint8(lgrPass) == 1'u8
    check uint8(lgrFail) == 2'u8
    check uint8(lgrSkip) == 3'u8
    check uint8(lgrDeferred) == 4'u8

suite "State Ledger Types — Constants":

  test "LedgerMagic is AXGL in hex":
    ## Given the magic number for Axiom Gate Ledger
    ## When checked
    ## Then it equals 0x4158474C ('A'=0x41, 'X'=0x58, 'G'=0x47, 'L'=0x4C)
    check LedgerMagic == 0x4158474C'u32

  test "LedgerVersion is 4":
    ## Given the binary layout version
    ## When checked
    ## Then it equals 4 (v4 added stagingTreeHash to WorkspaceState)
    check LedgerVersion == 4'u16

  test "LedgerHeaderSize is 64 bytes":
    ## Given the fixed header size
    ## When checked
    ## Then it equals 64
    check LedgerHeaderSize == 64

  test "LedgerTotalSize matches 7528 bytes":
    ## Given the total ledger size formula
    ## When computed: 64 + 160 + (57 * 128) + 4 + 4
    ## Then it equals 7528
    check LedgerTotalSize == 7528

  test "AxiomLedgerCap is 57":
    ## Given the ledger slot capacity in the manifest
    ## When checked
    ## Then it equals 57 (upper bound ≥ live gate count 54)
    check AxiomLedgerCap == 57

suite "State Ledger Types — GateStateEntry Accessors":

  test "fresh entry is not deferred":
    ## Given a default-initialized GateStateEntry
    ## When isDeferred is called
    ## Then it returns false
    var entry: GateStateEntry
    check isDeferred(entry) == false

  test "setDeferred marks entry as deferred":
    ## Given a GateStateEntry
    ## When setDeferred is called with stage and timestamp
    ## Then isDeferred returns true
    var entry: GateStateEntry
    setDeferred(entry, uint8(lsPreCommit), 1700000000)
    check isDeferred(entry) == true
    check entry.deferredAt == 1700000000
    check entry.deferredStage == uint8(lsPreCommit)

  test "clearDeferred resets deferred state":
    ## Given a deferred GateStateEntry
    ## When clearDeferred is called
    ## Then isDeferred returns false and deferredAt is zeroed
    var entry: GateStateEntry
    setDeferred(entry, uint8(lsPrePush), 1700000000)
    check isDeferred(entry) == true
    clearDeferred(entry)
    check isDeferred(entry) == false
    check entry.deferredAt == 0
    check entry.deferredStage == 0

  test "subtreeRoot round-trip via reserved bytes":
    ## Given a HashValue with non-zero data
    ## When setSubtreeRoot is called then getSubtreeRoot
    ## Then the original value is recovered
    var entry: GateStateEntry
    var root: HashValue
    root.data[0] = 0xDEADBEEF'u64
    root.data[1] = 0xCAFEBABE'u64
    root.data[2] = 0x12345678'u64
    root.data[3] = 0x87654321'u64
    setSubtreeRoot(entry, root)
    let recovered = getSubtreeRoot(entry)
    check recovered == root
