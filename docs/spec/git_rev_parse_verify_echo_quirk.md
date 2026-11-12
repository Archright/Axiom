# git rev-parse --verify full-OID echo quirk (object-existence bypass)

Status: documented 2026-11-02 (discovered during the ③ u64 slice cold
acceptance at MERGE_SHA `d1e59a9f5b33dc4ea78537e5f6e01249fb8a5622`; cost:
one immediate `WORKTREE FAIL` runner cycle).

## 1. Symptom

A cold-acceptance runner invoked `git worktree add --detach <path> <sha>`
for a merge SHA that existed only on the remote — the local object store
had not been fetched since the GitHub-native merge. git correctly failed:

    fatal: 잘못된 레퍼런스: d1e59a9f5b33dc4ea78537e5f6e01249fb8a5622

The trap was the quick existence check afterwards:

    git rev-parse --verify d1e59a9f5b33dc4ea78537e5f6e01249fb8a5622
    → d1e59a9f5b33dc4ea78537e5f6e01249fb8a5622   (exit 0, echoed)

    git cat-file -t d1e59a9f5b33dc4ea78537e5f6e01249fb8a5622
    → fatal: git cat-file: could not get object info

The echo suggested the object was local; `cat-file` proved it was not.

## 2. Root Cause

For a syntactically valid full 40-hex OID, `git rev-parse --verify` treats
the string as an already-resolved OID and echoes it; in this git build
(2.43.0) the `--verify` flag does not force an object-database lookup for
full OIDs. The echoed text is a SYNTAX acceptance, not an EXISTENCE
attestation. (Ref resolution and abbreviated SHAs behave differently —
they do hit the object database.)

## 3. Correct pattern

- Object existence authority: `git cat-file -t <oid>` (or `git log -1
  <oid>`), never `rev-parse --verify` on a full OID.
- A local clone never learns remote merge commits by itself: after
  `gh pr merge`, run `git fetch origin <branch>` BEFORE creating a
  detached worktree at the merge SHA, and cross-check the commit
  (`cat-file -t` → `commit`, parents verified).

## 4. Observed environment

git 2.43.0 (Ubuntu), Axiom4 main clone, 2026-11-02.
