## Inline forwarding stubs in src/core/
##
## For each forwarding stub:
## 1. Find all consumers that import it
## 2. Update imports to point to the real target module
## 3. Verify compilation with nim check
## 4. Delete the stub file

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, osproc, strutils, sequtils, sets, algorithm, tables]

const
  # Forwarding stubs: stub_name -> target_module (the real module path)
  Stubs = {
    "core/asset_collector": "core/trusted/asset_collector",
    "core/axiom_ir": "core/types/axiom_ir",
    "core/axiom_pragmas": "core/trusted/axiom_pragmas",
    "core/domain_utils": "core/types/domain_utils",
    "core/effect_shim": "core/trusted/effect_shim",
    "core/function_verification_summary": "core/types/function_verification_summary",
    "core/gate_types": "core/types/gate_types",
    "core/global_symbol_graph_types": "core/symbolic/global_symbol_graph_types",
    "core/heal_types": "core/types/heal_types",
    "core/import_graph": "core/topology/import_graph",
    "core/lean_lsp_types": "core/types/lean_lsp_types",
    "core/lean_util": "core/trusted/lean_util",
    "core/ledger_types": "core/types/ledger_types",
    "core/pipeline_core_types": "core/types/pipeline_core_types",
    "core/provenance_guard": "core/trusted/provenance_guard",
    "core/provider_interface": "core/trusted/provider_interface",
    "core/reasoning_recorder": "core/trusted/reasoning_recorder",
    "core/remediation_types": "core/types/remediation_types",
    "core/results": "core/types/results",
    "core/runtime_context": "core/trusted/runtime_context",
    "core/semantic_types": "core/types/semantic_types",
    "core/stdlib_shield": "core/trusted/stdlib_shield",
    "core/symbolic_types_exec": "core/symbolic/symbolic_types_exec",
    "core/symbolic_types_expr": "core/types/symbolic_types_expr",
    "core/symbolic_types_lean": "core/types/symbolic_types_lean",
    "core/symbolic_types_parse": "core/symbolic/symbolic_types_parse",
    "core/task_schema": "core/schema/task_schema",
    "core/universe_types": "core/types/universe_types",
    "core/verification_unit": "core/types/verification_unit",
    "core/workflow_state": "core/types/workflow_state",
  }.toTable

  MaxConsumers = 20

type
  StubInfo = object
    name: string
    target: string
    consumers: seq[string]

proc findConsumers(stubName: string): seq[string] =
  var files = initHashSet[string]()

  # Search for "import <stubName>" patterns
  let patterns = [
    "import " & stubName,
    "from " & stubName & " import"
  ]

  for pattern in patterns:
    let cmd = "grep -rn '" & pattern & "' src/ --include='*.nim' -l"
    let (output, _) = execCmdEx(cmd)
    for line in output.strip.splitLines:
      if line.len > 0 and fileExists(line):
        # Skip the stub file itself
        let stubPath = "src/" & stubName.replace("/", "_") & ".nim"
        # Check it's not the stub itself by checking the path
        if not line.endsWith(stubName.replace("/", "_") & ".nim") and
           not line.endsWith(stubName.splitFile().name & ".nim"):
          files.incl(line)

  result = files.toSeq
  result.sort()

proc updateImports(filePath: string, stubName: string, target: string): bool =
  ## Returns true if file was modified
  try:
    var content = readFile(filePath)
    var modified = false

    # Replace "import <stubName>" with "import <target>"
    let oldImport = "import " & stubName
    let newImport = "import " & target
    if oldImport in content:
      content = content.replace(oldImport, newImport)
      modified = true

    # Replace "from <stubName> import" with "from <target> import"
    let oldFrom = "from " & stubName & " import"
    let newFrom = "from " & target & " import"
    if oldFrom in content:
      content = content.replace(oldFrom, newFrom)
      modified = true

    if modified:
      writeFile(filePath, content)
    result = modified
  except CatchableError:
    result = false

proc nimCheck(filePath: string): (bool, string) =
  let (output, code) = execCmdEx("nim check --hints:off --warnings:off -d:allowMissingZ3 " & filePath)
  result = (code == 0, output)

proc main() =
  let args = commandLineParams()
  let dryRun = "--dry-run" in args
  let verifyOnly = "--verify-only" in args

  echo "=== Forwarding Stub Inliner ==="
  echo "Mode: " & (if dryRun: "DRY-RUN" elif verifyOnly: "VERIFY-ONLY" else: "EXECUTE")
  echo ""

  var stubsProcessed = 0
  var stubsSkipped = 0
  var totalFilesModified = 0
  var allModifiedFiles: seq[string] = @[]
  var skippedStubs: seq[string] = @[]

  # Sort stubs by name for deterministic processing
  var stubList: seq[tuple[name: string, target: string]]
  for name, target in Stubs.pairs:
    stubList.add((name, target))
  stubList.sort(proc(a, b: auto): int = cmp(a.name, b.name))

  for (stubName, target) in stubList:
    echo "--- Processing: " & stubName & " -> " & target

    let consumers = findConsumers(stubName)
    echo "  Consumers: " & $consumers.len

    if consumers.len > MaxConsumers:
      echo "  SKIPPED: Too many consumers (>" & $MaxConsumers & ")"
      skippedStubs.add(stubName & " (" & $consumers.len & " consumers)")
      inc stubsSkipped
      continue

    if consumers.len == 0:
      echo "  No consumers found, will just delete stub"
    else:
      for consumer in consumers:
        echo "    " & consumer

    if not dryRun and not verifyOnly:
      var filesModified: seq[string] = @[]
      for consumer in consumers:
        if updateImports(consumer, stubName, target):
          filesModified.add(consumer)
          inc totalFilesModified

      echo "  Modified: " & $filesModified.len & " files"
      allModifiedFiles.add(filesModified)

      # Verify compilation
      var allOk = true
      for f in filesModified:
        let (ok, output) = nimCheck(f)
        if not ok:
          echo "  COMPILE ERROR in " & f & ":"
          for line in output.splitLines:
            if "Error:" in line:
              echo "    " & line
          allOk = false

      if allOk:
        # Delete the stub
        let stubPath = "src/" & stubName.replace("/", "/") & ".nim"
        if fileExists(stubPath):
          removeFile(stubPath)
          echo "  Deleted: " & stubPath
          inc stubsProcessed
        else:
          echo "  WARNING: Stub file not found at " & stubPath
      else:
        echo "  SKIPPED deletion due to compile errors"
        skippedStubs.add(stubName & " (compile errors)")
        inc stubsSkipped
    else:
      inc stubsProcessed

  echo ""
  echo "=== Summary ==="
  echo "Stubs processed: " & $stubsProcessed
  echo "Stubs skipped: " & $stubsSkipped
  echo "Total files modified: " & $totalFilesModified

  if skippedStubs.len > 0:
    echo ""
    echo "Skipped stubs:"
    for s in skippedStubs:
      echo "  - " & s

  if dryRun:
    echo ""
    echo "DRY-RUN: No changes made. Use --execute to apply."

when isMainModule:
  main()
