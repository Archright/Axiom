# Command Policy Architecture — 3-Layer Deterministic Enforcement

## Overview

Agent 명령어 실행을 결정론적으로 통제하는 3-Layer 방어 시스템.

**핵심 아이디어**: AST 기반 보안 분석으로 안전한 명령어의 동적 구문을 허용하면서도, 위험한 명령어/패턴은 결정론적으로 차단한다.

## Layer Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Layer 0: PreToolUse Hook → command_policy_gate.nim          │
│   AST 기반 보안 분석 (shell_ast_analyzer).                    │
│   Compile-Time Policy AST (P11).                            │
│   입력: stdin JSON { "tool_input": { "command": "..." } }   │
│   출력: exit 0 (allow), exit 2 (block)                      │
├─────────────────────────────────────────────────────────────┤
│ Layer 1: .agent-bin/git → git_wrapper.nim                   │
│   실행 계층. structured argv (P5).                           │
│   Git alias resolution (P7). envp sanitization (P12).       │
│   commandLineParams() → 정책 대조 → startProcess(realGit)    │
├─────────────────────────────────────────────────────────────┤
│ Layer 2: /usr/bin/git = git_wrapper (Container bind-mount)  │
│   Container sandbox hardening (P10).                        │
│   mv /usr/bin/git /usr/bin/git.real + cp wrapper /usr/bin/  │
│   /tmp noexec + /dev/shm noexec + network egress block      │
└─────────────────────────────────────────────────────────────┘
```

## Applied Patches (12 total)

| # | Patch | Layer | Description |
|---|-------|-------|-------------|
| 1 | Option-argument handling | L0 | `FlagsWithArgs`: `-C`, `-c`, `--git-dir`, etc. |
| 2 | Shell operator splitting | L0 | `&&`, `\|\|`, `;`, `\|` with quote preservation |
| 3 | Fail-Closed | L0 | All try-catch → exit 2 |
| 4 | Wrapper skipping | L0 | `env`, `sudo`, `stdbuf`, etc. |
| 5 | Execution-Layer Wrapper | L1 | `commandLineParams()` → clean argv |
| 6 | Container Bind-Mount | L2 | `mv /usr/bin/git /usr/bin/git.real` |
| 7 | Git Alias Resolution | L1 | `git config --get alias.X` → resolve |
| 8 | splitByOperators fix | L0 | `block` → `opMatched` flag pattern |
| 9 | AST-Based Security Analysis | L0 | `shell_ast_analyzer.nim`: POSIX tokenizer 기반 보안 분석. 명령어별 위험도 평가. 안전한 명령어의 동적 구문 허용. |
| 10 | Container Sandbox | L2 | `/tmp` noexec + network egress block |
| 11 | Compile-Time Policy AST | L0+L1 | `staticRead` + `macro` → binary embedding |
| 12 | envp Whitelist | L1 | `GIT_EXTERNAL_DIFF`, `LD_PRELOAD`, etc. → strip |

## Bypass Vector Matrix

| # | Vector | L0 | L1 | L2 |
|---|--------|----|----|-----|
| 1 | `git merge main` | ✅ | ✅ | ✅ |
| 2 | `git -C . merge main` | ✅ P1 | ✅ P1 | ✅ P1 |
| 3 | `git "merge" main` | ✅ quote | ✅ argv | ✅ argv |
| 4 | `git merge && git push` | ✅ P2+P8 | N/A | N/A |
| 5 | `env git merge main` | ✅ P4 | ✅ P4 | ✅ P4 |
| 6 | `/usr/bin/git merge` | ✅ | ❌ | ✅ bind |
| 7 | `X=a; git $X main` | ✅ P9 | N/A | N/A |
| 8 | `$(echo git) merge` | ✅ P9 | N/A | N/A |
| 9 | `git mg main` (alias) | ❌ | ✅ P7 | ✅ P7 |
| 10 | `eval "git merge"` | ❌ | ✅ argv | ✅ argv |
| 11 | `/tmp/git merge` (download) | ✅ P9 | ❌ | ✅ noexec |
| 12 | `GIT_SSH_COMMAND=x git push` | ✅ P9 | ✅ P12 | ✅ |
| 13 | argv[0] 변조 | ❌ | ✅ | ✅ |

**Coverage**: Local 11/13 | Container 13/13

## Runtime Environment Constraints

| Constraint | Verified | Impact |
|------------|----------|--------|
| Kimi Code CLI = raw shell string only | stdin JSON analysis | Alternative A (structured tool) impossible |
| `Seccomp: 0` (no active filters) | `/proc/self/status` | seccomp applicable (Phase 2) |
| Nim C FFI `{.importc, header.}` | Context7 — posix.nim precedent | syscall binding possible |
| `std/shell` does not exist | Context7 verified | Custom POSIX tokenizer needed |

## Phase 2 Roadmap (Future)

| Component | Technology | Status |
|-----------|-----------|--------|
| Seccomp User Notification | Nim C FFI → `prctl` + BPF | Designed |
| Executable Identity (inode) | `/proc/[pid]/exe` → `readlink` → `stat` | Designed |
| envp Kernel Validation | `/proc/[pid]/environ` → whitelist | Designed |
| Landlock LSM | File system + execution permission | Designed |
| TOCTOU Mitigation | `SECCOMP_USER_NOTIF_FLAG_CONTINUE` | Designed |

## Policy SSOT

- `data/command_policy.json` — Runtime policy (read at compile time via `staticRead`)
- `src/gate/manifest.d/` — Gate registry (per-gate JSON files, compiled by `gate_codegen.nim`)
- `docs/spec/command_policy_architecture.md` — This document
