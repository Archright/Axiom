# Compile-time/Runtime Time State Isolation

## Problem

`src/policy/macros/policy_schema_macros.nim` called `now().utc.format("yyyy-MM-dd")`
inside a `{.compileTime.}` proc. `now()` calls `epochTime()`, which is a C FFI
(`importc` function). The Nim VM cannot execute FFI calls → `AssertionDefect` at
compile time.

## Wrong Fix

Using `staticExec("date +%Y-%m-%d")` to capture the host time at compile time:

```nim
let today = staticExec("date +%Y-%m-%d")  # WRONG
```

**Why wrong:**
1. **Host OS dependency** — `date` is a POSIX command; Windows has no equivalent.
2. **Non-deterministic** — compile-time output changes every day, breaking
   reproducible builds and gate cache keys.
3. **Architectural contradiction** — time is mutable runtime state. Freezing it at
   compile time conflates two distinct concerns: schema validation (static) vs.
   expiry enforcement (dynamic).

## Correct Fix

Separate the two concerns:

1. **Compile-time** (`{.compileTime.}` proc): validate that `expiry_date` matches
   the `YYYY-MM-DD` format pattern. This is a structural invariant — it never changes.
2. **Runtime** (`proc main()`): compare `expiry_date` against the current system
   clock to reject expired exemptions.

### Pattern

```nim
# Compile-time: format validation only
proc validateExemptions(entries: seq[ExemptionEntry]) {.compileTime.} =
  for e in entries:
    let expiry = $e.expiry_date
    if expiry.len != 10 or expiry[4] != '-' or expiry[7] != '-':
      macros.error("...")

# Runtime: expiry check with injected time
func isExempt(path: string, today: string): bool =
  for e in PythonShellExemptions:
    if string(e.path) == path:
      if today >= string(e.expiry_date):
        return false  # expired
      return true
  false

# I/O boundary: call now() only in proc main()
proc main() =
  let today = now().utc.format("yyyy-MM-dd")
  if isBanned(f, today):
    ...
```

### Principle

> "Time is a mutable runtime state. Freezing it at compile time is an
> architectural contradiction."

### Rule

- `isExempt(path, today)` — pass time as a parameter to keep `func` pure.
- Call `now()` only at the I/O boundary (`proc main()` or `proc mainWithVfs()`).
- Never call `now()`, `epochTime()`, `cpuTime()`, or any time-related FFI in a
  `{.compileTime.}` proc or `static` block.
