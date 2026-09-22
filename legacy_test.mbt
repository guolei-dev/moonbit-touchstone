///|
test "legacy defaults orders units and SI normalization" {
  let n = @touchstone.parse_legacy(
    "! input\r# MHz S RI R 50\r1 11 1 21 2\r12 3 22 4\r2 1 0 2 0 3 0 4 0",
    ports=2,
  )
  assert_eq(n.frequency_hz()[0], 1000000.0)
  let m = n.matrix(0)
  assert_eq(m[1].re, 12.0)
  assert_eq(m[2].re, 21.0)
  let z = @touchstone.parse_legacy(
    "# Hz Z RI R 4 9\n1 1 0 2 0 3 0 4 0",
    ports=2,
  )
  let zm = z.matrix(0)
  for i, x in [4.0, 18.0, 12.0, 36.0] {
    assert_true((zm[i].re - x).abs() < 1.0e-14)
  }
  let y = @touchstone.parse_legacy("# Y RI R 100 Hz\n1 2 0", ports=1)
  assert_true((y.matrix(0)[0].re - 0.02).abs() < 1.0e-15)
  let default = @touchstone.parse_legacy("#\n1 0.5 90", ports=1)
  assert_eq(default.frequency_hz()[0], 1000000000.0)
  assert_true((default.matrix(0)[0].im - 0.5).abs() < 1.0e-14)
}

///|
test "legacy physical hybrid units and generated output" {
  for kind in ["S", "Z", "Y", "H", "G"] {
    let text = "# Hz \{kind} RI R 4 9\n1 1 2 3 4 5 6 7 8"
    let n = @touchstone.parse_legacy(text, ports=2)
    if kind == "H" {
      let m = n.matrix(0)
      for i, x in [4.0, 10.0 / 3.0, 2.0, 7.0 / 9.0] {
        assert_true((m[i].re - x).abs() < 1.0e-14)
      }
    }
    for format in ["RI", "MA", "DB"] {
      let back = @touchstone.parse_legacy(
        n.write_legacy(format~, unit="KHZ"),
        ports=2,
      )
      for i, value in n.matrix(0) {
        assert_true(back.matrix(0)[i].sub(value).magnitude() < 1.0e-10)
      }
    }
  }
}

///|
test "legacy rejects malformed or misleading inputs" {
  for
    text in [
      "1 2 3", "#\n1 nan 0", "#\n1 0.5", "#\n1 -0.5 0", "#\n1 0.5 0\n1 0.2 0", "# THZ\n1 1 0",
      "# R -1\n1 1 0", "# RI RI\n1 1 0", "#\n1_0 1 0", "#\n1 1 0\u0000",
    ] {
    try @touchstone.parse_legacy(text, ports=1) catch {
      _ => ()
    } noraise {
      _ => fail("accepted malformed input: " + text)
    }
  }
}
