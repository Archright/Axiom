# VFS Handle Double Indirection Quirk

> **Module**: `src/gate/gate_run_context.nim`
> **Discovered**: 2026-06-22 (Issue 2 — SIGSEGV in gate dispatch)
> **Severity**: Critical (process crash)

---

## Problem

`MerkleVfs` is a `ref object` — in Nim, a `ref` **is already a pointer** (ARC-managed pointer to the
heap-allocated object). The original (buggy) code used:

```nim
# BUGGY — creates ptr-to-pointer (double indirection)
func buildVfsHandle*(vfs: MerkleVfs): VfsHandle =
  cast[VfsHandle](unsafeAddr vfs[])

# BUGGY — returns ptr MerkleVfs, not MerkleVfs
func derefVfs(ctx: GateRunContext): ptr MerkleVfs =
  cast[ptr MerkleVfs](ctx.vfs)
```

### Why it crashes

1. `vfs` parameter is a `MerkleVfs` (which is `ref MerkleVfsObj` — a pointer).
2. `unsafeAddr vfs[]` takes the address of the **dereferenced object**, producing a `ptr MerkleVfsObj`.
   But the code then casts to `VfsHandle` (a `pointer`), storing the address of the **object's first
   field** — not the address of the `ref` itself.
3. On restore, `cast[ptr MerkleVfs](ctx.vfs)` interprets the object address as a `ptr MerkleVfs`
   (pointer-to-pointer). The `[]` operator then performs:
   ```
   mov (%rdi), %rdi   ; load first 8 bytes of the object (= FileNode ref) as a pointer
   ```
   This reads the **first field** (a `FileNode` ref) as a `MerkleVfs*`, causing a misaligned
   dereference → **SIGSEGV**.

### Assembly evidence

The `[]` operator on `ptr MerkleVfs` compiles to a single `mov` load. When the stored pointer
actually points at the start of the `MerkleVfsObj` (not at the `ref` slot), the first 8 bytes
loaded are the first field of the object (the `FileNode` tree root), not a valid `MerkleVfs` pointer.

## Fix

```nim
# FIXED — ref IS the pointer, store directly
func buildVfsHandle*(vfs: MerkleVfs): VfsHandle {.inline, raises: [].} =
  cast[VfsHandle](vfs)

# FIXED — restore to MerkleVfs (not ptr MerkleVfs)
func derefVfs(ctx: GateRunContext): MerkleVfs {.inline, raises: [].} =
  cast[MerkleVfs](ctx.vfs)
```

**Key insight**: `cast[VfsHandle](vfs)` stores the `ref` value (which is already a raw pointer)
directly into the `VfsHandle`. On restore, `cast[MerkleVfs](ctx.vfs)` recovers the original `ref`.
Single indirection — no double deref.

## Safety Analysis

| Concern | Status |
|---------|--------|
| GC liveness | ✅ Original `ref` lives in a `{.threadvar.}` (process-lifetime, never freed by GC) |
| ARC bypass | ✅ `cast` bypasses refcount — acceptable because lifetime is guaranteed by `{.threadvar.}` |
| Thread safety | ✅ In-process gates dispatch sequentially on the main thread |
| Zero-copy | ✅ No heap allocation on store/restore path |

## Rule

> For `ref object` types in Nim, `cast[pointer](ref)` **IS** the pointer.
> **Never** use `unsafeAddr ref[]` — that takes the address of the dereferenced object,
> creating a pointer-to-pointer (double indirection) when the `ref` is later cast back.

This applies to any opaque-handle pattern where a `ref` is stored as a raw `pointer` or `distinct pointer`.

## Related

- `docs/spec/nim_effect_system_quirks.md` — Nim stdlib side-effect quirks
- `docs/spec/nim_effect_system_quirks.md §12` — `test -d '.git'` worktree quirk
- `src/gate/gate_run_context.nim` — the fixed module
