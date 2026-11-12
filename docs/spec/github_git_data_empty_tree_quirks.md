# GitHub Git Data API — empty-tree quirks

> Quirk Mandate record (AGENTS.md §0.5). Platform behavior observed live;
> consumers must not depend on the undocumented half of it.

## Q1. `GET /git/trees/{empty_tree_oid}` → 404 Not Found, permanently

The well-known empty-tree OID `4b825dc642cb6eb9a060e54bf8d69288fbee4904` is
refused by the trees endpoint: `GET /repos/{owner}/{repo}/git/trees/4b825dc6…`
returns **404 Not Found**, stably (re-tested ~40 minutes apart — not
replication lag). This holds even though the object is universally
addressable in git itself.

## Q2. The 404 propagates through commit dereference

`GET /git/trees/{commit_sha}` normally dereferences a commit SHA to its tree
(observed live: a non-empty tip commit → 200). But when the commit's tree IS
the empty tree, the dereference lands on Q1 and the request **404s**. Observed
failure (Evidence CAS run `37417742964`, 2026-10-06T05:24Z): the freshly rooted
`refs/heads/axiom/evidence-cas` tip (a root commit whose tree is the empty
tree) failed its exactly-once re-check with
`GET /git/trees/<root_commit_sha>?recursive=1 → 404 Not Found` — the append
failed closed and left the ref rooted at the empty-tree commit ("poisoned"
state: every later tree read at that tip 404s the same way).

Consumer impact: any side-ref ledger read that builds
`/git/trees/{tip}?recursive=1` straight from a commit tip fails closed on a
freshly rooted (entry-less) ledger — and on any ledger later found in that
state.

Rule: **resolve the tip first** (`GET /git/commits/{tip}` → `.tree.sha`, see
`LedgerTransport`-based `resolveTipTreeSha` in
`src/verification/ledger_side_ref.nim`) and answer a resolved `EmptyTreeSha`
with a **positive empty listing** before any trees call — never by sniffing
the 404. A 404 on any non-empty tree remains a fail-closed error. The
exactly-once re-check additionally skips the attempt that just created the
ledger root (a freshly rooted ledger contains nothing by construction).
