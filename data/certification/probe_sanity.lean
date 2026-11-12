theorem axiom_continuity_probe_sanity (x : Int) (r : Int)
    (h1 : r = if x * 2 > 100 then 0 else x * 2)
    (h2 : x * 2 > 100) :
    r = 0 := by
  simp [h1, h2]
