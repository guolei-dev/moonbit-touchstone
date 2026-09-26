///|
fn ripple_network(magnitudes : Array[Double]) -> @touchstone.Network raise {
  @touchstone.network(
    2,
    Array::makei(magnitudes.length(), i => (i + 1).to_double()),
    magnitudes.map(x => {
      [
        @touchstone.complex(0.0),
        @touchstone.complex(0.1),
        @touchstone.complex(x),
        @touchstone.complex(0.0),
      ]
    }),
    [50.0, 50.0],
  )
}

///|
test "ripple catches aggregate violation despite every point passing absolute loss" {
  let net = ripple_network([0.5, 0.25, 0.5])
  let absolute = @touchstone.band_limit(
    InsertionLossDb,
    1.0,
    3.0,
    input=0,
    output=1,
    maximum=13.0,
  )
  assert_eq(net.check_bands([absolute]).status, "pass")
  let ripple = net.check_ripple(
    1.0,
    3.0,
    input=0,
    output=1,
    maximum_ripple_db=6.0,
  )
  assert_eq(ripple.status, "fail")
  guard ripple.ripple_db is Some(value) else { fail("finite ripple expected") }
  assert_true((value - 6.020599913279624).abs() < 1.0e-12)
  guard ripple.lowest_loss is Some(low) && ripple.highest_loss is Some(high) else {
    fail("missing witnesses")
  }
  assert_eq(low.point, 0)
  assert_eq(high.point, 1)
  assert_eq(
    net.check_ripple(1.0, 3.0, input=0, output=1, maximum_ripple_db=value).status,
    "pass",
  )
  // The reverse S12 is constant; a transpose bug would miss the forward ripple.
  assert_eq(
    net.check_ripple(1.0, 3.0, input=1, output=0, maximum_ripple_db=0.0).status,
    "pass",
  )
}

///|
test "ripple distinguishes zero transmission and insufficient sampling" {
  let zeros = ripple_network([0.0, 0.0])
  let undefined = zeros.check_ripple(
    1.0,
    2.0,
    input=0,
    output=1,
    maximum_ripple_db=0.0,
  )
  assert_eq(undefined.status, "inconclusive")
  assert_eq(undefined.ripple_state, "undefined")
  assert_eq(undefined.ripple_db, None)
  let mixed = ripple_network([0.0, 0.5])
  let infinite = mixed.check_ripple(
    1.0,
    2.0,
    input=0,
    output=1,
    maximum_ripple_db=1000.0,
  )
  assert_eq(infinite.status, "fail")
  assert_eq(infinite.ripple_state, "infinite")
  assert_eq(infinite.ripple_db, None)
  let flat = ripple_network([0.5, 0.5, 0.5])
  assert_eq(
    flat.check_ripple(1.0, 1.0, input=0, output=1, maximum_ripple_db=0.0).status,
    "inconclusive",
  )
  assert_eq(
    flat.check_ripple(1.2, 1.8, input=0, output=1, maximum_ripple_db=0.0).status,
    "inconclusive",
  )
  assert_eq(
    flat.check_ripple(0.0, 3.0, input=0, output=1, maximum_ripple_db=0.0).status,
    "inconclusive",
  )
  assert_eq(
    mixed.check_ripple(0.0, 3.0, input=0, output=1, maximum_ripple_db=1000.0).status,
    "fail",
  )
}

///|
test "ripple rejects bad bounds ports and tolerances" {
  let net = ripple_network([0.5, 0.6])
  for
    maximum in [
      -1.0,
      0x7FF0000000000000L.reinterpret_as_double(),
      0x7FF8000000000000L.reinterpret_as_double(),
    ] {
    try
      net.check_ripple(1.0, 2.0, input=0, output=1, maximum_ripple_db=maximum)
    catch {
      _ => ()
    } noraise {
      _ => fail("invalid maximum accepted")
    }
  }
  try
    net.check_ripple(2.0, 1.0, input=0, output=1, maximum_ripple_db=1.0)
  catch {
    _ => ()
  } noraise {
    _ => fail("reversed band accepted")
  }
  try
    net.check_ripple(1.0, 2.0, input=0, output=2, maximum_ripple_db=1.0)
  catch {
    _ => ()
  } noraise {
    _ => fail("missing port accepted")
  }
}
