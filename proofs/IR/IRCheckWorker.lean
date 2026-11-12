/-
  IRCheckWorker — standalone Lean IR check worker binary
  (certification-continuity Phase 3.5 / Phase 3.75).

  Modes:
    ircheck --check-file <path>
      Reads a serialized Axiom IRExpr (8-byte aligned wire format, see
      IR/AxiomIRExpr.lean BinaryCodec) from a file, deserializes it, runs the
      MetaM-based structural type check (MetaCheckIR), and exits 0/1.

    ircheck extract --ast <astwire.bin> --out <ir.bin>       (Phase 3.75)
      Decodes the certified-subset AST wire (src/verification/ast_wire.nim)
      with the independent reference extractor
      (IR/ReferenceExtractor.lean — see its header for the INV-4
      independence claim), extracts the function's IRExpr per the certified
      subset rules, encodes it to the 8-byte-aligned IR binary format, and
      writes it to --out. Exit 0/1/2 (fail-closed on any unsupported node).

  Unlike IR/LeanWorker.lean (shared-memory variant, needs pre-compiled
  shm/fork shims), this worker has NO C dependencies — it builds with plain
  `lake build ircheck` and is the binary Nim invokes for the Tier-1
  semantic-closure check and the Tier-2 extraction agreement.

  Entry must be top-level `main` (Lake lean_exe contract).

  Exit codes (--check-file):
    0 = decode + meta-check passed
    1 = decode or meta-check failed
    2 = file unreadable
  Exit codes (extract):
    0 = AST decoded + extracted + encoded, output written
    1 = decode/extract/encode failure (fail-closed)
    2 = IO failure (unreadable input / unwritable output)
-/

import IR.AxiomIRExpr
import IR.MetaCheckIR
import IR.ReferenceExtractor
import Lean

open AxiomMetaCheck

/-- Entry point: `ircheck --check-file <path>` or
    `ircheck extract --ast <path> --out <path>` (argv[0] may be present
    or absent depending on the launcher). -/
def main (args : List String) : IO UInt32 := do
  match args with
  | ["--check-file", path] => checkIRFile path
  | [_prog, "--check-file", path] => checkIRFile path
  | ["extract", "--ast", astPath, "--out", outPath] => AxiomRef.extractIRFile astPath outPath
  | [_prog, "extract", "--ast", astPath, "--out", outPath] => AxiomRef.extractIRFile astPath outPath
  | _ =>
    IO.eprint "Usage: ircheck --check-file <serialized-ir.bin> | ircheck extract --ast <astwire.bin> --out <ir.bin>\n"
    return (1 : UInt32)