import std/[os, json, sets, strutils, algorithm]

proc collectRegistryNames(): HashSet[string] =
  let jsonPath = getCurrentDir() / "src/generated/type_registry_metadata.json"
  let content = readFile(jsonPath)
  let jsonNode = parseJson(content)
  for entry in jsonNode["entries"]:
    result.incl(entry["name"].getStr)

proc extractFunctionName(line: string): string =
  var declKeyword = ""
  if line.startsWith("proc "): declKeyword = "proc "
  elif line.startsWith("func "): declKeyword = "func "
  elif line.startsWith("method "): declKeyword = "method "
  elif line.startsWith("template "): declKeyword = "template "
  elif line.startsWith("macro "): declKeyword = "macro "
  if declKeyword.len == 0: return ""
  let afterKw = line[declKeyword.len..^1].strip()
  let nameEnd = min(
    (if '(' in afterKw: afterKw.find('(') else: afterKw.len),
    (if '*' in afterKw: afterKw.find('*') else: afterKw.len)
  )
  let funcName = afterKw[0..<nameEnd].strip()
  if funcName.len == 0 or funcName.contains(' '): return ""
  result = funcName

proc collectSourceDeclNames(): HashSet[string] =
  let srcDir = getCurrentDir() / "src"
  for filePath in walkDirRec(srcDir):
    if not filePath.endsWith(".nim"): continue
    if "/generated/" in filePath: continue
    if "/nimcache" in filePath: continue
    try:
      let content = readFile(filePath)
      let lines = content.splitLines()
      for line in lines:
        let stripped = line.strip()
        if stripped.startsWith("#") or stripped.startsWith("##"):
          continue
        let funcName = extractFunctionName(stripped)
        if funcName.len > 0:
          result.incl(funcName)
    except CatchableError:
      # axiom:best-effort(file read errors in source scan are non-fatal; registry mismatch assertion catches real issues)
      discard

when isMainModule:
  let registryNames = collectRegistryNames()
  let sourceNames = collectSourceDeclNames()
  doAssert registryNames.len > 0, "Registry must be non-empty"
  doAssert "deriveAssurance" in registryNames, "deriveAssurance must be in registry"
  ## Both directions are asserted, not just the subset. `registry <= source`
  ## alone passes when `src/` declares a symbol the registry never emitted, so a
  ## generator that under-emits and a hand-edited registry that drops an entry
  ## were both indistinguishable from a clean tree. Set equality makes the
  ## registry a claim about the tree rather than a lower bound on it.
  var registryOnly, sourceOnly: seq[string]
  for name in registryNames:
    if name notin sourceNames: registryOnly.add name
  for name in sourceNames:
    if name notin registryNames: sourceOnly.add name
  registryOnly.sort()
  sourceOnly.sort()
  doAssert registryOnly.len == 0,
    "Stale registry entries detected (" & $registryOnly.len &
    "): in src/generated/type_registry_metadata.json but not declared in src/: " &
    registryOnly.join(", ")
  doAssert sourceOnly.len == 0,
    "Unregistered declarations detected (" & $sourceOnly.len &
    "): declared in src/ but absent from src/generated/type_registry_metadata.json: " &
    sourceOnly.join(", ")