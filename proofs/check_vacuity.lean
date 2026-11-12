import Lean
open Lean

unsafe def scanEnv (env : Environment) : IO Nat := do
  let mut violations := 0
  for (name, _) in env.constants do
    let some cinfo := env.find? name | continue
    if cinfo.isAxiom then continue
    let some val := cinfo.value? | continue
    if val.hasSorry then
      IO.println s!"VACUITY [hasSorry] {name}"
      violations := violations + 1
  pure violations

-- Fail-closed vacuity scanner.
-- Returns a NONZERO count when the file fails to elaborate so that `main`
-- exits 1. Elaboration failure is NEVER swallowed (anti-theater, §0.9):
-- runFrontend returning `none` or throwing an exception is treated as a FAIL.
unsafe def scanFile (filePath : String) : IO Nat := do
  let input ← IO.FS.readFile filePath
  let opts : Options := {}
  let envOpt : Option Environment ← try
    Elab.runFrontend input opts filePath (`VacuityCheck) 0
  catch e =>
    IO.eprintln s!"VACUITY [elaboration-failed] {filePath}: {toString e}"
    pure none
  match envOpt with
  | some env => scanEnv env
  | none =>
      IO.eprintln s!"VACUITY [elaboration-failed] {filePath}"
      return 1

unsafe def main (args : List String) : IO Unit := do
  -- Lean 4.32+ requires initializers enabled before Elab.runFrontend
  -- invokes importModules (loadExts := true) under `lean --run`.
  enableInitializersExecution
  let files := args.filter (·.endsWith ".lean")
  if files.isEmpty then
    IO.eprintln "ERROR: no .lean files provided."
    IO.Process.exit 1
  let mut totalViolations := 0
  for file in files do
    let violations ← scanFile file
    if violations > 0 then
      IO.println s!"FAIL ({violations}): {file}"
    else
      IO.println s!"PASS: {file}"
    totalViolations := totalViolations + violations
  if totalViolations > 0 then
    IO.Process.exit 1
  else
    IO.Process.exit 0
