## axiom_clock.nim — Effect Polymorphic Clock with Virtual Ticking
##
## AGENTS.md §0.6: func 우선, proc only at I/O boundary.
## AGENTS.md §0.2: Ideal (compile-time prevention), Deterministic (identical input → identical output).
##
## SystemClock → tags: [IOEffect] → func에서 호출 시 컴파일 에러
## DeterministicClock → noSideEffect → func에서 자유롭게 호출
## Virtual Ticking → DeterministicClock이 var로 전달되어 가상 시간 전진 → 종료성 보장
import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import std/[times, monotimes]

type
  SystemClock* = object
    ## 실제 시스템 런타임 시계.
    ## wallSec/monoNs에 IOEffect 태그 → func에서 호출 시 컴파일 에러.

  DeterministicClock* = object
    ## 테스트 및 검증용 결정론적 고정 시계.
    ## wallSec/monoNs이 noSideEffect → func에서 자유롭게 호출 가능.
    wall*: int64       ## wall-clock timestamp (seconds)
    mono*: int64       ## monotonic timestamp (nanoseconds)
    tickStep*: int64   ## tick당 가상 시간 증가량 (nanoseconds)

# ── SystemClock: I/O boundary에서만 사용 ──

proc wallSec*(clk: SystemClock): int64 {.inline, tags: [IOEffect, TimeEffect].} =
  cast[int64](epochTime())

proc monoNs*(clk: SystemClock): int64 {.inline, tags: [IOEffect, TimeEffect].} =
  getMonoTime().ticks

# ── DeterministicClock: 순수 함수 컨텍스트 ──

func wallSec*(clk: DeterministicClock): int64 {.inline, noSideEffect.} =
  clk.wall

func monoNs*(clk: DeterministicClock): int64 {.inline, noSideEffect.} =
  clk.mono

# ── Virtual Ticking: 가상 시간 전진 ──

func tick*(clk: var DeterministicClock) {.inline, noSideEffect.} =
  ## 가상 시간을 tickStep만큼 전진.
  ## func 내에서 var 파라미터로 호출 가능 — 전역 상태 변경이 아님.
  clk.mono += clk.tickStep
  clk.wall += clk.tickStep div 1_000_000_000

proc tick*(clk: var SystemClock) {.inline, tags: [IOEffect, TimeEffect].} =
  ## SystemClock은 하드웨어가 알아서 흐름. Zero-overhead no-op.
  discard

# ── 생성자 (I/O boundary) ──

proc systemClock*(): SystemClock {.inline, tags: [IOEffect].} =
  SystemClock()

func deterministicClock*(wall, mono: int64;
    tickStep: int64 = 1_000_000): DeterministicClock {.inline.} =
  ## tickStep 기본값: 1ms (1,000,000 ns)
  DeterministicClock(wall: wall, mono: mono, tickStep: tickStep)

{.pop.}
