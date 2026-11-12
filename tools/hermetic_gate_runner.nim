import core/trusted/layer_declaration
axiomLayer "tools"
# tools/hermetic_gate_runner.nim
# Shadow Root Hermetic Gate Runner — Pure Stdlib Only (Bootstrap-Safe)
# 프로젝트 모듈 ZERO imports → 자기 참조적 부트스트랩 불가능

import std/[os, tempfiles, strutils, algorithm]

# ── 의존성 자동 발견 (gorge로 컴파일러 출력 파싱) ──────────────────
proc discoverDeps(runnerPath: string): seq[string] =
  ## nim check 출력에서 import된 모듈 경로를 추출
  let cmd = "nim check --hints:off --warnings:off --errorMax:0 " & runnerPath & " 2>&1"
  let (output, exitCode) = gorgeEx(cmd)

  var deps: seq[string]
  for line in output.splitLines():
    if "(1," in line and ".nim" in line:
      let pathStart = line.find("src/")
      if pathStart >= 0:
        let pathEnd = line.find(".nim", pathStart)
        if pathEnd > pathStart:
          let path = line[pathStart .. pathEnd + 3]
          if path notin deps:
            deps.add(path)

  result = @[]
  for dep in deps:
    if dep.startsWith("src/core/trusted/") or
       dep.startsWith("src/core/results") or
       dep.startsWith("src/gate/gate_types"):
      if dep notin result:
        result.add(dep)

# ── 섀도우 루트 생성 ──────────────────────────────────────────────
proc main() =
  let shadowRoot = createTempDir("axiom_hermetic_", "_gate")
  defer: removeDir(shadowRoot)

  # Step 1: 게이트 러너 물리적 복사
  let shadowRunners = shadowRoot / "src" / "gate" / "runners"
  createDir(shadowRunners)
  var runnerFiles: seq[string]
  for entry in walkDir("src/gate/runners"):
    if entry.path.endsWith(".nim"):
      let dst = shadowRunners / entry.path.extractFilename
      copyFile(entry.path, dst)
      runnerFiles.add(entry.path)

  # Step 2: 의존성 자동 발견 + 전이 복사 (Self-Healing)
  var allDeps: seq[string]
  for runner in runnerFiles:
    let deps = discoverDeps(runner)
    for dep in deps:
      if dep notin allDeps:
        allDeps.add(dep)

  # Step 3: 발견된 의존성 물리적 복사
  for dep in allDeps:
    let srcPath = dep
    let dstPath = shadowRoot / dep
    createDir(dstPath.parentDir)
    if fileExists(srcPath):
      copyFile(srcPath, dstPath)
      echo "[HERMETIC] Auto-discovered: " & dep

  # Step 4: 합성 import 파일 생성
  let combinedPath = shadowRoot / "hermetic_combined.nim"
  var imports: seq[string]
  for entry in walkDir(shadowRunners):
    if entry.path.endsWith(".nim"):
      imports.add("import gate/runners/" & entry.path.extractFilename.changeFileExt(""))
  imports.sort()
  writeFile(combinedPath, imports.join("\n") & "\n")

  # Step 5: 격리 공간에서 컴파일 (config.nims 없음)
  let cmd = "cd " & shadowRoot & " && nim check --hints:off --warnings:off hermetic_combined.nim"
  let (output, exitCode) = gorgeEx(cmd)

  if exitCode != 0:
    echo "[HERMETIC GATE] FAIL: Gate runner compilation failed in isolated environment"
    echo output
    quit(1)

  echo "[HERMETIC GATE] PASS: " & $imports.len & " runners, " &
       $allDeps.len & " auto-discovered deps in hermetic isolation"

main()
