import Lake
open Lake DSL

package proofs where
  leanOptions := #[⟨`autoImplicit, false⟩]

@[default_target]
lean_lib GateInvariants where
  srcDir := "."

@[default_target]
lean_lib Generated where
  srcDir := "."
  roots := #[`Generated]
  globs := #[Glob.submodules `Generated]

@[default_target]
lean_lib IR where
  srcDir := "."
  roots := #[`IR]
  globs := #[Glob.submodules `IR]

-- Lean 4 worker executable with POSIX shared-memory FFI (shm_shim.c).
-- shm_shim.o is pre-compiled by the build helper and linked in.
-- fork_shim.o provides fork/prctl/reap FFI for Zygote daemon mode.
-- Links -lrt for shm_open/shm_unlink on Linux.
lean_exe worker where
  srcDir := "."
  root := `IR.LeanWorker
  moreLinkArgs  := #["build/shm_shim.o", "build/fork_shim.o", "-lrt"]

-- Standalone file-mode IR check worker (Phase 3.5): no C shims required,
-- built with plain `lake build ircheck`. Nim invokes
-- `.lake/build/bin/ircheck --check-file <serialized-ir.bin>`.
lean_exe ircheck where
  srcDir := "."
  root := `IR.IRCheckWorker

-- Scanner script: run `lake run check-vacuity -- <file1.lean> [file2.lean ...]`
-- Delegates to lean --run check_vacuity.lean (via the toolchain kernel, so the
-- version matches the lake-built .olean files). Files after `--` are forwarded.
script check_vacuity (args) do
  if args.isEmpty then
    IO.eprintln "usage: lake run check-vacuity -- <file1.lean> [file2.lean ...]"
    return 1
  let proc ← IO.Process.output {
    cmd := "lake"
    args := #["env", "lean", "--run", "check_vacuity.lean"] ++ args
  }
  if proc.exitCode != 0 then
    IO.eprint proc.stderr
  IO.print proc.stdout
  return if proc.exitCode == 0 then 0 else 1
