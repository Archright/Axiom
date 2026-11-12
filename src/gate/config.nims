# ── Axiom Gate Domain Integrity Guard (Local Invariant) ──
# Nim 계층적 config 탐색 규칙에 따라 src/gate/ 하위 파일 컴파일 시 자동 적용.
# 루트 config.nims와 독립적으로 실행 — 전역 설정 오염 없음.
import std/os

const projectRoot = thisDir() / "../.."

static:
  # Skip during hermetic bootstrap sandbox builds — the sandbox only compiles
  # the gateway, not the full CLI (bin/axiom-gate bootstrap protocol).
  # AXIOM_CI_PRESERVE_CACHE: CI verify-static runs official gate checks on a
  # fresh checkout (no bin/ax) — treat as bootstrap sandbox.
  if not existsEnv("AXIOM_HERMETIC_BUILDING") and
     not existsEnv("AXIOM_CI_PRESERVE_CACHE") and
     not fileExists(projectRoot / "bin/ax"):
    echo "\n[Integrity Violation] Core engine binary 'bin/ax' is missing."
    echo "[Security Guard] Quality gate runners cannot be compiled without the core infrastructure."
    echo "Run: nimble build"
    quit(1)

# Git hooks verification (read-only)
block:
  if not fileExists(projectRoot / ".git" / "hooks" / "pre-commit"):
    echo "WARNING: Git hooks not configured. Run: nimble hooks"
