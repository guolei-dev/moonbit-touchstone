///|
/// Peak-to-peak insertion loss over sampled frequencies, in dB. This is an
/// aggregate constraint: every point can satisfy an absolute maximum yet the
/// difference between the lowest and highest values can violate a ripple limit.
/// Witness point indices refer to the original input network.
pub struct RippleReport {
  scope : String
  status : String
  start_hz : Double
  end_hz : Double
  input : Int
  output : Int
  maximum_ripple_db : Double
  sample_count : Int
  range_covered : Bool
  start_sampled : Bool
  end_sampled : Bool
  ripple_db : Double?
  ripple_state : String
  lowest_loss : BandObservation?
  highest_loss : BandObservation?
}

///|
pub impl ToJson for RippleReport with fn to_json(self) {
  {
    "scope": self.scope.to_json(),
    "status": self.status.to_json(),
    "start_hz": self.start_hz.to_json(),
    "end_hz": self.end_hz.to_json(),
    "input": self.input.to_json(),
    "output": self.output.to_json(),
    "maximum_ripple_db": self.maximum_ripple_db.to_json(),
    "sample_count": self.sample_count.to_json(),
    "range_covered": self.range_covered.to_json(),
    "start_sampled": self.start_sampled.to_json(),
    "end_sampled": self.end_sampled.to_json(),
    "ripple_db": nullable_number(self.ripple_db),
    "ripple_state": self.ripple_state.to_json(),
    "lowest_loss": match self.lowest_loss {
      Some(x) => x.to_json()
      None => null
    },
    "highest_loss": match self.highest_loss {
      Some(x) => x.to_json()
      None => null
    },
  }
}

///|
pub extend RippleReport with ToJson::{to_json}

///|
/// Check max(loss)-min(loss), loss = -20log10(abs(S[output,input])). Inclusive
/// maximum, no interpolated endpoints and no implicit tolerance. At least TWO
/// measured points are required even for an equal-edge band. Uncovered ranges
/// cannot pass, but an observed violation always fails. One zero transmission
/// and one nonzero transmission imply infinite ripple; all-zero transmission
/// is undefined (infinity-infinity), never a falsely perfect flat passband.
pub fn Network::check_ripple(
  self : Network,
  start_hz : Double,
  end_hz : Double,
  input~ : Int,
  output~ : Int,
  maximum_ripple_db~ : Double,
) -> RippleReport raise {
  validate_band_domain(start_hz, end_hz, input, output)
  check_ports(self.n, output, input)
  if !finite(maximum_ripple_db) || maximum_ripple_db < 0.0 {
    raise Failure("maximum_ripple_db must be finite and nonnegative")
  }
  // Internal measurement rule has no pointwise bounds. Reuse the same tested
  // selection, units, conversion and extrema implementation as check_bands.
  let rule : BandLimit = {
    metric: InsertionLossDb,
    start_hz,
    end_hz,
    input,
    output,
    minimum: None,
    maximum: None,
  }
  let (lo, hi) = band_indices(self.frequencies, rule)
  if hi - lo > 2000000 {
    raise Failure("ripple check exceeds 2000000 sampled evaluations")
  }
  let sample = check_band(self.convert("S"), rule, lo, hi, 0)
  let (value, state) : (Double?, String) = match
    (sample.lowest, sample.highest) {
    (Some(low), Some(high)) =>
      match (low.value, high.value) {
        (Some(a), Some(b)) => {
          let difference = b - a
          if !finite(difference) {
            raise Failure("ripple subtraction overflow")
          }
          (Some(difference), "finite")
        }
        (Some(_), None) => (None, "infinite")
        _ => (None, "undefined")
      }
    _ => (None, "undefined")
  }
  let status = if state == "infinite" ||
    (value is Some(x) && x > maximum_ripple_db) {
    "fail"
  } else if state == "undefined" ||
    sample.sample_count < 2 ||
    !sample.range_covered {
    "inconclusive"
  } else {
    "pass"
  }
  {
    scope: "sampled_points_only",
    status,
    start_hz,
    end_hz,
    input,
    output,
    maximum_ripple_db,
    sample_count: sample.sample_count,
    range_covered: sample.range_covered,
    start_sampled: sample.start_sampled,
    end_sampled: sample.end_sampled,
    ripple_db: value,
    ripple_state: state,
    lowest_loss: sample.lowest,
    highest_loss: sample.highest,
  }
}
