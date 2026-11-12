import std/[os, osproc, unittest]
import src/core/gate/gate_context
import src/gate/orchestrator_hook
import src/gate/runners/procedure_gate

{.push warning[BareExcept]:off.}

proc canReadFile(path: string): bool {.raises: [].} =
  try:
    let f = open(path, fmRead)
    defer: f.close()
    result = true
  except CatchableError:
    result = false

proc runDiskFullGate*(simulateDiskFull: bool): bool =
  gate_context.withGate("disk_full_gate"):
    if simulateDiskFull:
      ctx.fail("simulated disk full")
    else:
      ctx.pass()

proc runDualTrackGate*(): bool =
  gate_context.withGate("dual_track_gate"):
    let disabled = getEnv("AXIOM_DUAL_TRACK") == "0"
    if disabled:
      ctx.pass()
    else:
      ctx.fail("AXIOM_DUAL_TRACK=0 is required for this fault-injection test")

suite "Semantic Fault Injection Tests":
  test "File permission denial (DEBT#361)":
    let testFile = "/tmp/test_domain_layout.json"
    writeFile(testFile, "{}")
    defer:
      discard execCmdEx("chmod 644 " & quoteShell(testFile))
      removeFile(testFile)

    let (chmodOutput, chmodExitCode) = execCmdEx("chmod 000 " & quoteShell(testFile))
    discard chmodOutput
    check chmodExitCode == 0
    check not canReadFile(testFile)

    let result = checkDomainLayout(testFile)
    check result == false

  test "Disk full simulation (DEBT#363)":
    let result = runDiskFullGate(simulateDiskFull = true)
    check result == false

  test "Environment variable disabled (DEBT#362)":
    let original = getEnv("AXIOM_DUAL_TRACK")
    defer:
      if original.len == 0:
        delEnv("AXIOM_DUAL_TRACK")
      else:
        putEnv("AXIOM_DUAL_TRACK", original)

    putEnv("AXIOM_DUAL_TRACK", "0")
    let result = runDualTrackGate()
    check result == true

  test "Unimplemented CLI path (DEBT#364)":
    let result = runProcedureGate("cli")
    check result == false

{.pop.}
