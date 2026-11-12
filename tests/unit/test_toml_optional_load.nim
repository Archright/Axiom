## §1b prove-config optional toml load + strict root seam — unit tests.
##
## SSOT: docs/spec/productization_contract.md §1b (:40 root resolution —
## AXIOM_ROOT env first, else the anchor walk up from the binary location,
## first .axiom_root/axiom.toml terminates; a tree-external anchor miss is
## the optional-empty-config outcome for the toml call-site — the §1b
## fail-closed rule governs catalog reads, Q-013) +
## src/cli/config_loader.nim (loadTomlConfigIfPresent contract) +
## src/cli/external_subject_registry.nim (findRepoRootStrict, exported for
## the 2026-11-08 prove-config rotation).
##
## Measured here:
##   1. loadTomlConfigIfPresent: empty path → default (empty) config; a
##      non-existent path → default config (the §1b bundle ships NO
##      axiom.toml — every prove-consumed field has a safe default); an
##      EXISTING file is read and parsed (discriminated by the section
##      registry — value storage has a pre-existing parser defect recorded
##      out-of-scope); a present-but-unreadable file still RAISES IOError —
##      only absence is tolerated, never a real I/O error (§0.9).
##   2. findRepoRootStrict export: AXIOM_ROOT unset → the anchor walk from
##      the repo root, a repo subdir, and the test binary's own dir all
##      resolve to the repo root (§1b:40 source-tree preservation);
##      AXIOM_ROOT set → wins with trailing-slash normalization; a
##      tree-external startDir with no anchor → err (fail-closed).

import std/[os, strutils, tables, unittest]
from std/posix import geteuid
import ../../src/core/results
import ../../src/core/utils/repo_root
import ../../src/cli/config_loader
import ../../src/cli/external_subject_registry

suite "loadTomlConfigIfPresent — §1b optional toml load":

  test "empty path yields the default (empty) config":
    let cfg = loadTomlConfigIfPresent("")
    let prove = cfg.getSection("prove")
    check prove.getString("vault_dir", "") == ""
    check prove.getInt("budget_gas", 0) == 0
    check cfg.getSection("leanstral").getString("model", "") == ""

  test "non-existent path yields the default (empty) config (§1b bundle ships no axiom.toml)":
    let cfg = loadTomlConfigIfPresent(getTempDir() / "ax_no_such_axiom" / "axiom.toml")
    check cfg.getSection("prove").getString("vault_dir", "") == ""
    check cfg.getSection("prove").getInt("budget_gas", 0) == 0
    check cfg.getSection("leanstral").getString("api_url", "") == ""

  test "existing file is read and parsed (section registry)":
    # NOTE (pre-existing, OUT OF SCOPE for the §1b seam rotation — recorded
    # in docs/evidence/prove_toml_root_bundle_seam_2026-11-08.md):
    # parseTomlConfig stores section HEADERS but drops key/value pairs
    # (config_loader.nim:53-54 — `var section = result.mgetOrPut(...)`
    # copies the table on Nim 2.2.10, the mutation never lands). The
    # discriminating observable for THIS proc is the section registry:
    # the default path registers NO section, a parsed file DOES.
    # Value round-trip assertions belong to the follow-up fix of the
    # parser, not to this seam.
    let tmpDir = getTempDir() / "ax_toml_optional_test"
    createDir(tmpDir)
    let tomlPath = tmpDir / "axiom.toml"
    writeFile(tomlPath, """
[prove]
vault_dir = "/tmp/ax_toml_optional_vault"
budget_gas = 42

[leanstral]
model = "test-model"
""")
    let cfg = loadTomlConfigIfPresent(tomlPath)
    check cfg.hasKey("prove")
    check cfg.hasKey("leanstral")

  test "a present-but-unreadable file raises IOError (fail-closed, not theater)":
    # Only ABSENCE is tolerated; a file that exists but fails the real
    # read propagates IOError (the existence gate delegates to
    # loadTomlConfig which raises). Skipped under root (root bypasses
    # permission bits).
    let tmpDir = getTempDir() / "ax_toml_optional_unreadable"
    createDir(tmpDir)
    let f = tmpDir / "axiom.toml"
    writeFile(f, "[prove]\n")
    setFilePermissions(f, {fpUserWrite})
    defer:
      setFilePermissions(f, {fpUserRead, fpUserWrite})
    if geteuid() == 0:
      skip()
    expect IOError:
      discard loadTomlConfigIfPresent(f)

suite "findRepoRootStrict export — §1b:40 root resolution":

  test "anchor walk: repo root, repo subdir, and the test binary dir resolve to the repo root":
    let orig = getEnv("AXIOM_ROOT", "")
    if orig.len > 0: delEnv("AXIOM_ROOT")
    defer:
      if orig.len > 0: putEnv("AXIOM_ROOT", orig)
    let root = repoRootConst()
    for start in [root, root / "src" / "cli", getAppDir()]:
      let res = findRepoRootStrict(start)
      check res.isOk()
      if res.isOk():
        check res.get() == root

  test "AXIOM_ROOT env wins, trailing slashes normalized":
    let orig = getEnv("AXIOM_ROOT", "")
    defer:
      if orig.len > 0: putEnv("AXIOM_ROOT", orig)
      else: delEnv("AXIOM_ROOT")
    putEnv("AXIOM_ROOT", "/opt/axiom-root///")
    let res = findRepoRootStrict("/definitely/not/a/tree")
    check res.isOk()
    if res.isOk():
      check res.get() == "/opt/axiom-root"

  test "tree-external anchor miss is err (fail-closed)":
    let orig = getEnv("AXIOM_ROOT", "")
    if orig.len > 0: delEnv("AXIOM_ROOT")
    defer:
      if orig.len > 0: putEnv("AXIOM_ROOT", orig)
    let res = findRepoRootStrict("/definitely/not/a/tree")
    check res.isErr()
    if res.isErr():
      check res.error.contains("fail-closed")
