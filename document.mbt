///|
/// Noise figure is dB, gamma_opt is a complex reflection coefficient relative
/// to Document::noise_reference_ohms, and resistance is always physical ohm.
pub(all) struct NoisePoint {
  frequency_hz : Double
  minimum_figure_db : Double
  gamma_opt : Complex
  resistance_ohms : Double
} derive(ToJson)

///|
pub extend NoisePoint with ToJson::{to_json}

///|
/// File metadata is separate from a Network so a transformation cannot silently
/// pretend that unchanged noise or mixed-mode metadata describe a new network.
pub struct Document {
  priv data : Network
  priv noise : Array[NoisePoint]
  priv noise_reference : Double
  priv mixed : Array[String]
  priv information : Array[String]
}

///|
fn port_number(s : String, n : Int) -> Int raise {
  if s.is_empty() || !s.iter().all(c => c >= '0' && c <= '9') {
    raise Failure("invalid port descriptor")
  }
  let p = @string.parse_int(s)
  if p < 1 || p > n {
    raise Failure("descriptor port outside 1..N")
  }
  p - 1
}

///|
fn validate_mixed(net : Network, modes : Array[String]) -> Unit raise {
  if modes.is_empty() {
    return
  }
  if modes.length() != net.n || net.kind == "H" || net.kind == "G" {
    raise Failure("mixed-mode descriptors require N entries and S/Y/Z")
  }
  let seen : Map[String, Bool] = Map([])
  let owners = Array::make(net.n, "")
  for token in modes {
    if token.length() < 2 || seen.contains(token) {
      raise Failure("duplicate/empty mixed-mode descriptor")
    }
    seen[token] = true
    let tail = token[1:].to_owned()
    if token[0] == 'S' {
      let p = port_number(tail, net.n)
      if owners[p] != "" {
        raise Failure("overlapping mixed-mode descriptors")
      }
      owners[p] = token
    } else if token[0] == 'D' || token[0] == 'C' {
      let pair = tail.split(",").map(x => x.to_owned()).to_array()
      if pair.length() != 2 {
        raise Failure("expected pair descriptor")
      }
      let p = port_number(pair[0], net.n)
      let q = port_number(pair[1], net.n)
      if p == q || net.reference[p] != net.reference[q] {
        raise Failure(
          "mode pair requires distinct ports with equal real references",
        )
      }
      let owner = "\{p},\{q}"
      if (owners[p] != "" && owners[p] != owner) ||
        (owners[q] != "" && owners[q] != owner) {
        raise Failure("overlapping mode pairs")
      }
      owners[p] = owner
      owners[q] = owner
    } else {
      raise Failure("unknown mixed-mode descriptor")
    }
  }
  for token in modes {
    if token[0] == 'D' || token[0] == 'C' {
      let other = (if token[0] == 'D' { "C" } else { "D" }) +
        token[1:].to_owned()
      if !seen.contains(other) {
        raise Failure("D/C descriptors must occur as matching ordered pairs")
      }
    }
  }
  if owners.any(x => x == "") {
    raise Failure("mixed-mode ports incomplete")
  }
}

///|
/// Construct a file document with owned metadata. Noise must be an increasing
/// two-port series whose first frequency is <= the final network frequency.
pub fn document(
  data : Network,
  noise? : Array[NoisePoint] = [],
  noise_reference_ohms? : Double = 50.0,
  mixed_mode_order? : Array[String] = [],
  information? : Array[String] = [],
) -> Document raise {
  if !finite(noise_reference_ohms) || noise_reference_ohms <= 0.0 {
    raise Failure("invalid noise reference")
  }
  if noise.length() > 100000 || (!noise.is_empty() && data.n != 2) {
    raise Failure("noise only supports two-port bounded data")
  }
  for i, p in noise {
    if !finite(p.frequency_hz) ||
      p.frequency_hz < 0.0 ||
      !finite(p.minimum_figure_db) ||
      !finite(p.resistance_ohms) ||
      p.resistance_ohms < 0.0 ||
      (i > 0 && p.frequency_hz <= noise[i - 1].frequency_hz) ||
      (
        i == 0 &&
        p.frequency_hz > data.frequencies[data.frequencies.length() - 1]
      ) {
      raise Failure("invalid noise frequency/order/resistance")
    }
    ignore(checked(p.gamma_opt))
    if !finite(p.gamma_opt.magnitude()) {
      raise Failure("noise reflection magnitude overflow")
    }
  }
  let modes = mixed_mode_order.map(x => x.to_upper())
  validate_mixed(data, modes)
  let mut total = 0
  for line in information {
    total += line.length()
    if total > 1000000 ||
      line.contains("\r") ||
      line.contains("\n") ||
      uncomment(line).to_upper() == "[END INFORMATION]" {
      raise Failure("invalid information line or size")
    }
    ignore(text_lines(line))
  }
  {
    data,
    noise: noise.copy(),
    noise_reference: noise_reference_ohms,
    mixed: modes,
    information: information.copy(),
  }
}

///|
/// Explicitly access raw matrices. For mixed mode, indices denote descriptors,
/// and references remain SINGLE-ENDED port references, not effective mode Z0.
pub fn Document::raw_network(self : Document) -> Network {
  self.data
}

///|
/// Extract an ordinary network only when no noise/mode metadata would be lost.
pub fn Document::network_only(self : Document) -> Network raise {
  if !self.noise.is_empty() || !self.mixed.is_empty() {
    raise Failure(
      "explicit metadata handling required before network operations",
    )
  }
  self.data
}

///|
pub fn Document::noise_data(self : Document) -> Array[NoisePoint] {
  self.noise.copy()
}

///|
pub fn Document::noise_reference_ohms(self : Document) -> Double {
  self.noise_reference
}

///|
pub fn Document::mixed_mode_order(self : Document) -> Array[String] {
  self.mixed.copy()
}

///|
pub fn Document::information_lines(self : Document) -> Array[String] {
  self.information.copy()
}

///|
fn noise_line(
  line : String,
  factor : Double,
  resistance_scale : Double,
) -> NoisePoint raise {
  let tokens = words(line)
  if tokens.length() != 5 {
    raise Failure("noise record requires five numbers on one line")
  }
  {
    frequency_hz: number(tokens[0]) * factor,
    minimum_figure_db: number(tokens[1]),
    gamma_opt: pair(number(tokens[2]), number(tokens[3]), "MA"),
    resistance_ohms: number(tokens[4]) * resistance_scale,
  }
}

///|
fn legacy_document(text : String, ports : Int) -> Document raise {
  if ports < 1 || ports > 32 {
    raise Failure("legacy ports must be 1..32")
  }
  let network_text = StringBuilder()
  let mut opt : TextOptions? = None
  let mut remainder = 0
  let mut last = -1.0
  let mut in_noise = false
  let noise = []
  let width = 1 + ports * ports * 2
  for raw in text_lines(text) {
    let line = uncomment(raw)
    if line.is_empty() {
      continue
    }
    if line.has_prefix("#") {
      if opt is None {
        opt = Some(read_options(line))
        network_text.write_string(line + "\n")
      }
      continue
    }
    guard opt is Some(o) else { raise Failure("missing option line") }
    let tokens = words(line)
    if !in_noise &&
      ports == 2 &&
      remainder == 0 &&
      last >= 0.0 &&
      number(tokens[0]) * o.factor <= last {
      in_noise = true
    }
    if in_noise {
      noise.push(noise_line(line, o.factor, o.reference[0]))
      if noise.length() > 100000 {
        raise Failure("noise point limit exceeded")
      }
    } else {
      for token in tokens {
        if remainder == 0 {
          last = number(token) * o.factor
        }
        remainder = (remainder + 1) % width
      }
      network_text.write_string(line + "\n")
    }
  }
  guard opt is Some(o) else { raise Failure("missing option line") }
  document(
    parse_legacy(network_text.to_string(), ports~),
    noise~,
    noise_reference_ohms=o.reference[0],
  )
}
