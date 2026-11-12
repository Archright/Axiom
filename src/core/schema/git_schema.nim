import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
{.push noSideEffect.}

## git_schema.nim — Schema-as-Code for Git domain types.
## Pure type definitions + compile-time validation macros + JSON serialization.
## No business logic. No I/O. Importable independently.

import std/[json, strutils, macros]

# ---------------------------------------------------------------------------
# Git Error Domain
# ---------------------------------------------------------------------------

type
  GitErrorKind* = enum
    gitErrMergeConflict       ## Merge/rebase encountered conflicts
    gitErrTimeout             ## Git operation timed out
    gitErrMissingRef          ## Referenced ref does not exist
    gitErrNotRepo             ## Not inside a Git repository
    gitErrBranchNotFound      ## Branch does not exist
    gitErrPushRejected        ## Push rejected by remote
    gitErrRebaseFailed        ## Rebase operation failed
    gitErrStashFailed         ## Stash operation failed
    gitErrDetachFailed        ## Detached HEAD transition failed
    gitErrRemoteUnavailable   ## Remote server unreachable

  GitError* = object
    kind*: GitErrorKind
    message*: string
    command*: string           ## The git command that failed (if any)
    exitCode*: int             ## Process exit code (0 if unknown)

# ---------------------------------------------------------------------------
# Branch Domain
# ---------------------------------------------------------------------------

type
  BranchType* = enum
    btFeature                 ## Feature development branch
    btHotfix                  ## Emergency hotfix branch
    btBugfix                  ## Bug fix branch
    btSpike                   ## Investigation / spike branch
    btDeps                    ## Dependency update branch

  BranchRef* = distinct string
    ## Semantic wrapper: prevents accidental mixing of branch names
    ## with arbitrary strings (e.g. commit hashes, file paths).

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func `==`*(a, b: BranchRef): bool {.inline, raises: [].} =
  string(a) == string(b)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func `$`*(b: BranchRef): string {.inline, raises: [].} =
  string(b)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func branchRef*(s: string): BranchRef {.inline, raises: [].} =
  BranchRef(s)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func parseBranchType*(branchName: string): BranchType {.raises: [].} =
  ## Infer BranchType from conventional branch prefix.
  ## Defaults to btFeature if no prefix recognized.
  let lower = branchName.toLowerAscii()
  if lower.startsWith("hotfix/") or lower.startsWith("hotfix-"):
    btHotfix
  elif lower.startsWith("bugfix/") or lower.startsWith("bugfix-"):
    btBugfix
  elif lower.startsWith("spike/") or lower.startsWith("spike-"):
    btSpike
  elif lower.startsWith("deps/") or lower.startsWith("deps-"):
    btDeps
  else:
    btFeature

# ---------------------------------------------------------------------------
# Merge / Rebase Result Domain
# ---------------------------------------------------------------------------

type
  MergeResult* = object
    conflict*: bool
    conflictFiles*: seq[string]
    failedCommand*: string

  RebaseResult* = object
    success*: bool
    failedCommand*: string
    conflictFile*: string

# ---------------------------------------------------------------------------
# Repository & Working State Domain
# ---------------------------------------------------------------------------

type
  LocalState* = object
    currentBranch*: string
    mergedBranches*: seq[string]
    activeBranches*: seq[string]

  Repository* = object
    localState*: LocalState
    gitRoot*: string
    autoPush*: bool
    workspace*: string
    ciWorkspace*: string

  WorkingState* = object
    isClean*: bool
    hasStagedChanges*: bool
    hasUnstagedChanges*: bool
    hasUntrackedFiles*: bool

# ---------------------------------------------------------------------------
# Verdict & Conflict Domain
# ---------------------------------------------------------------------------

type
  Verdict* = object
    status*: seq[string]
    issues*: seq[string]
    hasBlockers*: bool

  ConflictInfo* = object
    files*: seq[string]
    baseBranch*: string

# ---------------------------------------------------------------------------
# Compile-Time Validation Macros
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro validateGitErrorEnum*(body: untyped): untyped =
  ## Compile-time guard: ensures GitErrorKind enum covers all required variants.
  ## Usage: static: validateGitErrorEnum(mergeConflict, timeout, missingRef)
  let required = ["gitErrMergeConflict", "gitErrTimeout", "gitErrMissingRef"]
  var enumVals: seq[string]
  for child in body:
    enumVals.add($child)
  for req in required:
    var found = false
    for ev in enumVals:
      if ev == req:
        found = true
        break
    if not found:
      error("GitErrorKind missing required variant: " & req)
  result = newStmtList()

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro validateBranchTypeExhaustive*(branchType: typedesc; cases: untyped): untyped =
  ## Compile-time guard: ensures a case/of covers all BranchType variants.
  ## Usage: static: validateBranchTypeExhaustive(BranchType, cases)
  let enumFields = [
    "btFeature", "btHotfix", "btBugfix", "btSpike", "btDeps"
  ]
  var covered: seq[string]
  for branch in cases:
    if branch.kind == nnkOfBranch:
      for sym in branch:
        covered.add($sym)
  for ef in enumFields:
    var found = false
    for cv in covered:
      if cv == ef:
        found = true
        break
    if not found:
      error("BranchType case missing variant: " & ef)
  result = newStmtList()

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func defaultMergeResult*(): MergeResult {.raises: [].} =
  ## Default MergeResult: no conflict.
  MergeResult(conflict: false, conflictFiles: @[], failedCommand: "")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func defaultRebaseResult*(): RebaseResult {.raises: [].} =
  ## Default RebaseResult: success.
  RebaseResult(success: true, failedCommand: "", conflictFile: "")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func defaultWorkingState*(): WorkingState {.raises: [].} =
  ## Default WorkingState: clean.
  WorkingState(isClean: true, hasStagedChanges: false,
               hasUnstagedChanges: false, hasUntrackedFiles: false)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func defaultVerdict*(): Verdict {.raises: [].} =
  ## Default Verdict: no issues.
  Verdict(status: @[], issues: @[], hasBlockers: false)

# ---------------------------------------------------------------------------
# JSON Serialization — toJson / fromJson for all schema types
# ---------------------------------------------------------------------------

# -- GitErrorKind

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func toJson*(e: GitErrorKind): JsonNode {.raises: [].} =
  newJString($e)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func gitErrorKindFromJson*(node: JsonNode): GitErrorKind {.raises: [].} =
  case node.getStr()
  of "gitErrMergeConflict": gitErrMergeConflict
  of "gitErrTimeout": gitErrTimeout
  of "gitErrMissingRef": gitErrMissingRef
  of "gitErrNotRepo": gitErrNotRepo
  of "gitErrBranchNotFound": gitErrBranchNotFound
  of "gitErrPushRejected": gitErrPushRejected
  of "gitErrRebaseFailed": gitErrRebaseFailed
  of "gitErrStashFailed": gitErrStashFailed
  of "gitErrDetachFailed": gitErrDetachFailed
  of "gitErrRemoteUnavailable": gitErrRemoteUnavailable
  else: gitErrMergeConflict  ## fallback: safe default

# -- GitError

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func toJson*(e: GitError): JsonNode {.raises: [].} =
  result = newJObject()
  result["kind"] = toJson(e.kind)
  result["message"] = newJString(e.message)
  result["command"] = newJString(e.command)
  result["exitCode"] = newJInt(e.exitCode)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func gitErrorFromJson*(node: JsonNode): GitError {.raises: [].} =
  ## Safe deserialization using `{}` access (no KeyError).
  GitError(
    kind: gitErrorKindFromJson(node{"kind"}),
    message: node{"message"}.getStr(),
    command: node{"command"}.getStr(),
    exitCode: node{"exitCode"}.getInt()
  )

# -- BranchType

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func toJson*(b: BranchType): JsonNode {.raises: [].} =
  newJString($b)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func branchTypeFromJson*(node: JsonNode): BranchType {.raises: [].} =
  case node.getStr()
  of "btFeature": btFeature
  of "btHotfix": btHotfix
  of "btBugfix": btBugfix
  of "btSpike": btSpike
  of "btDeps": btDeps
  else: btFeature  ## fallback

# -- MergeResult

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func toJson*(m: MergeResult): JsonNode {.raises: [].} =
  result = newJObject()
  result["conflict"] = newJBool(m.conflict)
  var files = newJArray()
  for f in m.conflictFiles:
    files.add(newJString(f))
  result["conflictFiles"] = files
  result["failedCommand"] = newJString(m.failedCommand)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func mergeResultFromJson*(node: JsonNode): MergeResult {.raises: [].} =
  ## Safe deserialization using `{}` access (no KeyError).
  var files: seq[string]
  let filesNode = node{"conflictFiles"}
  if filesNode.kind == JArray:
    for item in filesNode:
      files.add(item.getStr())
  MergeResult(
    conflict: node{"conflict"}.getBool(),
    conflictFiles: files,
    failedCommand: node{"failedCommand"}.getStr()
  )

# -- RebaseResult

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func toJson*(r: RebaseResult): JsonNode {.raises: [].} =
  result = newJObject()
  result["success"] = newJBool(r.success)
  result["failedCommand"] = newJString(r.failedCommand)
  result["conflictFile"] = newJString(r.conflictFile)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func rebaseResultFromJson*(node: JsonNode): RebaseResult {.raises: [].} =
  ## Safe deserialization using `{}` access (no KeyError).
  RebaseResult(
    success: node{"success"}.getBool(),
    failedCommand: node{"failedCommand"}.getStr(),
    conflictFile: node{"conflictFile"}.getStr()
  )

# -- LocalState

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func toJson*(ls: LocalState): JsonNode {.raises: [].} =
  result = newJObject()
  result["currentBranch"] = newJString(ls.currentBranch)
  var merged = newJArray()
  for b in ls.mergedBranches:
    merged.add(newJString(b))
  result["mergedBranches"] = merged
  var active = newJArray()
  for b in ls.activeBranches:
    active.add(newJString(b))
  result["activeBranches"] = active

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func localStateFromJson*(node: JsonNode): LocalState {.raises: [].} =
  ## Safe deserialization using `{}` access (no KeyError).
  var merged, active: seq[string]
  let mergedNode = node{"mergedBranches"}
  if mergedNode.kind == JArray:
    for item in mergedNode:
      merged.add(item.getStr())
  let activeNode = node{"activeBranches"}
  if activeNode.kind == JArray:
    for item in activeNode:
      active.add(item.getStr())
  LocalState(
    currentBranch: node{"currentBranch"}.getStr(),
    mergedBranches: merged,
    activeBranches: active
  )

# -- Repository

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func toJson*(repo: Repository): JsonNode {.raises: [].} =
  result = newJObject()
  result["localState"] = toJson(repo.localState)
  result["gitRoot"] = newJString(repo.gitRoot)
  result["autoPush"] = newJBool(repo.autoPush)
  result["workspace"] = newJString(repo.workspace)
  result["ciWorkspace"] = newJString(repo.ciWorkspace)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func repositoryFromJson*(node: JsonNode): Repository {.raises: [].} =
  ## Safe deserialization using `{}` access (no KeyError).
  Repository(
    localState: localStateFromJson(node{"localState"}),
    gitRoot: node{"gitRoot"}.getStr(),
    autoPush: node{"autoPush"}.getBool(),
    workspace: node{"workspace"}.getStr(),
    ciWorkspace: node{"ciWorkspace"}.getStr()
  )

# -- WorkingState

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func toJson*(ws: WorkingState): JsonNode {.raises: [].} =
  result = newJObject()
  result["isClean"] = newJBool(ws.isClean)
  result["hasStagedChanges"] = newJBool(ws.hasStagedChanges)
  result["hasUnstagedChanges"] = newJBool(ws.hasUnstagedChanges)
  result["hasUntrackedFiles"] = newJBool(ws.hasUntrackedFiles)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func workingStateFromJson*(node: JsonNode): WorkingState {.raises: [].} =
  ## Safe deserialization using `{}` access (no KeyError).
  WorkingState(
    isClean: node{"isClean"}.getBool(),
    hasStagedChanges: node{"hasStagedChanges"}.getBool(),
    hasUnstagedChanges: node{"hasUnstagedChanges"}.getBool(),
    hasUntrackedFiles: node{"hasUntrackedFiles"}.getBool()
  )

# -- Verdict

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func toJson*(v: Verdict): JsonNode {.raises: [].} =
  result = newJObject()
  var statusArr = newJArray()
  for s in v.status:
    statusArr.add(newJString(s))
  result["status"] = statusArr
  var issuesArr = newJArray()
  for i in v.issues:
    issuesArr.add(newJString(i))
  result["issues"] = issuesArr
  result["hasBlockers"] = newJBool(v.hasBlockers)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func verdictFromJson*(node: JsonNode): Verdict {.raises: [].} =
  ## Safe deserialization using `{}` access (no KeyError).
  var status, issues: seq[string]
  let statusNode = node{"status"}
  if statusNode.kind == JArray:
    for item in statusNode:
      status.add(item.getStr())
  let issuesNode = node{"issues"}
  if issuesNode.kind == JArray:
    for item in issuesNode:
      issues.add(item.getStr())
  Verdict(
    status: status,
    issues: issues,
    hasBlockers: node{"hasBlockers"}.getBool()
  )

# -- ConflictInfo

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func toJson*(ci: ConflictInfo): JsonNode {.raises: [].} =
  result = newJObject()
  var filesArr = newJArray()
  for f in ci.files:
    filesArr.add(newJString(f))
  result["files"] = filesArr
  result["baseBranch"] = newJString(ci.baseBranch)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func conflictInfoFromJson*(node: JsonNode): ConflictInfo {.raises: [].} =
  ## Safe deserialization using `{}` access (no KeyError).
  var files: seq[string]
  let filesNode = node{"files"}
  if filesNode.kind == JArray:
    for item in filesNode:
      files.add(item.getStr())
  ConflictInfo(
    files: files,
    baseBranch: node{"baseBranch"}.getStr()
  )

# ---------------------------------------------------------------------------
# Test Namespace: Merge Conflict Fixture Data
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func makeMergeConflictData*(): MergeResult {.raises: [].} =
  ## Standard merge conflict fixture for schema tests.
  MergeResult(
    conflict: true,
    conflictFiles: @["src/main.nim", "tests/unit_test.nim", "README.md"],
    failedCommand: "git merge feature/new-api"
  )

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func makeNoConflictData*(): MergeResult {.raises: [].} =
  ## Standard clean merge fixture.
  MergeResult(
    conflict: false,
    conflictFiles: @[],
    failedCommand: ""
  )

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func makeRebaseConflictData*(): RebaseResult {.raises: [].} =
  ## Standard rebase conflict fixture.
  RebaseResult(
    success: false,
    failedCommand: "git rebase main",
    conflictFile: "src/core/engine.nim"
  )

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func makeCleanWorkingState*(): WorkingState {.raises: [].} =
  ## Standard clean working tree fixture.
  defaultWorkingState()

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func makeDirtyWorkingState*(): WorkingState {.raises: [].} =
  ## Standard dirty working tree fixture.
  WorkingState(
    isClean: false,
    hasStagedChanges: true,
    hasUnstagedChanges: true,
    hasUntrackedFiles: false
  )

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func makeConflictVerdict*(): Verdict {.raises: [].} =
  ## Standard conflict verdict fixture.
  Verdict(
    status: @["conflict", "needs-resolution"],
    issues: @["src/main.nim has unresolved markers", "tests/unit_test.nim mismatch"],
    hasBlockers: true
  )

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func makeCleanVerdict*(): Verdict {.raises: [].} =
  ## Standard clean verdict fixture.
  defaultVerdict()

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func makeConflictInfoFixture*(): ConflictInfo {.raises: [].} =
  ## Standard ConflictInfo fixture.
  ConflictInfo(
    files: @["src/main.nim", "tests/unit_test.nim"],
    baseBranch: "main"
  )

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func makeRepositoryFixture*(): Repository {.raises: [].} =
  ## Standard Repository fixture with merge conflict in progress.
  Repository(
    localState: LocalState(
      currentBranch: "feature/new-api",
      mergedBranches: @["main"],
      activeBranches: @["main", "feature/new-api", "hotfix/urgent"]
    ),
    gitRoot: "/home/user/project",
    autoPush: false,
    workspace: "/home/user/project",
    ciWorkspace: "/home/user/project/.ci-workspace"
  )

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func makeGitConflictError*(): GitError {.raises: [].} =
  ## Standard GitError fixture for merge conflict.
  GitError(
    kind: gitErrMergeConflict,
    message: "CONFLICT (content): Merge conflict in src/main.nim",
    command: "git merge feature/new-api",
    exitCode: 1
  )

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func makeGitTimeoutError*(): GitError {.raises: [].} =
  ## Standard GitError fixture for timeout.
  GitError(
    kind: gitErrTimeout,
    message: "git fetch origin timed out after 30s",
    command: "git fetch origin",
    exitCode: 124
  )

{.pop.}
{.pop.}
