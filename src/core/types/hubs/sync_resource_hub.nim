import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import std/locks

when defined(windows):
  import std/winlean

## Canonical sync/resource types — SSOT for sync_utils_process and sync_utils_resource.
## Extracted to eliminate 9-type duplication cluster.

type
  CpuSample* = object
    valid*: bool
    idleTicks*: int64
    kernelTicks*: int64
    userTicks*: int64

  ResourceSnapshot* = object
    availableMemoryBytes*: int64
    cpuLoadRatio*: float
    recommendedLimit*: int

  ResourcePolicy* = object
    minAvailableMemoryBytes*: int64
    highCpuLoadRatio*: float
    lowCpuLoadRatio*: float

  ManagedProcessResult* = object
    exitCode*: int
    timedOut*: bool
    output*: string

  ResourceSemaphore* = object
    limit*: int
    active*: int
    maxLimit*: int
    policy*: ResourcePolicy
    lastSnapshot*: ResourceSnapshot
    previousCpuSample*: CpuSample
    gate*: Lock

  ResourceTimeoutError* = object of CatchableError
    ## Raised when ResourceSemaphore acquire exceeds deadline

  ResourceLimitError* = object of CatchableError
    ## Raised when ResourceSemaphore limit is 0 (guaranteed deadlock)

  ResourceTicket* = object
    ## RAII-style handle for semaphore slot. releaseTicket is guaranteed
    ## safe to call multiple times (idempotent).
    semaphore*: ptr ResourceSemaphore
    acquired*: bool

when defined(windows):
  type
    MemoryStatusEx* = object
      dwLength*: DWORD
      dwMemoryLoad*: DWORD
      ullTotalPhys*: uint64
      ullAvailPhys*: uint64
      ullTotalPageFile*: uint64
      ullAvailPageFile*: uint64
      ullTotalVirtual*: uint64
      ullAvailVirtual*: uint64
      ullAvailExtendedVirtual*: uint64

{.pop.}
