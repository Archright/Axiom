# AGENTS.md Embedded Historical Notes

This file preserves historical gate incidents that were previously embedded directly in `AGENTS.md §2.10`. They have been extracted to keep the constitutional layer free of post-mortem logs.

---

## Fork Bomb Prevention

`gate_self_check.nim` previously contained `execCmdEx("hooks/pre-commit")`, causing infinite recursion because `gate_hook` runs `gate-self-check` as gate #0. **Fixed**: smoke test removed; `gate_self_check` now performs pure Nim file inspection only.

## Root Cause of Freeze (2026-05-27)

**NOT OOM.** 16-core CPU saturation by gate processes + Chrome GPU load → AMDGPU driver timeout → MODE2 reset → display blackout. Mitigated by L3 cgroups v2 `wrapWithCgroupsIfAvailable` in `gate_hook.nim` (see AGENTS.md §1.2 4-Layer Table) guaranteeing 50% CPU headroom.
