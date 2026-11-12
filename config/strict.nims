# config/strict.nims — Strict Mode, Architecture Invariants, I/O Enforce
# Extracted from config.nims lines 178-279
# Provides: gateStrictEffects, axiom_gateway_build, axiomStrict scan, axiomIoEnforce

# ── Default Style Check: Hint Level ────────────────────────────────────────────
# AGENTS.md §4 GUARDIAN: styleCheck MUST be hint-level, NEVER error.
# This applies to all builds by default. The axiom_gateway_build block
# overrides to error for CI/CD strict builds only.
switch("styleCheck", "hint")

# AGENTS.md §0.6: Static First Enforcement — gate effect isolation
# Gates that have been VFS-migrated use strictEffects to prevent
# uncontrolled side effects. Category A gates (VFS-ready) are the first
# to adopt; Category C/D gates use gateIoBoundary until migrated.
when defined(gateStrictEffects):
  switch("strictEffects")

# ── Gateway Build Guard ───────────────────────────────────────────────────────
# -d:axiom_gateway_build 활성화 시 PBT 샌드박스 + strict 컴파일 모드 적용
# CI/CD 및 gateway 전용 빌드에서 사용 (AGENTS.md §0.6 Static First Enforcement)
when defined(axiom_gateway_build):
  switch("define", "axiom_pbt_sandbox")
  switch("define", "axiomStrict")  # ← Architecture invariants 활성화
  switch("warningAsError", "on")
  # AGENTS.md §4 GUARDIAN: styleCheck MUST be hint-level, NEVER error.
  switch("styleCheck", "hint")
  switch("hint", "XDeclaredButNotUsed:on")

# ── Architecture Invariant Auto-Scan (axiomStrict) ──
# -d:axiomStrict 활성화 시 core/ 전체를 자동 스캔하여
# I/O 누수, isMainModule, include 사용을 물리적으로 차단
when defined(axiomStrict):
  import os
  switch("path", ".")  # Ensure project root is on NimScript import path
  import core/trusted/architecture_invariants
  # ── Invariant 10: File Length Gate (500 lines) ──
  # AGENTS.md §0.3: Every module must be focused and cohesive.
  # Files over 500 lines indicate SRP violation.
  block:
    const lineCountLimit = 500
    let lineCountDirs = ["src/core", "src/gate", "src/infrastructure", "src/engine"]
    for dir in lineCountDirs:
      if not dirExists(dir): continue
      for entry in walkDirRec(dir):
        if entry.endsWith(".nim") and not entry.contains("trusted/"):
          let content = readFile(entry)
          let lineCount = content.splitLines().len
          if lineCount > lineCountLimit:
            # Check grandfather exceptions — these files are actively being reduced
            const grandfatherExceptions: seq[string] = @[
              "unified_gate_runner.nim",
              "documentation_first_gate.nim",
              "architecture_config_gate.nim",
              "debt_scan_gate.nim",
              "logging_policy_gate.nim",
              "codec_codegen.nim",
              "gate_memo.nim",
              "shell_ast_analyzer.nim",
              "semantic_boundary_guard.nim",
              "dependency_rules_gate.nim",
              "nim_check_runner.nim",
              "nimtry_cli.nim",
              "pipeline_orchestrator.nim",
              "task_schema.nim",
            ]
            var isExcepted = false
            for exc in grandfatherExceptions:
              if entry.endsWith(exc):
                isExcepted = true
                break
            if not isExcepted:
              echo "❌ [axiomStrict] File too long (", lineCount, " lines): ", entry
              echo "   Limit: ", lineCountLimit, " lines. Split into smaller modules per SRP."
              quit(1)
  # ── Invariant 11: gorge/staticExec Ban ──
  # AGENTS.md §1: Hermetic Build Orchestrator (v28) handles build introspection.
  # Direct gorge()/staticExec() in source files bypasses the controlled build
  # environment and introduces non-determinism.
  # Exception: config.nims (build system), tools/ (build infrastructure),
  # src/generated/ (hermetic build output).
  block:
    let gorgeBanDirs = ["src/core", "src/gate", "src/engine", "src/infrastructure"]
    for dir in gorgeBanDirs:
      if not dirExists(dir): continue
      for entry in walkDirRec(dir):
        if entry.endsWith(".nim") and not entry.contains("trusted/"):
          # Skip generated files
          if entry.contains("generated/"): continue
          let content = readFile(entry)
          let lines = content.splitLines()
          for i, line in lines:
            let stripped = line.strip()
            # Skip comments
            if stripped.startsWith("#"): continue
            # Skip string literals
            if "\"gorge(" in line or "\"staticExec(" in line: continue
            if "\"gorgeEx(" in line or "\"staticExec(" in line: continue
            for pattern in ["gorge(", "gorgeEx(", "staticExec("]:
              if pattern in stripped:
                echo "❌ [axiomStrict] gorge/staticExec ban at line ", i+1, " in ", entry
                echo "   Use hermetic_build.nim generated constants instead."
                echo "   See docs/spec/nim_effect_system_quirks.md §14"
                quit(1)
  proc scanCoreInvariants() =
    # Invariant 1: src/core/ root whitelist (must run first to ratchet new files)
    enforceCoreRootWhitelist()
    # Invariant 2: refactored topology modules may not import I/O modules
    enforceTopologyForbiddenImports()
    let coreDir = "src/core"
    for entry in walkDirRec(coreDir):
      if entry.endsWith(".nim") and not entry.contains("trusted/"):
        let content = readFile(entry)
        # Invariant 2: I/O 격리
        for pattern in ["readFile(", "writeFile(", "execProcess(", "startProcess("]:
          if content.contains(pattern):
            echo "❌ [axiomStrict] I/O leak in ", entry, ": ", pattern
            quit(1)
        # Invariant 3: isMainModule 금지
        if content.contains("when isMainModule"):
          echo "❌ [axiomStrict] isMainModule in ", entry
          quit(1)
        # Invariant 4: Import encapsulation — core/ must not import gate/cli/verification/
        for forbidden in ["import gate/", "import cli/", "import verification/",
                          "from gate/", "from cli/", "from verification/"]:
          if content.contains(forbidden):
            echo "❌ [axiomStrict] Import encapsulation violation in ", entry, ": ", forbidden
            quit(1)
    # Invariant 5: Echo ban — bare echo in core/gate/infrastructure is forbidden
    let echoBanDirs = ["src/core", "src/gate", "src/infrastructure"]
    for dir in echoBanDirs:
      for entry in walkDirRec(dir):
        if entry.endsWith(".nim") and not entry.contains("trusted/"):
          let content = readFile(entry)
          let lines = content.splitLines()
          for i, line in lines:
            let stripped = line.strip()
            if not stripped.startsWith("echo "): continue
            # Skip shell echo inside gorge/staticExec
            var skip = false
            for skipPat in ["gorge(", "staticExec(", "execProcess(",
                            "Logger.", "# echo", "echoCheck", "echoable"]:
              if skipPat in line:
                skip = true
                break
            if skip: continue
            echo "❌ [axiomStrict] Echo ban: bare 'echo' at line ", i+1, " in ", entry
            quit(1)
    # Invariant 7: stderr ban — stderr.writeLine/write in core/engine/infrastructure is forbidden
    # Use logging_facade from infrastructure instead
    let stderrBanDirs = ["src/core", "src/engine", "src/infrastructure"]
    for dir in stderrBanDirs:
      for entry in walkDirRec(dir):
        if entry.endsWith(".nim") and not entry.contains("trusted/"):
          let content = readFile(entry)
          let lines = content.splitLines()
          for i, line in lines:
            if "stderr.writeLine" in line or "stderr.write " in line:
              # Skip comments
              let stripped = line.strip()
              if stripped.startsWith("#"): continue
              # Skip string literals containing the pattern (basic heuristic)
              if "\"stderr.writeLine\"" in line or "\"stderr.write\"" in line: continue
              echo "❌ [axiomStrict] stderr ban at line ", i+1, " in ", entry
              echo "   Use logging_facade (logInfo/logWarn/logError) instead"
              quit(1)
    # Invariant 8: axiomEffect coverage — procs doing I/O must declare axiomEffect
    # This is a heuristic check; the definitive check is in effect_queries.nim
    for entry in walkDirRec("src/core"):
      if entry.endsWith(".nim") and not entry.contains("trusted/"):
        let content = readFile(entry)
        let lines = content.splitLines()
        for i, line in lines:
          let stripped = line.strip()
          if stripped.startsWith("proc ") and not stripped.contains("{.") and
             not stripped.contains("func "):
            # Check if this proc body (next 50 lines) contains I/O
            let startLine = i
            let endLine = min(i + 50, lines.len - 1)
            var hasIo = false
            for j in startLine..endLine:
              if "readFile(" in lines[j] or "writeFile(" in lines[j] or
                 "execProcess(" in lines[j] or "startProcess(" in lines[j] or
                 "stderr.writeLine" in lines[j] or "stdout.write" in lines[j]:
                hasIo = true
                break
            if hasIo:
              # Check if the proc has axiomEffect annotation
              let procBlock = lines[startLine..min(startLine+5, lines.len-1)].join(" ")
              if "axiomEffect" notin procBlock:
                echo "❌ [axiomStrict] I/O proc without axiomEffect at line ", i+1, " in ", entry
                echo "   Add {.axiomEffect: IoEffect.} to this proc."
                quit(1)
    # Invariant 9: Expanded cross-layer import enforcement
    # core/ must not import gate/, cli/, verification/, mcp/, frontend/, engine/
    # engine/ must not import cli/, frontend/
    # infrastructure/ must not import gate/, cli/, verification/
    let layerConstraints = [
      ("src/core", @["gate/", "cli/", "verification/", "mcp/", "frontend/", "engine/"]),
      ("src/engine", @["cli/", "frontend/"]),
      ("src/infrastructure", @["gate/", "cli/", "verification/"]),
    ]
    for (layerDir, forbiddenImports) in layerConstraints:
      for entry in walkDirRec(layerDir):
        if entry.endsWith(".nim") and not entry.contains("trusted/"):
          let content = readFile(entry)
          for forbidden in forbiddenImports:
            if ("import " & forbidden) in content or ("from " & forbidden) in content:
              echo "❌ [axiomStrict] Cross-layer import violation in ", entry, ": ", forbidden
              quit(1)
    # ── Phase 13: Effect Enforcement + Logging Unification ──
    # Collect verification/ files (not in strictSrcFiles base list)
    var phase13VerificationFiles: seq[string] = @[]
    if dirExists("src/verification"):
      for f in walkDirRec("src/verification"):
        if f.endsWith(".nim") and not f.contains("trusted/"):
          phase13VerificationFiles.add(f)
    # Invariant 13: Missing axiomEffect — error for core/verification/engine
    for entry in strictSrcFiles:
      if entry.endsWith(".nim") and not entry.contains("trusted/"):
        if entry.startsWith("src/core/") or entry.startsWith("src/engine/"):
          assertMissingAxiomEffect(entry)
    for entry in phase13VerificationFiles:
      assertMissingAxiomEffect(entry)
    # Invariant 14: CatchableError — hint for core/verification/engine
    for entry in strictSrcFiles:
      if entry.endsWith(".nim") and not entry.contains("trusted/"):
        if entry.startsWith("src/core/") or entry.startsWith("src/engine/"):
          assertNoCatchableError(entry)
    for entry in phase13VerificationFiles:
      assertNoCatchableError(entry)
    # Invariant 15: Func candidacy — hint for core/verification/engine
    for entry in strictSrcFiles:
      if entry.endsWith(".nim") and not entry.contains("trusted/"):
        if entry.startsWith("src/core/") or entry.startsWith("src/engine/"):
          assertFuncCandidate(entry)
    for entry in phase13VerificationFiles:
      assertFuncCandidate(entry)
    # Invariant 16: debugEcho — hint for core/engine/infrastructure
    for entry in strictSrcFiles:
      if entry.endsWith(".nim") and not entry.contains("trusted/"):
        if entry.startsWith("src/core/") or entry.startsWith("src/engine/") or
           entry.startsWith("src/infrastructure/"):
          assertNoDebugEcho(entry)
  scanCoreInvariants()

  # ── Invariant 12: Function Length Gate (100 lines) ──
  # AGENTS.md §0.3: Functions over 100 lines indicate SRP violation.
  # Detects proc/func/method declarations exceeding maxFuncLines.
  block:
    const maxFuncLines = 100
    let funcLenDirs = ["src/core", "src/gate", "src/infrastructure", "src/engine"]
    for dir in funcLenDirs:
      if not dirExists(dir): continue
      for entry in walkDirRec(dir):
        if entry.endsWith(".nim") and not entry.contains("trusted/"):
          let content = readFile(entry)
          if content.len == 0: continue
          let lines = content.splitLines()
          var i = 0
          while i < lines.len:
            let stripped = lines[i].strip()
            if stripped.startsWith("proc ") or stripped.startsWith("func ") or
               stripped.startsWith("method "):
              let funcStart = i
              var funcName = "unknown"
              let parts = stripped.split({ '(', ' ', ':' })
              if parts.len >= 2:
                funcName = parts[1]
              var j = i + 1
              var depth = 0
              while j < lines.len:
                let line = lines[j]
                for ch in line:
                  if ch == '{': inc depth
                  elif ch == '}': dec depth
                if depth <= 0 and j > funcStart + 1:
                  let nextStripped = line.strip()
                  if nextStripped.startsWith("proc ") or
                     nextStripped.startsWith("func ") or
                     nextStripped.startsWith("method ") or
                     nextStripped.startsWith("macro ") or
                     nextStripped.startsWith("template "):
                    break
                  if depth == 0 and nextStripped.len == 0:
                    var k = j + 1
                    while k < lines.len and lines[k].strip().len == 0:
                      inc k
                    if k < lines.len:
                      let ahead = lines[k].strip()
                      if ahead.startsWith("proc ") or ahead.startsWith("func ") or
                         ahead.startsWith("method ") or ahead.startsWith("macro ") or
                         ahead.startsWith("template ") or ahead.startsWith("const ") or
                         ahead.startsWith("type ") or ahead.startsWith("var ") or
                         ahead.startsWith("let "):
                        break
                inc j
              let funcLen = j - funcStart
              if funcLen > maxFuncLines:
                echo "❌ [axiomStrict] Function too long (", funcLen, " lines): ", funcName, " in ", entry
                echo "   Limit: ", maxFuncLines, " lines. Decompose per SRP (AGENTS.md §0.3)."
                quit(1)
            inc i

  # ── Invariant 17: AST Invariant Checker (Native Binary) ──
  # Scans source files using parseStmt + AST traversal to detect:
  #   1. Direct getEnv() calls — must use trusted/ wrapper
  #   2. Broad {.raises: [Exception].} — must narrow to specific exceptions
  #   3. Missing axiomEffect on I/O procs — must declare effect
  # Runs the native binary via gorgeEx() to avoid NimScript VM iteration limits.
  block:
    const checkerBin = "bin/ast_invariant_checker"
    if fileExists(checkerBin):
      let scanDirs = ["src/core", "src/verification", "src/engine"]
      var args = ""
      for dir in scanDirs:
        if dirExists(dir):
          if args.len > 0: args.add(" ")
          args.add(dir)
      if args.len > 0:
        let (output, exitCode) = gorgeEx(checkerBin & " " & args)
        if exitCode != 0:
          echo "❌ [axiomStrict] AST Invariant Checker found violations:"
          echo output
          quit(1)

# ── Import Encapsulation Gate ────────────────────────────────────────────────
# MOVED to runtime: src/gate/compile_time_checks.nim (Phase D)
# Previously ran grep-based scans on EVERY `nim c` invocation.
# Now executes only during pre-commit/pre-push gate runs.
# See: src/gate/compile_time_checks.nim → checkImportEncapsulation()

# ── SRP Import-Prefix Gate ──────────────────────────────────────────────────
# MOVED to runtime: src/gate/compile_time_checks.nim (Phase D)
# Previously parsed architecture_debt.json on EVERY `nim c` invocation.
# Now executes only during pre-commit/pre-push gate runs.
# See: src/gate/compile_time_checks.nim → checkSrpImportPrefix()

# ── Golden Data Integrity Gate ───────────────────────────────────────────────
# MOVED to runtime: src/gate/compile_time_checks.nim (Phase D)
# Previously ran `git status`/`git diff` on EVERY `nim c` invocation.
# Now executes only during pre-commit/pre-push gate runs.
# See: src/gate/compile_time_checks.nim → checkGoldenDataIntegrity()

# ── Project-Wide I/O Boundary Enforcement (axiomIoEnforce) ──
# -d:axiomIoEnforce 활성화 시 src/ 전체를 스캔하여,
# I/O 프리미티브를 사용하는 파일이 axiomIoBoundary()를 선언했는지 확인.
# 이는 Closed-World Build의 물리적 기반: I/O는 명시적 boundary에서만 허용.
# 단계적 도입을 위해 별도 플래그로 분리; 최종적으로는 axiomStrict에 통합.
when defined(axiomIoEnforce):
  import os
  import src/core/trusted/architecture_invariants
  proc scanProjectIoBoundaries() =
    let scanDirs = ["src/core", "src/verification", "src/infrastructure", "src/cli", "src/gate"]
    for dir in scanDirs:
      for entry in walkDirRec(dir):
        if entry.endsWith(".nim") and not entry.contains("trusted/"):
          enforceIoBoundary(entry)
  scanProjectIoBoundaries()
