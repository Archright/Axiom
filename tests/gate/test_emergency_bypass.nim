import std/os
import unittest
import core/trusted/bypass_verify

suite("emergency bypass"):

  test "AXIOM_EMERGENCY_NO_VERIFY not set returns false":
    delEnv("AXIOM_EMERGENCY_NO_VERIFY")
    check not isEmergencyBypass()

  test "AXIOM_EMERGENCY_NO_VERIFY=1 returns true":
    putEnv("AXIOM_EMERGENCY_NO_VERIFY", "1")
    check isEmergencyBypass()

  test "AXIOM_EMERGENCY_NO_VERIFY=true returns true (case-insensitive)":
    putEnv("AXIOM_EMERGENCY_NO_VERIFY", "true")
    check isEmergencyBypass()
    putEnv("AXIOM_EMERGENCY_NO_VERIFY", "TRUE")
    check isEmergencyBypass()
    putEnv("AXIOM_EMERGENCY_NO_VERIFY", "True")
    check isEmergencyBypass()
    putEnv("AXIOM_EMERGENCY_NO_VERIFY", " tRuE ")
    check isEmergencyBypass()

  test "AXIOM_EMERGENCY_NO_VERIFY=0 returns false":
    putEnv("AXIOM_EMERGENCY_NO_VERIFY", "0")
    check not isEmergencyBypass()

  test "AXIOM_EMERGENCY_NO_VERIFY=other values returns false":
    for val in ["false", "yes", "on", "2", "", "random"]:
      putEnv("AXIOM_EMERGENCY_NO_VERIFY", val)
      check(not isEmergencyBypass()) == true
