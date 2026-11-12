## check_lean_vacuity.nim — 3-Layer Lean Proof Totalness Scanner
##
## Scans .lean files for vacuous proofs using three layers:
##   Layer 1 — Compilation check (lean --run / lake build)
##   Layer 2 — #print axioms injection + sorryAx/custom-axiom detection
##   Layer 3 — Static source pattern detection (abbrev: Prop := True, trivial True, etc.)
##
## Custom axiom detection (Layer 2): any `axiom <name>` in `#print axioms`
## output that is NOT a known-good core axiom (Classical.choice, propext,
## Quot.sound, Quot.lift, funext, Classical.decEq, etc.) is flagged as
## a vkCustomAxiom violation. This catches project-defined axioms like
## `hash_injective`, `external_io_isolated`, etc. that bypass proof obligations.
##
## Usage:
##   bin/check_lean_vacuity [--allowlist <path>] <file_or_dir>...
##
## Exit code:
##   0 = clean, no vacuity found
##   1 = vacuity or compilation error detected
##
## Allowlist: JSON array of {file, line, pattern, reason} entries
##   to suppress known false positives.

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, osproc, json, strutils, re]

# ────────────────────────────────────────────────────────────────
# Types
# ────────────────────────────────────────────────────────────────

type
  VacuumKind* = enum
    vkCompileError     ## Layer 1: failed to compile
    vkSorryAx          ## Layer 2: #print axioms reveals sorryAx
    vkCustomAxiom      ## Layer 2: #print axioms reveals project-defined axiom
    vkAbbrevTrue       ## Layer 3: abbrev.*: Prop := True
    vkTheoremTrivial   ## Layer 3: theorem.*: True := by trivial
    vkTheoremSimp      ## Layer 3: theorem.*: True := by simp
    vkTheoremRfl       ## Layer 3: theorem.*: True := by rfl

  VacuumEntry* = object
    file*: string
    line*: int
    kind*: VacuumKind
    detail*: string

  AllowlistEntry* = object
    file*: string
    line*: int
    pattern*: string
    reason*: string

  CheckConfig* = object
    allowlistPath*: string
    allowlist*: seq[AllowlistEntry]
    paths*: seq[string]
    verbose*: bool

# ────────────────────────────────────────────────────────────────
# Config
# ────────────────────────────────────────────────────────────────

const AllowlistDir = "tools/ci" / "lean_vacuity_allowlist.json"

proc findRepoRoot(): string =
  var dir = getAppDir()
  while dir.len > 0:
    if fileExists(dir / ".axiom_root"):
      return dir
    let parent = parentDir(dir)
    if parent == dir: break
    dir = parent
  result = getAppDir() / ".." / ".."
  normalizePath(result)

proc parseAllowlist(path: string): seq[AllowlistEntry] =
  if not fileExists(path):
    return @[]
  let content = readFile(path)
  let json = parseJson(content)
  result = @[]
  for entry in json.getElems():
    result.add AllowlistEntry(
      file: entry["file"].getStr(""),
      line: entry["line"].getInt(0),
      pattern: entry["pattern"].getStr(""),
      reason: entry["reason"].getStr("")
    )

proc isAllowlisted(entry: VacuumEntry, allowlist: seq[AllowlistEntry]): bool =
  for a in allowlist:
    if a.file == entry.file and a.line == entry.line:
      return true
    if a.file == entry.file and a.line == 0 and a.pattern.len > 0:
      if entry.detail.contains(a.pattern):
        return true
  false

# ────────────────────────────────────────────────────────────────
# Known-good core Lean axioms (from stdlib / kernel)
# ────────────────────────────────────────────────────────────────

proc isKnownGoodAxiom(name: string): bool =
  case name
  of "Classical.choice", "propext", "Quot.sound", "Quot.lift",
     "funext", "Classical.decEq", "Classical.indefFunc", "Classical.em":
    true
  else:
    false

# ────────────────────────────────────────────────────────────────
# Layer 1 — Compilation Check
# ────────────────────────────────────────────────────────────────

proc checkLayer1(filePath: string): seq[VacuumEntry] =
  ## Run `lean <file>` for type-checking and check exit code.
  ## Also checks for `sorry` in output — a type error marker.
  result = @[]
  if not fileExists(filePath):
    return

  # Use `lean` without --run for type-checking only
  let (output, exitCode) = execCmdEx("lean " & quoteShell(filePath) & " 2>&1")
  if exitCode != 0:
    let detail = "Compilation failed (exit " & $exitCode & "): " & output.strip()
    result.add VacuumEntry(
      file: filePath,
      line: 0,
      kind: vkCompileError,
      detail: detail
    )
  elif output.contains("sorry") and output.contains("warning"):
    result.add VacuumEntry(
      file: filePath,
      line: 0,
      kind: vkCompileError,
      detail: "Compilation succeeded but sorry detected: " & output.strip()
    )

# ────────────────────────────────────────────────────────────────
# Layer 2 — #print axioms injection + sorryAx detection
# ────────────────────────────────────────────────────────────────

proc checkLayer2(filePath: string): seq[VacuumEntry] =
  ## Appends `#print axioms <name>` after each theorem/def in the source,
  ## runs Lean, and scans output for `sorryAx` and project-defined custom axioms.
  result = @[]
  if not fileExists(filePath):
    return

  let original = readFile(filePath)
  let lines = original.splitLines()

  # Collect all theorem/lemma/example declarations with their names,
  # tracking namespace context so we can use qualified names later.
  type DeclInfo = object
    name: string         # simple name
    fullName: string     # fully qualified name (e.g., "Axiom.IO.write_overwrite")
    lineIdx: int         # index in lines array where declaration starts

  var decls: seq[DeclInfo] = @[]
  var nsStack: seq[string] = @[]

  for i, line in lines:
    let stripped = line.strip()
    # Track namespace stack
    if stripped.startsWith("namespace "):
      let nsName = stripped[10..^1].strip()
      nsStack.add(nsName)
    elif stripped.startsWith("end ") and nsStack.len > 0:
      let endArg = stripped[4..^1].strip()
      if not endArg.isEmptyOrWhitespace():
          discard nsStack.pop()
    # Detect theorem/lemma/example declarations
    let keywordLen = if stripped.startsWith("theorem "): 8
                     elif stripped.startsWith("lemma "): 6
                     elif stripped.startsWith("example "): 8
                     else: -1
    if keywordLen > 0:
      let rest = stripped[keywordLen..^1].strip()
      let nameEnd = rest.find(' ')
      let simpleName = if nameEnd >= 0: rest[0..<nameEnd] else: rest
      if simpleName.len > 0:
        let fullName = if nsStack.len > 0: nsStack.join(".") & "." & simpleName else: simpleName
        decls.add(DeclInfo(name: simpleName, fullName: fullName, lineIdx: i))

  # Build modified source: insert #print axioms right before each 'end' or at EOF
  # We insert them scoped within whatever namespace was active when the decl was found
  var modified = newSeq[string]()
  var declIdx = 0
  while declIdx < decls.len:
    let d = decls[declIdx]
    # Add lines up to and including the declaration body
    var j = d.lineIdx + 1
    while j < lines.len:
      let bl = lines[j].strip()
      # Stop at next top-level construct
      if bl.startsWith("theorem ") or bl.startsWith("lemma ") or bl.startsWith("example ") or
         bl.startsWith("namespace ") or bl.startsWith("section ") or bl.startsWith("end ") or
         bl.startsWith("structure ") or bl.startsWith("inductive ") or bl.startsWith("class ") or
         bl.startsWith("variable ") or bl.startsWith("axiom "):
        break
      inc j
    for k in 0..<j:
      modified.add(lines[k])
    # Insert #print axioms inside the namespace scope (before any end/next decl)
    modified.add("")
    modified.add("#print axioms " & d.fullName)
    declIdx += 1

  # Add remaining lines not part of any declaration
  if decls.len > 0:
    let lastD = decls[^1]
    var j = lastD.lineIdx + 1
    while j < lines.len:
      let bl = lines[j].strip()
      if bl.startsWith("theorem ") or bl.startsWith("lemma ") or bl.startsWith("example ") or
         bl.startsWith("namespace ") or bl.startsWith("section ") or bl.startsWith("end ") or
         bl.startsWith("structure ") or bl.startsWith("inductive ") or bl.startsWith("class ") or
         bl.startsWith("variable ") or bl.startsWith("axiom "):
        break
      inc j
    for k in j..<lines.len:
      modified.add(lines[k])

  let tmpFile = filePath & ".ax_print_check.lean"
  try:
    writeFile(tmpFile, modified.join("\n"))
    let (output, _) = execCmdEx("lean " & quoteShell(tmpFile) & " 2>&1")

    # Scan output for sorryAx references regardless of exit code
    for outLine in output.splitLines():
      if outLine.contains("sorryAx"):
        result.add VacuumEntry(
          file: filePath,
          line: 0,
          kind: vkSorryAx,
          detail: "sorryAx detected: " & outLine.strip()
        )
      # Detect project-defined axioms (not known-good core axioms)
      let trimmed = outLine.strip()
      # Match Lean's "#print axioms" output: '<decl>' depends on axioms: [a1, a2, ...]
      if trimmed.contains("depends on axioms:") and trimmed.contains("[") and trimmed.contains("]"):
        let bracketStart = trimmed.find('[')
        let bracketEnd = trimmed.find(']')
        if bracketStart >= 0 and bracketEnd > bracketStart:
          let inside = trimmed[bracketStart+1..<bracketEnd].strip()
          if inside.len > 0:
            for part in inside.split(','):
              let rawName = part.strip().replace("'", "").replace("\"", "").strip()
              # Skip sorryAx here — the SORRY_AX rule already reports it (avoids
              # duplicate CUSTOM_AXIOM + SORRY_AX findings for the same sorry).
              if rawName.len > 0 and rawName != "sorryAx" and not isKnownGoodAxiom(rawName):
                result.add VacuumEntry(
                  file: filePath,
                  line: 0,
                  kind: vkCustomAxiom,
                  detail: "project-defined axiom detected: " & rawName
                )
  finally:
    removeFile(tmpFile)

# ────────────────────────────────────────────────────────────────
# Layer 3 — Static Source Pattern Detection
# ────────────────────────────────────────────────────────────────

proc checkLayer3(filePath: string): seq[VacuumEntry] =
  ## Fast path: scan source for vacuous proof patterns using regex.
  ## Handles single-line and multi-line theorem/lemma/example declarations.
  ## No Lean compiler needed for this layer.
  result = @[]
  if not fileExists(filePath):
    return

  let content = readFile(filePath)
  let lines = content.splitLines()

  # ── Pattern: abbrev X : Prop := True ──────────────────────────
  let patternAbbrevTrue = re(r"(?i)abbrev\s+\w+\s*:\s*Prop\s*:=\s*True\b")
  for i, line in lines:
    let stripped = line.strip()
    if stripped.startsWith("--") or stripped.startsWith("/-"):
      continue
    if contains(stripped, patternAbbrevTrue):
      result.add VacuumEntry(
        file: filePath, line: i + 1,
        kind: vkAbbrevTrue,
        detail: "abbrev: Prop := True: " & stripped
      )

  # ── Helper: detect vacuous theorem/lemma/example patterns ─────
  #
  # Single-line: theorem X : True := by trivial
  # Multi-line:  theorem X : True := by
  #                trivial
  #
  # We iterate lines, looking for declarations concluding ": True :=".
  # If followed on the same line by `by <tactic>` or on the next
  # non-comment/non-blank line by a recognized tactic, we flag it.

  let declPattern = re(r"(?i)(theorem|lemma|example)\s+\w*\s*:.*True\s*:=")
  let tacticSameLine = re(r"(?i)by\s+(trivial|simp|rfl)\b")
  let tacticNextLine = re(r"(?i)^(trivial|simp|rfl)\b")

  for i, line in lines:
    let stripped = line.strip()
    if stripped.startsWith("--") or stripped.startsWith("/-") or stripped.len == 0:
      continue
    if not contains(stripped, declPattern):
      continue

    let lineNum = i + 1

    # Single-line: ... := by trivial/simp/rfl  (on same line)
    if contains(stripped, tacticSameLine):
      let m = stripped.find(tacticSameLine)
      let tactic = if m >= 0: stripped[m..^1].strip() else: "?"
      var kind: VacuumKind
      if tactic.contains("trivial"): kind = vkTheoremTrivial
      elif tactic.contains("simp"): kind = vkTheoremSimp
      elif tactic.contains("rfl"): kind = vkTheoremRfl
      else: kind = vkTheoremTrivial
      result.add VacuumEntry(
        file: filePath, line: lineNum,
        kind: kind,
        detail: stripped
      )
      continue

    # Multi-line: ... := by  (then check next non-comment line)
    if not stripped.contains(":= by"):
      continue
    var nextLineIdx = i + 1
    var nextBody = ""
    while nextLineIdx < lines.len:
      let nextStripped = lines[nextLineIdx].strip()
      if nextStripped.startsWith("--") or nextStripped.startsWith("/-") or nextStripped.len == 0:
        nextLineIdx += 1
        continue
      nextBody = nextStripped
      break
    if contains(nextBody, tacticNextLine):
      var kind: VacuumKind
      if nextBody.contains("trivial"): kind = vkTheoremTrivial
      elif nextBody.contains("simp"): kind = vkTheoremSimp
      elif nextBody.contains("rfl"): kind = vkTheoremRfl
      else: kind = vkTheoremTrivial
      result.add VacuumEntry(
        file: filePath, line: lineNum,
        kind: kind,
        detail: stripped & "  --  " & nextBody
      )

# ────────────────────────────────────────────────────────────────
# Collect .lean files
# ────────────────────────────────────────────────────────────────

proc shouldSkipFile(path: string): bool =
  ## Skip files that are outside the scope of vacuity checking.
  ## Negative test files intentionally fail compilation.
  ## lakefile.lean is a build configuration file, not a proof.
  ## Feedback round files are auto-generated and may contain stubs.
  let name = extractFilename(path)
  if name == "lakefile.lean": return true
  if name.endsWith(".negative.lean"): return true
  if name.contains("_lean_feedback_round_"): return true
  false

proc collectLeanFiles(paths: seq[string]): seq[string] =
  result = @[]
  for p in paths:
    if fileExists(p) and p.endsWith(".lean") and not shouldSkipFile(p):
      result.add p
    elif dirExists(p):
      for path in walkDirRec(p):
        if path.endsWith(".lean") and not shouldSkipFile(path):
          result.add path

# ────────────────────────────────────────────────────────────────
# Main
# ────────────────────────────────────────────────────────────────

proc printVacuum(entry: VacuumEntry) =
  let kindStr = case entry.kind
    of vkCompileError: "COMPILE_ERROR"
    of vkSorryAx: "SORRY_AX"
    of vkCustomAxiom: "CUSTOM_AXIOM"
    of vkAbbrevTrue: "ABBREV_TRUE"
    of vkTheoremTrivial: "THEOREM_TRIVIAL"
    of vkTheoremSimp: "THEOREM_SIMP"
    of vkTheoremRfl: "THEOREM_RFL"
  let lineStr = if entry.line > 0: ":" & $entry.line else: ""
  echo "VACUITY [" & kindStr & "] " & entry.file & lineStr & " — " & entry.detail

proc main() =
  let repoRoot = findRepoRoot()
  let args = commandLineParams()

  var config = CheckConfig(
    allowlistPath: repoRoot / AllowlistDir,
    verbose: false
  )

  # Parse args
  var i = 0
  while i < args.len:
    if args[i] == "--allowlist" and i + 1 < args.len:
      config.allowlistPath = args[i + 1]
      i += 2
    elif args[i] == "--verbose" or args[i] == "-v":
      config.verbose = true
      i += 1
    else:
      config.paths.add args[i]
      i += 1

  if config.paths.len == 0:
    config.paths = @[repoRoot / "proofs", repoRoot / "src" / "verification", repoRoot / "tests" / "fixtures"]

  # Load allowlist
  config.allowlist = parseAllowlist(config.allowlistPath)
  if config.verbose:
    echo "Allowlist: " & config.allowlistPath & " (" & $config.allowlist.len & " entries)"

  # Collect .lean files
  let leanFiles = collectLeanFiles(config.paths)
  if leanFiles.len == 0:
    echo "No .lean files found in specified paths."
    quit(0)

  if config.verbose:
    echo "Scanning " & $leanFiles.len & " .lean files..."

  var allEntries: seq[VacuumEntry] = @[]
  var cleanCount = 0

  for f in leanFiles:
    if config.verbose:
      echo "  " & f

    var fileEntries: seq[VacuumEntry] = @[]

    # Layer 1: Compilation check
    fileEntries &= checkLayer1(f)

    # Layer 2: #print axioms + sorryAx detection
    fileEntries &= checkLayer2(f)

    # Layer 3: Static pattern detection
    fileEntries &= checkLayer3(f)

    # Filter allowlisted entries
    for entry in fileEntries:
      if not isAllowlisted(entry, config.allowlist):
        allEntries.add entry

    if fileEntries.len == 0:
      cleanCount += 1

  # Report results
  if allEntries.len > 0:
    echo ""
    echo "=== VACUITY VIOLATIONS (" & $allEntries.len & " found) ==="
    echo ""
    for entry in allEntries:
      printVacuum(entry)
    echo ""
    echo "Total: " & $leanFiles.len & " files, " & $cleanCount & " clean, " & $allEntries.len & " violations"
    quit(1)
  else:
    if config.verbose:
      echo ""
    echo "✅ All " & $leanFiles.len & " .lean files clean — no vacuity detected."
    quit(0)

when isMainModule:
  main()
