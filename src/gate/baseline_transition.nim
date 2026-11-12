import std/hashes

type
  TransitionChangeKind* = enum
    tkImprovement
    tkRegression
    tkReclassification
    tkMigration
    tkInvalidState

  BaselineTransitionInput* = object
    oldClaimPolicyVersion*: string
    newClaimPolicyVersion*: string
    oldClaimSetHash*: string
    newClaimSetHash*: string
    oldVkdNum*: int
    newVkdNum*: int
    policyDrift*: bool

func classifyChange*(t: BaselineTransitionInput): TransitionChangeKind {.raises: [].} =
  ## Detector + Classifier separation: the hash detects change;
  ## this function classifies the meaning of the change.
  ## Decision table (evaluated top-down; first match wins):
  if t.newClaimSetHash == t.oldClaimSetHash:
    if t.newVkdNum < t.oldVkdNum:
      # Same claim set but VKD dropped = relabel/reclassification (denominator effect).
      tkReclassification
    else:
      # Same claim set, VKD stable or improved = no meaningful change.
      tkImprovement
  elif t.policyDrift or t.newClaimPolicyVersion != t.oldClaimPolicyVersion:
    # Semantic/metric-contract changed (policy version or drift flag) → migration.
    tkMigration
  elif t.newVkdNum < t.oldVkdNum:
    # Claim set changed (hash differs), VKD dropped, no policy explanation → regression.
    tkRegression
  else:
    # Ambiguous: claim set changed but VKD did not drop and no policy signal.
    tkInvalidState

func isDetector*(oldHash, newHash: string): bool {.raises: [].} =
  ## Note: the HASH is only a detector; the classifier decides meaning.
  ## A hash difference signals that something changed, but not what kind.
  oldHash != newHash
