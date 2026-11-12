## z3_precache.nim — Pre-generate Z3 verification cache
##
## Run this BEFORE compilation to populate .axiom/z3_cache/.
## Replaces compile-time gorge() calls with pre-computed results.
##
## Usage:
##   nim c -o:bin/z3-precache tools/z3_precache.nim
##   bin/z3-precache [--scan] [--query "SMT-LIB2 query"]
##
## Workflow:
##   1. Scans src/ for Z3 query patterns (gorge calls in axiom_dsl.nim etc.)
##   2. Executes each query against the local Z3 binary
##   3. Stores results in .axiom/z3_cache/<sha256>.res
##   4. Compile-time code reads cache instead of calling gorge()
import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, sequtils, osproc]
import tools/z3_cache

{.push raises: [CatchableError].}

proc findZ3Path(): string =
  ## Locate Z3 binary: vendor/z3/z3 > Z3_PATH env > PATH lookup
  let vendorPath = "vendor/z3/z3"
  if fileExists(vendorPath):
    return vendorPath
  result = getEnv("Z3_PATH", "")
  if result.len == 0:
    result = findExe("z3")
  if result.len == 0:
    echo "ERROR: Z3 not found. Set Z3_PATH or add z3 to PATH."
    quit(1)

proc getZ3Version(z3Path: string): string =
  ## Get Z3 version string (e.g. "Z3 version 4.13.0")
  let (output, exitCode) = execCmdEx(z3Path & " --version")
  if exitCode == 0:
    result = output.strip()
  else:
    result = "unknown"

proc runZ3Query(z3Path, query: string): string =
  ## Execute a single SMT-LIB2 query against Z3
  let fullQuery = "(set-option :produce-models true)\n" &
    "(set-option :sat.random_seed 0)\n" &
    "(set-option :fp.spacer.random_seed 0)\n" &
    query & "\n(check-sat)\n(get-model)\n"
  let (output, exitCode) = execCmdEx(z3Path & " -in -smt2", input = fullQuery)
  if exitCode == 0:
    result = output.strip()
  else:
    result = "Z3 error (exit=" & $exitCode & "): " & output.strip()

proc collectSourceFiles(): seq[string] =
  ## Recursively collect .nim files from src/ that might contain Z3 queries
  for entry in walkDirRec("src/", yieldFilter = {pcFile}):
    if entry.endsWith(".nim"):
      result.add(entry)

proc scanForQueries(files: seq[string]): seq[string] =
  ## Scan source files for SMT-LIB2 query patterns.
  ## Looks for hardcoded assert/check-sat patterns and gorge Z3 calls.
  for filePath in files:
    try:
      let content = readFile(filePath)
      # Pattern 1: inline SMT-LIB2 fragments (assert ... check-sat)
      if "(check-sat)" in content or "(assert " in content:
        # Extract balanced SMT-LIB2 expressions
        var i = 0
        while i < content.len:
          let assertStart = content.find("(assert ", i)
          if assertStart < 0:
            break
          # Find the matching closing paren
          var depth = 0
          var j = assertStart
          while j < content.len:
            if content[j] == '(':
              inc depth
            elif content[j] == ')':
              dec depth
              if depth == 0:
                # Extract the full assertion + check-sat
                let assertion = content[assertStart .. j]
                # Look for trailing check-sat after this assertion
                let afterAssert = content.find("(check-sat)", j)
                if afterAssert >= 0 and afterAssert - j < 50:
                  let fullFragment = assertion & "\n(check-sat)\n(get-model)\n"
                  result.add(fullFragment)
                break
            inc j
          i = j + 1
    except CatchableError:
      discard  # Skip unreadable files

  # Deduplicate
  result = result.deduplicate(isSorted = false)

proc precacheQueries(queries: seq[string], z3Path, z3Version: string): int =
  ## Execute and cache all queries. Returns count of newly cached entries.
  echo "Pre-caching ", $queries.len, " Z3 queries..."
  var cached = 0
  for i, query in queries:
    let key = computeCacheKey(query, z3Version)
    if cacheExists(key):
      echo "  [", $(i + 1), "/", $queries.len, "] HIT  (", key[0 ..< 12], "...)"
      continue
    echo "  [", $(i + 1), "/", $queries.len, "] MISS — executing Z3..."
    let z3Result = runZ3Query(z3Path, query)
    writeCache(key, z3Result, query, z3Version)
    inc cached
    let verdict = if z3Result.startsWith("sat"): "SAT (counterexample)"
                  elif z3Result.startsWith("unsat"): "UNSAT (proven)"
                  else: "UNKNOWN"
    echo "    → ", verdict, " → cached as ", key[0 ..< 12], "..."
  cached

proc precacheSingle(query: string, z3Path, z3Version: string) =
  ## Cache a single user-provided query
  let key = computeCacheKey(query, z3Version)
  echo "Query key: ", key
  if cacheExists(key):
    echo "Already cached."
    return
  let z3Result = runZ3Query(z3Path, query)
  writeCache(key, z3Result, query, z3Version)
  echo "Cached. Result: ", z3Result[0 ..< min(z3Result.len, 80)]

proc cacheStatus() =
  ## Display cache statistics
  echo "Z3 Cache Status"
  echo "==============="
  echo "Cache dir: ", Z3CacheDir
  if not dirExists(Z3CacheDir):
    echo "Cache directory does not exist."
    return
  var count = 0
  for path in walkDirRec(Z3CacheDir):
    if path.endsWith(".res"):
      inc count
  echo "Cached entries: ", $count
  let versionFile = Z3CacheDir / "z3_version.txt"
  if fileExists(versionFile):
    echo "Z3 version: ", readFile(versionFile).strip()
  else:
    echo "Z3 version: not recorded"

proc printUsage() =
  echo "Usage: z3-precache [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --scan         Scan src/ for Z3 queries and pre-cache them (default)"
  echo "  --query <q>    Cache a single SMT-LIB2 query"
  echo "  --status       Show cache statistics"
  echo "  --clear        Remove all cached entries"
  echo "  --help         Show this help"

when isMainModule:
  let args = commandLineParams()
  let z3Path = findZ3Path()
  let z3Version = getZ3Version(z3Path)
  echo "Z3 binary: ", z3Path
  echo "Z3 version: ", z3Version
  echo "Cache directory: ", Z3CacheDir

  # Record Z3 version in cache root
  createDir(Z3CacheDir)
  writeFile(Z3CacheDir / "z3_version.txt", z3Version)

  if args.len == 0 or "--scan" in args:
    let files = collectSourceFiles()
    echo "Scanned ", $files.len, " source files."
    let queries = scanForQueries(files)
    if queries.len == 0:
      echo "No Z3 queries found in source files."
    else:
      let cached = precacheQueries(queries, z3Path, z3Version)
      echo ""
      echo "Done. ", $cached, " new entries cached."

  elif "--query" in args:
    let qIdx = args.find("--query")
    if qIdx + 1 >= args.len:
      echo "ERROR: --query requires a SMT-LIB2 query string"
      quit(1)
    precacheSingle(args[qIdx + 1], z3Path, z3Version)

  elif "--status" in args:
    cacheStatus()

  elif "--clear" in args:
    if dirExists(Z3CacheDir):
      for path in walkDirRec(Z3CacheDir):
        removeFile(path)
      removeDir(Z3CacheDir)
      echo "Cache cleared."
    else:
      echo "No cache to clear."

  elif "--help" in args:
    printUsage()

  else:
    echo "Unknown option: ", args[0]
    printUsage()
    quit(1)
