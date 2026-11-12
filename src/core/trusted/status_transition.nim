import core/trusted/layer_declaration
axiomLayer "trusted"
{.push raises: [].}

import core/crypto/hash_kernel
import core/types/certificate_types

type StatusTransition* = object
  certificateId*: string
  fromStatus*: string
  toStatus*: string
  reason*: string
  migrationInputHash*: string
  transitionId*: string

func computeTransitionId*(st: StatusTransition): string =
  sha256Hex(st.certificateId & st.fromStatus & st.toStatus & st.reason & st.migrationInputHash)

func makeStatusTransition*(
  certificateId: string,
  fromStatus: string,
  toStatus: string,
  reason: string,
  migrationInputHash: string
): StatusTransition =
  var st = StatusTransition(
    certificateId: certificateId,
    fromStatus: fromStatus,
    toStatus: toStatus,
    reason: reason,
    migrationInputHash: migrationInputHash
  )
  st.transitionId = computeTransitionId(st)
  st

func projectedCurrentStatus*(
  events: seq[StatusTransition],
  certificateId: string,
  baseStatus: string
): string =
  var current = baseStatus
  for ev in events:
    if ev.certificateId == certificateId:
      if ev.fromStatus == current:
        current = ev.toStatus
  current

func canAppendTransition*(
  events: seq[StatusTransition],
  t: StatusTransition,
  baseStatus: string
): bool =
  projectedCurrentStatus(events, t.certificateId, baseStatus) == t.fromStatus

proc appendStatusTransition*(
  events: var seq[StatusTransition],
  t: StatusTransition,
  baseStatus: string
): bool =
  if not canAppendTransition(events, t, baseStatus):
    return false
  let fromSt = parseCertificateStatus(t.fromStatus)
  let toSt = parseCertificateStatus(t.toStatus)
  if not isValidTransition(fromSt, toSt):
    return false
  events.add(t)
  true

{.pop.}