///|
fn header2(kind : String, count? : Int = 1) -> String {
  "[Version] 2.1\n# Hz \{kind} RI R 50\n[Number of Ports] 2\n[Two-Port Data Order] 12_21\n[Number of Frequencies] \{count}\n"
}

///|
test "2.x layouts references and physical non-S values" {
  for version in ["2.0", "2.1"] {
    for layout in ["Full", "Upper", "Lower"] {
      let records = if layout == "Full" {
        "10 1 2 3 4 3 4 5 6"
      } else {
        "10 1 2 3 4 5 6"
      }
      let text = "[Version] \{version}\n# Hz Z RI\n[Number of Ports] 2\n[Two-Port Data Order] 12_21\n[Number of Frequencies] 1\n[Reference]\n25\n100\n[Matrix Format] \{layout}\n[Network Data]\n\{records}\n[End]"
      let d = @touchstone.parse(text)
      let n = d.network_only()
      assert_eq(n.reference_ohms()[1], 100.0)
      assert_eq(n.matrix(0)[0].re, 1.0)
      // Off diagonal symmetry copies, not complex conjugation.
      assert_eq(n.matrix(0)[1].im, 4.0)
      assert_eq(n.matrix(0)[2].im, 4.0)
      assert_eq(
        @touchstone.parse(d.write()).network_only().matrix(0)[3].re,
        5.0,
      )
    }
  }
  let d = @touchstone.parse(
    header2("S") + "[Network Data]\n10 11 0 12 0 21 0 22 0\n[End]",
  )
  assert_eq(d.network_only().matrix(0)[1].re, 12.0)
}

///|
test "noise reference remains independent of Reference keyword" {
  let text = header2("S") +
    "[Reference] 75 75\n[Number of Noise Frequencies] 1\n[Network Data]\n10 0.1 0 0.2 0 0.3 0 0.4 0\n[Noise Data]\n1 2 0.5 90 5\n[End]"
  let d = @touchstone.parse(text)
  assert_eq(d.raw_network().reference_ohms()[0], 75.0)
  assert_eq(d.noise_reference_ohms(), 50.0)
  assert_eq(d.noise_data()[0].resistance_ohms, 5.0)
  assert_true((d.noise_data()[0].gamma_opt.im - 0.5).abs() < 1.0e-14)
  let back = @touchstone.parse(d.write())
  assert_eq(back.noise_reference_ohms(), 50.0)
  assert_eq(back.noise_data()[0].resistance_ohms, 5.0)
  try d.network_only() catch {
    _ => ()
  } noraise {
    _ => fail("metadata silently discarded")
  }
  let legacy = @touchstone.parse(
    "# Hz S RI R 50 75\n10 0.1 0 0.2 0 0.3 0 0.4 0\n1 2 0.5 90 0.1\n",
    ports=2,
  )
  assert_eq(legacy.noise_data()[0].resistance_ohms, 5.0)
  assert_eq(legacy.noise_reference_ohms(), 50.0)
}

///|
test "mixed mode validation information and loss prevention" {
  let base = "[Version] 2.1\n# Hz S RI\n[Number of Ports] 3\n[Number of Frequencies] 1\n"
  let body = "[Network Data]\n1 " +
    Array::make(9, "0.1 0").join(" ") +
    "\n[End]"
  let d = @touchstone.parse(
    base +
    "[Mixed-Mode Order]\nD1,2 S3 C1,2\n[Begin Information]\nfixture description ! retained\n[End Information]\n" +
    body,
  )
  assert_eq(d.mixed_mode_order()[0], "D1,2")
  assert_eq(
    @touchstone.parse(d.write()).information_lines()[0],
    "fixture description ! retained",
  )
  try d.network_only() catch {
    _ => ()
  } noraise {
    _ => fail("mixed data exposed as single ended")
  }
  for mode in ["D1,2 C2,1 S3", "D1,2 C1,2 S2", "S1 S1 S3", "D1,2 S2 S3"] {
    try
      @touchstone.parse(base + "[Mixed-Mode Order] " + mode + "\n" + body)
    catch {
      _ => ()
    } noraise {
      _ => fail("invalid mode accepted: " + mode)
    }
  }
}

///|
test "versioned malformed boundaries reject rather than truncate" {
  let body = "[Network Data]\n1 0 0 0 0 0 0 0 0\n[End]"
  for
    text in [
      header2("S") + body + "\n1 2",
      header2("S", count=2) + body,
      header2("S") + "[Reference] 50\n" + body,
      header2("S") + "[Number of Noise Frequencies] 1\n" + body,
      header2("S") + "[Reference] 50 50\n[Reference] 50 50\n" + body,
      header2("S") + "[Unknown] abc\n" + body,
      header2("S") + " [Network Data]\n1 0 0 0 0 0 0 0 0\n[End]",
    ] {
    try @touchstone.parse(text) catch {
      _ => ()
    } noraise {
      _ => fail("invalid versioned file accepted")
    }
  }
}
