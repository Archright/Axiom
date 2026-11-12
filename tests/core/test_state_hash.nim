import unittest
import core/observer/types
import core/observer/state_hash

suite "assertSyncProtocol - Gate 0":
  test "valid metadata on main branch returns true":
    let meta = GitMetadata(
      currentBranch: "main",
      isDetached: false,
      hasUncommittedChanges: false,
      syncBranchToken: false
    )
    check assertSyncProtocol(meta) == true

  test "valid metadata with sync authorization returns true":
    let meta = GitMetadata(
      currentBranch: "feature/my-feature",
      isDetached: false,
      hasUncommittedChanges: false,
      syncBranchToken: true
    )
    check assertSyncProtocol(meta) == true

  test "detached HEAD raises SyncProtocolError":
    let meta = GitMetadata(
      currentBranch: "HEAD",
      isDetached: true,
      hasUncommittedChanges: false,
      syncBranchToken: false
    )
    var caught = false
    try:
      discard assertSyncProtocol(meta)
    except SyncProtocolError:
      caught = true
    check caught

  test "uncommitted changes raises SyncProtocolError":
    let meta = GitMetadata(
      currentBranch: "main",
      isDetached: false,
      hasUncommittedChanges: true,
      syncBranchToken: false
    )
    var caught = false
    try:
      discard assertSyncProtocol(meta)
    except SyncProtocolError:
      caught = true
    check caught

  test "sync violation raises SyncProtocolError":
    let meta = GitMetadata(
      currentBranch: "develop",
      isDetached: false,
      hasUncommittedChanges: false,
      syncBranchToken: false
    )
    var caught = false
    try:
      discard assertSyncProtocol(meta)
    except SyncProtocolError:
      caught = true
    check caught
