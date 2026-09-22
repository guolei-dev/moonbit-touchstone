///|
test "passivity checks full quadratic form and separates lossless boundary" {
  let c = (x : Double) => @touchstone.complex(x)
  let n = @touchstone.network(
    2,
    [1.0, 2.0, 3.0],
    [
      [c(0.0), c(0.5), c(0.5), c(0.0)],
      [c(0.0), c(1.0), c(1.0), c(0.0)],
      [c(0.8), c(0.8), c(0.0), c(0.0)],
    ],
    [50.0, 75.0],
  )
  let ds = n.diagnostics()
  assert_eq(ds[0].passivity, "passive")
  assert_eq(ds[1].passivity, "boundary")
  assert_eq(ds[2].passivity, "active")
  assert_true(ds[0].reciprocal)
  assert_true(!ds[2].reciprocal)
}

///|
test "metrics encode physical infinity and active VSWR without nonfinite JSON" {
  let c = (x : Double) => @touchstone.complex(x)
  let n = @touchstone.network(
    1,
    [1.0, 2.0, 3.0, 4.0],
    [[c(0.0)], [c(0.5)], [c(1.0)], [c(1.5)]],
    [50.0],
  )
  let ms = n.metrics(0, 0)
  assert_true(ms[0].return_loss_infinite)
  assert_eq(ms[0].return_loss_db, None)
  assert_eq(ms[1].vswr, Some(3.0))
  assert_eq(ms[2].vswr_state, "infinite")
  assert_eq(ms[3].vswr_state, "active")
}

///|
test "phase unwrapping yields known delay across branch cut on nonuniform grid" {
  let n = @touchstone.network(
    1,
    [1.0, 2.0, 2.5],
    [
      [@touchstone.complex(0.0, im=-1.0)],
      [@touchstone.complex(-1.0)],
      [@touchstone.complex(-0.5.sqrt(), im=0.5.sqrt())],
    ],
    [50.0],
  )
  for d in n.group_delay(0, 0) {
    assert_true((d - 0.25).abs() < 1.0e-14)
  }
  let zero = @touchstone.network(
    1,
    [1.0, 2.0],
    [[@touchstone.complex(0.0)], [@touchstone.complex(1.0)]],
    [50.0],
  )
  try zero.group_delay(0, 0) catch {
    _ => ()
  } noraise {
    _ => fail("zero phase accepted")
  }
}
