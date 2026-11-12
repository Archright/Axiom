import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}

## Standalone CLI surface generator.
## Replaces compile-time macro (cli_surface_macro.nim) with pre-build generation.
##
## Usage: nim c -r tools/cli_surface_generator.nim
## Output: src/cli/cli_surface_generated.nim

import std/[os, strutils]
import shared_types/io_bridge

type
  EnumVariant = object
    name: string
    value: string

  FieldMeta = object
    name: string
    nimType: string
    hasDefault: bool
    defaultValue: string

proc autoKebabCase(fieldName: string): string {.raises: [].} =
  var kebab = ""
  for i, c in fieldName:
    if i > 0 and c in {'A'..'Z'}:
      kebab.add('-')
      kebab.add(c.toLowerAscii)
    else:
      kebab.add(c.toLowerAscii)
  result = "--" & kebab

proc extractEnumVariants(source: string; enumName: string): seq[EnumVariant] {.raises: [].} =
  ## Simple line-based parser for enum definitions with custom string values.
  ## Expects:   name = "value"
  ## Or:        name = (ordinal, "value")
  var inEnum = false
  var enumBaseIndent = 0
  for rawLine in source.splitLines():
    let line = rawLine.strip()
    if line.len == 0:
      continue
    if line.startsWith("##"):
      continue
    if line.startsWith("type"):
      if inEnum: break
      continue
    if inEnum:
      # End of enum: line at same or lesser indentation than enum declaration
      var currentIndent = 0
      for c in rawLine:
        if c == ' ': inc currentIndent
        elif c == '\t': inc currentIndent
        else: break
      if currentIndent <= enumBaseIndent and line.len > 0 and not line.startsWith("##"):
        break
      let eqIdx = line.find('=')
      if eqIdx >= 0:
        let name = line[0 ..< eqIdx].strip()
        let afterEq = line[eqIdx + 1 .. ^1].strip()
        var value = ""
        let firstQuote = afterEq.find('"')
        if firstQuote >= 0:
          let secondQuote = afterEq.find('"', firstQuote + 1)
          if secondQuote >= 0:
            value = afterEq[firstQuote + 1 ..< secondQuote]
        if name.len > 0 and value.len > 0:
          result.add(EnumVariant(name: name, value: value))
    elif line.startsWith(enumName) and "enum" in line:
      inEnum = true
      enumBaseIndent = 0
      for c in rawLine:
        if c == ' ': inc enumBaseIndent
        elif c == '\t': inc enumBaseIndent
        else: break

proc extractFieldsFromObject(source: string; typeName: string): seq[FieldMeta] {.raises: [].} =
  ## Simple line-based parser for object definitions in cli_types.nim
  var inObject = false
  for rawLine in source.splitLines():
    let line = rawLine.strip()
    if line.len == 0 or line.startsWith("##"):
      continue
    if line.startsWith("type"):
      continue
    if inObject:
      if line == "":
        continue
      if line.startsWith("type ") or line.startsWith("type\t"):
        break
      # Check for field definition: fieldName*: Type = default
      let colonIdx = line.find("*: ")
      if colonIdx >= 0:
        let fieldName = line[0 ..< colonIdx].strip()
        let afterColon = line[colonIdx + 3 .. ^1].strip()
        let eqIdx = afterColon.find('=')
        let nimType = if eqIdx >= 0: afterColon[0 ..< eqIdx].strip() else: afterColon
        let defaultValue = if eqIdx >= 0: afterColon[eqIdx + 1 .. ^1].strip().replace("##", "") else: ""
        result.add(FieldMeta(
          name: fieldName,
          nimType: nimType,
          hasDefault: eqIdx >= 0,
          defaultValue: defaultValue
        ))
      # Use rawLine indentation to detect end of object (non-indented line)
      if not rawLine.startsWith("    ") and not rawLine.startsWith("\t"):
        # End of object
        break
    elif line.startsWith(typeName) and "* = object" in line:
      inObject = true

proc generateParseFlagProc(enumName: string): string {.raises: [].} =
  ## Generates: proc parseEnumName*(arg: string): Result[EnumName, string]
  ## Uses enum iteration — no manual if/else chain.
  let procName = "parse" & enumName
  result = "proc " & procName & "*(arg: string): Result[" & enumName & ", string] {.raises: [].} =\n" &
           "  for flag in " & enumName & ":\n" &
           "    if arg == $flag:\n" &
           "      return Result[" & enumName & ", string](ok: true, value: flag)\n" &
           "  Result[" & enumName & ", string](ok: false, err: \"unknown option: \" & arg)\n"

proc generateParseFlagsProc(typeName: string; fields: seq[FieldMeta];
                            enumName: string): string {.raises: [].} =
  let procName = "parse" & typeName
  let flagProcName = "parse" & enumName
  var lines: seq[string] = @[]
  lines.add("proc " & procName & "*(args: seq[string]): Result[" & typeName & ", string] {.raises: [].} =")
  lines.add("  result = Result[" & typeName & ", string](ok: true, value: " & typeName & "())")
  lines.add("  var i = 0")
  lines.add("  while i < args.len:")
  lines.add("    let flagRes = " & flagProcName & "(args[i])")
  lines.add("    if not flagRes.ok:")
  lines.add("      return Result[" & typeName & ", string](ok: false, err: flagRes.err)")
  lines.add("    let flag = flagRes.value")
  lines.add("    case flag")

  for f in fields:
    let flagStr = autoKebabCase(f.name)
    # Map flag string to enum variant name by convention: strip '--' prefix,
    # convert to PascalCase, prefix with enum-specific prefix.
    # e.g., "--limit" -> "limit" -> "apLimit" (AxProveFlag prefix + field name)
    # For simplicity, derive from enumName + fieldName.
    var variantName = ""
    if enumName == "AxProveFlag":
      variantName = "ap" & f.name[0].toUpperAscii & f.name[1..^1]
    elif enumName == "AxReportFlag":
      variantName = "ar" & f.name[0].toUpperAscii & f.name[1..^1]
    else:
      variantName = f.name[0].toLowerAscii & f.name[1..^1]

    lines.add("    of " & variantName & ":")
    if f.nimType == "bool":
      if f.hasDefault and f.defaultValue == "true":
        let negFlag = flagStr.replace("--", "--no-")
        lines.add("      if i + 1 < args.len and args[i + 1] == \"" & negFlag & "\":")
        lines.add("        result.value." & f.name & " = false")
        lines.add("        i += 2")
        lines.add("      else:")
        lines.add("        result.value." & f.name & " = true")
        lines.add("        inc i")
      else:
        lines.add("      result.value." & f.name & " = true")
        lines.add("      inc i")
    elif f.nimType == "int":
      let resVar = f.name & "Res"
      lines.add("      if i + 1 >= args.len: return Result[" & typeName & ", string](ok: false, err: \"missing value: " & flagStr & "\")")
      lines.add("      let " & resVar & " = safeParseInt(args[i + 1])")
      lines.add("      if " & resVar & ".isErr: return Result[" & typeName & ", string](ok: false, err: \"invalid integer for " & flagStr & ": \" & args[i + 1])")
      lines.add("      result.value." & f.name & " = " & resVar & ".get")
      lines.add("      i += 2")
    elif f.nimType == "string":
      lines.add("      if i + 1 >= args.len: return Result[" & typeName & ", string](ok: false, err: \"missing value: " & flagStr & "\")")
      lines.add("      result.value." & f.name & " = args[i + 1]")
      lines.add("      i += 2")

  lines.add("    # No else — Nim compiler enforces exhaustiveness for enum case")

  # Check for targetDirectory positional arg
  var hasTargetDir = false
  for f in fields:
    if f.name == "targetDirectory":
      hasTargetDir = true
      break
  if hasTargetDir:
    lines.add("    # Positional arg handling")
    lines.add("    if i < args.len and not args[i].startsWith(\"-\"):")
    lines.add("      if result.value.targetDirectory.len > 0:")
    lines.add("        return Result[" & typeName & ", string](ok: false, err: \"unexpected positional argument: \" & args[i])")
    lines.add("      result.value.targetDirectory = args[i]")
    lines.add("      inc i")

  result = lines.join("\n")

proc generateValidateProc(typeName: string): string {.raises: [].} =
  let procName = "validate" & typeName
  result = "proc " & procName & "*(flags: " & typeName & "): Result[void, string] {.raises: [].} =\n" &
           "  result = Result[void, string](ok: true)\n"

proc generateHelpProc(typeName: string; fields: seq[FieldMeta]): string {.raises: [].} =
  let procName = typeName[0].toLowerAscii & typeName[1..^1] & "Help"
  var lines: seq[string] = @[]
  lines.add("proc " & procName & "*(): string {.raises: [].} =")
  lines.add("  result = \"Options for " & typeName & ":\\n\"")
  for f in fields:
    let flag = autoKebabCase(f.name)
    let desc = f.nimType & " parameter"
    lines.add("  result &= \"  " & flag.alignLeft(24) & " " & desc & "\\n\"")
    if f.nimType == "bool" and f.hasDefault and f.defaultValue == "true":
      let negFlag = flag.replace("--", "--no-")
      lines.add("  result &= \"  " & negFlag.alignLeft(24) & " Negate " & flag & "\\n\"")
  result = lines.join("\n")

proc extractFlagsFromFeatures*(featuresDir: string): seq[string] {.raises: [OSError].} =
  ## Scan all .feature files for CLI flag tokens (--flag-name).
  ## Skips @manual features. Returns sorted deduplicated flags.
  for file in walkDirRec(featuresDir):
    if not file.endsWith(".feature"): continue
    let content = try: readFileSafe(file) except CatchableError: ""
    if content.len == 0: continue
    if "@manual" in content: continue
    for line in content.splitLines():
      let stripped = line.strip()
      if stripped.startsWith("#"): continue
      var i = 0
      while i < line.len:
        if i + 2 < line.len and line[i] == '-' and line[i+1] == '-':
          let start = i
          i += 2
          while i < line.len and line[i] in {'a'..'z', '0'..'9', '-'}:
            inc i
          let flag = line[start ..< i]
          if flag.len > 2 and flag notin result:
            result.add(flag)
        else:
          inc i

proc extractFlagsFromObject(source: string; typeName: string): seq[string] {.raises: [].} =
  ## Extract CLI flag strings from object field definitions via autoKebabCase.
  let fields = extractFieldsFromObject(source, typeName)
  for f in fields:
    result.add(autoKebabCase(f.name))

proc validateFeatureCoverage*(specFlags, implFlags: seq[string]) {.raises: [].} =
  ## Bidirectional spec-binding validation.
  ## Forward: every flag in .feature must have a parser field.
  ## Backward: every parser field should be mentioned in .feature (warning only).
  ## NOTE: Existing omissions are tracked in DEBT_REGISTRY.md (DEBT#228+).
  ##       New omissions cause build warnings; hard fail is deferred until
  ##       all legacy flags are implemented in cli_types.nim.
  for flag in specFlags:
    if flag notin implFlags:
      echo "[spec-binding FORWARD WARN] Feature mentions " & flag & " but no parser field in cli_types.nim"
  for flag in implFlags:
    if flag notin specFlags:
      echo "[spec-binding BACKWARD WARN] Parser handles " & flag & " but no feature mentions it"

proc generateCliSurface*(inputPath, outputPath: string; featuresDir: string = "") {.raises: [OSError].} =
  ## Main entry point. Reads cli_types.nim, generates cli_surface_generated.nim.
  ## If featuresDir is provided, performs spec-binding validation.
  let source = try: readFileSafe(inputPath) except CatchableError: ""
  if source.len == 0:
    return

  # Spec-binding validation
  if featuresDir.len > 0 and dirExists(featuresDir):
    let specFlags = extractFlagsFromFeatures(featuresDir)
    var implFlags: seq[string] = @[]
    for typeName in ["AxProveFlags", "AxReportFlags"]:
      implFlags.add(extractFlagsFromObject(source, typeName))
    validateFeatureCoverage(specFlags, implFlags)

  let surface = [
    ("AxProveFlag", "AxProveFlags"),
    ("AxReportFlag", "AxReportFlags")
  ]

  var output: seq[string] = @[]
  output.add("## cli_surface_generated.nim")
  output.add("## Pre-build generated CLI surface for all ax commands.")
  output.add("## Generated by: tools/cli_surface_generator.nim")
  output.add("## DO NOT EDIT MANUALLY — regenerate via refresh_cli_binaries")
  output.add("")
  output.add("import core/results")
  output.add("import core/parsers/safe_parsers")
  output.add("import cli/cli_types")
  output.add("")

  for (enumName, flagsName) in surface:
    let variants = extractEnumVariants(source, enumName)
    let fields = extractFieldsFromObject(source, flagsName)
    if fields.len == 0:
      continue

    # Consistency check: every enum variant must map to an object field
    for v in variants:
      var found = false
      for f in fields:
        if autoKebabCase(f.name) == v.value:
          found = true
          break
      if not found:
        echo "[generator WARN] Enum variant " & v.name & " = \"" & v.value & "\" has no matching field in " & flagsName

    output.add("# ---------------------------------------------------------------------------")
    output.add("# " & flagsName)
    output.add("# ---------------------------------------------------------------------------")
    output.add("")
    output.add(generateParseFlagProc(enumName))
    output.add("")
    output.add(generateParseFlagsProc(flagsName, fields, enumName))
    output.add("")
    output.add(generateValidateProc(flagsName))
    output.add("")
    output.add(generateHelpProc(flagsName, fields))
    output.add("")

  try:
    discard writeFileSafe(outputPath, output.join("\n"))  # axiom:best-effort(generated CLI surface is a build artifact; stale output regenerated on next run)
  except CatchableError:  # axiom:best-effort(generator output write is best-effort; stale surface regenerated on next run)
    discard

when isMainModule:
  let repoRoot = getCurrentDir()
  generateCliSurface(
    repoRoot / "src/cli/cli_types.nim",
    repoRoot / "src/cli/cli_surface_generated.nim",
    repoRoot / "tests/features"
  )
