{.push raises: [CatchableError].}
## BDD feature test for process_sandbox.feature
## Verifies sandbox configuration, namespace flag computation,
## and capability detection.

import std/unittest
import gate/utils/process_sandbox

suite "SandboxConfig — construction":

  test "SandboxConfig default fields are accessible":
    let config = SandboxConfig(
      projectRoot: "/workspace",
      clockOffset: 0,
      readOnly: true,
      noNetwork: true,
      tmpfsSize: "100M"
    )
    check config.projectRoot == "/workspace"
    check config.clockOffset == 0
    check config.readOnly == true
    check config.noNetwork == true
    check config.tmpfsSize == "100M"

  test "SandboxConfig can be constructed with minimal fields":
    let config = SandboxConfig(projectRoot: "/tmp/project")
    check config.projectRoot == "/tmp/project"
    check config.readOnly == false  # default Nim bool is false
    check config.noNetwork == false

suite "SandboxResult — construction":

  test "SandboxResult reflects sandboxed state":
    let result = SandboxResult(exitCode: 0, output: "ok", sandboxed: true)
    check result.exitCode == 0
    check result.output == "ok"
    check result.sandboxed == true

  test "SandboxResult can represent failure":
    let result = SandboxResult(exitCode: 1, output: "error", sandboxed: false)
    check result.exitCode == 1
    check result.sandboxed == false

suite "sandboxFlags — namespace computation":

  test "sandboxFlags returns non-zero value":
    let flags = sandboxFlags()
    check flags != 0'i32

  test "sandboxFlags includes CLONE_NEWNS (mount namespace)":
    let flags = sandboxFlags()
    check (flags and CLONE_NEWNS) != 0'i32

  test "sandboxFlags includes CLONE_NEWNET (network namespace)":
    let flags = sandboxFlags()
    check (flags and CLONE_NEWNET) != 0'i32

  test "sandboxFlags includes CLONE_NEWPID (PID namespace)":
    let flags = sandboxFlags()
    check (flags and CLONE_NEWPID) != 0'i32

  test "sandboxFlags includes CLONE_NEWIPC (IPC namespace)":
    let flags = sandboxFlags()
    check (flags and CLONE_NEWIPC) != 0'i32

suite "Namespace constants — value verification":

  test "CLONE_NEWNS has expected value":
    check CLONE_NEWNS == 0x00020000'i32

  test "CLONE_NEWIPC has expected value":
    check CLONE_NEWIPC == 0x08000000'i32

  test "CLONE_NEWPID has expected value":
    check CLONE_NEWPID == 0x20000000'i32

  test "CLONE_NEWNET has expected value":
    check CLONE_NEWNET == 0x40000000'i32

  test "namespace constants are all distinct":
    check CLONE_NEWNS != CLONE_NEWIPC
    check CLONE_NEWIPC != CLONE_NEWPID
    check CLONE_NEWPID != CLONE_NEWNET
    check CLONE_NEWNS != CLONE_NEWNET

suite "canSandbox — capability detection":

  test "canSandbox returns a boolean (no crash)":
    # This calls unshare(CLONE_NEWNS) internally — must not crash.
    # Return value depends on kernel/capabilities.
    let capable = canSandbox()
    # Returns without crashing; actual capability depends on kernel/capabilities

{.pop.}
