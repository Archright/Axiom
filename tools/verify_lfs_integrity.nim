## LFS 무결성 검증 — .gitattributes 설정이 모든 환경에서 바이너리를 올바르게 추적하는지 확인
## CI에서 실행하여 LFS 설정 문제를 조기에 탐지

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils]

proc verifyLfsIntegrity*(): bool =
  let gaPath = "vendor/z3/.gitattributes"
  if not fileExists(gaPath):
    echo "❌ vendor/z3/.gitattributes not found"
    return false

  let gitattributes = readFile(gaPath)

  # 1. libz3.so가 LFS로 추적되는지 확인
  if "libz3.so" notin gitattributes or "filter=lfs" notin gitattributes:
    echo "❌ libz3.so is NOT tracked by Git LFS"
    return false

  # 2. .gitattributes에 필수 패턴이 포함되어 있는지 확인
  let requiredPatterns = ["libz3.so", "filter=lfs"]
  for pattern in requiredPatterns:
    if pattern notin gitattributes:
      echo "❌ Missing pattern in .gitattributes: ", pattern
      return false

  # axiom:theater-fix(DEBT#373)
  # 3. vendor/z3/ 디렉토리에 바이너리가 실제로 존재하는지 확인
  if not fileExists("vendor/z3/lib/libz3.so"):
    echo "❌ vendor/z3/lib/libz3.so not found — Z3 binary is required for integrity verification"
    return false

  echo "✅ LFS integrity verified"
  return true

when isMainModule:
  if not verifyLfsIntegrity():
    quit(QuitFailure)
