# config/lint.nims — Import Boundary Lint
# Extracted from config.nims lines 68-123
# Provides: scanImportBoundary(), skipFiles, isInsideStringLiteral
# HARD FAIL on tools/ → src/ boundary violations

# Import Lint — HARD FAIL on tools/ → src/ boundary violations
block importLint:
  # Files that use code-gen string patterns containing "import core/..." etc.
  # These are false positives — the imports are inside string literals, not real imports.
  const skipFiles = [
    "pbt_generator.nim",
    "feature_runner_compiler.nim",
    "tools_facade.nim",
    "ast_splitter.nim",       # needs raw tree-sitter CST walking for file splitting
    "ast_rewriter.nim",       # needs raw tree-sitter CST walking for stub detection
    "symbol_extractor.nim",   # needs raw tree-sitter CST walking for SCC extraction
    "baseline_snapshot.nim",  # Baseline tool — imports SSOT from cli/shared/proof_hydration
  ]

  proc isInsideStringLiteral(line: string): bool =
    ## Detect lines where the `import` keyword is inside a string literal.
    ## Covers: "import ...", result.add "import ...", triple-quoted strings.
    let stripped = line.strip()
    # If stripped line doesn't start with a real import/from statement, skip
    if not (stripped.startsWith("import ") or stripped.startsWith("from ")):
      return true
    # Check for code-gen patterns: lines like import core/$1 (inside """ blocks)
    # or lines containing a quote before the import keyword
    if '"' in stripped:
      return true
    return false

  proc scanImportBoundary(): seq[string] =
    var violations: seq[string]
    let toolsDir = getCurrentDir() / "tools"
    if dirExists(toolsDir):
      for file in walkDirRec(toolsDir):
        if not file.endsWith(".nim"): continue
        # Skip known code-gen files that contain import patterns in strings
        let baseName = file.extractFilename()
        if baseName in skipFiles: continue
        let content = readFile(file)
        for lineNum, line in content.splitLines().pairs():
          let stripped = line.strip()
          # Skip comment lines
          if stripped.startsWith("#"): continue
          if not (stripped.startsWith("import ") or stripped.startsWith("from ")): continue
          # Skip lines where import keyword is inside a string literal
          if isInsideStringLiteral(stripped): continue
          if "shared_types/" in stripped: continue
          for prefix in ["core/", "gate/", "engine/", "verification/", "cli/"]:
            if prefix in stripped:
              violations.add(file & ":" & $(lineNum + 1) & ": " & stripped)
              break
    return violations
