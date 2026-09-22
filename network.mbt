///|
/// Opaque owned network. Matrices are row-major and frequencies are Hz.
/// Parameters are S (dimensionless), Z (ohm), Y (siemens), or two-port H/G.
/// H/G diagonal units differ; file normalization is resolved by the parser.
pub struct Network {
  priv n : Int
  priv kind : String
  priv frequencies : Array[Double]
  priv reference : Array[Double]
  priv values : Array[Array[Complex]]
}

///|
/// Copy and validate inputs: 1..32 ports, positive real references, nonnegative
/// strictly increasing frequencies, at most 100000 points / 2000000 values.
pub fn network(
  ports : Int,
  frequencies : Array[Double],
  values : Array[Array[Complex]],
  reference : Array[Double],
  parameter? : String = "S",
) -> Network raise {
  let kind = parameter.to_upper()
  if ports < 1 || ports > 32 || reference.length() != ports {
    raise Failure("ports must be 1..32 with one real reference per port")
  }
  if !(kind == "S" || kind == "Z" || kind == "Y" || kind == "H" || kind == "G") ||
    ((kind == "H" || kind == "G") && ports != 2) {
    raise Failure("unsupported parameter or non-two-port hybrid network")
  }
  if frequencies.is_empty() ||
    frequencies.length() > 100000 ||
    frequencies.length() > 2000000 / (ports * ports) ||
    values.length() != frequencies.length() {
    raise Failure("network point count/shape exceeds bounds")
  }
  for r in reference {
    if !finite(r) || r <= 0.0 {
      raise Failure("reference must be positive and finite")
    }
  }
  for i, f in frequencies {
    if !finite(f) || f < 0.0 || (i > 0 && f <= frequencies[i - 1]) {
      raise Failure(
        "frequencies must be finite, nonnegative and strictly increasing",
      )
    }
    matrix_size(ports, values[i])
  }
  {
    n: ports,
    kind,
    frequencies: frequencies.copy(),
    reference: reference.copy(),
    values: values.map(x => x.copy()),
  }
}

///|
pub fn Network::ports(self : Network) -> Int {
  self.n
}

///|
pub fn Network::parameter(self : Network) -> String {
  self.kind
}

///|
pub fn Network::frequency_hz(self : Network) -> Array[Double] {
  self.frequencies.copy()
}

///|
pub fn Network::reference_ohms(self : Network) -> Array[Double] {
  self.reference.copy()
}

///|
/// Obtain an independent matrix copy; point is a zero-based frequency index.
pub fn Network::matrix(self : Network, point : Int) -> Array[Complex] raise {
  if point < 0 || point >= self.values.length() {
    raise Failure("frequency index out of range")
  }
  self.values[point].copy()
}
