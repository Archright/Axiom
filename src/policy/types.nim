## Policy-as-Code Types
## Compile-time policy data types with distinct wrappers to prevent
## accidental confusion between policy fields.

import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

import std/times

type
  FilePath* = distinct string
  IssueId* = distinct string
  ExpiryDate* = distinct string
  ApprovedBy* = distinct string
  Reason* = distinct string
  LibraryId* = distinct string
  LibraryName* = distinct string

  ExemptionEntry* = object
    path*: FilePath
    reason*: Reason
    issueId*: IssueId
    expiryDate*: ExpiryDate
    approvedBy*: ApprovedBy

  AllowedLibEntry* = object
    id*: LibraryId
    names*: seq[LibraryName]
    reason*: Reason

proc `$`*(p: FilePath): string {.inline.} = string(p)
proc `$`*(i: IssueId): string {.inline.} = string(i)
proc `$`*(d: ExpiryDate): string {.inline.} = string(d)
proc `$`*(a: ApprovedBy): string {.inline.} = string(a)
proc `$`*(r: Reason): string {.inline.} = string(r)
proc `$`*(l: LibraryId): string {.inline.} = string(l)
proc `$`*(n: LibraryName): string {.inline.} = string(n)

proc parseExpiry(d: ExpiryDate): DateTime {.raises: [ValueError].} =
  ## Parse expiry date string (YYYY-MM-DD) in UTC.
  parse($d, "yyyy-MM-dd", utc())

{.pop.}
