///|
// All representations become A V = B I, with currents entering both ports.
// Solving for the destination variables directly avoids false singularities
// introduced by routing every conversion through Z (e.g. an ideal thru).
fn constraints(
  n : Int,
  kind : String,
  m : Array[Complex],
  refs : Array[Double],
) -> (Array[Complex], Array[Complex]) {
  let id = identity(n)
  match kind {
    "Z" => (id, m)
    "Y" => (m, id)
    "H" =>
      (
        [complex(1.0), m[1].scale(-1.0), complex(0.0), m[3].scale(-1.0)],
        [m[0], complex(0.0), m[2], complex(-1.0)],
      )
    "G" =>
      (
        [m[0], complex(0.0), m[2].scale(-1.0), complex(1.0)],
        [complex(1.0), m[1].scale(-1.0), complex(0.0), m[3]],
      )
    _ =>
      (
        Array::makei(n * n, k => id[k].sub(m[k]).scale(1.0 / refs[k % n].sqrt())),
        Array::makei(n * n, k => id[k].add(m[k]).scale(refs[k % n].sqrt())),
      )
  }
}

///|
fn solve_representation(
  n : Int,
  kind : String,
  a : Array[Complex],
  b : Array[Complex],
  refs : Array[Double],
) -> Array[Complex] raise {
  let (left, right) = match kind {
    "Z" => (a, b)
    "Y" => (b, a)
    "H" =>
      (
        [a[0], b[1].scale(-1.0), a[2], b[3].scale(-1.0)],
        [b[0], a[1].scale(-1.0), b[2], a[3].scale(-1.0)],
      )
    "G" =>
      (
        [b[0], a[1].scale(-1.0), b[2], a[3].scale(-1.0)],
        [a[0], b[1].scale(-1.0), a[2], b[3].scale(-1.0)],
      )
    _ =>
      (
        Array::makei(n * n, k => {
          a[k]
          .scale(refs[k % n].sqrt())
          .add(b[k].scale(1.0 / refs[k % n].sqrt()))
        }),
        Array::makei(n * n, k => {
          b[k]
          .scale(1.0 / refs[k % n].sqrt())
          .sub(a[k].scale(refs[k % n].sqrt()))
        }),
      )
  }
  product(n, invert_matrix(n, left), right)
}

///|
/// Convert S/Y/Z/H/G directly; H/G require two ports. References remain fixed.
/// Ill-conditioned destination equations raise; no diagonal jitter is added.
pub fn Network::convert(self : Network, parameter : String) -> Network raise {
  let kind = parameter.to_upper()
  if !(kind == "S" || kind == "Y" || kind == "Z" || kind == "H" || kind == "G") ||
    ((kind == "H" || kind == "G") && self.n != 2) {
    raise Failure("invalid destination parameter")
  }
  if kind == self.kind {
    return self
  }
  let values = self.values.map(m => {
    let (a, b) = constraints(self.n, self.kind, m, self.reference)
    solve_representation(self.n, kind, a, b, self.reference)
  })
  network(self.n, self.frequencies, values, self.reference, parameter=kind)
}

///|
/// Return S parameters at new positive real per-port reference impedances.
/// Uses direct wave equations, including ideal throughs where Z is undefined.
pub fn Network::renormalize(
  self : Network,
  reference_ohms : Array[Double],
) -> Network raise {
  if reference_ohms.length() != self.n ||
    reference_ohms.any(x => !finite(x) || x <= 0.0) {
    raise Failure("expected positive real reference for each port")
  }
  let values = self.values.map(m => {
    let (a, b) = constraints(self.n, self.kind, m, self.reference)
    solve_representation(self.n, "S", a, b, reference_ohms)
  })
  network(self.n, self.frequencies, values, reference_ohms)
}

///|
/// Select/reorder zero-based ports, terminating omitted ports in their own
/// matched reference impedances. Output is S; this is not an open-circuit cut.
pub fn Network::select_ports(
  self : Network,
  ports : Array[Int],
) -> Network raise {
  if ports.is_empty() || ports.length() > self.n {
    raise Failure("invalid port selection")
  }
  let seen = Array::make(self.n, false)
  for p in ports {
    if p < 0 || p >= self.n || seen[p] {
      raise Failure("port outside range or duplicated")
    }
    seen[p] = true
  }
  let s = self.convert("S")
  let n = ports.length()
  let values = s.values.map(m => {
    Array::makei(n * n, k => m[ports[k / n] * self.n + ports[k % n]])
  })
  network(n, self.frequencies, values, ports.map(p => self.reference[p]))
}

///|
/// Piecewise linear interpolation in the current complex Cartesian parameters.
/// No extrapolation, phase fitting, noise interpolation or causality claim.
pub fn Network::interpolate(
  self : Network,
  frequency_hz : Array[Double],
) -> Network raise {
  if frequency_hz.is_empty() ||
    frequency_hz.length() > 100000 ||
    frequency_hz.length() > 2000000 / (self.n * self.n) {
    raise Failure("interpolation point limit exceeded")
  }
  let values = frequency_hz.map(f => {
    let last = self.frequencies.length() - 1
    if !finite(f) || f < self.frequencies[0] || f > self.frequencies[last] {
      raise Failure("interpolation outside measured range")
    }
    let mut lo = 0
    let mut hi = last
    while lo + 1 < hi {
      let mid = (lo + hi) / 2
      if self.frequencies[mid] <= f {
        lo = mid
      } else {
        hi = mid
      }
    }
    if self.frequencies[lo] == f {
      self.values[lo].copy()
    } else if self.frequencies[hi] == f {
      self.values[hi].copy()
    } else {
      let t = (f - self.frequencies[lo]) /
        (self.frequencies[hi] - self.frequencies[lo])
      Array::makei(self.n * self.n, k => {
        checked(
          self.values[lo][k].scale(1.0 - t).add(self.values[hi][k].scale(t)),
        )
      })
    }
  })
  network(self.n, frequency_hz, values, self.reference, parameter=self.kind)
}
