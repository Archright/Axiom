## 런타임 프로젝트 루트 경로 해석
## getAppDir()은 Linux에서 /proc/self/exe를 readlink로 해석하여
## 실행 파일의 실제 위치를 반환. 빌드 머신 경로에 의존하지 않음.

import core/trusted/layer_declaration
axiomLayer "domain"
import std/os
import core/trusted/axiom_pragmas
{.push raises: [].}

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc getProjectRoot*(): string =
  ## 런타임에 실행 파일 위치 기준으로 프로젝트 루트 계산
  getAppDir()

{.pop}
