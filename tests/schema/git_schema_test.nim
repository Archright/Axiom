import std/[unittest, json]
import core/schema/git_schema

# ===========================================================================
# GitErrorKind Enum Tests
# ===========================================================================

suite "GitErrorKind enum":
  test "all variants are distinct":
    var seen: seq[GitErrorKind]
    for kind in [gitErrMergeConflict, gitErrTimeout, gitErrMissingRef,
                 gitErrNotRepo, gitErrBranchNotFound, gitErrPushRejected,
                 gitErrRebaseFailed, gitErrStashFailed, gitErrDetachFailed,
                 gitErrRemoteUnavailable]:
      check kind notin seen
      seen.add(kind)

  test "enum serializes to JsonNode":
    let node = toJson(gitErrMergeConflict)
    check node.kind == JString
    check node.getStr() == "gitErrMergeConflict"

  test "enum roundtrip via JSON":
    let original = gitErrRebaseFailed
    let node = toJson(original)
    let restored = gitErrorKindFromJson(node)
    check restored == original

# ===========================================================================
# GitError Object Tests
# ===========================================================================

suite "GitError object":
  test "makeGitConflictError fixture fields":
    let err = makeGitConflictError()
    check err.kind == gitErrMergeConflict
    check err.message == "CONFLICT (content): Merge conflict in src/main.nim"
    check err.command == "git merge feature/new-api"
    check err.exitCode == 1

  test "makeGitTimeoutError fixture fields":
    let err = makeGitTimeoutError()
    check err.kind == gitErrTimeout
    check err.exitCode == 124

  test "GitError JSON roundtrip":
    let original = makeGitConflictError()
    let node = toJson(original)
    let restored = gitErrorFromJson(node)
    check restored.kind == original.kind
    check restored.message == original.message
    check restored.command == original.command
    check restored.exitCode == original.exitCode

  test "GitError JSON has expected keys":
    let node = toJson(makeGitConflictError())
    check node.hasKey("kind")
    check node.hasKey("message")
    check node.hasKey("command")
    check node.hasKey("exitCode")

# ===========================================================================
# BranchType & BranchRef Tests
# ===========================================================================

suite "BranchType enum":
  test "parseBranchType detects hotfix":
    check parseBranchType("hotfix/urgent-fix") == btHotfix
    check parseBranchType("hotfix-emergency") == btHotfix

  test "parseBranchType detects bugfix":
    check parseBranchType("bugfix/null-ptr") == btBugfix
    check parseBranchType("bugfix-login") == btBugfix

  test "parseBranchType detects spike":
    check parseBranchType("spike/async-eval") == btSpike

  test "parseBranchType detects deps":
    check parseBranchType("deps/update-nim") == btDeps

  test "parseBranchType defaults to feature":
    check parseBranchType("feature/my-work") == btFeature
    check parseBranchType("random-branch") == btFeature

  test "parseBranchType is case-insensitive":
    check parseBranchType("Hotfix/Urgent") == btHotfix
    check parseBranchType("BUGFIX/null") == btBugfix

  test "BranchType JSON roundtrip":
    for bt in [btFeature, btHotfix, btBugfix, btSpike, btDeps]:
      let node = toJson(bt)
      let restored = branchTypeFromJson(node)
      check restored == bt

suite "BranchRef distinct type":
  test "BranchRef equality":
    let a = branchRef("main")
    let b = branchRef("main")
    let c = branchRef("develop")
    check a == b
    check a != c

  test "BranchRef string conversion":
    let ref1 = branchRef("feature/x")
    check $ref1 == "feature/x"

  test "BranchRef wraps string":
    let ref1 = branchRef("test")
    check string(ref1) == "test"

# ===========================================================================
# MergeResult Tests
# ===========================================================================

suite "MergeResult":
  test "makeMergeConflictData fixture":
    let mr = makeMergeConflictData()
    check mr.conflict == true
    check mr.conflictFiles.len == 3
    check "src/main.nim" in mr.conflictFiles
    check mr.failedCommand == "git merge feature/new-api"

  test "makeNoConflictData fixture":
    let mr = makeNoConflictData()
    check mr.conflict == false
    check mr.conflictFiles.len == 0
    check mr.failedCommand == ""

  test "defaultMergeResult has no conflict":
    let mr = defaultMergeResult()
    check mr.conflict == false

  test "MergeResult JSON roundtrip":
    let original = makeMergeConflictData()
    let node = toJson(original)
    let restored = mergeResultFromJson(node)
    check restored.conflict == original.conflict
    check restored.conflictFiles == original.conflictFiles
    check restored.failedCommand == original.failedCommand

  test "MergeResult JSON preserves array order":
    let original = makeMergeConflictData()
    let node = toJson(original)
    let restored = mergeResultFromJson(node)
    check restored.conflictFiles[0] == "src/main.nim"
    check restored.conflictFiles[1] == "tests/unit_test.nim"
    check restored.conflictFiles[2] == "README.md"

# ===========================================================================
# RebaseResult Tests
# ===========================================================================

suite "RebaseResult":
  test "makeRebaseConflictData fixture":
    let rr = makeRebaseConflictData()
    check rr.success == false
    check rr.failedCommand == "git rebase main"
    check rr.conflictFile == "src/core/engine.nim"

  test "defaultRebaseResult is success":
    let rr = defaultRebaseResult()
    check rr.success == true

  test "RebaseResult JSON roundtrip":
    let original = makeRebaseConflictData()
    let node = toJson(original)
    let restored = rebaseResultFromJson(node)
    check restored.success == original.success
    check restored.failedCommand == original.failedCommand
    check restored.conflictFile == original.conflictFile

# ===========================================================================
# LocalState Tests
# ===========================================================================

suite "LocalState":
  test "LocalState JSON roundtrip from fixture":
    let repo = makeRepositoryFixture()
    let ls = repo.localState
    let node = toJson(ls)
    let restored = localStateFromJson(node)
    check restored.currentBranch == "feature/new-api"
    check restored.mergedBranches == @["main"]
    check restored.activeBranches.len == 3
    check "hotfix/urgent" in restored.activeBranches

# ===========================================================================
# Repository Tests
# ===========================================================================

suite "Repository":
  test "makeRepositoryFixture fields":
    let repo = makeRepositoryFixture()
    check repo.gitRoot == "/home/user/project"
    check repo.autoPush == false
    check repo.workspace == "/home/user/project"
    check repo.ciWorkspace == "/home/user/project/.ci-workspace"
    check repo.localState.currentBranch == "feature/new-api"

  test "Repository JSON roundtrip":
    let original = makeRepositoryFixture()
    let node = toJson(original)
    let restored = repositoryFromJson(node)
    check restored.gitRoot == original.gitRoot
    check restored.autoPush == original.autoPush
    check restored.workspace == original.workspace
    check restored.ciWorkspace == original.ciWorkspace
    check restored.localState.currentBranch == original.localState.currentBranch
    check restored.localState.activeBranches == original.localState.activeBranches

# ===========================================================================
# WorkingState Tests
# ===========================================================================

suite "WorkingState":
  test "makeCleanWorkingState fixture":
    let ws = makeCleanWorkingState()
    check ws.isClean == true
    check ws.hasStagedChanges == false
    check ws.hasUnstagedChanges == false
    check ws.hasUntrackedFiles == false

  test "makeDirtyWorkingState fixture":
    let ws = makeDirtyWorkingState()
    check ws.isClean == false
    check ws.hasStagedChanges == true
    check ws.hasUnstagedChanges == true
    check ws.hasUntrackedFiles == false

  test "defaultWorkingState is clean":
    let ws = defaultWorkingState()
    check ws.isClean == true

  test "WorkingState JSON roundtrip":
    let original = makeDirtyWorkingState()
    let node = toJson(original)
    let restored = workingStateFromJson(node)
    check restored.isClean == original.isClean
    check restored.hasStagedChanges == original.hasStagedChanges
    check restored.hasUnstagedChanges == original.hasUnstagedChanges
    check restored.hasUntrackedFiles == original.hasUntrackedFiles

  test "WorkingState JSON preserves all booleans independently":
    let ws = WorkingState(
      isClean: false, hasStagedChanges: true,
      hasUnstagedChanges: false, hasUntrackedFiles: true
    )
    let node = toJson(ws)
    let restored = workingStateFromJson(node)
    check restored.hasStagedChanges == true
    check restored.hasUnstagedChanges == false
    check restored.hasUntrackedFiles == true

# ===========================================================================
# Verdict Tests
# ===========================================================================

suite "Verdict":
  test "makeConflictVerdict fixture":
    let v = makeConflictVerdict()
    check v.hasBlockers == true
    check v.status.len == 2
    check "conflict" in v.status
    check v.issues.len == 2

  test "makeCleanVerdict fixture":
    let v = makeCleanVerdict()
    check v.hasBlockers == false
    check v.status.len == 0
    check v.issues.len == 0

  test "defaultVerdict has no blockers":
    let v = defaultVerdict()
    check v.hasBlockers == false

  test "Verdict JSON roundtrip":
    let original = makeConflictVerdict()
    let node = toJson(original)
    let restored = verdictFromJson(node)
    check restored.status == original.status
    check restored.issues == original.issues
    check restored.hasBlockers == original.hasBlockers

# ===========================================================================
# ConflictInfo Tests
# ===========================================================================

suite "ConflictInfo":
  test "makeConflictInfoFixture fields":
    let ci = makeConflictInfoFixture()
    check ci.baseBranch == "main"
    check ci.files.len == 2
    check "src/main.nim" in ci.files
    check "tests/unit_test.nim" in ci.files

  test "ConflictInfo JSON roundtrip":
    let original = makeConflictInfoFixture()
    let node = toJson(original)
    let restored = conflictInfoFromJson(node)
    check restored.files == original.files
    check restored.baseBranch == original.baseBranch

  test "ConflictInfo empty files":
    let ci = ConflictInfo(files: @[], baseBranch: "develop")
    let node = toJson(ci)
    let restored = conflictInfoFromJson(node)
    check restored.files.len == 0
    check restored.baseBranch == "develop"

# ===========================================================================
# Cross-Type Integration: Full Conflict Scenario
# ===========================================================================

suite "Full conflict scenario integration":
  test "complete merge conflict workflow via schema types":
    # 1. Git operation fails
    let gitErr = makeGitConflictError()
    check gitErr.kind == gitErrMergeConflict

    # 2. Merge result captures conflict state
    let mergeRes = makeMergeConflictData()
    check mergeRes.conflict == true
    check mergeRes.conflictFiles.len == 3

    # 3. Verdict reports blockers
    let verdict = makeConflictVerdict()
    check verdict.hasBlockers == true

    # 4. ConflictInfo provides detail
    let conflictInfo = makeConflictInfoFixture()
    check conflictInfo.baseBranch == "main"
    check conflictInfo.files.len == 2

    # 5. Working state is dirty
    let ws = makeDirtyWorkingState()
    check ws.isClean == false
    check ws.hasStagedChanges == true

    # 6. Repository snapshot
    let repo = makeRepositoryFixture()
    check repo.localState.currentBranch == "feature/new-api"

    # 7. All types serialize to JSON without error
    let payload = %*{
      "error": toJson(gitErr),
      "mergeResult": toJson(mergeRes),
      "verdict": toJson(verdict),
      "conflictInfo": toJson(conflictInfo),
      "workingState": toJson(ws),
      "repository": toJson(repo)
    }
    check payload.kind == JObject
    check payload.hasKey("error")
    check payload.hasKey("mergeResult")

  test "branch type inference in conflict scenario":
    let repo = makeRepositoryFixture()
    let bt = parseBranchType(repo.localState.currentBranch)
    check bt == btFeature

    let hotfixBt = parseBranchType("hotfix/urgent-patch")
    check hotfixBt == btHotfix
