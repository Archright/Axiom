# Z3 Static Linking Architecture

> **STATUS: REMOVED (v30)**
> Z3 FFI — including both the shared (`libz3.so`) and static (`libz3.a`) linking
> described in this document — was completely removed on 2026-07-02 (see
> `docs/spec/z3_ffi_architecture.md` §10). All Z3 solver interactions now use
> the CLI subprocess path via `src/verification/solver/z3_pool.nim`
> (`startProcess("z3", ["-smt2", "-in"])`). Z3 is an external binary pin
> (4.13.3, declared in `src/core/config/toolchain_config.nim`, resolved at
> runtime by `resolveZ3Path()` in `src/core/types/z3_solver_config.nim`) and is
> not linked into `bin/ax`. `vendor/z3/` is untracked local content (gitignored
> via `vendor/*`); `tools/fetch_z3.nim` materializes it from the upstream Z3
> release after SHA-256 verification.
> **Historical reference only** — the linking paths below are no longer active.

## Overview
Axiom **used to** access the Z3 SMT solver via C API FFI bindings. The build system **supported** both shared (libz3.so) and static (libz3.a) linking.

## Historical State (Bridge Phase)
- **Default**: Shared library (`libz3.so`) with `$ORIGIN` rpath
- **Library location**: `vendor/z3/lib/libz3.so`
- **Runtime dependency**: `libz3.so` must be findable via rpath or `LD_LIBRARY_PATH`

## Static Build

### Prerequisites
- cmake >= 3.15
- g++ or clang++
- python3 (for Z3 configure script)

### Build Command
```bash
nimble buildZ3Static
```

This will:
1. Clone Z3 4.13.3 source to `vendor/z3/src/` (if not present)
2. Run CMake with `Z3_BUILD_LIBZ3_SHARED=OFF`
3. Build `libz3.a` in `vendor/z3/build_static/`
4. Copy `libz3.a` to `vendor/z3/lib/`

### Switching to Static Linking
After building `libz3.a`:
1. Edit `src/verification/z3_ffi.nim`: remove `{.dynlib.}` pragmas from all `importc` procs
2. Edit `config/vendors.nims`: change `-lz3` to direct `libz3.a` path
3. Rebuild: `nim c -o:bin/ax src/cli/main.nim`
4. Verify: `ldd bin/ax | grep z3` should show no z3 dependency

## Library Search Order
1. `$ORIGIN/../vendor/z3/lib/` (rpath — preferred)
2. `LD_LIBRARY_PATH` (fallback)
3. System paths (last resort)

## Version Pinning
- Z3 version: 4.13.3 (declared in `config/vendors.nims`)
- CMake option: `Z3_BUILD_LIBZ3_SHARED=OFF`
- Static build excludes Python/.NET/Java/Julia bindings
