# ── Axiom Test Domain Integrity Guard (Local Invariant) ──
# Nim 계층적 config 탐색 규칙에 따라 tests/ 하위 파일 컴파일 시 자동 적용.
import std/os

const projectRoot = thisDir() / ".."

static:
  if not fileExists(projectRoot / "bin" / "ax"):
    echo "\n[Integrity Violation] Core engine binary 'bin/ax' is missing."
    echo "[Security Guard] Test suites cannot execute without validating the core artifact."
    echo "Run: nimble build"
    quit(1)
