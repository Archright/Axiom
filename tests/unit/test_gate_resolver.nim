import std/unittest
import std/os
import core/gate/gate_resolver

suite "normalizeGateEntryName":
  test "gate-self-check -> gate_self_check":
    check normalizeGateEntryName("gate-self-check") == "gate_self_check"

  test "abc -> abc":
    check normalizeGateEntryName("abc") == "abc"

  test "empty string -> empty string":
    check normalizeGateEntryName("") == ""

  test "a-b-c -> a_b_c":
    check normalizeGateEntryName("a-b-c") == "a_b_c"

suite "gateSourceCandidates":
  test "empty entry returns empty seq":
    check gateSourceCandidates("") == newSeq[string]()

  test "entry with path prefix: first candidate is entry.nim":
    let r = gateSourceCandidates("src/gate/runners/nim_check_gate")
    check r.len > 0
    check r[0] == "src/gate/runners/nim_check_gate.nim"

  test "bin/gate_self_check (raw==normalized) full ordered list":
    check gateSourceCandidates("bin/gate_self_check") == @[
      "bin/gate_self_check.nim",
      "src/gate/runners/gate_self_check.nim",
      "scripts/gate_self_check.nim",
      "src/cli/gate_self_check.nim",
    ]

  test "bin/some-hyphen-gate (raw!=normalized) normalized precedes raw":
    check gateSourceCandidates("bin/some-hyphen-gate") == @[
      "bin/some-hyphen-gate.nim",
      "src/gate/runners/some_hyphen_gate.nim",
      "src/gate/runners/some-hyphen-gate.nim",
      "scripts/some_hyphen_gate.nim",
      "scripts/some-hyphen-gate.nim",
      "src/cli/some_hyphen_gate.nim",
      "src/cli/some-hyphen-gate.nim",
    ]

  test ".nim-suffixed entry keeps single suffix (no foo.nim.nim)":
    check gateSourceCandidates("src/gate/runners/readiness_start_gate.nim") == @[
      "src/gate/runners/readiness_start_gate.nim",
      "src/gate/runners/readiness_start_gate.nim",
      "scripts/readiness_start_gate.nim",
      "src/cli/readiness_start_gate.nim",
    ]

  test ".nim-suffixed hyphen entry normalizes after suffix strip":
    check gateSourceCandidates("bin/some-hyphen-gate.nim") == @[
      "bin/some-hyphen-gate.nim",
      "src/gate/runners/some_hyphen_gate.nim",
      "src/gate/runners/some-hyphen-gate.nim",
      "scripts/some_hyphen_gate.nim",
      "scripts/some-hyphen-gate.nim",
      "src/cli/some_hyphen_gate.nim",
      "src/cli/some-hyphen-gate.nim",
    ]

suite "resolveGateSourcePath with repoRoot":
  test "bin/gate_self_check -> src/gate/runners/gate_self_check.nim":
    let root = getCurrentDir()
    check resolveGateSourcePath("bin/gate_self_check", root) ==
      "src/gate/runners/gate_self_check.nim"

  test "src/gate/runners/nim_check_gate resolves directly (first candidate hits)":
    let root = getCurrentDir()
    check resolveGateSourcePath("src/gate/runners/nim_check_gate", root) ==
      "src/gate/runners/nim_check_gate.nim"

  test "non-existent gate returns empty string":
    let root = getCurrentDir()
    check resolveGateSourcePath("bin/definitely_not_a_gate_xyz", root) == ""

  test ".nim-suffixed entry resolves (regression: foo.nim.nim)":
    let root = getCurrentDir()
    check resolveGateSourcePath("src/gate/runners/readiness_start_gate.nim", root) ==
      "src/gate/runners/readiness_start_gate.nim"

suite "resolveGateSourcePath (single-arg, CWD=repo root)":
  test "gate_self_check resolves via CWD-relative fileExists":
    check resolveGateSourcePath("bin/gate_self_check") ==
      "src/gate/runners/gate_self_check.nim"

suite "filesystem-independent temp-dir resolution":
  test "first existing candidate wins; after deletion, next wins":
    let tmpDir = getTempDir() / "axiom_gr_test_" & $getCurrentProcessId()
    createDir(tmpDir / "bin")
    createDir(tmpDir / "src" / "gate" / "runners")
    defer: removeDir(tmpDir)

    writeFile(tmpDir / "bin" / "self_check_gate.nim", "")
    writeFile(tmpDir / "src" / "gate" / "runners" / "self_check_gate.nim", "")

    check resolveGateSourcePath("bin/self_check_gate", tmpDir) ==
      "bin/self_check_gate.nim"

    removeFile(tmpDir / "bin" / "self_check_gate.nim")

    check resolveGateSourcePath("bin/self_check_gate", tmpDir) ==
      "src/gate/runners/self_check_gate.nim"
