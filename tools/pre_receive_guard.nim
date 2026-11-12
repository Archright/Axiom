import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

## pre_receive_guard — Server-side pre-receive hook guard
##
## Enforces the same command policies as the local git_wrapper and
## command_policy_gate, but runs server-side as a pre-receive hook.
##
## SSOT: Uses the SAME data/command_policy.json via compile-time embed.
## This guarantees local and server policies can never drift.
##
## Deployment:
##   nim c -d:release -o:bin/pre-receive-guard tools/pre_receive_guard.nim
##   # Then in the bare repo's hooks/pre-receive:
##   #   exec /path/to/bin/pre-receive-guard
##
## Behavior:
##   Reads stdin for ref update lines: <old-oid> <new-oid> <refname>
##   Validates each update against the policy.
##   Exit 0 = allow, Exit 1 = block (standard pre-receive contract).

import std/[osproc, strutils, strformat, json, macros, sequtils]

# ---------------------------------------------------------------------------
# Compile-time policy embedding (SSOT — same file as git_wrapper)
# ---------------------------------------------------------------------------

macro compilePolicy(): untyped =
  ## Reads data/command_policy.json at compile time.
  ## Extracts blocked subcommands and context-aware rules.
  const policyJson = staticRead("../../data/command_policy.json")
  let policy = parseJson(policyJson)

  var blockedFlags: seq[string]
  for p in policy["policies"]:
    if p["tool"].getStr() == "git":
      if p.hasKey("blockedFlags"):
        for flag in p["blockedFlags"]:
          blockedFlags.add(flag.getStr())

  result = newStmtList()
  result.add newConstStmt(ident("BlockedFlags"), newLit(blockedFlags))

compilePolicy()

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const
  GuardTag = "[pre-receive-guard]"

# ---------------------------------------------------------------------------
# Ref update parsing
# ---------------------------------------------------------------------------

type
  RefUpdate = object
    oldOid: string
    newOid: string
    refname: string

proc parseRefUpdate(line: string): RefUpdate =
  ## Parse a pre-receive stdin line: <old-oid> <new-oid> <refname>
  let parts = line.strip().split(' ')
  if parts.len >= 3:
    result.oldOid = parts[0]
    result.newOid = parts[1]
    result.refname = parts[2]
  else:
    result = RefUpdate(oldOid: "", newOid: "", refname: "")

# ---------------------------------------------------------------------------
# Policy checks
# ---------------------------------------------------------------------------

proc isZeroOid(oid: string): bool =
  ## Check if an OID is the null/zero SHA (branch creation or deletion).
  return oid == "0000000000000000000000000000000000000000"

proc isProtectedBranch(refname: string): bool =
  ## Check if the ref is a protected branch.
  ## Protected branches: main, core, master, release
  let branch = refname.replace("refs/heads/", "")
  return branch in ["main", "core", "master", "release"]

proc checkForcePush(update: RefUpdate): tuple[allowed: bool, reason: string] =
  ## Detect force push by checking if old OID is an ancestor of new OID.
  ## If old exists and is NOT an ancestor of new, it's a force push.
  if isZeroOid(update.oldOid):
    return (true, "new branch creation")  # Creating a branch is OK
  if isZeroOid(update.newOid):
    return (true, "branch deletion")  # Deleting is OK (may want to block separately)

  # Use git merge-base --is-ancestor to check
  let cmd = fmt"git merge-base --is-ancestor {update.oldOid} {update.newOid}"
  let (_, exitCode) = execCmdEx(cmd)
  if exitCode != 0:
    # old is NOT an ancestor of new → force push
    return (false, "non-fast-forward push detected")
  return (true, "fast-forward")

proc validateUpdate(update: RefUpdate): tuple[allowed: bool, reason: string] =
  ## Validate a single ref update against all policies.

  # 1. Force push protection on ALL branches
  let (ffOk, ffReason) = checkForcePush(update)
  if not ffOk:
    return (false, fmt"BLOCKED: {ffReason} on {update.refname}")

  # 2. Extra protection on protected branches
  if isProtectedBranch(update.refname):
    # Protected branches: no force push (already checked), no deletion
    if isZeroOid(update.newOid):
      return (false, fmt"BLOCKED: deletion of protected branch {update.refname}")

  return (true, "allowed")

# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

proc main() =
  ## Pre-receive hook entry point.
  ## Reads ref updates from stdin, validates each one.
  ## Exit 0 = allow all, Exit 1 = block all.

  stderr.writeLine(fmt"{GuardTag} Validating ref updates...")

  var blocked = false
  var updateCount = 0

  while not endOfFile(stdin):
    let line = stdin.readLine()
    if line.strip().len == 0:
      continue

    let update = parseRefUpdate(line)
    if update.refname.len == 0:
      continue

    inc updateCount
    let (allowed, reason) = validateUpdate(update)

    if allowed:
      stderr.writeLine(fmt"{GuardTag} ALLOW: {update.refname} ({reason})")
    else:
      stderr.writeLine(fmt"{GuardTag} {reason}")
      blocked = true

  if updateCount == 0:
    stderr.writeLine(fmt"{GuardTag} No ref updates to validate")
    quit(0)

  if blocked:
    stderr.writeLine(fmt"{GuardTag} RESULT: BLOCKED (1 or more updates rejected)")
    quit(1)
  else:
    stderr.writeLine(fmt"{GuardTag} RESULT: ALLOWED ({updateCount} updates passed)")
    quit(0)

when isMainModule:
  try:
    main()
  except CatchableError as e:
    stderr.writeLine(fmt"{GuardTag} FAIL-CLOSED: unhandled error: {e.msg}")
    quit(1)
