## Lane module resolution (§6c identity subject binding) — unit level.
##
## Audit F4 (2026-11-01, read-only security audit): resolveLaneModule's
## candidate walk preferred repoRoot over projectAbs, so a lock module
## relative path that exists as a DISTINCT file in BOTH trees bound the
## identity to the WRONG file (repo's instead of the subject's). The strict
## rule under test: an ambiguous subject binding fails closed ("") — the
## identity bundle then gaps (all-or-nothing), never silently binds a
## foreign file.
##
## Runs standalone like the other lane tests (not in the gateway feature
## glob): nim c -r --hints:off tests/unit/test_lane_module_resolution.nim

import std/[os, unittest]

import cli/rust_lane_cli

proc prepare(base, rel: string; repoContent, projContent: string) =
  let repo = base / "repo"
  let proj = base / "proj"
  createDir(repo / rel.splitFile().dir)
  createDir(proj / rel.splitFile().dir)
  if repoContent.len > 0:
    writeFile(repo / rel, repoContent)
  if projContent.len > 0:
    writeFile(proj / rel, projContent)

suite "resolveLaneModule — subject binding strictness (audit F4)":

  test "ambiguous — module present as DISTINCT files in both trees fails closed":
    ## The lock names a module relative path; both the repo tree and the
    ## subject tree contain a DIFFERENT file at that path. Choosing either
    ## would bind the identity to an unproven file — the only safe answer
    ## is no answer ("").
    let base = getTempDir() / "lane_module_resolution_ambiguous"
    removeDir(base)
    createDir(base)
    prepare(base, "src/lib.rs", "repo copy\n", "subject copy\n")
    check resolveLaneModule("src/lib.rs", base / "proj", base / "repo") == ""

  test "subject-owned module resolves to the subject file (repo copy absent)":
    let base = getTempDir() / "lane_module_resolution_subject"
    removeDir(base)
    createDir(base)
    prepare(base, "src/error.rs", "", "subject error module\n")
    check resolveLaneModule("src/error.rs", base / "proj", base / "repo") ==
      base / "proj" / "src" / "error.rs"

  test "repo-owned module (probe fixture shape) resolves when the subject lacks it":
    let base = getTempDir() / "lane_module_resolution_repo"
    removeDir(base)
    createDir(base)
    prepare(base, "tests/fixtures/probe/lib.rs", "repo fixture\n", "")
    check resolveLaneModule("tests/fixtures/probe/lib.rs",
                            base / "proj", base / "repo") ==
      base / "repo" / "tests" / "fixtures" / "probe" / "lib.rs"

  test "identical file (projectAbs is repoRoot) is not ambiguous":
    let base = getTempDir() / "lane_module_resolution_same"
    removeDir(base)
    createDir(base / "src")
    writeFile(base / "src" / "lib.rs", "one tree, one file\n")
    check resolveLaneModule("src/lib.rs", base, base) == base / "src" / "lib.rs"

  test "lock module nowhere — the subject src/lib.rs fallback stands":
    let base = getTempDir() / "lane_module_resolution_fallback"
    removeDir(base)
    createDir(base / "proj" / "src")
    writeFile(base / "proj" / "src" / "lib.rs", "subject fallback\n")
    check resolveLaneModule("src/other.rs", base / "proj", base / "repo") ==
      base / "proj" / "src" / "lib.rs"
