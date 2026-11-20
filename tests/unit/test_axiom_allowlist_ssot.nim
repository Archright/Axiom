# test_axiom_allowlist_ssot.nim — deterministic sync guard for the INV-6
# primitive axiom set (docs/spec/certification_continuity_contract.md INV-6,
# docs/spec/lean_sorry_gate.md §4).
#
# `funext` is a theorem alias whose `#print axioms` dependency is `Quot.sound`;
# it is not a primitive axiom. Every code mirror and the bundle doc projection
# must carry exactly {propext, Classical.choice, Quot.sound}.
#
# Execution: nim c --hints:off -r tests/unit/test_axiom_allowlist_ssot.nim

import std/[algorithm, os, sequtils, strutils, unittest]

import core/judge/lean_replay
import core/utils/repo_root
import verification/certificate_verifier
import verification/evidence_bundle/bundle_schema
import verification/kernel_reexecution
import verification/lean_lsp_protocol

const
  PrimitiveAxioms = ["propext", "Classical.choice", "Quot.sound"]
  TheTheoremAlias = "funext"

func canonical(names: openArray[string]): seq[string] =
  names.toSeq.sorted

proc checkMirror(label: string; names: openArray[string]) =
  check label.len > 0
  check names.len == PrimitiveAxioms.len
  check canonical(names) == canonical(PrimitiveAxioms)
  check TheTheoremAlias notin names

suite "INV-6 axiom allowlist SSOT sync":
  test "Nim mirrors carry exactly the three primitive axioms":
    checkMirror("lean_replay.leanBuiltinAxiomAllowlist",
      leanBuiltinAxiomAllowlist)
    checkMirror("certificate_verifier.leanCertBuiltinAxiomAllowlist",
      leanCertBuiltinAxiomAllowlist)
    checkMirror("lean_lsp_protocol.LeanAxiomAllowlist", LeanAxiomAllowlist)
    checkMirror("bundle_schema.AxiomAllowlist", AxiomAllowlist)
    checkMirror("kernel_reexecution.axiomAllowlist", axiomAllowlist())

  test "ax_vacuity_check.lean inserts only primitive axioms":
    let src = readFile(repoRootConst() / "src" / "verification" /
      "ax_vacuity_check.lean")
    check src.contains("``Classical.choice")
    check src.contains("``Quot.sound")
    check src.contains("``propext")
    check not src.contains("``funext")

  test "check_lean_vacuity.nim known-good axiom set excludes funext":
    let src = readFile(repoRootConst() / "tools" / "ci" /
      "check_lean_vacuity.nim")
    check src.contains("\"Classical.choice\"")
    check src.contains("\"Quot.sound\"")
    check src.contains("\"propext\"")
    check not src.contains("\"funext\"")

  test "evidence_bundle_v2.md projects the primitive set, not the alias":
    let doc = readFile(repoRootConst() / "docs" / "spec" /
      "evidence_bundle_v2.md")
    check doc.contains("{propext, Classical.choice, Quot.sound}")
    check not doc.contains("{propext, Classical.choice, Quot.sound, funext}")