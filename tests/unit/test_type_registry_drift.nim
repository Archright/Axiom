import std/[os, json, sets, strutils]

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
  doAssert registryNames <= sourceNames, "Stale registry entries detected: registry has symbols not present in src/"