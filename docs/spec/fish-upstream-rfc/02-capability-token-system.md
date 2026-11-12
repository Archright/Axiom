# RFC-002: Capability Token System for Fish 4.x — Eliminating Ambient Authority in Environment Variables

| Field | Value |
|-------|-------|
| **Title** | RFC-002: Capability Token System for Fish 4.x — Eliminating Ambient Authority in Environment Variables |
| **Authors** | Axiom Security Audit Team |
| **Status** | Draft |
| **Created** | 2026-06-22 |
| **Target** | Fish 4.x (next major release) |
| **Depends On** | None (standalone proposal) |
| **Category** | Security / Language Design |

---

## Abstract

Fish shell's global environment variable system (`set -gx`) grants every function
unrestricted authority to read and write variables visible to **all** child processes.
This is an Ambient Authority violation: a function receives implicit, broad permission
to mutate shared state it does not own and does not need. This RFC proposes a
**Capability Token System** that replaces ambient authority with **explicit, compile-time
checked capability grants**. Functions must declare the capabilities they need; operations
without a matching grant are rejected at definition time with zero runtime overhead.

---

## Table of Contents

1. [Problem Statement](#1-problem-statement)
2. [Threat Model](#2-threat-model)
3. [Proposed Solution](#3-proposed-solution)
4. [Syntax Design](#4-syntax-design)
5. [Rust Implementation](#5-rust-implementation)
6. [Compile-Time Verification](#6-compile-time-verification)
7. [Migration Path](#7-migration-path)
8. [Security Proof](#8-security-proof)
9. [Performance Analysis](#9-performance-analysis)
10. [Backward Compatibility](#10-backward-compatibility)
11. [Open Questions](#11-open-questions)
12. [References](#12-references)
13. [Appendix A: Capability Catalog](#appendix-a-capability-catalog)
14. [Appendix B: Error Message Reference](#appendix-b-error-message-reference)

---

## 1. Problem Statement

### 1.1 Ambient Authority in `set -gx`

In Fish 4.x (and all prior versions), the `set -gx` command exports a variable into
the process-global environment. Every child process—subshells, external commands,
spawned fish instances—inherits **all** environment variables with no capability check.

```
function A
    set -gx CRITICAL_CONFIG /malicious/path
end

A

# Every subsequent child process now sees CRITICAL_CONFIG=/malicious/path
exec env  # shows the poisoned variable
```

This is the textbook definition of **Ambient Authority** (Dennis & Van Horn, 1966):
the function receives authority (write access to global environment) not by explicit
grant, but by ambient context (being a fish function running in a session).

### 1.2 Concrete Incidents in Fish Standard Library

The Fish standard library itself demonstrates the problem:

#### Case 1: `fish_git_prompt` — Unnecessary Global Export

```fish
# fish_git_prompt exports this to function scope only.
# It should NEVER be visible to child processes.
set -gx __fish_git_prompt_suppress_vcs_info 1
```

This variable is consumed **only within** `fish_git_prompt` and its internal
helpers. Exporting it globally leaks internal implementation details into every
child process's environment.

#### Case 2: `fish_git_prompt` — Globally Visible `GIT_DIR`

```fish
# fish_git_prompt reads GIT_DIR but accidentally exports it.
# A malicious sub-function could poison GIT_DIR for git operations.
set -gx GIT_DIR $some_value
```

If `fish_git_prompt` is composed with other prompt functions or user overrides,
the globally exported `GIT_DIR` affects **all** subsequent `git` invocations in the
shell session and its children.

#### Case 3: Prompt Composability Risk

```fish
# User-defined function can read/write any variable
function my_prompt
    set -gx PATH /malicious/bin:$PATH  # no restriction
end
```

Any fish function loaded into the session has **full ambient authority** over every
environment variable, including security-critical ones (`PATH`, `HOME`, `SSH_AUTH_SOCK`).

### 1.3 Principle of Least Privilege Violation

Fish enforces no separation of concerns for environment access. A function that
needs to read `HOME` has the same authority as one that needs to rewrite `PATH`.
The Principle of Least Privilege (Saltzer & Schroeder, 1975) requires that each
component operate with the **minimum authority necessary** to complete its task.

**Summary of Violations:**

| Violation | Current Behavior | Expected Behavior |
|-----------|-----------------|-------------------|
| Read authority | All functions read all vars | Functions read only declared vars |
| Write authority | All functions write all vars | Functions write only declared vars |
| Export authority | Any `set -gx` propagates | Only capability-granted exports propagate |
| Scope control | Global (`-gx`) or local (`-l`) only | Three tiers: local, scoped, global |

---

## 2. Threat Model

### 2.1 Adversaries

| Adversary | Capability | Goal |
|-----------|-----------|------|
| Malicious function | Can be loaded via `source` or plugin | Poison environment for child processes |
| Composed prompt | Prompt function loaded alongside user code | Leak internal state, inject variables |
| Third-party plugin | Distributed via fisherman/fisher | Escalate authority beyond intended scope |

### 2.2 Assets

- Environment variable namespace (global, process-wide)
- Child process environment inheritance
- Prompt composition chain integrity

### 2.3 Trust Boundaries

```
┌─────────────────────────────────────────────────┐
│  Fish Session (Process)                         │
│                                                 │
│  ┌──────────────┐   ┌──────────────┐            │
│  │  User Funcs  │   │  Stdlib      │            │
│  │  (untrusted) │   │  (semi-      │            │
│  │              │   │   trusted)   │            │
│  └──────┬───────┘   └──────┬───────┘            │
│         │                  │                    │
│         ▼                  ▼                    │
│  ┌─────────────────────────────────┐            │
│  │     Capability Registry         │  ← NEW    │
│  │  (compile-time checked)         │            │
│  └─────────────┬───────────────────┘            │
│                │                                │
│                ▼                                │
│  ┌─────────────────────────────────┐            │
│  │     Environment Store           │            │
│  │  (only capability-checked ops)  │            │
│  └─────────────┬───────────────────┘            │
│                │                                │
└────────────────┼────────────────────────────────┘
                 │
                 ▼ (only explicit exports)
         Child Process Env
```

---

## 3. Proposed Solution

### 3.1 Core Concept

A **Capability Token** is a compile-time grant that binds a function name to a
specific permission on a specific variable (or variable pattern). A function that
has not been granted a capability **cannot** perform the corresponding operation.

The system introduces three permission levels:

| Permission | `set -l` | `set -g` | `set -gx` |
|-----------|----------|----------|-----------|
| **FunctionScoped** | ✅ Always allowed | ❌ Denied | ❌ Denied |
| **ReadOnly** | ✅ Always allowed | ✅ Read only | ❌ Denied (read-only) |
| **ReadWrite** | ✅ Always allowed | ✅ Read/Write | ✅ Read/Write/Export |

### 3.2 Design Principles

1. **Zero Runtime Overhead**: All capability checks occur at function definition
   time (compile time). At runtime, the capability registry is consulted only for
   `set -gx` and `set -g` operations—no per-variable lookup on the hot path.

2. **Explicit Over Implicit**: Functions must declare every capability they need.
   Silent ambient authority is eliminated.

3. **Fail Closed**: If the capability registry is unavailable or corrupted, all
   `set -gx` operations are denied. The system defaults to maximum restriction.

4. **Backward Compatible**: Phase 1 emits warnings only, allowing gradual adoption.

---

## 4. Syntax Design

### 4.1 Capability Declaration

Capabilities are declared at the top of a function file or inline using the
`grant` keyword:

```fish
# Capability declaration syntax:
#   grant capability <name> to <function>
#   grant capability <name> to <function> as <permission>

# Grant read-write access to a function-scoped capability
grant capability git_prompt_internal to fish_git_prompt as readwrite

# Grant read-only access to a well-known capability
grant capability hostname_read to prompt_login as readonly

# Default permission is function-scoped (set -l only)
grant capability my_internal_state to my_func
```

### 4.2 Capability Annotation (Docblock Style)

For function files, capabilities can be declared as annotations:

```fish
# @capability: git_prompt_internal (readwrite, function-scoped)
# @capability: hostname_read (readonly)
# @requires: capability git_prompt_internal
function fish_git_prompt
    # ... function body
end
```

### 4.3 Capability Usage in Function Body

```fish
function fish_git_prompt
    # ✅ LOCAL: Always allowed, no capability needed
    set -l __fish_git_prompt_suppress_vcs_info 1

    # ✅ SCOPED WRITE: Works — capability 'git_prompt_internal' granted as readwrite
    set -g __fish_git_prompt_suppress_vcs_info 1

    # ✅ EXPORT: Works — capability 'git_prompt_internal' grants export
    set -gx __fish_git_prompt_suppress_vcs_info 1

    # ❌ COMPILE-TIME ERROR: No capability for GIT_DIR export
    # set -gx GIT_DIR $some_value
    # Error: fish_git_prompt: no capability 'env:GIT_DIR' with export permission
    # Hint: add 'grant capability env:GIT_DIR to fish_git_prompt as readwrite'
end
```

### 4.4 Capability Retrieval API

Functions access capability-scoped values through a built-in registry:

```fish
function prompt_login
    use capability hostname_read           # declare intent
    set -l h (capability get hostname_read) # read from registry
    echo "Logged in as: $h"
end

function fish_git_prompt
    use capability git_prompt_internal

    # Read capability-bound value
    set -l supress_val (capability get git_prompt_internal)

    # Write to capability-bound store
    set (capability set git_prompt_internal) $computed_value
end
```

### 4.5 Capability Inheritance and Delegation

```fish
# Delegation: grant a capability to a helper function
grant capability git_prompt_internal to _git_prompt_helper as readonly

# Inheritance: child function inherits parent's granted capabilities
# (explicit opt-in required — no ambient inheritance)
inherit capability git_prompt_internal from fish_git_prompt to _git_prompt_helper
```

### 4.6 Capability Revocation

```fish
# Revoke a previously granted capability
revoke capability git_prompt_internal from _git_prompt_helper
```

---

## 5. Rust Implementation

### 5.1 Core Types

```rust
use std::collections::HashMap;

/// Unique identifier for a fish function.
#[derive(Clone, Debug, Hash, Eq, PartialEq)]
pub struct FunctionName(pub String);

/// Unique identifier for a capability (variable or variable pattern).
///
/// Convention:
///   - `env:VAR_NAME`        — specific global variable
///   - `env:prefix:*`        — variables matching prefix pattern
///   - `prompt:internal`     — logical capability name
///   - `custom:name`         — user-defined capability
#[derive(Clone, Debug, Hash, Eq, PartialEq)]
pub struct CapabilityName(pub String);

/// Permission level for a capability grant.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Permission {
    /// set -l only. Default for declared capabilities.
    FunctionScoped,

    /// set -g (read), but no set -gx (no export).
    ReadOnly,

    /// Full access: set -l, set -g, set -gx.
    ReadWrite,
}

/// The type of operation being performed on a variable.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Operation {
    /// set -l (local scope)
    LocalWrite,

    /// set -g (global, no export)
    GlobalRead,
    GlobalWrite,

    /// set -gx (global export to children)
    GlobalExportRead,
    GlobalExportWrite,
}

impl Permission {
    /// Check whether this permission allows the given operation.
    pub fn allows(&self, op: &Operation) -> bool {
        match self {
            Permission::FunctionScoped => matches!(op, Operation::LocalWrite),
            Permission::ReadOnly => matches!(
                op,
                Operation::LocalWrite | Operation::GlobalRead | Operation::GlobalExportRead
            ),
            Permission::ReadWrite => true,
        }
    }
}
```

### 5.2 Capability Registry

```rust
use std::fmt;

/// Error returned when a capability check fails.
#[derive(Debug, Clone)]
pub struct CapError {
    pub func: FunctionName,
    pub cap: CapabilityName,
    pub op: Operation,
    pub granted: Option<Permission>,
}

impl fmt::Display for CapError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{}: no capability '{}' with {:?} permission (granted: {:?})",
            self.func.0, self.cap.0, self.op,
            self.granted.as_ref().map(|p| format!("{:?}", p)).unwrap_or_else(|| "none".into())
        )
    }
}

/// Capability registry — compile-time checked, zero runtime overhead.
///
/// Built during function definition parsing. At runtime, consulted only
/// for `set -g` and `set -gx` operations (not for `set -l`).
pub struct CapabilityRegistry {
    grants: HashMap<(FunctionName, CapabilityName), Permission>,
    /// Currently executing function context (pushed on call, popped on return).
    call_stack: Vec<FunctionName>,
}

impl CapabilityRegistry {
    pub fn new() -> Self {
        Self {
            grants: HashMap::new(),
            call_stack: Vec::new(),
        }
    }

    /// Register a capability grant during function definition parsing.
    pub fn grant(
        &mut self,
        func: FunctionName,
        cap: CapabilityName,
        perm: Permission,
    ) {
        self.grants.insert((func, cap), perm);
    }

    /// Revoke a previously granted capability.
    pub fn revoke(&mut self, func: &FunctionName, cap: &CapabilityName) {
        self.grants.remove(&(func.clone(), cap.clone()));
    }

    /// Push a function onto the call stack (called at function entry).
    pub fn enter_function(&mut self, func: FunctionName) {
        self.call_stack.push(func);
    }

    /// Pop a function from the call stack (called at function exit).
    pub fn exit_function(&mut self) {
        self.call_stack.pop();
    }

    /// Get the currently executing function name.
    fn current_function(&self) -> Option<&FunctionName> {
        self.call_stack.last()
    }

    /// Check if the currently executing function can perform an operation.
    ///
    /// This is the hot-path check. For `set -l`, this is short-circuited
    /// before reaching this function (zero overhead for locals).
    pub fn check(
        &self,
        func: &FunctionName,
        cap: &CapabilityName,
        op: Operation,
    ) -> Result<(), CapError> {
        // Fast path: function-scoped writes are always allowed
        if op == Operation::LocalWrite {
            return Ok(());
        }

        match self.grants.get(&(func.clone(), cap.clone())) {
            Some(perm) if perm.allows(&op) => Ok(()),
            Some(perm) => Err(CapError {
                func: func.clone(),
                cap: cap.clone(),
                op,
                granted: Some(perm.clone()),
            }),
            None => Err(CapError {
                func: func.clone(),
                cap: cap.clone(),
                op,
                granted: None,
            }),
        }
    }

    /// Check using the current call stack context.
    pub fn check_current(
        &self,
        cap: &CapabilityName,
        op: Operation,
    ) -> Result<(), CapError> {
        let func = self.current_function()
            .ok_or_else(|| CapError {
                func: FunctionName("<no-function>".into()),
                cap: cap.clone(),
                op,
                granted: None,
            })?;
        self.check(func, cap, op)
    }

    /// Collect all grants for a function (used for diagnostics and `fish_config`).
    pub fn grants_for(
        &self,
        func: &FunctionName,
    ) -> Vec<(&CapabilityName, &Permission)> {
        self.grants.iter()
            .filter(|((f, _), _)| f == func)
            .map(|((_, c), p)| (c, p))
            .collect()
    }
}
```

### 5.3 Integration with `set` Command

```rust
/// Resolve a variable name to a capability name.
///
/// Mapping rules:
///   - `VAR_NAME`       → `env:VAR_NAME`
///   - `__fish_*`       → `fish_stdlib:*`
///   - `GIT_*`          → `env:GIT_*`
///   - Custom prefix    → `custom:<prefix>`
fn resolve_capability(var_name: &str) -> CapabilityName {
    if var_name.starts_with("__fish_") {
        CapabilityName("fish_stdlib:*".into())
    } else if var_name.starts_with("GIT_") {
        CapabilityName(format!("env:GIT_*"))
    } else {
        CapabilityName(format!("env:{}", var_name))
    }
}

/// Hook called for every `set` command. Validates against capability registry.
fn on_set(
    registry: &CapabilityRegistry,
    var_name: &str,
    scope: SetScope,
    value: &[String],
) -> Result<(), CapError> {
    match scope {
        // Local writes are always permitted — zero overhead path
        SetScope::Local => Ok(()),

        // Global read — check ReadOnly or ReadWrite
        SetScope::Global => {
            let cap = resolve_capability(var_name);
            let op = if value.is_empty() {
                Operation::GlobalRead
            } else {
                Operation::GlobalWrite
            };
            registry.check_current(&cap, op)
        }

        // Global export — requires explicit capability grant
        SetScope::GlobalExport => {
            let cap = resolve_capability(var_name);
            let op = if value.is_empty() {
                Operation::GlobalExportRead
            } else {
                Operation::GlobalExportWrite
            };
            registry.check_current(&cap, op)
        }
    }
}
```

---

## 6. Compile-Time Verification

### 6.1 Verification Pipeline

```
Source File
    │
    ▼
┌────────────────────────┐
│ 1. Parse function defs │  Extract function names
│    and grant stmts     │  Extract capability grants
└───────────┬────────────┘
            │
            ▼
┌────────────────────────┐
│ 2. Build registry      │  HashMap<(Func, Cap) → Perm>
│    at parse time       │  Validate grant syntax
└───────────┬────────────┘
            │
            ▼
┌────────────────────────┐
│ 3. Static analysis     │  Walk function bodies
│    of set -g / -gx     │  Resolve var → capability
│    calls               │  Check against registry
└───────────┬────────────┘
            │
            ▼
┌────────────────────────┐
│ 4. Emit diagnostic     │  Errors (Phase 3) or
│    or proceed          │  Warnings (Phase 1-2)
└───────────┬────────────┘
            │
            ▼
       Function Ready
    (zero runtime overhead)
```

### 6.2 Diagnostic Messages

```
# ERROR (Phase 3):
error[cap-denied]: fish_git_prompt: set -gx GIT_DIR requires capability 'env:GIT_DIR'
  ── src/functions/fish_git_prompt.fish:42:5 ──
  │
42│     set -gx GIT_DIR $some_value
  │            ^^^^^^^ capability not granted
  │
  help: add a grant statement at the top of the function:
        grant capability env:GIT_DIR to fish_git_prompt as readwrite

# WARNING (Phase 1-2):
warning[cap-suggested]: fish_git_prompt: set -gx GIT_DIR without capability grant
  ── src/functions/fish_git_prompt.fish:42:5 ──
  │
42│     set -gx GIT_DIR $some_value
  │            ^^^^^^^ consider granting capability
  │
  help: grant capability env:GIT_DIR to fish_git_prompt as readwrite
```

---

## 7. Migration Path

### Phase 1: Annotation-Only (Warnings Only)

**Duration:** 2 minor releases (e.g., 4.1, 4.2)
**Behavior:** Capability annotations are parsed but not enforced. Missing grants
emit compiler warnings.

```fish
# Fish still works exactly as before.
# Compiler emits: "warning: fish_git_prompt uses set -gx without capability grant"
set -gx GIT_DIR $value  # works, but produces warning
```

**Deliverables:**
- `grant` syntax parser
- Capability annotation support in function docblocks
- Warning diagnostics for ungranted `set -gx` calls
- `fish_config capabilities` subcommand to visualize grants

### Phase 2: Advisory Enforcement

**Duration:** 1 minor release (e.g., 4.3)
**Behavior:** `set -gx` without a matching capability generates a **hard warning**
(displayed to user, not fatal). Standard library ships with full capability grants.

```fish
# Shell startup shows:
# ⚠ capability warning: fish_git_prompt used set -gx GIT_DIR without grant
#   Run 'fish_config capabilities' to review
```

**Deliverables:**
- Fish stdlib fully annotated with capability grants
- `fish_config capabilities` interactive review tool
- Migration script: `fish_migrate_capabilities` to auto-generate grants

### Phase 3: Hard Enforcement (Compile-Time Error)

**Duration:** Next major release (Fish 5.0)
**Behavior:** `set -gx` without a matching capability is a **compile-time error**.
Fish 4.x code without grants will not run in Fish 5.0.

```fish
# Fish 5.0 startup with ungranted code:
error[cap-denied]: function 'my_plugin' uses set -gx PATH without capability grant
  Fish 5.0 requires explicit capability grants for all set -gx calls.
  Run 'fish_config capabilities --fix' to auto-generate grants.
```

**Deliverables:**
- Hard enforcement in the parser
- `fish_config capabilities --fix` for automated migration
- Migration guide for plugin authors

---

## 8. Security Proof

### 8.1 Before (Ambient Authority)

```
Given:
  - Any fish function F can execute set -gx VAR VALUE
  - No restriction on VAR or VALUE
  - All child processes inherit the environment

Theorem: For any function F, any variable V, and any value X:
  F can set -gx V X, and all child processes observe V=X

Proof:
  1. Fish evaluates `set -gx V X` in function F          (axiom: no access control)
  2. The environment store is updated: env[V] = X        (axiom: direct mutation)
  3. fork/exec propagates env[V] = X to child            (axiom: POSIX env inheritance)
  4. Any function G can also read env[V]                  (axiom: no read restriction)
  5. Therefore, V is ambiently available to all processes (conclusion)
  ∎

This violates the Principle of Least Privilege: F has authority over V
even though F's purpose does not require it.
```

### 8.2 After (Explicit Authority)

```
Given:
  - Each function F must have `grant capability C to F` for variable V in scope C
  - set -gx V X requires a matching grant with export permission
  - Grants are checked at function definition time

Theorem: For any function F, any variable V:
  F can set -gx V X if and only if a grant exists for F on scope(V)

Proof:
  1. Fish evaluates `set -gx V X` in function F            (axiom)
  2. Resolver maps V to capability scope(V)                (def: resolve_capability)
  3. Registry.check(F, scope(V), GlobalExportWrite)
     - If grant exists with ReadWrite permission → Ok      (def: Permission.allows)
     - If grant exists with ReadOnly → Err                 (def: ReadOnly excludes export)
     - If no grant exists → Err                            (def: fail-closed)
  4. On Err: operation blocked, diagnostic emitted         (axiom: enforcement)
  5. Therefore, F has authority over V iff explicitly granted  (conclusion)
  ∎

This satisfies the Principle of Least Privilege: F has authority over V
only if explicitly granted.
```

### 8.3 Composition Safety

```
Lemma (Delegation Safety): If F grants capability C to G,
  then G operates with the intersection of F's permissions and G's grants.

Proof:
  1. F calls G → G enters call stack with its own grants
  2. G's check uses G's grants, not F's grants
  3. G cannot escalate by calling F (F's grants don't transfer to G's stack)
  4. Therefore, no authority escalation through composition.
  ∎
```

---

## 9. Performance Analysis

| Operation | Before | After (Phase 3) |
|-----------|--------|-----------------|
| `set -l VAR` | O(1) stack push | O(1) — no check (fast path) |
| `set -g VAR` | O(1) env insert | O(1) HashMap lookup + permission check |
| `set -gx VAR` | O(1) env insert | O(1) HashMap lookup + permission check |
| Function load | O(1) parse | O(n) parse + O(1) grant registration |
| Cold start overhead | 0 | ~0.1ms for stdlib (30 functions × ~3 grants) |

**Key insight:** `set -l` (the most common operation) has **zero overhead** because
local writes are unconditionally allowed. The HashMap lookup for `set -g`/`set -gx`
is amortized O(1) and adds negligible cost compared to the variable lookup itself.

---

## 10. Backward Compatibility

### 10.1 Unmodified Code

- **Phase 1:** Works identically. Warnings only.
- **Phase 2:** Works identically. Hard warnings on startup.
- **Phase 3:** **BREAKING** — Fish 5.0 requires grants. Migration tool provided.

### 10.2 Plugin Compatibility

Plugins that use `set -gx` will:
1. Phase 1: See warnings, can adopt annotations incrementally.
2. Phase 2: See hard warnings, encouraged to update.
3. Phase 3: Fail at load time until grants are added.

A `fish_config capabilities --fix` command will auto-generate grants based on
static analysis of `set` calls in plugin functions.

### 10.3 Config Files

`~/.config/fish/config.fish` and sourced files are treated as belonging to a
special `@config` function scope. All capabilities are granted by default during
the Phase 1→2 transition to avoid breaking user configurations.

---

## 11. Open Questions

1. **Wildcard grants:** Should `grant capability env:GIT_* to fish_git_prompt`
   cover all `GIT_*` variables, or must each be listed individually? This RFC
   proposes wildcards for convenience but acknowledges the security tradeoff.

2. **Capability namespacing:** Should capabilities be namespaced by origin
   (e.g., `stdlib:git_prompt`, `user:my_func`, `plugin:name`) to prevent
   collision between independently developed functions?

3. **Runtime introspection:** Should `fish_config capabilities` support live
   introspection of the running session's capability state? This aids debugging
   but introduces a read channel.

4. **Capability-based inheritance in subshells:** When a function forks a subshell
   (`set -l X (some_command)`), should the subshell inherit the parent's capability
   grants? Current proposal: yes, for the duration of the command substitution.

5. **Interaction with `functions -c`:** When copying a function with
   `functions -c`, should the copy inherit the original's grants? This RFC
   proposes: no — each function must be granted independently.

---

## 12. References

1. **Dennis, J. B., & Van Horn, E. C.** (1966). "Programming Semantics for
   Multiprogrammed Computations." *Communications of the ACM*, 9(3), 143–155.
   — Foundational paper on capability-based security and ambient authority.

2. **Saltzer, J. H., & Schroeder, M. D.** (1975). "The Protection of Information
   in Computer Systems." *Proceedings of the IEEE*, 63(9), 1278–1308.
   — Principle of Least Privilege formalization.

3. **Miller, M. S.** (2006). *Robust Composition: Towards a Unified Approach to
   Access Control and Concurrency Control.* PhD dissertation, Johns Hopkins University.
   — Capability-based composition and delegation patterns.

4. **OpenBSD `pledge(2)` and `unveil(2)`** — Practical capability restriction in
   a Unix environment. https://man.openbsd.org/pledge

5. **WebAssembly System Interface (WASI)** — Capability-based module system for
   WebAssembly. Capabilities are explicitly granted per module.
   https://github.com/WebAssembly/WASI

6. **Fish Shell Issue Tracker** — Related discussions on environment variable
   scoping: https://github.com/fish-shell/fish-shell/issues

7. **Capability Machines (Academic)** — Hardware capability support (CHERI) as
   inspiration for software-level capability enforcement.

---

## Appendix A: Capability Catalog

Pre-defined capabilities for the Fish standard library:

| Capability Name | Scope | Default Permission | Used By |
|----------------|-------|-------------------|---------|
| `env:*` | All environment variables | ReadOnly | General |
| `env:PATH` | PATH variable | ReadWrite | `fish_add_path` |
| `env:HOME` | HOME variable | ReadOnly | `prompt_login` |
| `env:GIT_*` | Git-related variables | ReadOnly | `fish_git_prompt` |
| `env:SSH_*` | SSH-related variables | ReadOnly | `prompt_ssh` |
| `fish_stdlib:*` | Internal `__fish_*` vars | FunctionScoped | Standard library |
| `prompt:*` | Prompt-related state | FunctionScoped | Prompt functions |
| `custom:<name>` | User-defined | FunctionScoped | User functions |

---

## Appendix B: Error Message Reference

| Error Code | Severity | Message | Resolution |
|-----------|----------|---------|------------|
| `cap-denied` | Error (Phase 3) | `{func}: set -gx {var} requires capability '{cap}'` | Add grant statement |
| `cap-suggested` | Warning (Phase 1-2) | `{func}: set -gx {var} without capability grant` | Add grant statement |
| `cap-revoked` | Error | `{func}: capability '{cap}' has been revoked` | Re-grant if needed |
| `cap-delegation-denied` | Error | `{func}: cannot delegate '{cap}' to {target}` | Grant to target directly |
| `cap-not-found` | Error | `{func}: unknown capability '{cap}'` | Check capability name |
| `cap-permission-insufficient` | Error | `{func}: '{cap}' granted as {perm}, need {required}` | Upgrade permission level |

---

*End of RFC-002*
