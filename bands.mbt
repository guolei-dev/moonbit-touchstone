///|
/// Scalar S-parameter metrics. Losses use -20 log10(|S|), not power dB.
/// Reflection/return loss/VSWR use S[input,input]; transmission/insertion
/// loss use S[output,input]. Other ports are matched at their real references.
pub(all) enum BandMetric {
  ReflectionMagnitude
  TransmissionMagnitude
  ReturnLossDb
  InsertionLossDb
  Vswr
}

///|
pub fn BandMetric::name(self : BandMetric) -> String {
  match self {
    ReflectionMagnitude => "reflection_magnitude"
    TransmissionMagnitude => "transmission_magnitude"
    ReturnLossDb => "return_loss_db"
    InsertionLossDb => "insertion_loss_db"
    Vswr => "vswr"
  }
}

///|
/// A validated, immutable rule over a CLOSED frequency interval in Hz.
/// Limits are inclusive, finite and exact (no implicit tolerance).
pub struct BandLimit {
  metric : BandMetric
  start_hz : Double
  end_hz : Double
  input : Int
  output : Int
  minimum : Double?
  maximum : Double?
}

///|
fn validate_band_domain(
  start_hz : Double,
  end_hz : Double,
  input : Int,
  output : Int,
) -> Unit raise {
  if !finite(start_hz) || !finite(end_hz) || start_hz < 0.0 || end_hz < start_hz {
    raise Failure("band edges must be finite with 0 <= start_hz <= end_hz")
  }
  if input < 0 || input >= 32 || output < 0 || output >= 32 {
    raise Failure("band ports must be zero-based indices in 0..31")
  }
}

///|
/// At least one bound is required. Equal frequency edges permit a single-point
/// check. Port existence is additionally checked against the target network.
pub fn band_limit(
  metric : BandMetric,
  start_hz : Double,
  end_hz : Double,
  input~ : Int,
  output~ : Int,
  minimum? : Double,
  maximum? : Double,
) -> BandLimit raise {
  validate_band_domain(start_hz, end_hz, input, output)
  if minimum is None && maximum is None {
    raise Failure("band rule requires a minimum or maximum")
  }
  if minimum is Some(x) && !finite(x) {
    raise Failure("band minimum must be finite")
  }
  if maximum is Some(x) && !finite(x) {
    raise Failure("band maximum must be finite")
  }
  if minimum is Some(lo) && maximum is Some(hi) && lo > hi {
    raise Failure("band minimum exceeds maximum")
  }
  { metric, start_hz, end_hz, input, output, minimum, maximum, }
}

///|
/// Source index is zero-based in the ORIGINAL network, not the selected band.
/// state: finite, infinite (+infinity), or undefined (active-reflection VSWR).
/// JSON value is an explicit number/null, never a one-element Option array.
pub struct BandObservation {
  point : Int
  frequency_hz : Double
  value : Double?
  state : String
}

///|
fn nullable_number(value : Double?) -> Json {
  match value {
    Some(x) => x.to_json()
    None => null
  }
}

///|
pub impl ToJson for BandObservation with fn to_json(self) {
  {
    "point": self.point.to_json(),
    "frequency_hz": self.frequency_hz.to_json(),
    "value": nullable_number(self.value),
    "state": self.state.to_json(),
  }
}

///|
pub extend BandObservation with ToJson::{to_json}

///|
/// reason: below_minimum, above_maximum, or undefined. Issues are ordered by
/// rule then original frequency; they are NOT contiguous violation intervals.
pub struct BandIssue {
  observation : BandObservation
  reason : String
} derive(ToJson)

///|
pub extend BandIssue with ToJson::{to_json}

///|
/// pass means all selected SAMPLES passed, with nonempty selection, dataset
/// range covering both requested edges and no undefined values. It does NOT
/// certify the unsampled frequencies, even when both edge_sampled flags hold.
/// fail takes precedence over inconclusive. Undefined values are not extrema.
/// Repeated extrema retain the first original point. Counts are never capped.
pub struct BandResult {
  rule : BandLimit
  status : String
  range_covered : Bool
  start_sampled : Bool
  end_sampled : Bool
  sample_count : Int
  failed_count : Int
  undefined_count : Int
  lowest : BandObservation?
  highest : BandObservation?
  issues : Array[BandIssue]
  issues_truncated : Bool
}

///|
pub impl ToJson for BandResult with fn to_json(self) {
  {
    "metric": self.rule.metric.name().to_json(),
    "start_hz": self.rule.start_hz.to_json(),
    "end_hz": self.rule.end_hz.to_json(),
    "input": self.rule.input.to_json(),
    "output": self.rule.output.to_json(),
    "minimum": nullable_number(self.rule.minimum),
    "maximum": nullable_number(self.rule.maximum),
    "status": self.status.to_json(),
    "range_covered": self.range_covered.to_json(),
    "start_sampled": self.start_sampled.to_json(),
    "end_sampled": self.end_sampled.to_json(),
    "sample_count": self.sample_count.to_json(),
    "failed_count": self.failed_count.to_json(),
    "undefined_count": self.undefined_count.to_json(),
    "lowest": match self.lowest {
      Some(x) => x.to_json()
      None => null
    },
    "highest": match self.highest {
      Some(x) => x.to_json()
      None => null
    },
    "issues": self.issues.to_json(),
    "issues_truncated": self.issues_truncated.to_json(),
  }
}

///|
pub extend BandResult with ToJson::{to_json}

///|
/// Aggregate sampled-only verdict, preserving the original reference ohms.
/// fail if ANY rule fails; else inconclusive if ANY rule is inconclusive.
/// Details share ONE global max_details budget, consumed in rule/point order.
pub struct BandReport {
  scope : String
  status : String
  reference_ohms : Array[Double]
  max_details : Int
  results : Array[BandResult]
} derive(ToJson)

///|
pub extend BandReport with ToJson::{to_json}

///|
// Returns [lo,hi) indices selecting the closed [start,end] frequency interval.
// Strictly increasing finite frequencies are guaranteed by Network.
fn band_indices(frequencies : Array[Double], rule : BandLimit) -> (Int, Int) {
  let lo = match frequencies.binary_search(rule.start_hz) {
    Ok(i) | Err(i) => i
  }
  let hi = match frequencies.binary_search(rule.end_hz) {
    Ok(i) => i + 1
    Err(i) => i
  }
  (lo, hi)
}

///|
// None is +infinity here; undefined observations never enter comparisons.
fn observation_less(a : BandObservation, b : BandObservation) -> Bool {
  match (a.value, b.value) {
    (Some(x), Some(y)) => x < y
    (Some(_), None) => true
    _ => false
  }
}

///|
fn band_observation(
  s : Network,
  rule : BandLimit,
  point : Int,
) -> BandObservation raise {
  let column = rule.input
  let row = match rule.metric {
    TransmissionMagnitude | InsertionLossDb => rule.output
    _ => rule.input
  }
  let magnitude = s.values[point][row * s.n + column].magnitude()
  if !finite(magnitude) {
    raise Failure("band metric magnitude overflow")
  }
  let (value, state) : (Double?, String) = match rule.metric {
    ReflectionMagnitude | TransmissionMagnitude => (Some(magnitude), "finite")
    ReturnLossDb | InsertionLossDb =>
      if magnitude == 0.0 {
        (None, "infinite")
      } else {
        (Some(-20.0 * @math.log10(magnitude)), "finite")
      }
    Vswr =>
      if magnitude > 1.0 {
        (None, "undefined")
      } else if magnitude == 1.0 {
        (None, "infinite")
      } else {
        (Some((1.0 + magnitude) / (1.0 - magnitude)), "finite")
      }
  }
  { point, frequency_hz: s.frequencies[point], value, state, }
}

///|
fn check_band(
  s : Network,
  rule : BandLimit,
  lo : Int,
  hi : Int,
  budget : Int,
) -> BandResult raise {
  let mut lowest : BandObservation? = None
  let mut highest : BandObservation? = None
  let mut failed_count = 0
  let mut undefined_count = 0
  let issues : Array[BandIssue] = []
  for point in lo..<hi {
    let observation = band_observation(s, rule, point)
    let reason = if observation.state == "undefined" {
      undefined_count += 1
      "undefined"
    } else {
      if lowest is None ||
        (lowest is Some(x) && observation_less(observation, x)) {
        lowest = Some(observation)
      }
      if highest is None ||
        (highest is Some(x) && observation_less(x, observation)) {
        highest = Some(observation)
      }
      if observation.value is Some(x) &&
        rule.minimum is Some(bound) &&
        x < bound {
        "below_minimum"
      } else if rule.maximum is Some(bound) &&
        (
          observation.value is None ||
          (observation.value is Some(x) && x > bound)
        ) {
        "above_maximum"
      } else {
        ""
      }
    }
    if reason != "" {
      if reason != "undefined" {
        failed_count += 1
      }
      if issues.length() < budget {
        issues.push({ observation, reason, })
      }
    }
  }
  let range_covered = s.frequencies[0] <= rule.start_hz &&
    s.frequencies[s.frequencies.length() - 1] >= rule.end_hz
  let status = if failed_count > 0 {
    "fail"
  } else if hi == lo || !range_covered || undefined_count > 0 {
    "inconclusive"
  } else {
    "pass"
  }
  {
    rule,
    status,
    range_covered,
    start_sampled: lo < hi && s.frequencies[lo] == rule.start_hz,
    end_sampled: lo < hi && s.frequencies[hi - 1] == rule.end_hz,
    sample_count: hi - lo,
    failed_count,
    undefined_count,
    lowest,
    highest,
    issues,
    issues_truncated: issues.length() < failed_count + undefined_count,
  }
}

///|
/// Check 1..256 rules on ORIGINAL sampled frequencies only. No interpolation,
/// extrapolation, resampling, or automatic reference renormalization. Convert
/// the network to S once; a singular conversion fails the whole operation.
/// Limit total selected point/rule evaluations to 2,000,000. Detail budget is
/// 0..100000 (default 256); truncation never changes verdicts/counts/extrema.
pub fn Network::check_bands(
  self : Network,
  limits : Array[BandLimit],
  max_details? : Int = 256,
) -> BandReport raise {
  if limits.is_empty() || limits.length() > 256 {
    raise Failure("band check requires 1..256 rules")
  }
  if max_details < 0 || max_details > 100000 {
    raise Failure("max_details must be in 0..100000")
  }
  let ranges : Array[(Int, Int)] = []
  let mut evaluations = 0
  for rule in limits {
    check_ports(self.n, rule.output, rule.input)
    let (lo, hi) = band_indices(self.frequencies, rule)
    evaluations += hi - lo
    if evaluations > 2000000 {
      raise Failure("band checks exceed 2000000 point/rule evaluations")
    }
    ranges.push((lo, hi))
  }
  let s = self.convert("S")
  let results : Array[BandResult] = []
  let mut budget = max_details
  let mut status = "pass"
  for i, rule in limits {
    let (lo, hi) = ranges[i]
    let result = check_band(s, rule, lo, hi, budget)
    budget -= result.issues.length()
    if result.status == "fail" {
      status = "fail"
    } else if result.status == "inconclusive" && status == "pass" {
      status = "inconclusive"
    }
    results.push(result)
  }
  {
    scope: "sampled_points_only",
    status,
    reference_ohms: self.reference.copy(),
    max_details,
    results,
  }
}

///|
/// Export retained issues only. An empty CSV is NOT a pass certificate: use
/// the JSON report for uncovered bands, counts, verdicts and truncation flags.
/// All strings are fixed library identifiers; no user text enters CSV cells.
pub fn BandReport::issues_csv(self : BandReport) -> String {
  let out = StringBuilder()
  out.write_string(
    "rule,metric,input,output,point,frequency_hz,value,state,reason\n",
  )
  for i, result in self.results {
    for issue in result.issues {
      let p = issue.observation
      let value = match p.value {
        Some(x) => x.to_string()
        None => ""
      }
      out.write_string(
        "\{i},\{result.rule.metric.name()},\{result.rule.input},\{result.rule.output},\{p.point},\{p.frequency_hz},\{value},\{p.state},\{issue.reason}\n",
      )
    }
  }
  out.to_string()
}
