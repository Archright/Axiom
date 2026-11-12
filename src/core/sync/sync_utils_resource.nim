import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import std/locks
import std/os
import std/strutils
import std/times
import core/trusted/axiom_pragmas

when defined(windows):
  import std/winlean

import core/types/hubs/sync_resource_hub
export sync_resource_hub

# @axiom-hint: lean="lpBuffer_ullTotalPhys ≥ 0 ∧ lpBuffer_ullAvailPhys ≥ 0 ∧ lpBuffer_ullTotalPageFile ≥ 0 ∧ lpBuffer_ullAvailPageFile ≥ 0 ∧ lpBuffer_ullTotalVirtual ≥ 0 ∧ lpBuffer_ullAvailVirtual ≥ 0 ∧ lpBuffer_ullAvailExtendedVirtual ≥ 0" smt="(assert (and (>= lpBuffer_ullTotalPhys 0) (>= lpBuffer_ullAvailPhys 0) (>= lpBuffer_ullTotalPageFile 0) (>= lpBuffer_ullAvailPageFile 0) (>= lpBuffer_ullTotalVirtual 0) (>= lpBuffer_ullAvailVirtual 0) (>= lpBuffer_ullAvailExtendedVirtual 0)))"
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
when defined(windows):
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
  func globalMemoryStatusEx(lpBuffer: var MemoryStatusEx): WINBOOL {.
    stdcall, dynlib: "kernel32", importc: "GlobalMemoryStatusEx".}

const
  defaultMinAvailableMemoryBytes* = 1'i64 shl 30
  defaultHighCpuLoadRatio* = 0.85
  defaultLowCpuLoadRatio* = 0.55

# @axiom-hint: lean="limit > 0 ∧ limit ∧ limit > 0 → result = limit" smt="(assert (and (> limit 0) limit (=> (> limit 0) (= result limit))))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func clampResourceLimit(limit: int): int =
  if limit > 0:
    return limit
  1

## Init Resource Policy.
# @axiom-hint: lean="minAvailableMemoryBytes ≥ -9223372036854775808 ∧ minAvailableMemoryBytes ≤ 9223372036854775807" smt="(assert (and (and (>= minAvailableMemoryBytes -9223372036854775808) (<= minAvailableMemoryBytes 9223372036854775807))))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func initResourcePolicy*(
  minAvailableMemoryBytes: int64 = defaultMinAvailableMemoryBytes;
  highCpuLoadRatio: float = defaultHighCpuLoadRatio;
  lowCpuLoadRatio: float = defaultLowCpuLoadRatio
): ResourcePolicy {.inline.} =
  ResourcePolicy(
    minAvailableMemoryBytes: minAvailableMemoryBytes,
    highCpuLoadRatio: highCpuLoadRatio,
    lowCpuLoadRatio: lowCpuLoadRatio
  )

## Recommend Resource Limit.
# @axiom-hint: lean="currentLimit > boundedDesired" smt="(assert (and (> currentLimit boundedDesired)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func recommendResourceLimit*(
  currentLimit: int;
  desiredLimit: int;
  snapshot: ResourceSnapshot;
  policy: ResourcePolicy
): int =
  let boundedDesired = clampResourceLimit(desiredLimit)
  let boundedCurrent =
    if currentLimit > boundedDesired:
      boundedDesired
    else:
      clampResourceLimit(currentLimit)
  if snapshot.availableMemoryBytes > 0'i64 and
      snapshot.availableMemoryBytes < policy.minAvailableMemoryBytes:
    return max(1, boundedCurrent - 1)
  if snapshot.cpuLoadRatio > policy.highCpuLoadRatio:
    return max(1, boundedCurrent - 1)
  if snapshot.availableMemoryBytes >= policy.minAvailableMemoryBytes * 2'i64 and
      snapshot.cpuLoadRatio < policy.lowCpuLoadRatio:
    return min(boundedDesired, boundedCurrent + 1)
  boundedCurrent

## Init Resource Semaphore.
# @axiom-hint: lean="(semaphore ≥ 0) ∧ semaphore_previousCpuSample_valid = true ∨ semaphore_previousCpuSample_valid = false" smt="(assert (and (>= semaphore 0) (or (= semaphore_previousCpuSample_valid true) (= semaphore_previousCpuSample_valid false))))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func initResourceSemaphore*(
  semaphore: var ResourceSemaphore;
  limit: int;
  policy: ResourcePolicy = initResourcePolicy()
) =
  let boundedLimit = clampResourceLimit(limit)
  semaphore.limit = boundedLimit
  semaphore.maxLimit = boundedLimit
  semaphore.active = 0
  semaphore.policy = policy
  semaphore.lastSnapshot = ResourceSnapshot(
    availableMemoryBytes: 0,
    cpuLoadRatio: 0.0,
    recommendedLimit: boundedLimit
  )
  semaphore.previousCpuSample = CpuSample(valid: false)
  initLock(semaphore.gate)

## Deinit Resource Semaphore.
# @axiom-hint: lean="semaphore_limit ≥ -9223372036854775808 ∧ semaphore_limit ≤ 9223372036854775807 ∧ semaphore_active ≥ -9223372036854775808 ∧ semaphore_active ≤ 9223372036854775807 ∧ semaphore_maxLimit ≥ -9223372036854775808 ∧ semaphore_maxLimit ≤ 9223372036854775807 ∧ semaphore_policy_minAvailableMemoryBytes ≥ -9223372036854775808 ∧ semaphore_policy_minAvailableMemoryBytes ≤ 9223372036854775807 ∧ semaphore_lastSnapshot_availableMemoryBytes ≥ -9223372036854775808 ∧ semaphore_lastSnapshot_availableMemoryBytes ≤ 9223372036854775807 ∧ semaphore_lastSnapshot_recommendedLimit ≥ -9223372036854775808 ∧ semaphore_lastSnapshot_recommendedLimit ≤ 9223372036854775807 ∧ semaphore_previousCpuSample_valid = true ∨ semaphore_previousCpuSample_valid = false ∧ semaphore_previousCpuSample_idleTicks ≥ -9223372036854775808 ∧ semaphore_previousCpuSample_idleTicks ≤ 9223372036854775807 ∧ semaphore_previousCpuSample_kernelTicks ≥ -9223372036854775808 ∧ semaphore_previousCpuSample_kernelTicks ≤ 9223372036854775807 ∧ semaphore_previousCpuSample_userTicks ≥ -9223372036854775808 ∧ semaphore_previousCpuSample_userTicks ≤ 9223372036854775807" smt="(assert (and (and (>= semaphore_limit -9223372036854775808) (<= semaphore_limit 9223372036854775807)) (and (>= semaphore_active -9223372036854775808) (<= semaphore_active 9223372036854775807)) (and (>= semaphore_maxLimit -9223372036854775808) (<= semaphore_maxLimit 9223372036854775807)) (and (>= semaphore_policy_minAvailableMemoryBytes -9223372036854775808) (<= semaphore_policy_minAvailableMemoryBytes 9223372036854775807)) (and (>= semaphore_lastSnapshot_availableMemoryBytes -9223372036854775808) (<= semaphore_lastSnapshot_availableMemoryBytes 9223372036854775807)) (and (>= semaphore_lastSnapshot_recommendedLimit -9223372036854775808) (<= semaphore_lastSnapshot_recommendedLimit 9223372036854775807)) (or (= semaphore_previousCpuSample_valid true) (= semaphore_previousCpuSample_valid false)) (and (>= semaphore_previousCpuSample_idleTicks -9223372036854775808) (<= semaphore_previousCpuSample_idleTicks 9223372036854775807)) (and (>= semaphore_previousCpuSample_kernelTicks -9223372036854775808) (<= semaphore_previousCpuSample_kernelTicks 9223372036854775807)) (and (>= semaphore_previousCpuSample_userTicks -9223372036854775808) (<= semaphore_previousCpuSample_userTicks 9223372036854775807))))"
# @axiom-hint: lean="semaphore_previousCpuSample_valid = true ∨ semaphore_previousCpuSample_valid = false" smt="(assert (and (or (= semaphore_previousCpuSample_valid true) (= semaphore_previousCpuSample_valid false))))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func deinitResourceSemaphore*(semaphore: var ResourceSemaphore) =
  deinitLock(semaphore.gate)

## Read Available Memory Bytes.
# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc readAvailableMemoryBytes*(): int64 {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  when defined(windows):
    var memoryStatus = MemoryStatusEx()
    memoryStatus.dwLength = DWORD(sizeof(MemoryStatusEx))
    var ok: WINBOOL
    ok = globalMemoryStatusEx(memoryStatus)
    if ok != 0:
      return int64(memoryStatus.ullAvailPhys)
    0'i64
  elif defined(linux):
    try:
      for line in lines("/proc/meminfo"):
        if line.startsWith("MemAvailable:"):
          let parts = line.splitWhitespace()
          if parts.len >= 2:
            return parseBiggestInt(parts[1]) * 1024
      for line in lines("/proc/meminfo"):
        if line.startsWith("MemFree:"):
          let parts = line.splitWhitespace()
          if parts.len >= 2:
            return parseBiggestInt(parts[1]) * 1024
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
    0'i64
  else:
    0'i64

## Read Cpu Load Ratio.
# @axiom-hint: lean="ok = 0 ∧ totalDelta ≤ 0'i64 ∧ busyDelta ≤ 0'i64 ∧ busyDelta ≥ totalDelta ∧ (ok ≥ 0) ∧ (semaphore ≥ 0) ∧ semaphore_previousCpuSample_valid = true ∨ semaphore_previousCpuSample_valid = false" smt="(assert (and (= ok 0) (<= totalDelta 0'i64) (<= busyDelta 0'i64) (>= busyDelta totalDelta) (>= ok 0) (>= semaphore 0) (or (= semaphore_previousCpuSample_valid true) (= semaphore_previousCpuSample_valid false))))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc readCpuLoadRatio*(semaphore: var ResourceSemaphore): float {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  when defined(windows):
    var idleTime, kernelTime, userTime: FILETIME
    var ok: WINBOOL
    ok = getSystemTimes(idleTime, kernelTime, userTime)
    if ok == 0:
      return semaphore.lastSnapshot.cpuLoadRatio
    let currentSample = CpuSample(
      valid: true,
      idleTicks: rdFileTime(idleTime),
      kernelTicks: rdFileTime(kernelTime),
      userTicks: rdFileTime(userTime)
    )
    if not semaphore.previousCpuSample.valid:
      semaphore.previousCpuSample = currentSample
      return 0.0
    let idleDelta = currentSample.idleTicks - semaphore.previousCpuSample.idleTicks
    let kernelDelta = currentSample.kernelTicks - semaphore.previousCpuSample.kernelTicks
    let userDelta = currentSample.userTicks - semaphore.previousCpuSample.userTicks
    semaphore.previousCpuSample = currentSample
    let totalDelta = kernelDelta + userDelta
    if totalDelta <= 0'i64:
      return semaphore.lastSnapshot.cpuLoadRatio
    let busyDelta = totalDelta - idleDelta
    if busyDelta <= 0'i64:
      return 0.0
    if busyDelta >= totalDelta:
      return 1.0
    busyDelta.float / totalDelta.float
  elif defined(linux):
    try:
      let f = open("/proc/stat", fmRead)
      let line = f.readLine()
      f.close()
      if line.startsWith("cpu "):
        let parts = line.splitWhitespace()
        if parts.len >= 5:
          let userTicks = parseBiggestInt(parts[1])
          let niceTicks = if parts.len > 2: parseBiggestInt(parts[2]) else: 0
          let systemTicks = if parts.len > 3: parseBiggestInt(parts[3]) else: 0
          let idleTicks = if parts.len > 4: parseBiggestInt(parts[4]) else: 0
          let ioWaitTicks = if parts.len > 5: parseBiggestInt(parts[5]) else: 0
          let irqTicks = if parts.len > 6: parseBiggestInt(parts[6]) else: 0
          let softIrqTicks = if parts.len > 7: parseBiggestInt(parts[7]) else: 0
          let currentSample = CpuSample(
            valid: true,
            idleTicks: idleTicks + ioWaitTicks,
            kernelTicks: systemTicks + irqTicks + softIrqTicks,
            userTicks: userTicks + niceTicks
          )
          if not semaphore.previousCpuSample.valid:
            semaphore.previousCpuSample = currentSample
            return semaphore.lastSnapshot.cpuLoadRatio
          let idleDelta = currentSample.idleTicks - semaphore.previousCpuSample.idleTicks
          let kernelDelta = currentSample.kernelTicks - semaphore.previousCpuSample.kernelTicks
          let userDelta = currentSample.userTicks - semaphore.previousCpuSample.userTicks
          semaphore.previousCpuSample = currentSample
          let totalDelta = idleDelta + kernelDelta + userDelta
          let busyDelta = kernelDelta + userDelta
          if totalDelta <= 0'i64:
            return semaphore.lastSnapshot.cpuLoadRatio
          if busyDelta <= 0'i64:
            return 0.0
          if busyDelta >= totalDelta:
            return 1.0
          return busyDelta.float / totalDelta.float
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
    semaphore.lastSnapshot.cpuLoadRatio
  else:
    semaphore.lastSnapshot.cpuLoadRatio

## Sample System Resources.
# @axiom-hint: lean="semaphore_limit ≥ -9223372036854775808 ∧ semaphore_limit ≤ 9223372036854775807 ∧ semaphore_active ≥ -9223372036854775808 ∧ semaphore_active ≤ 9223372036854775807 ∧ semaphore_maxLimit ≥ -9223372036854775808 ∧ semaphore_maxLimit ≤ 9223372036854775807 ∧ semaphore_policy_minAvailableMemoryBytes ≥ -9223372036854775808 ∧ semaphore_policy_minAvailableMemoryBytes ≤ 9223372036854775807 ∧ semaphore_lastSnapshot_availableMemoryBytes ≥ -9223372036854775808 ∧ semaphore_lastSnapshot_availableMemoryBytes ≤ 9223372036854775807 ∧ semaphore_lastSnapshot_recommendedLimit ≥ -9223372036854775808 ∧ semaphore_lastSnapshot_recommendedLimit ≤ 9223372036854775807 ∧ semaphore_previousCpuSample_valid = true ∨ semaphore_previousCpuSample_valid = false ∧ semaphore_previousCpuSample_idleTicks ≥ -9223372036854775808 ∧ semaphore_previousCpuSample_idleTicks ≤ 9223372036854775807 ∧ semaphore_previousCpuSample_kernelTicks ≥ -9223372036854775808 ∧ semaphore_previousCpuSample_kernelTicks ≤ 9223372036854775807 ∧ semaphore_previousCpuSample_userTicks ≥ -9223372036854775808 ∧ semaphore_previousCpuSample_userTicks ≤ 9223372036854775807 ∧ desiredLimit ≥ -9223372036854775808 ∧ desiredLimit ≤ 9223372036854775807" smt="(assert (and (and (>= semaphore_limit -9223372036854775808) (<= semaphore_limit 9223372036854775807)) (and (>= semaphore_active -9223372036854775808) (<= semaphore_active 9223372036854775807)) (and (>= semaphore_maxLimit -9223372036854775808) (<= semaphore_maxLimit 9223372036854775807)) (and (>= semaphore_policy_minAvailableMemoryBytes -9223372036854775808) (<= semaphore_policy_minAvailableMemoryBytes 9223372036854775807)) (and (>= semaphore_lastSnapshot_availableMemoryBytes -9223372036854775808) (<= semaphore_lastSnapshot_availableMemoryBytes 9223372036854775807)) (and (>= semaphore_lastSnapshot_recommendedLimit -9223372036854775808) (<= semaphore_lastSnapshot_recommendedLimit 9223372036854775807)) (or (= semaphore_previousCpuSample_valid true) (= semaphore_previousCpuSample_valid false)) (and (>= semaphore_previousCpuSample_idleTicks -9223372036854775808) (<= semaphore_previousCpuSample_idleTicks 9223372036854775807)) (and (>= semaphore_previousCpuSample_kernelTicks -9223372036854775808) (<= semaphore_previousCpuSample_kernelTicks 9223372036854775807)) (and (>= semaphore_previousCpuSample_userTicks -9223372036854775808) (<= semaphore_previousCpuSample_userTicks 9223372036854775807)) (and (>= desiredLimit -9223372036854775808) (<= desiredLimit 9223372036854775807))))"
# @axiom-hint: lean="(semaphore ≥ 0) ∧ (result ≥ 0) ∧ semaphore_previousCpuSample_valid = true ∨ semaphore_previousCpuSample_valid = false" smt="(assert (and (>= semaphore 0) (>= result 0) (or (= semaphore_previousCpuSample_valid true) (= semaphore_previousCpuSample_valid false))))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc sampleSystemResources*(
  semaphore: var ResourceSemaphore;
  desiredLimit: int
): ResourceSnapshot {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  let boundedDesired = clampResourceLimit(desiredLimit)
  result.availableMemoryBytes = readAvailableMemoryBytes()
  result.cpuLoadRatio = readCpuLoadRatio(semaphore)
  result.recommendedLimit = recommendResourceLimit(
    semaphore.limit,
    boundedDesired,
    result,
    semaphore.policy
  )
  semaphore.maxLimit = boundedDesired
  semaphore.limit = result.recommendedLimit
  semaphore.lastSnapshot = result

## Refresh Resource Semaphore.
# @axiom-hint: lean="semaphore_limit ≥ -9223372036854775808 ∧ semaphore_limit ≤ 9223372036854775807 ∧ semaphore_active ≥ -9223372036854775808 ∧ semaphore_active ≤ 9223372036854775807 ∧ semaphore_maxLimit ≥ -9223372036854775808 ∧ semaphore_maxLimit ≤ 9223372036854775807 ∧ semaphore_policy_minAvailableMemoryBytes ≥ -9223372036854775808 ∧ semaphore_policy_minAvailableMemoryBytes ≤ 9223372036854775807 ∧ semaphore_lastSnapshot_availableMemoryBytes ≥ -9223372036854775808 ∧ semaphore_lastSnapshot_availableMemoryBytes ≤ 9223372036854775807 ∧ semaphore_lastSnapshot_recommendedLimit ≥ -9223372036854775808 ∧ semaphore_lastSnapshot_recommendedLimit ≤ 9223372036854775807 ∧ semaphore_previousCpuSample_valid = true ∨ semaphore_previousCpuSample_valid = false ∧ semaphore_previousCpuSample_idleTicks ≥ -9223372036854775808 ∧ semaphore_previousCpuSample_idleTicks ≤ 9223372036854775807 ∧ semaphore_previousCpuSample_kernelTicks ≥ -9223372036854775808 ∧ semaphore_previousCpuSample_kernelTicks ≤ 9223372036854775807 ∧ semaphore_previousCpuSample_userTicks ≥ -9223372036854775808 ∧ semaphore_previousCpuSample_userTicks ≤ 9223372036854775807 ∧ desiredLimit ≥ -9223372036854775808 ∧ desiredLimit ≤ 9223372036854775807" smt="(assert (and (and (>= semaphore_limit -9223372036854775808) (<= semaphore_limit 9223372036854775807)) (and (>= semaphore_active -9223372036854775808) (<= semaphore_active 9223372036854775807)) (and (>= semaphore_maxLimit -9223372036854775808) (<= semaphore_maxLimit 9223372036854775807)) (and (>= semaphore_policy_minAvailableMemoryBytes -9223372036854775808) (<= semaphore_policy_minAvailableMemoryBytes 9223372036854775807)) (and (>= semaphore_lastSnapshot_availableMemoryBytes -9223372036854775808) (<= semaphore_lastSnapshot_availableMemoryBytes 9223372036854775807)) (and (>= semaphore_lastSnapshot_recommendedLimit -9223372036854775808) (<= semaphore_lastSnapshot_recommendedLimit 9223372036854775807)) (or (= semaphore_previousCpuSample_valid true) (= semaphore_previousCpuSample_valid false)) (and (>= semaphore_previousCpuSample_idleTicks -9223372036854775808) (<= semaphore_previousCpuSample_idleTicks 9223372036854775807)) (and (>= semaphore_previousCpuSample_kernelTicks -9223372036854775808) (<= semaphore_previousCpuSample_kernelTicks 9223372036854775807)) (and (>= semaphore_previousCpuSample_userTicks -9223372036854775808) (<= semaphore_previousCpuSample_userTicks 9223372036854775807)) (and (>= desiredLimit -9223372036854775808) (<= desiredLimit 9223372036854775807))))"
# @axiom-hint: lean="(result ≥ 0) ∧ semaphore_previousCpuSample_valid = true ∨ semaphore_previousCpuSample_valid = false" smt="(assert (and (>= result 0) (or (= semaphore_previousCpuSample_valid true) (= semaphore_previousCpuSample_valid false))))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc refreshResourceSemaphore*(
  semaphore: ptr ResourceSemaphore;
  desiredLimit: int
): ResourceSnapshot {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  acquire(semaphore[].gate)
  result = sampleSystemResources(semaphore[], desiredLimit)
  release(semaphore[].gate)

## Acquire Resource Semaphore.
# @axiom-hint: lean="semaphore_limit ≥ -9223372036854775808 ∧ semaphore_limit ≤ 9223372036854775807 ∧ semaphore_active ≥ -9223372036854775808 ∧ semaphore_active ≤ 9223372036854775807 ∧ semaphore_maxLimit ≥ -9223372036854775808 ∧ semaphore_maxLimit ≤ 9223372036854775807 ∧ semaphore_policy_minAvailableMemoryBytes ≥ -9223372036854775808 ∧ semaphore_policy_minAvailableMemoryBytes ≤ 9223372036854775807 ∧ semaphore_lastSnapshot_availableMemoryBytes ≥ -9223372036854775808 ∧ semaphore_lastSnapshot_availableMemoryBytes ≤ 9223372036854775807 ∧ semaphore_lastSnapshot_recommendedLimit ≥ -9223372036854775808 ∧ semaphore_lastSnapshot_recommendedLimit ≤ 9223372036854775807 ∧ semaphore_previousCpuSample_valid = true ∨ semaphore_previousCpuSample_valid = false ∧ semaphore_previousCpuSample_idleTicks ≥ -9223372036854775808 ∧ semaphore_previousCpuSample_idleTicks ≤ 9223372036854775807 ∧ semaphore_previousCpuSample_kernelTicks ≥ -9223372036854775808 ∧ semaphore_previousCpuSample_kernelTicks ≤ 9223372036854775807 ∧ semaphore_previousCpuSample_userTicks ≥ -9223372036854775808 ∧ semaphore_previousCpuSample_userTicks ≤ 9223372036854775807" smt="(assert (and (and (>= semaphore_limit -9223372036854775808) (<= semaphore_limit 9223372036854775807)) (and (>= semaphore_active -9223372036854775808) (<= semaphore_active 9223372036854775807)) (and (>= semaphore_maxLimit -9223372036854775808) (<= semaphore_maxLimit 9223372036854775807)) (and (>= semaphore_policy_minAvailableMemoryBytes -9223372036854775808) (<= semaphore_policy_minAvailableMemoryBytes 9223372036854775807)) (and (>= semaphore_lastSnapshot_availableMemoryBytes -9223372036854775808) (<= semaphore_lastSnapshot_availableMemoryBytes 9223372036854775807)) (and (>= semaphore_lastSnapshot_recommendedLimit -9223372036854775808) (<= semaphore_lastSnapshot_recommendedLimit 9223372036854775807)) (or (= semaphore_previousCpuSample_valid true) (= semaphore_previousCpuSample_valid false)) (and (>= semaphore_previousCpuSample_idleTicks -9223372036854775808) (<= semaphore_previousCpuSample_idleTicks 9223372036854775807)) (and (>= semaphore_previousCpuSample_kernelTicks -9223372036854775808) (<= semaphore_previousCpuSample_kernelTicks 9223372036854775807)) (and (>= semaphore_previousCpuSample_userTicks -9223372036854775808) (<= semaphore_previousCpuSample_userTicks 9223372036854775807))))"
# @axiom-hint: lean="true ∧ semaphore_previousCpuSample_valid = true ∨ semaphore_previousCpuSample_valid = false" smt="(assert (and true (or (= semaphore_previousCpuSample_valid true) (= semaphore_previousCpuSample_valid false))))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc acquireResourceSemaphore*(semaphore: ptr ResourceSemaphore) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  while true:
    acquire(semaphore[].gate)
    if semaphore[].active < semaphore[].limit:
      inc semaphore[].active
      release(semaphore[].gate)
      return
    release(semaphore[].gate)
    sleep(1)

## Release Resource Semaphore.
# @axiom-hint: lean="semaphore_limit ≥ -9223372036854775808 ∧ semaphore_limit ≤ 9223372036854775807 ∧ semaphore_active ≥ -9223372036854775808 ∧ semaphore_active ≤ 9223372036854775807 ∧ semaphore_maxLimit ≥ -9223372036854775808 ∧ semaphore_maxLimit ≤ 9223372036854775807 ∧ semaphore_policy_minAvailableMemoryBytes ≥ -9223372036854775808 ∧ semaphore_policy_minAvailableMemoryBytes ≤ 9223372036854775807 ∧ semaphore_lastSnapshot_availableMemoryBytes ≥ -9223372036854775808 ∧ semaphore_lastSnapshot_availableMemoryBytes ≤ 9223372036854775807 ∧ semaphore_lastSnapshot_recommendedLimit ≥ -9223372036854775808 ∧ semaphore_lastSnapshot_recommendedLimit ≤ 9223372036854775807 ∧ semaphore_previousCpuSample_valid = true ∨ semaphore_previousCpuSample_valid = false ∧ semaphore_previousCpuSample_idleTicks ≥ -9223372036854775808 ∧ semaphore_previousCpuSample_idleTicks ≤ 9223372036854775807 ∧ semaphore_previousCpuSample_kernelTicks ≥ -9223372036854775808 ∧ semaphore_previousCpuSample_kernelTicks ≤ 9223372036854775807 ∧ semaphore_previousCpuSample_userTicks ≥ -9223372036854775808 ∧ semaphore_previousCpuSample_userTicks ≤ 9223372036854775807" smt="(assert (and (and (>= semaphore_limit -9223372036854775808) (<= semaphore_limit 9223372036854775807)) (and (>= semaphore_active -9223372036854775808) (<= semaphore_active 9223372036854775807)) (and (>= semaphore_maxLimit -9223372036854775808) (<= semaphore_maxLimit 9223372036854775807)) (and (>= semaphore_policy_minAvailableMemoryBytes -9223372036854775808) (<= semaphore_policy_minAvailableMemoryBytes 9223372036854775807)) (and (>= semaphore_lastSnapshot_availableMemoryBytes -9223372036854775808) (<= semaphore_lastSnapshot_availableMemoryBytes 9223372036854775807)) (and (>= semaphore_lastSnapshot_recommendedLimit -9223372036854775808) (<= semaphore_lastSnapshot_recommendedLimit 9223372036854775807)) (or (= semaphore_previousCpuSample_valid true) (= semaphore_previousCpuSample_valid false)) (and (>= semaphore_previousCpuSample_idleTicks -9223372036854775808) (<= semaphore_previousCpuSample_idleTicks 9223372036854775807)) (and (>= semaphore_previousCpuSample_kernelTicks -9223372036854775808) (<= semaphore_previousCpuSample_kernelTicks 9223372036854775807)) (and (>= semaphore_previousCpuSample_userTicks -9223372036854775808) (<= semaphore_previousCpuSample_userTicks 9223372036854775807))))"
# @axiom-hint: lean="semaphore_previousCpuSample_valid = true ∨ semaphore_previousCpuSample_valid = false" smt="(assert (and (or (= semaphore_previousCpuSample_valid true) (= semaphore_previousCpuSample_valid false))))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func releaseResourceSemaphore*(semaphore: ptr ResourceSemaphore) =
  acquire(semaphore[].gate)
  if semaphore[].active > 0:
    dec semaphore[].active
  release(semaphore[].gate)

const
  resourceSemaphoreTimeoutMs* = 30000

## Acquire Resource Semaphore with Timeout.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc acquireResourceSemaphoreTimeout*(
  semaphore: ptr ResourceSemaphore;
  timeoutMs: int = resourceSemaphoreTimeoutMs
) {.raises: [ResourceTimeoutError, ResourceLimitError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Acquire a semaphore slot with a hard deadline. Raises on timeout or limit=0.
  let deadline = getTime().toUnixFloat().int64 * 1000 + int64(timeoutMs)
  while true:
    acquire(semaphore[].gate)
    if semaphore[].limit <= 0:
      release(semaphore[].gate)
      raise newException(ResourceLimitError,
        "ResourceSemaphore limit=0 — guaranteed deadlock prevented")
    if semaphore[].active < semaphore[].limit:
      inc semaphore[].active
      release(semaphore[].gate)
      return
    release(semaphore[].gate)
    sleep(1)
    if getTime().toUnixFloat().int64 * 1000 >= deadline:
      raise newException(ResourceTimeoutError,
        "ResourceSemaphore acquire timed out after " & $timeoutMs & "ms")

## Acquire Ticket.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc acquireTicket*(
  semaphore: ptr ResourceSemaphore;
  timeoutMs: int = resourceSemaphoreTimeoutMs
): ResourceTicket {.raises: [ResourceTimeoutError, ResourceLimitError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  acquireResourceSemaphoreTimeout(semaphore, timeoutMs)
  ResourceTicket(semaphore: semaphore, acquired: true)

## Release Ticket.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func releaseTicket*(ticket: var ResourceTicket) {.raises: [].} =
  if not ticket.acquired: return
  acquire(ticket.semaphore[].gate)
  if ticket.semaphore[].active > 0:
    dec ticket.semaphore[].active
  release(ticket.semaphore[].gate)
  ticket.acquired = false

## Epoch Milliseconds.
# @axiom-hint: lean="depth >= 0" smt="(assert (>= depth 0))"

## POSIX land-lock FFI — central {.importc.} site (nimtry solid-forbidden-pragmas
## allowlist: I/O boundary consumers import these instead of declaring local FFI).
when defined(linux) or defined(macosx) or defined(freebsd) or defined(netbsd) or defined(openbsd):
  proc c_flock*(fd: cint, operation: cint): cint {.
    importc: "flock", header: "<sys/file.h>", sideEffect.}
proc posixOpen*(path: cstring, oflag: cint, mode: cint): cint {.
  importc: "open", header: "<fcntl.h>", sideEffect.}
proc posixClose*(fd: cint): cint {.
  importc: "close", header: "<unistd.h>", sideEffect.}

{.pop.}
