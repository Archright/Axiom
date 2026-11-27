# Pre-Push Hook Environment Quirks (Windows Host, Git Bash, WSL2)

> AGENTS.md §0.5 Quirk Mandate - measured 2026-11-27 while landing a docs-only
> change from a Git Bash shell on a WSL-hosted clone.
> This document records observed behavior only. It changes no code, no hook, and
> no policy: `.githooks/**` is FROZEN, so every resolution below is an operator
> rule, not a patch.

**Environment**

- Windows 11 25H2, Git for Windows (Git Bash) as the outer shell.
- WSL2 Ubuntu-24.04, kernel 6.6.87.2-microsoft-standard-WSL2, WSL 2.6.3.0.
- Nim 2.2.10: the Linux build inside WSL, the Windows build on the host.
- Repository at /home/wintr/develop/Axiom in the WSL filesystem, worktrees at
  /home/wintr/<name>. From Git Bash both are reachable only as the UNC path
  //wsl.localhost/Ubuntu-24.04/home/wintr/...

## Q1 - The pre-push hook is WSL-only

**Symptom.** `git push` from Git Bash on the UNC path stops inside the hook and
prints nothing beyond the first build line and the ref-update failure. The same
push from WSL passes.

**Evidence.** Verbatim output of the Git Bash push:

```text
[Hook] Building gate_tier_integrity...
error: failed to push some refs to 'https://github.com/Archright/Axiom.git'
```

Stamps written by a passing WSL push under `.cache/axiom/prepush/gates/*.stamp`
record:

```text
META_HOST=Linux 6.6.87.2-microsoft-standard-WSL2
CLOSURE:/home/wintr/develop/Axiom/src/...
```

`which make` in Git Bash prints `which: no make in (...)` and no mingw32-make is
installed. Its `sha256sum` and `nim` cannot satisfy the Merkle guard either (Q2).

**Root cause.** Two independent barriers, in the order the hook hits them:

1. Part 1 (`.githooks/pre-push:507-508`) prints `[Hook] Building
   gate_tier_integrity...` and compiles with the Windows `nim`. On a UNC project
   root that compile fails the Merkle guard (Q2; reproduced 2026-11-27 by running
   the identical command from Git Bash in a `//wsl.localhost/...` worktree), and
   Part 1 discards the compiler output (Q3), so `set -e` aborts the hook with
   nothing but the two lines above.
2. Part 4a rebuilds the seven `GATE_PAIRS` binaries with `make -B bin/<gate>`,
   captures each closure with `nim genDepend` over POSIX absolute paths, and
   digests the binary with `sha256sum`. Git Bash has no `make` at all (no
   `mingw32-make` either), so neither the rebuild nor the capture step can
   complete in that shell.

Parts 1/3 discarding diagnostics (Q3) is what makes both barriers look like the
same silent failure.

**Resolution.** Run every `git push` from WSL:

```bash
wsl.exe -e bash -lc 'cd /home/wintr/<worktree> && git push ...'
```

Never `--no-verify`.

## Q2 - Windows coreutils sha256sum on backslash paths breaks the Merkle guard

**Symptom.** A Windows `nim` compiling any module that loads config/integrity.nims
aborts with a Merkle-guard message even though the four guarded files are
untouched. The message names the command and prints the raw `sha256sum` output.

**Evidence.** Verbatim output of
`nim c -d:danger --hints:off -o:bin/gate_tier_integrity tools/gate_tier_integrity.nim`
from Git Bash in `//wsl.localhost/Ubuntu-24.04/home/wintr/wt-frozen-prune`:

```text
[integrity] GUARD THE GUARD (Merkle Root): sha256sum did not return one digest per guarded file
  command: sha256sum \\wsl.localhost\Ubuntu-24.04\home\wintr\wt-frozen-prune\src\core\trusted\architecture_invariants.nim \\wsl.localhost\Ubuntu-24.04\home\wintr\wt-frozen-prune\src\core\trusted\axiom_pragmas.nim \\wsl.localhost\Ubuntu-24.04\home\wintr\wt-frozen-prune\src\core\trusted\effect_types.nim \\wsl.localhost\Ubuntu-24.04\home\wintr\wt-frozen-prune\src\core\trusted\effect_bridge.nim
  output:  \3da71963b18c1988ff17fb6547b99b05d19ada8f5aa2a954f08857e5949e92e6 *\\\\wsl.localhost\\Ubuntu-24.04\\home\\wintr\\wt-frozen-prune\\src\\core\\trusted\\architecture_invariants.nim
\9be7ef910000c83e94eb14cad1ce67b14709bf9f19801d813a7e7084eb356ec2 *\\\\wsl.localhost\\Ubuntu-24.04\\home\\wintr\\wt-frozen-prune\\src\\core\\trusted\\axiom_pragmas.nim
\23a75e4a56c8cf38b5dd7b3cc7ee32741bb2488255dbc39d9f09608e72f51365 *\\\\wsl.localhost\\Ubuntu-24.04\\home\\wintr\\wt-frozen-prune\\src\\core\\trusted\\effect_types.nim
\15a79be1cb3df2c07349fe0eaf9f94f7a79f6cca33f4f3fe7cd98bb52e55e729 *\\\\wsl.localhost\\Ubuntu-24.04\\home\\wintr\\wt-frozen-prune\\src\\core\\trusted\\effect_bridge.nim
EXIT=1
```

**Root cause.** config/integrity.nims:77-98 builds one
`sha256sum <four guarded files>` command through `gorge` and requires each output
line's `fields[0]` to be a 64-character lowercase hex digest. With the Windows
`nim` build and a UNC `projectRoot`, the paths reach GNU sha256sum with
backslashes. sha256sum detects a backslash in a filename and switches to its
escaped-filename output form: the line is prefixed with `\` and every backslash
in the name is doubled, so `fields[0]` is 65 characters (`\` plus 64 hex) and
fails the length test, then `quit(1)`. The guard failed closed on the path FORM;
the guarded bytes were unchanged.

**Evidence that content is intact.** The same compile under WSL `nim` prints:

```text
[integrity] merkle root OK: 6f77cf2b8a9d092bc0965f5cd572cafbe1deb32ebda9f2b207617bad7bc5fc0e
```

**Resolution.** Build in WSL. Do not shim `sha256sum` and do not edit
config/integrity.nims: the guard's rejection is correct for the input form it was
given.

## Q3 - Parts 1 and 3 swallow compile diagnostics

**Symptom.** A compile-time `quit(1)` inside the hook surfaces only as the two
lines shown in Q1. No compiler message, no failing command, no exit code.

**Evidence.** `.githooks/pre-push:508` (Part 1) and `.githooks/pre-push:533`
(Part 3) both discard stdout and stderr:

```bash
nim c -d:danger --hints:off -o:bin/gate_tier_integrity tools/gate_tier_integrity.nim > /dev/null 2>&1
```

The stamp path (Part 4a) deliberately prints the exact manual command instead
(`.githooks/pre-push:720`, `Run: make -B bin/$gate`). Parts 1/3 predate that
diagnostic contract.

**Root cause.** Both redirects collapse compiler output into `/dev/null`, and
`set -e` turns the non-zero exit into an immediate hook exit. The hook stays
fail-closed, but a failing invocation is guaranteed to look like a silent
failure.

**Resolution.** Diagnose by running the exact `nim` command from the hook line in
the same environment. Do not edit the hook (`.githooks/**` is FROZEN).
Follow-up candidate, recorded only: emit a fail-closed message carrying the exact
command, mirroring Part 4a. No change accompanies this document.

## Q4 - Nothing under src/gate or tests compiles before bin/ax exists

**Symptom.** `[Integrity Violation] bin/ax is missing. Run: nimble build first.`
during a hook build in a fresh worktree.

**Evidence.** config/integrity.nims:148-159 (SourceCoherence guard) blocks any
compile whose current directory is under src/gate or tests while `bin/ax` is
absent. Observed when Part 3 built src/gate/runners/layer_enforcement_gate.nim in
a fresh worktree whose `bin/` was empty.

**Root cause.** The guard binds the gate/test domain to a built CLI, and a fresh
worktree starts with an empty `bin/`, so the hook's own gate build is the first
compile in that domain.

**Resolution.** In WSL, in the worktree:

```bash
make build && make gate-binaries
```

(about 3 minutes). `make build` rewrites the tracked file
src/generated/build_metadata.json, so revert it
(`git checkout -- src/generated/build_metadata.json`) rather than committing build
noise (see docs/spec/build_metadata_stamp_porcelain_quirk.md).

## Q5 - WSL2 NAT can lose all outbound TCP while DNS still resolves

**Symptom.** Name resolution works and every TCP connect fails; `wsl --shutdown`
followed by a restart does not restore connectivity.

**Evidence (2026-11-27).**

- `getent hosts github.com` answers via resolver 10.255.255.254.
- TCP connect fails to 1.1.1.1:443, 8.8.8.8:53, github.com:443, api.github.com:443,
  and the gateway 172.17.112.1.
- `wsl --shutdown` did not restore it.
- `Get-NetNat` showed no NAT object.

**Workaround that worked.** Create C:\Users\wintr\.wslconfig with:

```ini
[wsl2]
networkingMode=mirrored
```

then run `wsl --shutdown`. Verified afterwards: `wslinfo --networking-mode` prints
`mirrored` and `git ls-remote origin HEAD` succeeds. Prerequisite: Windows 11
22H2+ with WSL 2.x.

**Root cause (as observed).** The resolver at 10.255.255.254 stayed reachable
while the NAT egress path was gone, and no NAT object remained on the host. The
mechanism that removed it was not measured; mirrored mode replaces the NAT path
with a mirrored interface and restored egress.

**Consequence for this repo.** With WSL networking down no push can pass the
pre-push hook (Q1), because the hook only runs in WSL and no Git Bash fallback
exists.

## Q6 - Publication script-scan judges ADDED LINES against an allowed-script set

**Symptom.** Korean text in a new docs/evidence file passed every PR-venue check
and failed only in the merge_group `script-scan` job, after the branch was already
green.

**Evidence.** The merge_group job printed:

```text
publication_script_eval: FAIL (added=92, violations=652, unknowns=0)
```

**Root cause.** The script-scan dimension evaluates added lines only and allows
the ASCII range plus the Latin, Greek, Common, and Inherited scripts; the
`pull_request` venue does not run that dimension, so a branch can look green and
still fail at merge_group. Policy is compliance/policy/script-scan-policy.yml and
the judge is tools/ci/publication_script_eval.nim. The rule, its limitations, and
the incident history are owned by docs/spec/publication_script_scan_quirks.md
(SSOT) and are not restated here.

**Resolution.** Keep every added line ASCII (the way this document is written).
Reproduce the verdict locally in seconds with `make preflight-script-scan`
(tools/ci/preflight_script_scan.nim, issue #422). Run it AFTER committing: it
diffs HEAD against merge-base(origin/main, HEAD), so uncommitted edits are
invisible to it.

## Status

All six quirks were observed on 2026-11-27 on the environment above. Q1, Q2, and
Q4 are resolved by operating in WSL (build and push); Q5 is resolved by
`networkingMode=mirrored`; Q6 is resolved by writing ASCII; Q3 is documented only
and stays a follow-up candidate because `.githooks/**` is FROZEN. No gate, hook,
workflow, or policy behavior is changed by this record.

## Related

- `.githooks/pre-push` (Part 1, Part 3, Part 4a)
- config/integrity.nims
- docs/spec/nim_gendepend_quirks.md
- docs/spec/build_metadata_stamp_porcelain_quirk.md
- docs/spec/publication_script_scan_quirks.md
- docs/agents/constitution_details.md (section 0.5b quirk list)