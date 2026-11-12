## LLBC → shared Rust canonical producer tests (feat/rust-subject-v1).
##
## Contract under test (src/verification/llbc_to_canonical.nim):
##   1. Real-probe positive — the MEASURED Charon 0.1.281 extraction
##      (/tmp/axiom-rust-probe/axiom_rust_probe.llbc) yields valid
##      RustCanonical values for the straight-line functions, with resolved
##      type interning, the AddChecked collapse and the tool-layer
##      failureMode fact.
##   2. Real-probe boolean Switch collapse — `is_zero` in the measured probe
##      lowers `a == 0 && b == 0` into nested `Switch` statements; the v1.3
##      boolean collapse folds them into `and(eq(a,0), eq(b,0))` (the
##      straight-line grammar alone would reject it).
##   3. Rejection matrix — Call / Switch / SwitchInt, u64 types, unsafe,
##      generics, unresolved interning, re-assignment, incomplete collapse:
##      every rejection names the offending node, nothing is dropped.
##   4. Fallback — when the probe file is absent, the inline fixture suites
##      below cover the same shapes without it (explicit skip, not failure).

import std/[unittest, strutils, os, json]

import core/trusted/rust_canonical
import verification/llbc_to_canonical
import verification/rust_ast_wire

## The committed measured extraction first (CI-reproducible), then the
## historical /tmp probe path for environments that keep it there.
let ProbePath* =
  block:
    var found = ""
    for p in @[
        currentSourcePath().parentDir / ".." / ".." / "tests" / "fixtures" /
          "rust" / "axiom_rust_probe" / "axiom_rust_probe.llbc",
        "/tmp/axiom-rust-probe/axiom_rust_probe.llbc"]:
      if fileExists(p):
        found = p
        break
    found

let probePresent = ProbePath.len > 0

if not probePresent:
  echo "SKIP: real probe not found at " & ProbePath &
    " — inline fixture suites still run (explicit skip, not a failure)"

proc countAddChecked(c: RustCanonical): int =
  for s in c.body:
    if s.kind == rskAssign and s.rvalue.kind == rrvAddChecked:
      inc result

# ─── Suite 1: real measured probe (guarded on file presence) ────────────────

if probePresent:
  suite "llbc_to_canonical — real probe (charon 0.1.281, axiom_rust_probe)":

    let f = parseLlbcFile(ProbePath)

    test "probe parses as LLBC JSON":
      check f.ok
      check not f.root.isNil

    test "extractable names, document order":
      check llbcFunctionNames(f.root) == @["add_u8", "add_u8_mutant", "is_zero"]

    test "add_u8 → valid canonical; type interning resolves BOTH params to u8":
      let r = llbcFunctionToCanonical(f.root, "add_u8")
      check r.ok
      check r.error == rceNone
      check validateRustCanonical(r.canonical) == rceNone
      check r.canonical.funcName == "add_u8"
      check r.canonical.modulePath == "axiom_rust_probe"
      # property 5: provenance from item_meta.name + span
      check r.canonical.sourceIdentity == "src/lib.rs:3:0-5:1"
      # property 1+2: identifiers AND types — inputs[0] is the inline
      # {"Value": [4, u8]} definition, inputs[1] the {"Deduplicated": 4}
      # reference; both MUST resolve to (int, 8, unsigned)
      check r.canonical.params.len == 2
      check r.canonical.params[0].name == "a"
      check r.canonical.params[1].name == "b"
      for p in r.canonical.params:
        check p.ty.kind == rtyInt
        check p.ty.widthBits == 8
        check p.ty.signedness == rsgUnsigned
      check r.canonical.retType.kind == rtyInt
      check r.canonical.retType.widthBits == 8
      check r.canonical.retType.signedness == rsgUnsigned

    test "add_u8 → checked-add collapse: one rrvAddChecked, failureMode fact":
      let c = llbcFunctionToCanonical(f.root, "add_u8").canonical
      check countAddChecked(c) == 1
      check c.failureMode == rfmPanicOnOverflowObserved
      check c.returnPlace == "_0"
      # collapsed statement: Assign(_0, AddChecked(Copy _3, Copy _4))
      var found = false
      for s in c.body:
        if s.kind == rskAssign and s.rvalue.kind == rrvAddChecked:
          found = true
          check s.dest == "_0"
          check s.rvalue.addLhs.kind == ropCopy
          check s.rvalue.addLhs.place == "_3"
          check s.rvalue.addRhs.kind == ropCopy
          check s.rvalue.addRhs.place == "_4"
      check found
      # straight-line: exactly one Return, LAST
      check c.body[c.body.len - 1].kind == rskReturn

    test "add_u8 → produced canonical flows into the existing wire codec":
      let r = llbcFunctionToCanonical(f.root, "add_u8")
      let wire = serializeCanonicalWire(r.canonical)
      check wire.ok
      let decoded = deserializeCanonicalWire(wire.bytes)
      check decoded.ok
      check validateRustCanonical(decoded.canonical) == rceNone

    test "add_u8_mutant → TWO AddChecked collapse, constant operand preserved":
      let r = llbcFunctionToCanonical(f.root, "add_u8_mutant")
      check r.ok
      check r.error == rceNone
      check validateRustCanonical(r.canonical) == rceNone
      check r.canonical.funcName == "add_u8_mutant"
      check r.canonical.sourceIdentity == "src/lib.rs:9:0-11:1"
      check r.canonical.failureMode == rfmPanicOnOverflowObserved
      check countAddChecked(r.canonical) == 2
      # second add is `+ 1`: AddChecked(Copy _3, Const 1 : u8)
      var constSeen = false
      for s in r.canonical.body:
        if s.kind == rskAssign and s.rvalue.kind == rrvAddChecked:
          if s.rvalue.addRhs.kind == ropConstant:
            constSeen = true
            check s.rvalue.addRhs.value == 1
            check s.rvalue.addRhs.ty.kind == rtyInt
            check s.rvalue.addRhs.ty.widthBits == 8
      check constSeen
      check r.canonical.body[r.canonical.body.len - 1].kind == rskReturn

    test "is_zero (real probe) → ACCEPTED by the boolean Switch collapse: " &
        "a == 0 && b == 0 becomes and(eq(a,0), eq(b,0))":
      let r = llbcFunctionToCanonical(f.root, "is_zero")
      check r.ok
      check r.error == rceNone
      check validateRustCanonical(r.canonical) == rceNone
      check r.canonical.retType.kind == rtyBool
      check r.canonical.body.len == 2
      check r.canonical.body[0].kind == rskAssign
      check r.canonical.body[0].rvalue.kind == rrvExpr
      let e = r.canonical.body[0].rvalue.expr
      check e.kind == rexBinaryOp
      check e.form == rboAnd
      check e.lhs.kind == rexBinaryOp and e.lhs.form == rboEq
      check e.rhs.kind == rexBinaryOp and e.rhs.form == rboEq

    test "llbcAllToCanonical → every fun_decl reported, none dropped":
      let all = llbcAllToCanonical(f.root)
      check all.len == 3
      check all[0].ok and all[1].ok and all[2].ok

# ─── Suite 2: inline fixtures — positives (always run; probe fallback) ──────

const AddFixture = """
{
 "charon_version": "0.1.281",
 "has_errors": false,
 "translated": {
  "crate_name": "synth",
  "files": [
   {
    "id": 0,
    "name": {
     "Local": "src/synth.rs"
    },
    "crate_name": "synth",
    "contents": "fn synth_add(a: u8, b: u8) -> u8 { a.wrapping_add(b) }\n"
   }
  ],
  "fun_decls": [
   {
    "item_meta": {
     "name": [
      {
       "Ident": [
        "synth",
        0
       ]
      },
      {
       "Ident": [
        "synth_add",
        0
       ]
      }
     ],
     "span": {
      "Untagged": {
       "data": {
        "file_id": 0,
        "beg": {
         "line": 1,
         "col": 0
        },
        "end": {
         "line": 3,
         "col": 1
        }
       },
       "generated_from_span": null
      }
     },
     "has_errors": false
    },
    "signature": {
     "is_unsafe": false,
     "abi": "Rust",
     "is_variadic": false,
     "inputs": [
      {
       "Value": [
        4,
        {
         "Scalar": {
          "Integer": {
           "Unsigned": "U8"
          }
         }
        }
       ]
      },
      {
       "Deduplicated": 4
      }
     ],
     "output": {
      "Deduplicated": 4
     },
     "generics": {
      "regions": [],
      "types": [],
      "const_generics": [],
      "trait_clauses": [],
      "regions_outlive": [],
      "types_outlive": [],
      "trait_type_constraints": []
     }
    },
    "body": {
     "Structured": {
      "locals": {
       "arg_count": 2,
       "locals": [
        {
         "index": 0,
         "name": null,
         "ty": {
          "Deduplicated": 4
         }
        },
        {
         "index": 1,
         "name": "a",
         "ty": {
          "Deduplicated": 4
         }
        },
        {
         "index": 2,
         "name": "b",
         "ty": {
          "Deduplicated": 4
         }
        },
        {
         "index": 3,
         "name": null,
         "ty": {
          "Deduplicated": 4
         }
        },
        {
         "index": 4,
         "name": null,
         "ty": {
          "Deduplicated": 4
         }
        },
        {
         "index": 5,
         "name": null,
         "ty": {
          "Deduplicated": 4
         }
        }
       ]
      },
      "body": {
       "statements": [
        {
         "kind": {
          "StorageLive": 0
         }
        },
        {
         "kind": {
          "StorageLive": 3
         }
        },
        {
         "kind": {
          "Assign": [
           {
            "kind": {
             "Local": 3
            },
            "ty": {
             "Deduplicated": 4
            }
           },
           {
            "Use": [
             {
              "Copy": {
               "kind": {
                "Local": 1
               },
               "ty": {
                "Deduplicated": 4
               }
              }
             },
             "Yes"
            ]
           }
          ]
         }
        },
        {
         "kind": {
          "StorageLive": 4
         }
        },
        {
         "kind": {
          "Assign": [
           {
            "kind": {
             "Local": 4
            },
            "ty": {
             "Deduplicated": 4
            }
           },
           {
            "Use": [
             {
              "Copy": {
               "kind": {
                "Local": 2
               },
               "ty": {
                "Deduplicated": 4
               }
              }
             },
             "Yes"
            ]
           }
          ]
         }
        },
        {
         "kind": {
          "StorageLive": 5
         }
        },
        {
         "kind": {
          "Assign": [
           {
            "kind": {
             "Local": 5
            },
            "ty": {
             "Deduplicated": 4
            }
           },
           {
            "BinaryOp": [
             "AddChecked",
             {
              "Copy": {
               "kind": {
                "Local": 3
               },
               "ty": {
                "Deduplicated": 4
               }
              }
             },
             {
              "Copy": {
               "kind": {
                "Local": 4
               },
               "ty": {
                "Deduplicated": 4
               }
              }
             }
            ]
           }
          ]
         }
        },
        {
         "kind": {
          "Assert": {
           "assert": {
            "cond": {
             "Move": {
              "kind": {
               "Projection": [
                {
                 "kind": {
                  "Local": 5
                 },
                 "ty": {
                  "Deduplicated": 5
                 }
                },
                {
                 "Field": [
                  null,
                  1
                 ]
                }
               ]
              },
              "ty": {
               "Deduplicated": 6
              }
             }
            },
            "expected": false,
            "check_kind": {
             "Overflow": [
              {
               "Add": "Wrap"
              },
              {
               "Move": {
                "kind": {
                 "Local": 3
                },
                "ty": {
                 "Deduplicated": 4
                }
               }
              },
              {
               "Move": {
                "kind": {
                 "Local": 4
                },
                "ty": {
                 "Deduplicated": 4
                }
               }
              }
             ]
            }
           },
           "on_failure": {
            "Panic": null
           },
           "on_unwind": {
            "statements": [
             {
              "kind": "UnwindResume"
             }
            ]
           }
          }
         }
        },
        {
         "kind": {
          "Assign": [
           {
            "kind": {
             "Local": 0
            },
            "ty": {
             "Deduplicated": 4
            }
           },
           {
            "Use": [
             {
              "Move": {
               "kind": {
                "Projection": [
                 {
                  "kind": {
                   "Local": 5
                  },
                  "ty": {
                   "Deduplicated": 5
                  }
                 },
                 {
                  "Field": [
                   null,
                   0
                  ]
                 }
                ]
               },
               "ty": {
                "Deduplicated": 4
               }
              }
             },
             "Yes"
            ]
           }
          ]
         }
        },
        {
         "kind": {
          "StorageDead": 3
         }
        },
        {
         "kind": {
          "StorageDead": 4
         }
        },
        {
         "kind": "Return"
        }
       ]
      }
     }
    }
   }
  ]
 }
}
"""

const EqFixture = """
{
 "charon_version": "0.1.281",
 "has_errors": false,
 "translated": {
  "crate_name": "synth",
  "files": [
   {
    "id": 0,
    "name": {
     "Local": "src/synth.rs"
    },
    "crate_name": "synth",
    "contents": "fn synth_is_zero(x: u8) -> bool { x == 0 }\n"
   }
  ],
  "fun_decls": [
   {
    "item_meta": {
     "name": [
      {
       "Ident": [
        "synth",
        0
       ]
      },
      {
       "Ident": [
        "synth_is_zero",
        0
       ]
      }
     ],
     "span": {
      "Untagged": {
       "data": {
        "file_id": 0,
        "beg": {
         "line": 5,
         "col": 0
        },
        "end": {
         "line": 7,
         "col": 1
        }
       },
       "generated_from_span": null
      }
     },
     "has_errors": false
    },
    "signature": {
     "is_unsafe": false,
     "abi": "Rust",
     "is_variadic": false,
     "inputs": [
      {
       "Value": [
        4,
        {
         "Scalar": {
          "Integer": {
           "Unsigned": "U8"
          }
         }
        }
       ]
      }
     ],
     "output": {
      "Value": [
       6,
       {
        "Scalar": "Bool"
       }
      ]
     },
     "generics": {
      "regions": [],
      "types": [],
      "const_generics": [],
      "trait_clauses": [],
      "regions_outlive": [],
      "types_outlive": [],
      "trait_type_constraints": []
     }
    },
    "body": {
     "Structured": {
      "locals": {
       "arg_count": 1,
       "locals": [
        {
         "index": 0,
         "name": null,
         "ty": {
          "Deduplicated": 6
         }
        },
        {
         "index": 1,
         "name": "x",
         "ty": {
          "Deduplicated": 4
         }
        },
        {
         "index": 3,
         "name": null,
         "ty": {
          "Deduplicated": 6
         }
        },
        {
         "index": 4,
         "name": null,
         "ty": {
          "Deduplicated": 4
         }
        }
       ]
      },
      "body": {
       "statements": [
        {
         "kind": {
          "StorageLive": 0
         }
        },
        {
         "kind": {
          "StorageLive": 3
         }
        },
        {
         "kind": {
          "StorageLive": 4
         }
        },
        {
         "kind": {
          "Assign": [
           {
            "kind": {
             "Local": 4
            },
            "ty": {
             "Deduplicated": 4
            }
           },
           {
            "Use": [
             {
              "Copy": {
               "kind": {
                "Local": 1
               },
               "ty": {
                "Deduplicated": 4
               }
              }
             },
             "Yes"
            ]
           }
          ]
         }
        },
        {
         "kind": {
          "Assign": [
           {
            "kind": {
             "Local": 3
            },
            "ty": {
             "Deduplicated": 6
            }
           },
           {
            "BinaryOp": [
             "Eq",
             {
              "Move": {
               "kind": {
                "Local": 4
               },
               "ty": {
                "Deduplicated": 4
               }
              }
             },
             {
              "Const": {
               "Value": [
                7,
                [
                 {
                  "Integer": {
                   "Unsigned": [
                    "U8",
                    "0"
                   ]
                  }
                 },
                 {
                  "Deduplicated": 4
                 }
                ]
               ]
              }
             }
            ]
           }
          ]
         }
        },
        {
         "kind": {
          "Assign": [
           {
            "kind": {
             "Local": 0
            },
            "ty": {
             "Deduplicated": 6
            }
           },
           {
            "Use": [
             {
              "Move": {
               "kind": {
                "Local": 3
               },
               "ty": {
                "Deduplicated": 6
               }
              }
             },
             "Yes"
            ]
           }
          ]
         }
        },
        {
         "kind": {
          "StorageDead": 3
         }
        },
        {
         "kind": {
          "StorageDead": 4
         }
        },
        {
         "kind": "Return"
        }
       ]
      }
     }
    }
   }
  ]
 }
}
"""

suite "llbc_to_canonical — inline fixtures (probe-independent positives)":

  test "synthetic straight-line add: full pipeline from fixture JSON":
    let doc = parseJson(AddFixture)
    let r = llbcFunctionToCanonical(doc, "synth_add")
    check r.ok
    check r.error == rceNone
    check validateRustCanonical(r.canonical) == rceNone
    check r.canonical.modulePath == "synth"
    check r.canonical.funcName == "synth_add"
    check r.canonical.sourceIdentity == "src/synth.rs:1:0-3:1"
    check r.canonical.params.len == 2
    check r.canonical.params[0].name == "a"
    check r.canonical.params[1].name == "b"
    for p in r.canonical.params:
      check p.ty.widthBits == 8 and p.ty.signedness == rsgUnsigned
    check r.canonical.retType.widthBits == 8
    check r.canonical.failureMode == rfmPanicOnOverflowObserved
    check countAddChecked(r.canonical) == 1
    check r.canonical.body[r.canonical.body.len - 1].kind == rskReturn

  test "BinaryOp(Eq) + bool output + interned constant → valid canonical":
    let doc = parseJson(EqFixture)
    let r = llbcFunctionToCanonical(doc, "synth_is_zero")
    check r.ok
    check r.error == rceNone
    check validateRustCanonical(r.canonical) == rceNone
    check r.canonical.params.len == 1
    check r.canonical.params[0].name == "x"
    check r.canonical.params[0].ty.widthBits == 8
    # bool type resolved from {"Scalar": "Bool"} → (bool, 1, unsigned)
    check r.canonical.retType.kind == rtyBool
    check r.canonical.retType.widthBits == 1
    check r.canonical.retType.signedness == rsgUnsigned
    # no checked add in the body → NO failureMode observation
    check r.canonical.failureMode == rfmNoneObserved
    var eqSeen = false
    for s in r.canonical.body:
      if s.kind == rskAssign and s.rvalue.kind == rrvBinaryOp:
        eqSeen = true
        check s.rvalue.form == rboEq
        check s.rvalue.lhs.kind == ropMove
        check s.rvalue.rhs.kind == ropConstant
        check s.rvalue.rhs.value == 0
        check s.rvalue.rhs.ty.widthBits == 8
    check eqSeen

  test "BinaryOp(Lt) form → rceUnsupportedGrammar (boLtU does NOT widen " &
      "the Rust LLBC admission — comparison BinaryOp forms stay rejected)":
    let doc = parseJson(EqFixture.replace("\"Eq\"", "\"Lt\""))
    let r = llbcFunctionToCanonical(doc, "synth_is_zero")
    check not r.ok
    check r.error == rceUnsupportedGrammar
    check r.reason.contains("BinaryOp form 'Lt'")

  test "BinaryOp(Sub) form → rceUnsupportedGrammar (same closed grammar)":
    let doc = parseJson(EqFixture.replace("\"Eq\"", "\"Sub\""))
    let r = llbcFunctionToCanonical(doc, "synth_is_zero")
    check not r.ok
    check r.error == rceUnsupportedGrammar
    check r.reason.contains("BinaryOp form 'Sub'")

  test "deduplicated constant reference resolves via the const intern table":
    # second Eq referencing {"Const": {"Deduplicated": 7}} — the constant
    # interned by the first Eq's {"Value": [7, …]}
    var doc = parseJson(EqFixture).copy()
    doc["translated"]["fun_decls"][0]["body"]["Structured"]["body"]["statements"] =
      parseJson("""[
 {
  "kind": {
   "StorageLive": 0
  }
 },
 {
  "kind": {
   "StorageLive": 3
  }
 },
 {
  "kind": {
   "StorageLive": 4
  }
 },
 {
  "kind": {
   "Assign": [
    {
     "kind": {
      "Local": 4
     },
     "ty": {
      "Deduplicated": 4
     }
    },
    {
     "Use": [
      {
       "Copy": {
        "kind": {
         "Local": 1
        },
        "ty": {
         "Deduplicated": 4
        }
       }
      },
      "Yes"
     ]
    }
   ]
  }
 },
 {
  "kind": {
   "Assign": [
    {
     "kind": {
      "Local": 3
     },
     "ty": {
      "Deduplicated": 6
     }
    },
    {
     "BinaryOp": [
      "Eq",
      {
       "Move": {
        "kind": {
         "Local": 4
        },
        "ty": {
         "Deduplicated": 4
        }
       }
      },
      {
       "Const": {
        "Value": [
         7,
         [
          {
           "Integer": {
            "Unsigned": [
             "U8",
             "0"
            ]
           }
          },
          {
           "Deduplicated": 4
          }
         ]
        ]
       }
      }
     ]
    }
   ]
  }
 },
 {
  "kind": {
   "Assign": [
    {
     "kind": {
      "Local": 0
     },
     "ty": {
      "Deduplicated": 6
     }
    },
    {
     "BinaryOp": [
      "Eq",
      {
       "Const": {
        "Deduplicated": 7
       }
      },
      {
       "Const": {
        "Deduplicated": 7
       }
      }
     ]
    }
   ]
  }
 },
 {
  "kind": {
   "StorageDead": 3
  }
 },
 {
  "kind": {
   "StorageDead": 4
  }
 },
 {
  "kind": "Return"
 }
]""")
    let r = llbcFunctionToCanonical(doc, "synth_is_zero")
    check r.ok
    var dedupConstSeen = false
    for s in r.canonical.body:
      if s.kind == rskAssign and s.rvalue.kind == rrvBinaryOp:
        if s.rvalue.lhs.kind == ropConstant:
          dedupConstSeen = true
          check s.rvalue.lhs.value == 0
          check s.rvalue.lhs.ty.widthBits == 8
    check dedupConstSeen

# ─── Suite 3: inline fixtures — the rejection matrix (fail-closed) ──────────

proc withStatements(stmts: string): JsonNode =
  ## The Add fixture with its statement list replaced.
  var doc = parseJson(AddFixture).copy()
  doc["translated"]["fun_decls"][0]["body"]["Structured"]["body"]["statements"] =
    parseJson(stmts)
  doc

proc withDecl(mutate: proc (fd: JsonNode)): JsonNode =
  ## The Add fixture with its fun_decl mutated (generics live at decl level
  ## in the measured charon 0.1.281 shape).
  var doc = parseJson(AddFixture).copy()
  mutate(doc["translated"]["fun_decls"][0])
  doc

suite "llbc_to_canonical — rejection matrix (fail-closed, nothing dropped)":

  test "Call statement → rceUnsupportedGrammar naming the kind":
    let r = llbcFunctionToCanonical(withStatements("""[
 {
  "kind": {
   "StorageLive": 0
  }
 },
 {
  "kind": {
   "Assert": {
    "assert": {
     "cond": {
      "Copy": {
       "kind": {
        "Local": 3
       },
       "ty": {
        "Deduplicated": 4
       }
      }
     },
     "expected": true,
     "check_kind": {
      "Overflow": [
       {
        "Add": "Wrap"
       }
      ]
     }
    },
    "on_failure": {
     "Panic": null
    }
   }
  }
 },
 {
  "kind": "Return"
 }
]"""), "synth_add")
    check not r.ok
    check r.error == rceUnsupportedGrammar
    check r.reason.contains("Assert outside the checked-add pattern")

  test "Return not last → rceMalformed (validation re-check after production)":
    let r = llbcFunctionToCanonical(withStatements("""[
      {"kind": {"StorageLive": 0}},
      {"kind": "Return"},
      {"kind": {"StorageDead": 3}}]"""), "synth_add")
    check not r.ok
    check r.error == rceMalformed
    check r.reason.contains("validation")

  test "unknown function name → not found (explicit, not a default)":
    let doc = parseJson(AddFixture)
    let r = llbcFunctionToCanonical(doc, "no_such_function")
    check not r.ok
    check r.error == rceMalformed
    check r.reason.contains("not found")

  test "top-level has_errors → rejected for every extraction":
    var doc = parseJson(AddFixture)
    doc["has_errors"] = newJBool(true)
    let r = llbcFunctionToCanonical(doc, "synth_add")
    check not r.ok
    check r.reason.contains("has_errors")

  test "parseLlbcFile on a missing path → explicit not-ok (never raises)":
    let f = parseLlbcFile("/tmp/axiom_llbc_no_such_file.llbc")
    check not f.ok
    check f.root.isNil
    check f.reason.len > 0

  test "llbcAllToCanonical on the fixture → exactly the one declaration":
    let all = llbcAllToCanonical(parseJson(AddFixture))
    check all.len == 1
    check all[0].ok

# ─── Suite 2: impl identity (axiom_impl_probe fixture, 2026-11-02) ───────────
#
# The committed fixture (tests/fixtures/rust/axiom_impl_probe/) pins the
# DEBT#510 closure and the Q11/Q12 quirks: cross-module same-last-segment
# free functions (m1::add_u8 / m2::add_u8), inherent-impl methods with
# intern-resolved Adt owners (Dog/Cat), a scalar-owner prototype
# (core::num::<impl u8>::wrapping_add), and the layout-expression type-id
# pollution (Q12) that the intern collector must skip.

const ImplFixturePath = currentSourcePath().parentDir().parentDir() /
    "fixtures" / "rust" / "axiom_impl_probe" / "axiom_impl_probe.llbc"

suite "llbc_to_canonical — impl identity (axiom_impl_probe fixture)":

  let f = parseLlbcFile(ImplFixturePath)

  test "fixture parses as LLBC JSON":
    check f.ok
    check not f.root.isNil

  test "llbcFunDeclNamePaths: impl methods exposed with owner-qualified " &
      "structured names, document order; scalar-owner prototype skipped":
    let paths = llbcFunDeclNamePaths(f.root)
    var fullNames: seq[string] = @[]
    for p in paths: fullNames.add(p.fullName)
    check fullNames == @[
      "axiom_impl_probe::free_add_u8",
      "axiom_impl_probe::m1::add_u8",
      "axiom_impl_probe::m2::add_u8",
      "axiom_impl_probe::m1::Dog::new",
      "axiom_impl_probe::m1::Dog::speak",
      "axiom_impl_probe::m2::Cat::new",
      "axiom_impl_probe::m2::Cat::speak"]
    # the scalar-owner impl (core::num::<impl u8>::wrapping_add) has no
    # nominal owner path (Q11) — unaddressable, skipped, never invented
    for p in paths:
      check not p.fullName.contains("wrapping_add")
    # lastSegment is the bare word for every entry
    check paths[3].lastSegment == "new"
    check paths[4].lastSegment == "speak"

  test "DEBT#510: bare add_u8 → EXPLICIT Ambiguous naming both candidates " &
      "(never the first document-order m1 match)":
    let r = llbcFunctionToCanonical(f.root, "add_u8")
    check not r.ok
    check r.error == rceMalformed
    check r.reason.contains("ambiguous target 'add_u8'")
    check r.reason.contains("axiom_impl_probe::m1::add_u8")
    check r.reason.contains("axiom_impl_probe::m2::add_u8")
    check r.reason.contains("DEBT#510")

  test "exact structured name axiom_impl_probe::m1::add_u8 → the m1 decl " &
      "(modulePath/sourceIdentity m1, NOT m2)":
    let r = llbcFunctionToCanonical(f.root, "axiom_impl_probe::m1::add_u8")
    check r.ok
    check r.error == rceNone
    check validateRustCanonical(r.canonical) == rceNone
    check r.canonical.modulePath == "axiom_impl_probe::m1"
    check r.canonical.funcName == "add_u8"
    check r.canonical.sourceIdentity == "src/m1.rs:12:0-14:1"
    # Q12 regression: the u8 intern id 0 resolves THROUGH the type space
    # (item_names), not the shadowing Dog layout Constant — the params
    # decode as u8 and the body collapses to one AddChecked
    check r.canonical.params.len == 2
    for p in r.canonical.params:
      check p.ty.kind == rtyInt
      check p.ty.widthBits == 8
      check p.ty.signedness == rsgUnsigned
    check r.canonical.retType.kind == rtyInt
    check r.canonical.retType.widthBits == 8
    check countAddChecked(r.canonical) == 1
    check r.canonical.failureMode == rfmPanicOnOverflowObserved
    check r.canonical.body[r.canonical.body.len - 1].kind == rskReturn

  test "exact structured name axiom_impl_probe::m2::add_u8 → the m2 decl " &
      "(the identity is DISTINCT — the selection is not first-match)":
    let r = llbcFunctionToCanonical(f.root, "axiom_impl_probe::m2::add_u8")
    check r.ok
    check r.error == rceNone
    check r.canonical.modulePath == "axiom_impl_probe::m2"
    check r.canonical.funcName == "add_u8"
    check r.canonical.sourceIdentity == "src/m2.rs:12:0-14:1"
    check countAddChecked(r.canonical) == 1

  test "impl method exact name Dog::speak → SELECTED and honestly " &
      "out-of-subset (borrowed self ⇒ region generic), never NotFound":
    let r = llbcFunctionToCanonical(f.root, "axiom_impl_probe::m1::Dog::speak")
    check not r.ok
    check r.error == rceUnsupportedGrammar
    # Measured: an &self method carries an anonymous region generic, so the
    # monomorphic gate fires BEFORE param decoding names the Ref type — the
    # reason honestly names the generic parameter (selection is proven by
    # reaching the decl's own signature gates, not a NotFound/ambiguous).
    check r.reason.contains("regions")

  test "bare speak → EXPLICIT Ambiguous across impl owners":
    let r = llbcFunctionToCanonical(f.root, "speak")
    check not r.ok
    check r.error == rceMalformed
    check r.reason.contains("ambiguous target 'speak'")
    check r.reason.contains("axiom_impl_probe::m1::Dog::speak")
    check r.reason.contains("axiom_impl_probe::m2::Cat::speak")

  test "bare new → EXPLICIT Ambiguous (Dog::new / Cat::new)":
    let r = llbcFunctionToCanonical(f.root, "new")
    check not r.ok
    check r.error == rceMalformed
    check r.reason.contains("ambiguous target 'new'")

  test "single-bare-name fallback survives: free_add_u8 selected, honest " &
      "Call rejection (wrapping_add body is out-of-subset)":
    let r = llbcFunctionToCanonical(f.root, "free_add_u8")
    check not r.ok
    check r.error == rceUnsupportedGrammar
    check r.reason.contains("Call")

  test "scalar-owner prototype by bare name → extern prototype (unaddressable " &
      "by structured name; last-segment fallback still reports it honestly)":
    let r = llbcFunctionToCanonical(f.root, "wrapping_add")
    check not r.ok
    check r.reason.contains("no Structured body")

  test "unknown structured name → NotFound unchanged":
    let r = llbcFunctionToCanonical(f.root, "axiom_impl_probe::m3::add_u8")
    check not r.ok
    check r.reason.contains("not found")

# ─── Suite 3: u64 boundary types (axiom_u64_probe fixture, 2026-11-02) ───────
#
# The committed fixture (tests/fixtures/rust/axiom_u64_probe/) pins the ③
# u64 full-domain slice (docs/spec/rust_certified_subset.md §1 v1.2):
# echo (boundary passthrough — params/returns certified), seven /
# seven_mutant (u64 constant operands — the decodeConstOperand U64
# admission), and add / add_mutant (full-width '+' — v1.2 RETIRED the
# producer wall: the no-overflow obligation discharges in the equivalent
# closed form `lhs + rhs ≤ 2^64−1` via the two-part literal form; the
# retired refusal reason stays greppable as `retiredWidth64WallReason` so
# a regression back to the wall is machine-detectable).

const U64FixturePath = currentSourcePath().parentDir().parentDir() /
    "fixtures" / "rust" / "axiom_u64_probe" / "axiom_u64_probe.llbc"

suite "llbc_to_canonical — u64 boundary types (axiom_u64_probe fixture)":

  let f = parseLlbcFile(U64FixturePath)

  test "fixture parses as LLBC JSON":
    check f.ok
    check not f.root.isNil

  test "llbcFunctionNames, document order":
    check llbcFunctionNames(f.root) ==
      @["u64_echo", "u64_seven", "u64_seven_mutant", "u64_add",
        "u64_add_mutant"]

  test "u64_echo → valid canonical; the param AND the return are u64 " &
      "(the boundary row certifies identity/params/returns)":
    let r = llbcFunctionToCanonical(f.root, "u64_echo")
    check r.ok
    check r.error == rceNone
    check validateRustCanonical(r.canonical) == rceNone
    check r.canonical.funcName == "u64_echo"
    check r.canonical.modulePath == "axiom_u64_probe"
    check r.canonical.sourceIdentity == "src/lib.rs:1:0-3:1"
    check r.canonical.params.len == 1
    check r.canonical.params[0].name == "x"
    for t in [r.canonical.params[0].ty, r.canonical.retType]:
      check t.kind == rtyInt
      check t.widthBits == 64
      check t.signedness == rsgUnsigned
    check countAddChecked(r.canonical) == 0
    check r.canonical.failureMode == rfmNoneObserved
    # body: one collapsed Assign(_0, Use(Copy x)) — the operand keeps the
    # source-level local name (measured: local 1 is "x"), + Return LAST
    var found = false
    for s in r.canonical.body:
      if s.kind == rskAssign and s.rvalue.kind == rrvUse:
        found = true
        check s.dest == "_0"
        check s.rvalue.operand.kind == ropCopy
        check s.rvalue.operand.place == "x"
    check found
    check r.canonical.body[r.canonical.body.len - 1].kind == rskReturn

  test "u64_echo → the produced canonical flows through the wire codec " &
      "(isSupportedRustType admits width 64 on both codec sides)":
    let r = llbcFunctionToCanonical(f.root, "u64_echo")
    let wire = serializeCanonicalWire(r.canonical)
    check wire.ok
    let decoded = deserializeCanonicalWire(wire.bytes)
    check decoded.ok
    check validateRustCanonical(decoded.canonical) == rceNone
    check decoded.canonical.retType.widthBits == 64

  test "u64_seven → constant operand 7 typed u64 (the decodeConstOperand " &
      "U64 admission — the inline {\"Integer\": {\"Unsigned\": [\"U64\", …]}})":
    let r = llbcFunctionToCanonical(f.root, "u64_seven")
    check r.ok
    check r.error == rceNone
    check validateRustCanonical(r.canonical) == rceNone
    check r.canonical.funcName == "u64_seven"
    check r.canonical.sourceIdentity == "src/lib.rs:5:0-7:1"
    check r.canonical.retType.widthBits == 64
    var constSeen = false
    for s in r.canonical.body:
      if s.kind == rskAssign and s.rvalue.kind == rrvUse and
          s.rvalue.operand.kind == ropConstant:
        constSeen = true
        check s.rvalue.operand.value == 7
        check s.rvalue.operand.ty.kind == rtyInt
        check s.rvalue.operand.ty.widthBits == 64
        check s.rvalue.operand.ty.signedness == rsgUnsigned
    check constSeen
    # the constant flows through the wire codec too
    let wire = serializeCanonicalWire(r.canonical)
    check wire.ok

  test "u64_seven_mutant → constant operand 8 typed u64 (the negative " &
      "control's spec result == 7 is falsified by THIS 8)":
    let r = llbcFunctionToCanonical(f.root, "u64_seven_mutant")
    check r.ok
    check r.error == rceNone
    check r.canonical.funcName == "u64_seven_mutant"
    check r.canonical.sourceIdentity == "src/lib.rs:9:0-11:1"
    var constSeen = false
    for s in r.canonical.body:
      if s.kind == rskAssign and s.rvalue.kind == rrvUse and
          s.rvalue.operand.kind == ropConstant:
        constSeen = true
        check s.rvalue.operand.value == 8
        check s.rvalue.operand.ty.widthBits == 64
    check constSeen
    # distinct wire bytes from u64_seven — the mutant IS a distinct subject
    let seven = llbcFunctionToCanonical(f.root, "u64_seven").canonical
    let wMut = serializeCanonicalWire(r.canonical)
    let wSeven = serializeCanonicalWire(seven)
    check wMut.ok and wSeven.ok
    check wMut.bytes != wSeven.bytes

  test "u64_add → ADMITTED (v1.2 wall retirement): full-width '+' collapses " &
      "to AddChecked; the retired refusal reason stays greppable as the " &
      "named constant (a regression back to the wall is machine-detectable)":
    let r = llbcFunctionToCanonical(f.root, "u64_add")
    check r.ok
    check r.error == rceNone
    check validateRustCanonical(r.canonical) == rceNone
    check r.canonical.funcName == "u64_add"
    check r.canonical.params.len == 2
    check r.canonical.retType.widthBits == 64
    check countAddChecked(r.canonical) >= 1
    # the retired wall reason is preserved VERBATIM (exported constant —
    # the string must stay greppable in source per docs/spec §1)
    check retiredWidth64WallReason.len > 0
    check retiredWidth64WallReason.contains("full-width '+' outside the closed v1 set")
    check retiredWidth64WallReason.contains("unrepresentable in the IR literal domain")
    check retiredWidth64WallReason.contains("boundary-type-only")
    check retiredWidth64WallReason.contains("wraparound/checked semantics are the declared follow-up")

  test "u64_add_mutant → distinct admitted canonical (the negative " &
      "control: a + b + 1 yields its own AddChecked shape)":
    let r = llbcFunctionToCanonical(f.root, "u64_add_mutant")
    check r.ok
    check r.error == rceNone
    check validateRustCanonical(r.canonical) == rceNone
    check r.canonical.funcName == "u64_add_mutant"
    check countAddChecked(r.canonical) >= 1
    # distinct wire bytes from u64_add — the mutant IS a distinct subject
    let add = llbcFunctionToCanonical(f.root, "u64_add").canonical
    let wMut = serializeCanonicalWire(r.canonical)
    let wAdd = serializeCanonicalWire(add)
    check wMut.ok and wAdd.ok
    check wMut.bytes != wAdd.bytes

  proc sevenConstValue(doc: JsonNode): JsonNode =
    doc["translated"]["fun_decls"][1]["body"]["Structured"]["body"]["statements"][1]["kind"]["Assign"][1]["Use"][0]["Const"]["Value"][1]

  test "u64 constant 16-digit literal (old 15-digit cap) → accepted over " &
      "the full u64 range (signed-domain value, exact)":
    var doc = f.root.copy()
    let constArr = sevenConstValue(doc)
    constArr[0]["Integer"]["Unsigned"].elems[1] = %"1234567890123456"
    let r = llbcFunctionToCanonical(doc, "u64_seven")
    check r.ok
    check r.error == rceNone
    var constSeen = false
    for s in r.canonical.body:
      if s.kind == rskAssign and s.rvalue.kind == rrvUse and
          s.rvalue.operand.kind == ropConstant:
        constSeen = true
        check s.rvalue.operand.value == 1234567890123456
        check s.rvalue.operand.valueU64 == 0'u64  # signed domain active
    check constSeen

  test "u64 constant 2^63 exactly → the u64-domain two-part form " &
      "(valueU64 carries it; never a signed reinterpretation)":
    var doc = f.root.copy()
    let constArr = sevenConstValue(doc)
    constArr[0]["Integer"]["Unsigned"].elems[1] = %"9223372036854775808"
    let r = llbcFunctionToCanonical(doc, "u64_seven")
    check r.ok
    check r.error == rceNone
    var constSeen = false
    for s in r.canonical.body:
      if s.kind == rskAssign and s.rvalue.kind == rrvUse and
          s.rvalue.operand.kind == ropConstant:
        constSeen = true
        check s.rvalue.operand.value == 0
        check s.rvalue.operand.valueU64 == 9223372036854775808'u64
    check constSeen
    # the two-part form survives the wire codec byte-exactly
    let wire = serializeCanonicalWire(r.canonical)
    check wire.ok
    let decoded = deserializeCanonicalWire(wire.bytes)
    check decoded.ok
    var decodedSeen = false
    for s in decoded.canonical.body:
      if s.kind == rskAssign and s.rvalue.kind == rrvUse and
          s.rvalue.operand.kind == ropConstant:
        decodedSeen = true
        check s.rvalue.operand.value == 0
        check s.rvalue.operand.valueU64 == 9223372036854775808'u64
    check decodedSeen

  test "u64 constant 2^64−1 (real boundary) → accepted, u64-domain form":
    var doc = f.root.copy()
    let constArr = sevenConstValue(doc)
    constArr[0]["Integer"]["Unsigned"].elems[1] = %"18446744073709551615"
    let r = llbcFunctionToCanonical(doc, "u64_seven")
    check r.ok
    check r.error == rceNone
    var constSeen = false
    for s in r.canonical.body:
      if s.kind == rskAssign and s.rvalue.kind == rrvUse and
          s.rvalue.operand.kind == ropConstant:
        constSeen = true
        check s.rvalue.operand.value == 0
        check s.rvalue.operand.valueU64 == 18446744073709551615'u64
    check constSeen

  test "u64 constant beyond the 20-digit parse cap → malformed":
    var doc = f.root.copy()
    let constArr = sevenConstValue(doc)
    constArr[0]["Integer"]["Unsigned"].elems[1] = %"123456789012345678901"
    let r = llbcFunctionToCanonical(doc, "u64_seven")
    check not r.ok
    check r.error == rceMalformed
    check r.reason.contains("20-digit cap")

  test "u64 constant 20 digits but > 2^64−1 → malformed (full u64 range " &
      "check — the accepted domain is [0, 2^64−1], nothing wider)":
    var doc = f.root.copy()
    let constArr = sevenConstValue(doc)
    constArr[0]["Integer"]["Unsigned"].elems[1] = %"99999999999999999999"
    let r = llbcFunctionToCanonical(doc, "u64_seven")
    check not r.ok
    check r.error == rceMalformed
    check r.reason.contains("exceeds u64 range")

  test "u64 constant tag vs a u8 interned/inline type → width mismatch " &
      "malformed (type/width agreement still enforced at width 64)":
    var doc = f.root.copy()
    let constArr = sevenConstValue(doc)
    constArr.elems[1] = %*{"Scalar": {"Integer": {"Unsigned": "U8"}}}
    let r = llbcFunctionToCanonical(doc, "u64_seven")
    check not r.ok
    check r.error == rceMalformed
    check r.reason.contains("integer constant typed U64 but its interned type is not u64")
