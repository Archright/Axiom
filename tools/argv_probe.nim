import std/[os, strutils]

for i, a in commandLineParams():
  echo i, " len=", a.len, " hex=", a.toHex