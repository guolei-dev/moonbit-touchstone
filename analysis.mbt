///|
/// Pointwise diagnostics, not a broadband causality or physical certification.
/// passive: I-S^H S-tol*I is positive definite; active: I-S^H S+tol*I
/// is not positive definite; boundary: the tolerance band between them.
pub(all) struct Diagnostic {
  frequency_hz : Double
  reciprocity_error : Double
  reciprocal : Bool
  passivity : String
} derive(ToJson)

///|
pub extend Diagnostic with ToJson::{to_json}

///|
// Hermitian Cholesky tests the full quadratic form, not just column powers.
// Strict positive definiteness keeps singular lossless networks in the band.
fn positive_definite(n : Int, h : Array[Complex], shift : Double) -> Bool raise {
  let l = Array::make(n * n, complex(0.0))
  for i in 0..<n {
    for j in 0..<=i {
      let mut v = h[i * n + j]
      if i == j {
        v = v.add(complex(shift))
      }
      for k in 0..<j {
        v = checked(v.sub(l[i * n + k].mul(l[j * n + k].conjugate())))
      }
      if i == j {
        if v.re <= 0.0 {
          return false
        }
        l[i * n + j] = complex(v.re.sqrt())
      } else {
        l[i * n + j] = v.divide(l[j * n + j])
      }
    }
  }
  true
}

///|
/// Power-wave diagnostics at real references. Tolerance is absolute on the
/// dimensionless Hermitian form and on S-S^T; must be in (0, 0.01].
pub fn Network::diagnostics(
  self : Network,
  tolerance? : Double = 1.0e-9,
) -> Array[Diagnostic] raise {
  if !finite(tolerance) || tolerance <= 0.0 || tolerance > 0.01 {
    raise Failure("diagnostic tolerance must be in (0, 0.01]")
  }
  let s = self.convert("S")
  let n = s.n
  Array::makei(s.values.length(), p => {
    let m = s.values[p]
    let mut error = 0.0
    let h = identity(n)
    for i in 0..<n {
      for j in 0..<=i {
        error = error.max(checked(m[i * n + j].sub(m[j * n + i])).magnitude())
        let mut gram = complex(0.0)
        for k in 0..<n {
          gram = checked(gram.add(m[k * n + i].conjugate().mul(m[k * n + j])))
        }
        let v = checked(h[i * n + j].sub(gram))
        h[i * n + j] = v
        h[j * n + i] = v.conjugate()
      }
    }
    if !finite(error) {
      raise Failure("diagnostic magnitude overflow")
    }
    let passivity = if positive_definite(n, h, -tolerance) {
      "passive"
    } else if positive_definite(n, h, tolerance) {
      "boundary"
    } else {
      "active"
    }
    {
      frequency_hz: s.frequencies[p],
      reciprocity_error: error,
      reciprocal: error <= tolerance,
      passivity,
    }
  })
}

///|
/// None dB with its infinite flag means exact zero magnitude (+infinity dB).
/// VSWR is None for unit reflection (infinite) or active reflection (undefined).
/// ToJson omits None-valued fields; state/flag fields are always present.
pub(all) struct SignalMetric {
  frequency_hz : Double
  reflection_magnitude : Double
  transmission_magnitude : Double
  return_loss_db : Double?
  return_loss_infinite : Bool
  insertion_loss_db : Double?
  insertion_loss_infinite : Bool
  vswr : Double?
  vswr_state : String
} derive(ToJson)

///|
pub extend SignalMetric with ToJson::{to_json}

///|
fn check_ports(n : Int, output : Int, input : Int) -> Unit raise {
  if output < 0 || output >= n || input < 0 || input >= n {
    raise Failure("zero-based port index outside range")
  }
}

///|
/// Return loss/VSWR at input and insertion loss from input to output.
/// Ports are zero-based. All other ports are matched to their reference.
pub fn Network::metrics(
  self : Network,
  output : Int,
  input : Int,
) -> Array[SignalMetric] raise {
  check_ports(self.n, output, input)
  let s = self.convert("S")
  Array::makei(s.values.length(), p => {
    let r = s.values[p][input * self.n + input].magnitude()
    let t = s.values[p][output * self.n + input].magnitude()
    if !finite(r) || !finite(t) {
      raise Failure("metric magnitude overflow")
    }
    let vswr = if r < 1.0 { Some((1.0 + r) / (1.0 - r)) } else { None }
    {
      frequency_hz: s.frequencies[p],
      reflection_magnitude: r,
      transmission_magnitude: t,
      return_loss_db: if r == 0.0 {
        None
      } else {
        Some(-20.0 * @math.log10(r))
      },
      return_loss_infinite: r == 0.0,
      insertion_loss_db: if t == 0.0 {
        None
      } else {
        Some(-20.0 * @math.log10(t))
      },
      insertion_loss_infinite: t == 0.0,
      vswr,
      vswr_state: if r < 1.0 {
        "finite"
      } else if r == 1.0 {
        "infinite"
      } else {
        "active"
      },
    }
  })
}

///|
/// Group delay in seconds: -d unwrap(arg S[out,in])/d(2*pi*f).
/// Uses centered secants internally and one-sided endpoints, including uneven
/// grids. Requires >=2 points and nonzero transmission throughout. Adjacent
/// true phase changes >=pi cannot be recovered from sampled data unambiguously.
pub fn Network::group_delay(
  self : Network,
  output : Int,
  input : Int,
) -> Array[Double] raise {
  check_ports(self.n, output, input)
  if self.frequencies.length() < 2 {
    raise Failure("group delay requires at least two frequencies")
  }
  let s = self.convert("S")
  let phases : Array[Double] = []
  let mut previous = 0.0
  for i, m in s.values {
    let v = m[output * self.n + input]
    if v.re == 0.0 && v.im == 0.0 {
      raise Failure("group delay undefined at zero transmission")
    }
    let phase = v.phase()
    if i == 0 {
      phases.push(phase)
    } else {
      let mut d = phase - previous
      if d > @math.PI {
        d = d - 2.0 * @math.PI
      } else if d < -@math.PI {
        d = d + 2.0 * @math.PI
      }
      phases.push(phases[i - 1] + d)
    }
    previous = phase
  }
  Array::makei(phases.length(), i => {
    let lo = (i - 1).max(0)
    let hi = (i + 1).min(phases.length() - 1)
    let delay = -(phases[hi] - phases[lo]) /
      (s.frequencies[hi] - s.frequencies[lo]) /
      (2.0 * @math.PI)
    if !finite(delay) {
      raise Failure("group delay overflow")
    }
    delay
  })
}
