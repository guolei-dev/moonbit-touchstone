///|
test "complex division and scaled inverse independently known solutions" {
  let a = @touchstone.complex(1.0, im=2.0).divide(
    @touchstone.complex(3.0, im=-4.0),
  )
  assert_true((a.re + 0.2).abs() < 1.0e-14)
  assert_true((a.im - 0.4).abs() < 1.0e-14)
  let c = (x : Double) => @touchstone.complex(x)
  let inv = @touchstone.invert_matrix(2, [c(4.0), c(7.0), c(2.0), c(6.0)])
  for i, expected in [0.6, -0.7, -0.2, 0.4] {
    assert_true((inv[i].re - expected).abs() < 1.0e-14)
  }
  // Row pivoting is necessary; inverse is [[0, 1/3], [1/2, 0]].
  let swapped = @touchstone.invert_matrix(2, [c(0.0), c(2.0), c(3.0), c(0.0)])
  assert_true((swapped[1].re - 1.0 / 3.0).abs() < 1.0e-14)
  assert_true((swapped[2].re - 0.5).abs() < 1.0e-14)
  try @touchstone.invert_matrix(2, [c(1.0), c(2.0), c(2.0), c(4.0)]) catch {
    _ => ()
  } noraise {
    _ => fail("singular input must fail")
  }
}

///|
test "owned network validation and caller isolation" {
  let frequencies = [1.0, 2.0]
  let reference = [50.0]
  let values = [[@touchstone.complex(0.2)], [@touchstone.complex(0.3)]]
  let net = @touchstone.network(1, frequencies, values, reference)
  frequencies[0] = -1.0
  reference[0] = 0.0
  values[0][0] = @touchstone.complex(99.0)
  assert_eq(net.frequency_hz()[0], 1.0)
  assert_eq(net.reference_ohms()[0], 50.0)
  assert_eq(net.matrix(0)[0].re, 0.2)
  let copy = net.matrix(0)
  copy[0] = @touchstone.complex(88.0)
  assert_eq(net.matrix(0)[0].re, 0.2)
  try @touchstone.network(1, [2.0, 1.0], values, [50.0]) catch {
    _ => ()
  } noraise {
    _ => fail("unsorted frequencies accepted")
  }
  try
    @touchstone.network(1, [1.0], [[@touchstone.complex(0.0 / 0.0)]], [50.0])
  catch {
    _ => ()
  } noraise {
    _ => fail("NaN accepted")
  }
}
