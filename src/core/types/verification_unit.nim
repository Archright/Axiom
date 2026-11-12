import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## VerificationUnit — Callback-Based DIP (AGENTS.md §0.2, §1.2)
##
## Domain이 Infrastructure를 직접 import하지 않고 콜백으로 주입받습니다.
## Concept 기반 제네릭 변환은 점진적으로 진행하고, 현재는 콜백 주입으로 SoC를 보장합니다.
##
## Context7: "An empty raises list signifies that a procedure is not allowed
##            to raise any exceptions."

import core/types/pipeline_core_types
import core/types/domain_types

type
  HealingCallback* = proc(
    sourceCode: string;
    translation: UniversalTranslation;
    initialScan: NegativeInvariantScan;
    maxRounds: int;
    priorInvariant: string
  ): tuple[finalSource: string, finalScan: NegativeInvariantScan, rounds: seq[HealingRound]] {.raises: [CatchableError], gcsafe.}

  RefinementCallback* = proc(
    req: UniversalPipelineRequest;
    translation: UniversalTranslation;
    sourceCode: string;
    activeInvariant: string;
    maxRounds: int
  ): tuple[
    finalSource: string;
    finalInvariant: string;
    rounds: seq[HealingRound];
    nearestDiagnostic: string;
    failedReplayAttempts: int;
    leanKernelVerified: bool;
    vacuityProven: bool
  ] {.raises: [CatchableError], gcsafe.}

  ScanCallback* = proc(
    translation: UniversalTranslation;
    sourceCode: string;
    priorInvariant: string
  ): NegativeInvariantScan {.raises: [CatchableError], gcsafe.}

  MergeCallback* = proc(
    prior: string; refined: string
  ): string {.raises: [], gcsafe.}

  VerificationUnit* = object
    ## Stateless container for pure verification transformations.
    ## All behavior is injected via callbacks — no direct Infrastructure imports.
    maxRounds*: int
    leanExe*: string
    doHeal*: HealingCallback
    doRefine*: RefinementCallback
    doScan*: ScanCallback
    doMerge*: MergeCallback

func initVerificationUnit*(
  doHeal: HealingCallback;
  doRefine: RefinementCallback;
  doScan: ScanCallback;
  doMerge: MergeCallback;
  leanExe: string = "lean";
  maxRounds: int = 6
): VerificationUnit {.raises: [].} =
  VerificationUnit(
    maxRounds: maxRounds,
    leanExe: leanExe,
    doHeal: doHeal,
    doRefine: doRefine,
    doScan: doScan,
    doMerge: doMerge
  )

{.pop.}
