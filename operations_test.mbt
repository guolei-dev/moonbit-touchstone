///|
test "known impedance conversion and ideal thru remain nonsingular where defined" {
  let c = (x : Double) => @touchstone.complex(x)
  let z = @touchstone.network(1, [1.0], [[c(100.0)]], [50.0], parameter="Z")
  assert_true((z.convert("S").matrix(0)[0].re - 1.0 / 3.0).abs() < 1.0e-14)
  assert_true((z.convert("Y").matrix(0)[0].re - 0.01).abs() < 1.0e-14)
  let open = @touchstone.network(1, [1.0], [[c(0.0)]], [50.0], parameter="Y")
  assert_eq(open.convert("S").matrix(0)[0].re, 1.0)
  let thru = @touchstone.network(2, [1.0], [[c(0.0), c(1.0), c(1.0), c(0.0)]], [
    50.0, 50.0,
  ])
  assert_true(
    (thru.renormalize([75.0, 75.0]).matrix(0)[2].re - 1.0).abs() < 1.0e-14,
  )
  assert_eq(thru.cascade(thru).matrix(0)[2].re, 1.0)
  try thru.convert("Z") catch {
    _ => ()
  } noraise {
    _ => fail("undefined thru Z accepted")
  }
}

///|
test "hybrid definitions and matched-port selection" {
  let c = (x : Double) => @touchstone.complex(x)
  let z = @touchstone.network(
    2,
    [1.0, 2.0],
    [[c(4.0), c(2.0), c(3.0), c(6.0)], [c(8.0), c(4.0), c(6.0), c(12.0)]],
    [50.0, 75.0],
    parameter="Z",
  )
  let h = z.convert("H").matrix(0)
  for i, value in [3.0, 1.0 / 3.0, -0.5, 1.0 / 6.0] {
    assert_true((h[i].re - value).abs() < 1.0e-13)
  }
  for kind in ["S", "Y", "H", "G"] {
    let back = z.convert(kind).convert("Z")
    for i, value in z.matrix(0) {
      assert_true(back.matrix(0)[i].sub(value).magnitude() < 1.0e-11)
    }
  }
  assert_true((z.interpolate([1.5]).matrix(0)[0].re - 6.0).abs() < 1.0e-14)
  let s = z.convert("S")
  assert_eq(s.select_ports([1]).matrix(0)[0].re, s.matrix(0)[3].re)
  try z.interpolate([0.0]) catch {
    _ => ()
  } noraise {
    _ => fail("extrapolation accepted")
  }
  try s.select_ports([0, 0]) catch {
    _ => ()
  } noraise {
    _ => fail("duplicate ports accepted")
  }
}

///|
test "matched attenuator cascade and fixture removal" {
  let c = (x : Double) => @touchstone.complex(x)
  let a = @touchstone.network(2, [1.0], [[c(0.0), c(0.5), c(0.5), c(0.0)]], [
    50.0, 50.0,
  ])
  let total = a.cascade(a).cascade(a)
  assert_eq(total.matrix(0)[2].re, 0.125)
  let recovered = total.deembed(a, a)
  assert_eq(recovered.matrix(0)[2].re, 0.5)
}
