import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}

import std/random

proc randomizeOnce*() =
  var initialized {.global.} = false
  if not initialized:
    randomize()
    initialized = true

proc genInt*(min = 0, max = 10000): int =
  randomizeOnce()
  rand(min..max)

proc genString*(minLen = 1, maxLen = 64): string =
  randomizeOnce()
  let len = rand(minLen..maxLen)
  const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  result = newString(len)
  for i in 0..<len:
    result[i] = chars[rand(chars.len - 1)]

proc genBool*(): bool =
  randomizeOnce()
  rand(bool)

proc genSeq*[T](genElem: proc(): T, minLen = 0, maxLen = 8): seq[T] =
  randomizeOnce()
  let len = rand(minLen..maxLen)
  result = newSeq[T](len)
  for i in 0..<len:
    result[i] = genElem()

{.pop.}
