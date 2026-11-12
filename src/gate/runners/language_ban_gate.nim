import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## Language Ban Gate
##
## Fast-fail pre-commit gate that enforces the Axiom Nim-only policy
## by verifying that no disallowed file extensions are staged for commit.
##
## Python(.py), Shell(.sh, .bash), and other interpreted scripts are
## banned as project source. Existing scripts are temporarily exempted
## only if listed in src/policy/python_shell_exemptions.nim.
##
## Allowlisted extensions: nim, lean, md, toml, nims, lock, feature,
## json, yaml, yml, gitignore, gitattributes, editorconfig.
##
## Conjunctive extension×path rules: an extension listed in
## ExtensionPathRules is allowed ONLY under its registered path prefixes,
## never repo-wide. Current rule: .rs ONLY under src/frontend/rust/ and
## tests/fixtures/rust/ (verification subject frontend and fixtures;
## docs/agents/architecture.md §Language Ban).
##
## Allowlisted path patterns (bypass extension check):
##   vendor/, dotfiles, LICENSE, README, lakefile, Makefile, lean-toolchain.
##   NOTE: tools/ is NOT allowlisted; Python/Shell scripts under tools/
##   must be in the exemption registry or they are banned.
##
## When passFilenames is true in gate_list.nim, the orchestrator passes
## staged file paths as positional arguments. When false, this gate
## falls back to `git diff --cached --name-only`.

import std/os
import std/osproc
import std/strutils
import core/axiom_pragmas
import core/gate/gate_vfs
import policy/python_shell_exemptions
import infrastructure/logger
import std/times
import infrastructure/logging_facade


# axiomIoBoundary

axiomIoBoundary()

const
  GateTag = "[language-ban]"

  ## Extensions allowed by the Axiom project policy (AGENTS.md §0.2).
  AllowedExtensions: array[14, string] = [
    "nim", "lean", "md", "toml", "nims", "lock", "feature",
    "json", "yaml", "yml", "gitignore", "gitattributes", "editorconfig",
    "nimble"
  ]

  ## Path prefixes/patterns that bypass the extension check.
  AllowedPrefixes: array[6, string] = [
    "vendor/", ".", "LICENSE", "README", "lakefile", "lean-toolchain"
  ]

  ## Exact-match patterns (full path must equal).
  ## Hook infrastructure files have no extension but are required by the
  ## project and maintained as source-of-truth scripts.
  AllowedExact: array[7, string] = [
    "Makefile", "lean-toolchain", "Dockerfile.build",
    "logs/bypass_audit.jsonl", "bin/sync-branch",
    "bin/sync-main-worktree",
    "data/expected_invariant_hash.txt"
  ]

  ## Conjunctive extension×path rules: for a listed extension, the path is
  ## allowed ONLY under one of the registered prefixes — the extension is
  ## NOT added to AllowedExtensions (that would permit it repo-wide).
  ## Policy SSOT: docs/agents/architecture.md §Language Ban.
  ExtensionPathRules: seq[tuple[ext: string, prefixes: seq[string]]] = @[
    ("rs", @["src/frontend/rust/", "tests/fixtures/rust/"])
  ]



proc hasAllowedExtension(path: string): bool =
  ## Returns true if the file path ends with one of the allowed extensions.
  let lastDot = path.rfind('.')
  if lastDot < 0:
    return false
  let ext = path[lastDot + 1 .. ^1].toLowerAscii()
  for allowed in AllowedExtensions:
    if ext == allowed:
      return true
  false

proc isExempt(path: string, today: string): bool =
  ## Returns true if the path is listed in PythonShellExemptions AND not expired.
  for e in PythonShellExemptions:
    if string(e.path) == path:
      if today >= string(e.expiryDate):
        return false  # expired exemption is invalid
      return true
  false

proc matchesAllowedPath(path: string): bool =
  ## Returns true if the path matches any allowlisted path pattern.
  ## Checks prefix matches, exact matches, and basename matches.
  for prefix in AllowedPrefixes:
    if path.startsWith(prefix):
      return true
  for exact in AllowedExact:
    if path == exact:
      return true
    # Also match basename: "proofs/lean-toolchain" matches "lean-toolchain"
    let lastSlash = path.rfind('/')
    if lastSlash >= 0 and path[lastSlash + 1 .. ^1] == exact:
      return true
  false

proc extensionHasPathRule(path: string): bool =
  ## Returns true if the path's extension has a conjunctive extension×path
  ## rule in ExtensionPathRules.
  let lastDot = path.rfind('.')
  if lastDot < 0:
    return false
  let ext = path[lastDot + 1 .. ^1].toLowerAscii()
  for rule in ExtensionPathRules:
    if rule.ext == ext:
      return true
  false

proc pathMatchesExtensionRule(path: string): bool =
  ## For an extension with a conjunctive rule, returns true iff the path is
  ## under one of the registered prefixes for that extension.
  let lastDot = path.rfind('.')
  if lastDot < 0:
    return false
  let ext = path[lastDot + 1 .. ^1].toLowerAscii()
  for rule in ExtensionPathRules:
    if rule.ext == ext:
      for prefix in rule.prefixes:
        if path.startsWith(prefix):
          return true
  false

proc isBanned*(path: string, today: string): bool =
  ## A file is banned if:
  ## - it is NOT exempt AND lacks an allowed extension AND does not match any allowlisted path pattern.
  ## - exempt files bypass the ban even if they have banned extensions.
  ## - an extension with a conjunctive extension×path rule (ExtensionPathRules)
  ##   is allowed ONLY under its registered prefixes; the same extension
  ##   anywhere else stays banned (checked before the general path bypass).
  if isExempt(path, today):
    false
  elif extensionHasPathRule(path):
    not pathMatchesExtensionRule(path)
  else:
    not (hasAllowedExtension(path) or matchesAllowedPath(path))

proc getStagedFiles(): seq[string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## Retrieves staged file names. Uses --diff-filter=ACM to match
  ## the Bash hook parity (Added, Copied, Modified only).
  let (output, exitCode) = execCmdEx(
    "git diff --cached --name-only --diff-filter=ACM"
  )
  if exitCode != 0:
    logError("language_ban_gate", $(GateTag) & " FAIL — could not list staged files (git exit code: " & $(exitCode) & ")")
    quit(1)

  result = @[]
  for line in output.splitLines():
    let trimmed = line.strip()
    if trimmed.len > 0:
      result.add(trimmed)

proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## Entry point. Reads filenames from args or git, checks each against
  ## the allowlist, and exits 0 (clean) or 1 (banned files found).
  let today = now().utc.format("yyyy-MM-dd")
  var files: seq[string]

  if paramCount() > 0:
    # passFilenames mode: orchestrator provides staged file paths as args.
    files = @[]
    for i in 1 .. paramCount():
      files.add(paramStr(i))
  else:
    # Fallback: query git directly (standalone / manual invocation).
    files = getStagedFiles()

  if files.len == 0:
    logInfo("language_ban_gate", $(GateTag) & " PASS — no staged files to check")
    quit(0)

  var bannedFiles: seq[string] = @[]
  for f in files:
    # Skip deleted files: a deletion of a previously-tracked banned file is
    # allowed because it removes, not adds, the banned content.
    if not fileExists(f):
      continue
    if isBanned(f, today):
      bannedFiles.add(f)

  if bannedFiles.len == 0:
    logger.info $GateTag & " PASS — " & $files.len & " staged file(s) all have allowed extensions"
    quit(0)
  else:
    logError("language_ban_gate", $(GateTag) & " FAIL — " & $(bannedFiles.len) & " banned file(s) detected in staging area:")
    for bf in bannedFiles:
      logInfo("language_ban_gate", "  " & $(bf))
    logInfo("language_ban_gate", "")
    logError("language_ban_gate", "BLOCKED: Axiom is a Nim-only project (docs/agents/architecture.md §Language Ban).")
    logInfo("language_ban_gate", "  Allowed extensions: .nim .lean .md .toml .nims .lock .feature .json .yaml .yml .gitignore .gitattributes .editorconfig")
    logInfo("language_ban_gate", "  .rs allowed ONLY under src/frontend/rust/ or tests/fixtures/rust/ (verification subject)")
    logInfo("language_ban_gate", "  Bypass: bin/agent-bypass-commit --sign <message> (Ed25519-sanctioned)")
    quit(1)

proc mainWithVfs(ctx: GateContext) =
  ## VFS entry point. Reads filenames from VFS-provided git diff or args,
  ## checks each against the allowlist, and exits 0/1.
  let today = now().utc.format("yyyy-MM-dd")
  var files: seq[string]

  if paramCount() > 0:
    files = @[]
    for i in 1 .. paramCount():
      files.add(paramStr(i))
  else:
    # Fallback: query git via VFS subprocess provider.
    let result = vfsExec(ctx, "git", @["diff", "--cached", "--name-only", "--diff-filter=ACM"])
    if result.exitCode != 0:
      logError("language_ban_gate", $(GateTag) & " FAIL — could not list staged files (git exit code: " & $(result.exitCode) & ")")
      quit(1)
    files = @[]
    for line in result.output.splitLines():
      let trimmed = line.strip()
      if trimmed.len > 0:
        files.add(trimmed)

  if files.len == 0:
    logInfo("language_ban_gate", $(GateTag) & " PASS — no staged files to check")
    quit(0)

  var bannedFiles: seq[string] = @[]
  for f in files:
    if not vfsExists(ctx, f):
      continue
    if isBanned(f, today):
      bannedFiles.add(f)

  if bannedFiles.len == 0:
    logger.info $GateTag & " PASS — " & $files.len & " staged file(s) all have allowed extensions"
    quit(0)
  else:
    logError("language_ban_gate", $(GateTag) & " FAIL — " & $(bannedFiles.len) & " banned file(s) detected in staging area:")
    for bf in bannedFiles:
      logInfo("language_ban_gate", "  " & $(bf))
    logInfo("language_ban_gate", "")
    logError("language_ban_gate", "BLOCKED: Axiom is a Nim-only project (docs/agents/architecture.md §Language Ban).")
    logInfo("language_ban_gate", "  Allowed extensions: .nim .lean .md .toml .nims .lock .feature .json .yaml .yml .gitignore .gitattributes .editorconfig")
    logInfo("language_ban_gate", "  .rs allowed ONLY under src/frontend/rust/ or tests/fixtures/rust/ (verification subject)")
    logInfo("language_ban_gate", "  Bypass: bin/agent-bypass-commit --sign <message> (Ed25519-sanctioned)")
    quit(1)

{.pop.}

when isMainModule:
  main()

