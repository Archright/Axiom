# nim-check: skip — out-of-tree decode-state probe for the B-SEC-01 capdelta
# (followup/checkout_trio). It imports the consumer's exact module and
# replicates stickyshell's exact decode call form (sth.nim:8/:12,
# `Toml.decode(readFile(p), StickyshellOpts)`, un-keyed, no flags) to dump the
# decoded field values, because the consumer's customMessages=@[] state emits a
# random-by-design banner that cannot be byte-compared at process level.
# Binaries stay in /tmp; the consumer and library checkouts are opened
# read-only via --path.
import std/[os, sequtils]
import toml_serialization
import stickyshell

let p = paramStr(1)
try:
  let o = Toml.decode(readFile(p), StickyshellOpts)
  echo "port=", o.port
  echo "delay=", o.delay
  echo "maxLineLength=", o.maxLineLength
  echo "maxConcurrentClients=", o.maxConcurrentClients
  echo "customMessages.len=", o.customMessages.len
  for m in o.customMessages:
    echo "cm=[", m, "]"
  echo "DECODE_RESULT=OK"
except CatchableError as e:
  echo "DECODE_RESULT=RAISE msg=[", e.msg, "]"
