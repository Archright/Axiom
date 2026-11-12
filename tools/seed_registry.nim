import core/trusted/layer_declaration
axiomLayer "tools"
import std/[json, os, osproc, strutils, re, tables, sequtils, hashes, sets]

const
  RegistryPath = "tests/specs/algebraic_registry.json"
  BootstrapPath = "tests/specs/bootstrap_manifest.json"
  DumpDir = "tests/generated_code_dump"
  Layer01PathsFile = "tests/specs/layer01_tier1_paths.txt"  # NOTE: relocated from tests/auto_generated/
  BannedImports = ["import os", "import posix", "import asyncdispatch", "import net", "import streams"]

type
  ModuleInfo = object
    path: string
    tier: string
    functions: seq[tuple[name: string, properties: seq[string]]]

type
  CompileResult = object
    success: bool
    stderr: string

proc readRegistry(): JsonNode =
  let content = readFile(RegistryPath)
  result = parseJson(content)

proc writeRegistry(registry: JsonNode) =
  writeFile(RegistryPath, registry.pretty)

proc readLayerPaths(layerFile: string): HashSet[string] =
  result = initHashSet[string]()
  if not fileExists(layerFile):
    return
  let content = readFile(layerFile)
  for line in content.splitLines:
    let trimmed = line.strip
    if trimmed.len > 0:
      result.incl(trimmed)

proc classifyModuleTier(modPath: string): string =
  let srcPath = "src/core/" & modPath & ".nim"
  if not fileExists(srcPath):
    return "tier1"
  try:
    let f = open(srcPath, fmRead)
    defer: close(f)
    var buf = newString(4096)
    let bytesRead = f.readBuffer(addr buf[0], 4096)
    buf.setLen(bytesRead)
    let content = buf
    for b in BannedImports:
      if b in content:
        return "tier2"
    result = "tier1"
  except CatchableError:
    result = "tier1"

proc syncBootstrapFromRegistry(layerFile: string): seq[ModuleInfo] =
  let registry = readRegistry()
  let layerPaths = readLayerPaths(layerFile)
  var modules: seq[ModuleInfo] = @[]
  let mods = registry{"modules"}
  if mods.isNil:
    return modules
  for modPath, modData in mods.pairs:
    if layerPaths.len > 0 and modPath notin layerPaths:
      continue
    let inferred = modData{"inferred"}
    if inferred.isNil:
      continue
    var funcs: seq[tuple[name: string, properties: seq[string]]] = @[]
    for funcName, props in inferred.pairs:
      if funcName.len == 0:
        continue
      var cleanProps: seq[string] = @[]
      for p in props:
        cleanProps.add(p.getStr("").replace("_candidate", ""))
      funcs.add((funcName, cleanProps))
    if funcs.len > 0:
      let tier = classifyModuleTier(modPath)
      modules.add(ModuleInfo(path: modPath, tier: tier, functions: funcs))
  let manifest = %* {"modules": modules.mapIt(%* {
    "path": it.path,
    "tier": it.tier,
    "functions": it.functions.mapIt(%* {"name": it.name, "properties": it.properties})
  })}
  createDir("tests/specs")
  writeFile(BootstrapPath, manifest.pretty)
  echo "[seed] Synced " & $modules.len & " modules to " & BootstrapPath
  result = modules

proc runGeneratePbtTests(): bool =
  echo "[seed] Running pbt_generator (Pure Nim)..."
  let (output, code) = execCmdEx("nim c -r --hints:off tools/pbt_generator.nim", options = {poStdErrToStdOut})
  echo output
  if code != 0:
    echo "[seed] ERROR: pbt_generator failed"
    return false
  result = true

proc compileAndRun(nimFile: string): CompileResult =
  echo "[seed] Compiling: " & nimFile
  let (output, code) = execCmdEx("nim c -r " & nimFile, options = {poStdErrToStdOut})
  result.success = code == 0
  result.stderr = output
  if result.success:
    echo "[seed]   PASS: " & nimFile
  else:
    echo "[seed]   FAIL: " & nimFile & " (exit=" & $code & ")"
    let lines = output.strip.splitLines
    for line in lines[max(0, lines.len - 5) ..< lines.len]:
      echo "[seed]     " & line

proc parseSkippedProperties(nimFile: string): Table[string, HashSet[string]] =
  result = initTable[string, HashSet[string]]()
  if not fileExists(nimFile):
    return
  let content = readFile(nimFile)
  var currentFunc = ""
  let testPattern = re"""test\s+"(\w+)\s+algebraic properties"""
  let skipPattern = re"""\[PBT-SKIPPED\]\s+(\w+)"""
  for line in content.splitLines:
    var m: array[1, string]
    if line.find(testPattern, m) >= 0:
      currentFunc = m[0]
      continue
    if line.find(skipPattern, m) >= 0:
      let prop = m[0]
      if currentFunc.len > 0:
        if not result.hasKey(currentFunc):
          result[currentFunc] = initHashSet[string]()
        result[currentFunc].incl(prop)

proc classifyFailure(stderr: string): string =
  let stderrLower = stderr.toLowerAscii
  if "undeclared identifier" in stderrLower:
    return "undeclared_identifier"
  if "type mismatch" in stderrLower:
    return "type_mismatch"
  if "invalid indentation" in stderrLower:
    return "invalid_indentation"
  if "cannot open file" in stderrLower:
    return "missing_import"
  if "template/generic instantiation" in stderrLower:
    return "template_instantiation_error"
  result = "unknown"

proc updateRegistry(modules: seq[ModuleInfo]; results: Table[string, CompileResult]) =
  var registry = readRegistry()
  var promoted = 0
  var skippedCount = 0
  var quarantinedCount = 0
  for m in modules:
    let modPath = m.path
    let modData = registry{"modules"}{modPath}
    if modData.isNil:
      continue
    let inferred = modData{"inferred"}
    if inferred.isNil:
      continue
    var verified = modData{"verified"}
    if verified.isNil:
      verified = newJObject()
      registry{"modules"}{modPath}{"verified"} = verified
    var skipped = modData{"skipped"}
    if skipped.isNil:
      skipped = newJObject()
      registry{"modules"}{modPath}{"skipped"} = skipped
    var quarantined = modData{"quarantined"}
    if quarantined.isNil:
      quarantined = newJObject()
      registry{"modules"}{modPath}{"quarantined"} = quarantined
    let moduleName = modPath.split("/")[^1]
    let nimFile = DumpDir / (moduleName & "_pbt.nim")
    let fileSkipped = parseSkippedProperties(nimFile)
    for f in m.functions:
      let funcName = f.name
      let inferredProps = inferred{funcName}
      if inferredProps.isNil:
        continue
      let funcSkipped = fileSkipped.getOrDefault(funcName)
      var testPassed = false
      var stderr = ""
      if results.hasKey(nimFile):
        testPassed = results[nimFile].success
        stderr = results[nimFile].stderr
      var propsToVerify: seq[string] = @[]
      var propsToSkip: seq[string] = @[]
      for p in inferredProps:
        let cleanP = p.getStr("").replace("_candidate", "")
        if cleanP in funcSkipped:
          propsToSkip.add(p.getStr(""))
        else:
          propsToVerify.add(p.getStr(""))
      if testPassed:
        if propsToVerify.len > 0:
          verified[funcName] = %* propsToVerify
          promoted += propsToVerify.len
        if propsToSkip.len > 0:
          var existing: seq[string] = @[]
          if skipped.hasKey(funcName):
            for e in skipped[funcName]:
              existing.add(e.getStr(""))
          for p in propsToSkip:
            if p notin existing:
              existing.add(p)
          skipped[funcName] = %* existing
          skippedCount += propsToSkip.len
        inferred.delete(funcName)
      else:
        let reason = classifyFailure(stderr)
        let stderrPreview = stderr.strip
        let preview = if stderrPreview.len > 300: stderrPreview[^300..^1] else: stderrPreview
        quarantined[funcName] = %* {
          "properties": inferredProps,
          "reason": reason,
          "stderrPreview": preview,
          "stderrHash": $(hash(stderr) and 0xFFFFFFFF)
        }
        inferred.delete(funcName)
        quarantinedCount += inferredProps.len
    # Clean up empty sections
    if inferred.len == 0:
      registry{"modules"}{modPath}.delete("inferred")
    if verified.len == 0:
      registry{"modules"}{modPath}.delete("verified")
    if skipped.len == 0:
      registry{"modules"}{modPath}.delete("skipped")
    if quarantined.len == 0:
      registry{"modules"}{modPath}.delete("quarantined")
    if registry{"modules"}{modPath}.len == 0:
      registry{"modules"}.delete(modPath)
  writeRegistry(registry)
  echo "[seed] Registry updated: " & $promoted & " promoted, " & $skippedCount & " skipped, " & $quarantinedCount & " quarantined"

proc main() =
  let args = commandLineParams()
  var layerFile = Layer01PathsFile
  for i in 0 ..< args.len:
    if args[i] == "--layer":
      if i + 1 < args.len:
        if args[i + 1] == "2+":
          layerFile = ""
        elif args[i + 1] != "0-1":
          echo "[seed] WARNING: unknown layer filter '" & args[i + 1] & "', defaulting to 0-1"
  echo "[seed] Phase C2+ — Triage-aware Compiler-Validated Seeding"
  let modules = syncBootstrapFromRegistry(layerFile)
  if not runGeneratePbtTests():
    quit(1)
  var results = initTable[string, CompileResult]()
  for m in modules:
    let moduleName = m.path.split("/")[^1]
    let nimFile = DumpDir / (moduleName & "_pbt.nim")
    if fileExists(nimFile):
      let res = compileAndRun(nimFile)
      results[nimFile] = res
    else:
      echo "[seed] SKIP: " & nimFile & " not found"
      results[nimFile] = CompileResult(success: false, stderr: "")
  updateRegistry(modules, results)
  echo "[seed] Seeding complete."

when isMainModule:
  main()
