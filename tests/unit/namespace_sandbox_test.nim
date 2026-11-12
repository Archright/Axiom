## Unit tests for NamespaceSandbox — default configuration,
## unshare argument building, namespace availability detection.

import std/[unittest, strutils]
import core/gate/namespace_sandbox

suite "NamespaceSandbox":
  test "defaultNamespaceConfig has expected defaults":
    let cfg = defaultNamespaceConfig("/repo")
    check cfg.useNamespace == true
    check cfg.mountNs == true
    check cfg.pidNs == false
    check cfg.netNs == true
    check cfg.userNs == true
    check cfg.readonlyPaths == @["/repo"]
    check cfg.tmpfsPaths == @["/tmp"]
    check cfg.maxMemBytes == 512 * 1024 * 1024
    check cfg.maxCpuSeconds == 300
    check cfg.allowedPaths.len == 0

  test "defaultNamespaceConfig reflects different repoRoot":
    let cfg = defaultNamespaceConfig("/my/project")
    check cfg.readonlyPaths == @["/my/project"]

  test "buildUnshareArgs includes correct flags":
    let cfg = defaultNamespaceConfig("/repo")
    let args = buildUnshareArgs(cfg)
    # Default: userNs=true, mountNs=true, pidNs=false, netNs=true
    check "--user" in args
    check "--mount" in args
    check "--net" in args
    check "--fork" in args  # mountNs triggers fork
    check "--map-root-user" in args
    check "--pid" notin args

  test "buildUnshareArgs with pidNs adds --pid":
    var cfg = defaultNamespaceConfig("/repo")
    cfg.pidNs = true
    let args = buildUnshareArgs(cfg)
    check "--pid" in args
    check "--fork" in args

  test "buildMountScript generates mount commands":
    let cfg = defaultNamespaceConfig("/repo")
    let script = buildMountScript(cfg)
    check "mount -t tmpfs tmpfs /tmp" in script
    check "mount --bind --readonly /repo /repo" in script

  test "isNamespaceAvailable returns a bool":
    let available = isNamespaceAvailable()
    # Returns without crashing; actual availability depends on kernel support
