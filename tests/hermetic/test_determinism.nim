{.push raises: [].}

## Determinism E2E Test — Wave 7F-1
##
## Tests that all deterministic build components produce
## identical outputs when given identical inputs.

import std/[unittest, tables, os]
import gate/action_key
import core/gate/content_store

suite "Determinism Tests":
  
  test "Action Key is deterministic":
    ## Same inputs → same key, regardless of call order.
    var inputs1 = initTable[string, string]()
    inputs1["src/a.nim"] = "hash_a"
    inputs1["src/b.nim"] = "hash_b"
    
    var inputs2 = initTable[string, string]()
    inputs2["src/b.nim"] = "hash_b"
    inputs2["src/a.nim"] = "hash_a"
    
    let key1 = computeActionKey(inputs1, "pm_hash", 1750000000, "gate:test", @[])
    let key2 = computeActionKey(inputs2, "pm_hash", 1750000000, "gate:test", @[])
    check string(key1) == string(key2)

  test "Action Key changes with different inputs":
    var inputs1 = initTable[string, string]()
    inputs1["src/a.nim"] = "hash_a"
    
    var inputs2 = initTable[string, string]()
    inputs2["src/a.nim"] = "hash_b"
    
    let key1 = computeActionKey(inputs1, "pm", 0, "cmd", @[])
    let key2 = computeActionKey(inputs2, "pm", 0, "cmd", @[])
    check string(key1) != string(key2)

  test "Action Key changes with different command":
    var inputs = initTable[string, string]()
    inputs["src/a.nim"] = "hash_a"
    
    let key1 = computeActionKey(inputs, "pm", 0, "cmd1", @[])
    let key2 = computeActionKey(inputs, "pm", 0, "cmd2", @[])
    check string(key1) != string(key2)

  test "Content Store is deterministic":
    ## Same content → same hash, stored once.
    let store = initStore(".axiom/test_store_det")
    let hash1 = store.put("hello world")
    let hash2 = store.put("hello world")
    check hash1 == hash2
    check store.exists(hash1)
    check store.get(hash1) == "hello world"
    
    # Cleanup
    removeDir(".axiom/test_store_det")

  test "Content Store is content-addressed":
    ## Different content → different hash.
    let store = initStore(".axiom/test_store_ca")
    let hash1 = store.put("content A")
    let hash2 = store.put("content B")
    check hash1 != hash2
    check store.get(hash1) == "content A"
    check store.get(hash2) == "content B"
    
    # Cleanup
    removeDir(".axiom/test_store_ca")

  test "Short Key is stable":
    let key = ActionKey("abcdef1234567890abcdef1234567890")
    check shortKey(key, 8) == "abcdef12"
    check shortKey(key, 16) == "abcdef1234567890"
    check shortKey(key, 64) == "abcdef1234567890abcdef1234567890"
