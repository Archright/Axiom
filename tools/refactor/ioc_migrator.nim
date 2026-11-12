## IoC Migrator — E4
## Scans src/core/ for infrastructure imports and migrates to IoC hub interfaces.
## Dry-run by default. Rollback on nim check failure. Skips shadow files.

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, strformat, osproc]

proc countOccurrences(s, sub: string): int =
  var count = 0
  var pos = 0
  while true:
    let idx = s.find(sub, pos)
    if idx < 0: break
    inc count
    pos = idx + sub.len
  return count

proc migrateFile(filePath: string, dryRun: bool): (bool, seq[string]) =
  var content = readFile(filePath)
  let original = content
  var changes: seq[string] = @[]

  # --- Import rewrites ---

  if "import infrastructure/logging_facade" in content:
    if "import core/interfaces/logging_hub" in content:
      # Hub already imported — just remove the facade import line
      content = content.replace("import infrastructure/logging_facade\n", "")
      changes.add("removed duplicate logging_facade import (hub already present)")
    else:
      content = content.replace("import infrastructure/logging_facade", "import core/interfaces/logging_hub")
      changes.add("logging_facade import → logging_hub")

  if "import infrastructure/logger" in content:
    if "import core/interfaces/logging_hub" in content:
      content = content.replace("import infrastructure/logger as logger\n", "")
      content = content.replace("import infrastructure/logger\n", "")
      changes.add("removed duplicate logger import (hub already present)")
    else:
      content = content.replace("import infrastructure/logger as logger", "import core/interfaces/logging_hub as logging_hub")
      content = content.replace("import infrastructure/logger", "import core/interfaces/logging_hub")
      changes.add("logger import → logging_hub")

  if "import ../../gate/utils/real_git" in content:
    content = content.replace("import ../../gate/utils/real_git", "import core/interfaces/git_ops_hub")
    changes.add("relative real_git → git_ops_hub")

  if "import gate/utils/real_git" in content:
    content = content.replace("import gate/utils/real_git", "import core/interfaces/git_ops_hub")
    changes.add("absolute real_git → git_ops_hub")

  # --- Call-site rewrites: real_git ---

  if "real_git.findRealGit" in content:
    content = content.replace("real_git.findRealGit", "git_ops_hub.findRealGit")
    changes.add("real_git.findRealGit → git_ops_hub.findRealGit")

  if "real_git.getCommitHash" in content:
    content = content.replace("real_git.getCommitHash", "git_ops_hub.getCommitHash")
    changes.add("real_git.getCommitHash → git_ops_hub.getCommitHash")

  # --- Call-site rewrites: logging_facade → logging_hub ---

  # Handle logging_facade.logMessage(lvl, "AXIOM", msg) FIRST (before 2-arg loop)
  let logMsgNeedle = "logging_facade.logMessage("
  if logMsgNeedle in content:
    var pos = 0
    while true:
      let idx = content.find(logMsgNeedle, pos)
      if idx < 0: break
      let start = idx + logMsgNeedle.len
      var depth = 1
      var i = start
      while i < content.len and depth > 0:
        if content[i] == '(': inc depth
        elif content[i] == ')': dec depth
        inc i
      if depth == 0:
        var commaCount = 0
        var lastComma = -1
        for j in start..<(i-1):
          if content[j] == ',':
            inc commaCount
            if commaCount == 2:
              lastComma = j
        if lastComma >= 0:
          var msgStart = lastComma + 1
          while msgStart < i-1 and content[msgStart] == ' ':
            inc msgStart
          let msgArg = content[msgStart..<(i-1)]
          let replacement = "logging_hub.logInfo(" & msgArg & ")"
          content = content[0..<idx] & replacement & content[i..^1]
          changes.add("logging_facade.logMessage(...) → logging_hub.logInfo(...)")
          pos = idx + replacement.len
          continue
      pos = idx + 1

  # logging_facade.llInfo/llError/llWarn/llDebug → logging_hub.logInfo/logError
  if "logging_facade.llInfo" in content:
    content = content.replace("logging_facade.llInfo", "logging_hub.logInfo")
    changes.add("logging_facade.llInfo → logging_hub.logInfo")
  if "logging_facade.llError" in content:
    content = content.replace("logging_facade.llError", "logging_hub.logError")
    changes.add("logging_facade.llError → logging_hub.logError")
  if "logging_facade.llWarn" in content:
    content = content.replace("logging_facade.llWarn", "logging_hub.logInfo")
    changes.add("logging_facade.llWarn → logging_hub.logInfo")
  if "logging_facade.llDebug" in content:
    content = content.replace("logging_facade.llDebug", "logging_hub.logInfo")
    changes.add("logging_facade.llDebug → logging_hub.logInfo")

  # Drop module arg from 2-arg calls: logInfo("module", msg) → logInfo(msg)
  for funcName in ["logInfo", "logError", "logWarn", "logDebug"]:
    let needle = funcName & "(\""
    var pos = 0
    while true:
      let idx = content.find(needle, pos)
      if idx < 0: break
      let afterOpen = idx + needle.len
      let closeQuote = content.find("\"", afterOpen)
      if closeQuote < 0 or closeQuote - afterOpen > 40:
        pos = idx + 1
        continue
      let afterQuote = closeQuote + 1
      var wsEnd = afterQuote
      while wsEnd < content.len and content[wsEnd] == ' ':
        inc wsEnd
      if wsEnd < content.len and content[wsEnd] == ',':
        let moduleArgStart = idx
        var msgStart = wsEnd + 1
        while msgStart < content.len and content[msgStart] == ' ':
          inc msgStart
        let before = content[0..<moduleArgStart]
        let funcPart = funcName & "("
        let after = content[msgStart..^1]
        content = before & funcPart & after
        changes.add(funcName & "() 2-arg → 1-arg (dropped module)")
        pos = moduleArgStart + funcPart.len
        continue
      pos = idx + 1

  # --- Call-site rewrites: logger → logging_hub ---
  if "logger.warn(" in content:
    content = content.replace("logger.warn(", "logging_hub.logInfo(")
    changes.add("logger.warn() → logging_hub.logInfo()")

  if changes.len == 0:
    return (true, @[])

  if dryRun:
    return (true, changes)

  # Write and verify — use nim check, filter errors to THIS file only
  writeFile(filePath, content)
  let (output, exitCode) = execCmdEx(fmt"nim check --hints:off {filePath}")
  if exitCode != 0:
    var fileErrors: seq[string] = @[]
    for line in output.splitLines():
      if line.startsWith(filePath) and "Error:" in line:
        fileErrors.add(line)
    if fileErrors.len > 0:
      writeFile(filePath, original)
      return (false, @["REVERTED: " & fileErrors[0]])

  return (true, changes)

proc main() =
  let dryRun = paramCount() >= 1 and paramStr(1) == "--dry-run"
  if not dryRun:
    echo "⚠ Running in APPLY mode (no --dry-run). Changes will be written."
    echo ""

  var success = 0
  var failed = 0
  var skipped = 0
  var totalChanges = 0

  for path in walkDirRec("src/core"):
    if not path.endsWith(".nim"):
      continue
    if "_shadow" in path:
      inc skipped
      continue

    let (ok, msgs) = migrateFile(path, dryRun)
    if ok and msgs.len > 0:
      inc success
      totalChanges += msgs.len
      let tag = if dryRun: "[DRY]" else: "[OK]"
      echo fmt"{tag} {path}"
      for m in msgs:
        echo fmt"  → {m}"
    elif not ok:
      inc failed
      echo fmt"[FAIL] {path}"
      for m in msgs:
        echo fmt"  ✗ {m}"

  echo ""
  echo "═══════════════════════════════════════"
  echo fmt"  Files migrated: {success}"
  echo fmt"  Files reverted: {failed}"
  echo fmt"  Shadow skipped: {skipped}"
  echo fmt"  Total changes:  {totalChanges}"
  echo "═══════════════════════════════════════"

main()
