///|
test "closed bands retain source indices, inclusive bounds and first tied extrema" {
  let net = @touchstone.network(
    1,
    [1.0, 2.0, 4.0, 7.0],
    [0.25, 0.5, 0.5, 0.75].map(x => [@touchstone.complex(x)]),
    [75.0],
  )
  let rule = @touchstone.band_limit(
    ReflectionMagnitude,
    2.0,
    4.0,
    input=0,
    output=0,
    minimum=0.5,
    maximum=0.5,
  )
  let report = net.check_bands([rule])
  assert_eq(report.scope, "sampled_points_only")
  assert_eq(report.status, "pass")
  let result = report.results[0]
  assert_eq(result.sample_count, 2)
  assert_true(
    result.start_sampled && result.end_sampled && result.range_covered,
  )
  guard result.lowest is Some(lo) && result.highest is Some(hi) else {
    fail("missing extrema")
  }
  assert_eq(lo.point, 1)
  assert_eq(hi.point, 1)
  assert_eq(lo.value, Some(0.5))
  // Changing a report reference array cannot mutate the network.
  report.reference_ohms[0] = 10.0
  assert_eq(net.reference_ohms()[0], 75.0)
}

///|
test "empty, uncovered, and unmeasured-edge bands cannot imply continuous pass" {
  let net = @touchstone.network(
    1,
    [1.0, 3.0, 5.0],
    [0.2, 0.2, 0.2].map(x => [@touchstone.complex(x)]),
    [50.0],
  )
  let rule = (a, b) => {
    @touchstone.band_limit(Vswr, a, b, input=0, output=0, maximum=2.0)
  }
  let report = net.check_bands([
    rule(1.5, 2.5),
    rule(0.0, 5.0),
    rule(1.5, 4.5),
    rule(3.0, 3.0),
  ])
  assert_eq(report.status, "inconclusive")
  assert_eq(report.results[0].sample_count, 0)
  assert_true(report.results[0].lowest is None)
  assert_eq(report.results[0].status, "inconclusive")
  assert_true(!report.results[1].range_covered)
  assert_eq(report.results[1].status, "inconclusive")
  assert_eq(report.results[2].status, "pass")
  assert_true(
    !report.results[2].start_sampled && !report.results[2].end_sampled,
  )
  assert_eq(report.results[3].sample_count, 1)
  assert_eq(report.results[3].status, "pass")
}

///|
test "loss infinity and undefined active VSWR have distinct verdicts and JSON states" {
  let net = @touchstone.network(
    1,
    [1.0, 2.0, 3.0, 4.0],
    [0.0, 0.5, 1.0, 1.5].map(x => [@touchstone.complex(x)]),
    [50.0],
  )
  let loss = @touchstone.band_limit(
    ReturnLossDb,
    1.0,
    1.0,
    input=0,
    output=0,
    minimum=1000.0,
  )
  let vswr = @touchstone.band_limit(
    Vswr,
    1.0,
    4.0,
    input=0,
    output=0,
    maximum=3.0,
  )
  let report = net.check_bands([loss, vswr])
  assert_eq(report.status, "fail")
  assert_eq(report.results[0].status, "pass")
  guard report.results[0].lowest is Some(infinite) else {
    fail("missing infinite extremum")
  }
  json_inspect(infinite, content={
    "point": 0,
    "frequency_hz": 1,
    "value": null,
    "state": "infinite",
  })
  let result = report.results[1]
  assert_eq(result.failed_count, 1)
  assert_eq(result.undefined_count, 1)
  assert_eq(result.issues[0].reason, "above_maximum")
  assert_eq(result.issues[1].reason, "undefined")
  guard result.lowest is Some(lo) else { fail("missing minimum") }
  json_inspect(lo, content={
    "point": 0,
    "frequency_hz": 1,
    "value": 1,
    "state": "finite",
  })
  let active = net.check_bands([
    @touchstone.band_limit(Vswr, 4.0, 4.0, input=0, output=0, minimum=0.0),
  ])
  assert_eq(active.status, "inconclusive")
  assert_true(
    active.results[0].lowest is None && active.results[0].highest is None,
  )
  assert_true(
    report.issues_csv().contains("1,vswr,0,0,3,4,,undefined,undefined"),
  )
}

///|
test "one global detail budget does not cap counts or omit worst extrema" {
  let net = @touchstone.network(
    1,
    [1.0, 2.0, 3.0],
    [0.1, 0.2, 0.9].map(x => [@touchstone.complex(x)]),
    [50.0],
  )
  let rule = @touchstone.band_limit(
    TransmissionMagnitude,
    1.0,
    3.0,
    input=0,
    output=0,
    maximum=0.0,
  )
  let report = net.check_bands([rule, rule], max_details=2)
  for result in report.results {
    assert_eq(result.failed_count, 3)
    assert_true(result.issues_truncated)
    guard result.highest is Some(hi) else { fail("missing maximum") }
    assert_eq(hi.point, 2)
  }
  assert_eq(report.results[0].issues.length(), 2)
  assert_eq(report.results[1].issues.length(), 0)
  let no_details = net.check_bands([rule], max_details=0)
  assert_eq(no_details.status, "fail")
  assert_eq(
    no_details.issues_csv(),
    "rule,metric,input,output,point,frequency_hz,value,state,reason\n",
  )
}

///|
test "non-S conversion and asymmetric direction retain physical references" {
  let net = @touchstone.network(
    2,
    [1.0],
    [
      [
        @touchstone.complex(0.1),
        @touchstone.complex(0.25),
        @touchstone.complex(0.5),
        @touchstone.complex(0.2),
      ],
    ],
    [50.0, 75.0],
  )
  let forward = @touchstone.band_limit(
    InsertionLossDb,
    1.0,
    1.0,
    input=0,
    output=1,
    minimum=6.0,
    maximum=6.1,
  )
  let reverse = @touchstone.band_limit(
    TransmissionMagnitude,
    1.0,
    1.0,
    input=1,
    output=0,
    maximum=0.3,
  )
  for kind in ["S", "Z", "Y", "H", "G"] {
    let result = net.convert(kind).check_bands([forward, reverse])
    assert_eq(result.status, "pass")
    guard result.results[1].lowest is Some(lo) else { fail("missing reverse") }
    assert_true((lo.value.unwrap() - 0.25).abs() < 1.0e-12)
  }
}

///|
test "band rules reject invalid contracts and bound work before evaluation" {
  let rule = @touchstone.band_limit(
    Vswr,
    0.0,
    100000.0,
    input=0,
    output=0,
    maximum=2.0,
  )
  let net = @touchstone.network(1, [1.0], [[@touchstone.complex(0.0)]], [50.0])
  let bad : Array[() -> Unit raise] = [
    () => {
      ignore(
        @touchstone.band_limit(Vswr, 2.0, 1.0, input=0, output=0, maximum=2.0),
      )
    },
    () => ignore(@touchstone.band_limit(Vswr, 0.0, 1.0, input=0, output=0)),
    () => {
      ignore(
        @touchstone.band_limit(
          Vswr,
          0.0,
          1.0,
          input=0,
          output=0,
          minimum=3.0,
          maximum=2.0,
        ),
      )
    },
    () => {
      ignore(
        @touchstone.band_limit(
          Vswr,
          0.0,
          1.0,
          input=0,
          output=0,
          maximum=1.0 / 0.0,
        ),
      )
    },
    () => {
      ignore(
        @touchstone.band_limit(
          Vswr,
          0.0 / 0.0,
          1.0,
          input=0,
          output=0,
          maximum=2.0,
        ),
      )
    },
    () => ignore(net.check_bands([])),
    () => ignore(net.check_bands(Array::make(257, rule))),
    () => ignore(net.check_bands([rule], max_details=-1)),
    () => ignore(net.check_bands([rule], max_details=100001)),
    () => {
      ignore(
        net.check_bands([
          @touchstone.band_limit(Vswr, 1.0, 1.0, input=1, output=0, maximum=2.0),
        ]),
      )
    },
  ]
  for check in bad {
    try check() catch {
      _ => ()
    } noraise {
      _ => fail("invalid band request accepted")
    }
  }
  let large = @touchstone.network(
    1,
    Array::makei(10000, i => i.to_double()),
    Array::make(10000, [@touchstone.complex(0.0)]),
    [50.0],
  )
  try large.check_bands(Array::make(201, rule)) catch {
    _ => ()
  } noraise {
    _ => fail("work budget exceeded without rejection")
  }
}
