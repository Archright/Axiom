{.push raises: [CatchableError].}

## Namespace E2E Test — Wave 7F-3
##
## Tests namespace sandbox detection and configuration.
## Does NOT test actual namespace isolation (requires kernel support).

import std/[unittest, strutils]
import core/gate/namespace_sandbox

{.push warning[BareExcept]:off.}
suite "Namespace Sandbox":

  test "Default config has correct structure":
    let cfg = defaultNamespaceConfig("/repo")
    check cfg.useNamespace == true
    check cfg.mountNs == true
    check cfg.netNs == true
    check cfg.userNs == true
    check cfg.pidNs == false
    check "/repo" in cfg.readonlyPaths
    check "/tmp" in cfg.tmpfsPaths

  test "Build unshare args contains expected flags":
    let cfg = defaultNamespaceConfig("/repo")
    let args = buildUnshareArgs(cfg)
    check "--user" in args
    check "--mount" in args
    check "--net" in args
    check "--fork" in args  # because mountNs is true
    check "--map-root-user" in args

  test "Mount script generates tmpfs and bind mounts":
    let cfg = defaultNamespaceConfig("/repo")
    let script = buildMountScript(cfg)
    check "tmpfs" in script
    check "/tmp" in script
    check "/repo" in script

  test "Namespace detection does not crash":
    ## Just verify it returns without error
    let available = isNamespaceAvailable()
    # Returns without crashing; actual availability depends on kernel support

  test "Disabled namespace config":
    var cfg = defaultNamespaceConfig("/repo")
    cfg.useNamespace = false
    cfg.mountNs = false
    cfg.netNs = false
    cfg.userNs = false
    let args = buildUnshareArgs(cfg)
    check args.len == 0  # no namespace flags when disabled

  test "PID namespace adds --pid flag":
    var cfg = defaultNamespaceConfig("/repo")
    cfg.pidNs = true
    let args = buildUnshareArgs(cfg)
    check "--pid" in args
    check "--fork" in args  # fork required when pidNs is true

{.pop.}
