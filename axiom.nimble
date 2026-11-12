version       = "0.6.3"
author        = "Suhyok Yoon"
description   = "Archright Axiom Enterprise integrity engine"
license       = "LicenseRef-Axiom-SAL-1.0"
requires "nim >= 2.2.10"
requires "malebolgia >= 1.3.0"

requires "checksums >= 0.2.0"
requires "fusion >= 1.2"
requires "nimcrypto >= 0.6.0"
# ed25519 is vendored in vendor/ed25519/ — not a nimble dependency

import std/os

proc ensureBinDir() =
  ## bin/ 디렉터리 존재 보장. Clean Slate Model과 호환.
  if not dirExists("bin"):
    mkDir("bin")

before build:
  ## bin/ 전체 삭제(rmDir)는 AOT 게이트 CAS 캐시(.axiom/cache/gates)와
  ## 무관하지만, nimble build가 bin/을 지우면 게이트 실행 시 매번 재-materialize
  ## 되어 60초 타임아웃을 유발한다. 따라서 bin/을 보존하고, orphan 바이너리만
  ## 정리한다 (gate_hook.nim의 dangling symlink 제거 + clean task에서 처리).
  ## 참고: bin/ 자체는 nimble이 타깃 바이너리를 덮어쓰므로 삭제 불필요.
  if not dirExists("bin"):
    mkDir("bin")

srcDir = "src"

bin = @["bin/ax", "bin/run_gate"]

task test, "Run all tests with Makefile":
  exec "make test"


task generate_docs, "Regenerate src/policy/embedded_agents_docs.nim from local SSOT":
  exec "nim c -r -o:bin/generate_embedded_docs tools/generate_embedded_docs.nim"


task gate_daemon, "Build the gate-daemon binary (in-process MemoDb cache for hooks)":
  ## Best-effort: the hook falls back to direct mode if the daemon is absent.
  ensureBinDir()
  echo "[nimble] Building gate-daemon binary..."
  exec "nim c -d:release -o:bin/gate-daemon src/gate/daemon/gate_daemon_server.nim"

task hermetic, "Run hermetic pre-build (captures build env and validates import boundaries)":
  ensureBinDir()
  exec "nim c -o:bin/hermetic_build --hints:off tools/hermetic_build.nim"
  exec "bin/hermetic_build"

task devBuild, "Dev build: skip hermetic scan + manifest sync, build only core binaries":
  ## DX-only: AXIOM_FAST_BUILD/AXIOM_HERMETIC_BUILDING skip config.nims scans and
  ## hermetic_build import/type/debt codegen. Builds the binaries a dev actually
  ## needs. ~40-100s instead of 200-400s. NOT for CI (CI uses `task build`).
  ensureBinDir()
  putEnv("AXIOM_FAST_BUILD", "1")
  putEnv("AXIOM_HERMETIC_BUILDING", "1")
  exec "nim c -d:release -o:bin/ax src/cli/main.nim"
  exec "nim c -d:release -o:bin/axiom-gate src/gate/gateway.nim"
  exec "nim c -d:release -o:bin/precompile_gates src/cli/precompile_gates.nim"
  echo "[nimble] Dev build complete (hermetic scan + manifest sync skipped)"

task build, "Build all CLI binaries to bin/":
  exec "nimble hermetic"
  exec "nim c -d:release -o:bin/ax src/cli/main.nim"
  exec "nim c -d:release -o:bin/run_gate src/cli/run_gate.nim"
  exec "nim c -d:release -o:bin/axiom-status src/cli/axiom_status.nim"
  echo "[nimble] All binaries built in bin/"

task ast_refine, "Build ast-refine tool to bin/":
  ensureBinDir()
  exec "nim c --hints:off --path:src -o:bin/ast-refine tools/ast_refine.nim"
  echo "[nimble] ast-refine built in bin/"

task lint, "Enforce {.raises: []} on src/core (CI gate)":
  ## Builds ast-refine then runs add-raises in dry-run mode.
  ## Exits 1 if any file is non-compliant, failing CI.
  ensureBinDir()
  exec "nim c --hints:off --path:src -o:bin/ast-refine tools/ast_refine.nim"
  exec "bin/ast-refine add-raises src/core --dry-run"
  echo "[nimble] lint passed — all src/core files comply with {.raises: [].}."

task immutable_build, "Build with The Immutable Builder (transactional)":
  ## 오케스트레이터 기반 자가 치유 빌드 시스템
  ## src/ 불변 보장, overlay에서만 수정, 성공 시에만 커밋
  ensureBinDir()
  exec "nim c -d:release -o:bin/build tools/build.nim && bin/build"

task immutable_dry, "Dry run: show what The Immutable Builder would do":
  ensureBinDir()
  exec "nim c -o:bin/build tools/build.nim && bin/build --dryRun"

task immutable_verify, "Verify build idempotency (2-pass binary comparison)":
  ensureBinDir()
  exec "nim c -d:release -o:bin/build tools/build.nim && bin/build --verify"

task lintBannedImports, "Check for banned legacy imports in src/core/":
  let banned = @["import checksums/sha2", "import checksums/sha1"]
  var violations: seq[string] = @[]
  for file in walkDirRec("src/core"):
    if not file.endsWith(".nim"): continue
    let content = readFile(file)
    for ban in banned:
      if ban in content:
        violations.add(file & ": " & ban)
  if violations.len > 0:
    echo "BANNED IMPORTS DETECTED:"
    for v in violations:
      echo "  ", v
    quit(1)
  echo "No banned imports found."

task lintCompilerInternal, "Monitor axiomCompilerInternal files":
  ensureBinDir()
  exec "nim c --hints:off --path:src -o:bin/ast-refine tools/ast_refine.nim"
  exec "bin/ast-refine monitor-internal src/core"
  echo "[nimble] monitor-internal scan complete."

task lintAll, "Run lint and lintBannedImports":
  exec "nimble lint"
  exec "nimble lintBannedImports"
  echo "[nimble] lintAll passed."

task z3precache, "Build z3-precache tool and scan source for Z3 queries":
  ensureBinDir()
  exec "nim c --hints:off -o:bin/z3-precache tools/z3_precache.nim"
  exec "bin/z3-precache --scan"
  echo "[nimble] Z3 precache complete."

task syncTopology, "Sync manifest.d/*.json + manifest_registry.nim from topology_spec.nim SSOT":
  ensureBinDir()
  exec "nim c --hints:off -o:bin/sync_topology tools/sync_topology.nim"
  exec "bin/sync_topology"
