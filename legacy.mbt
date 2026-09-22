///|
/// Read legacy 1.0/1.1 network data; ports must come from a trusted filename or
/// explicit caller choice. Frequencies become Hz, non-S values become SI.
/// Noise sections are not accepted by this network-only entry point.
pub fn parse_legacy(text : String, ports~ : Int) -> Network raise {
  if ports < 1 || ports > 32 {
    raise Failure("ports must be 1..32")
  }
  let mut options : TextOptions? = None
  let pending : Array[Double] = []
  let freq = []
  let values = []
  let mut refs = []
  let width = 1 + 2 * ports * ports
  for line in text_lines(text) {
    let line = uncomment(line)
    if line.is_empty() {
      continue
    }
    if line.has_prefix("#") {
      // The standard explicitly ignores option lines after the first.
      if options is None {
        let opt = read_options(line)
        refs = references(opt.reference, ports)
        options = Some(opt)
      }
      continue
    }
    if line.has_prefix("[") {
      raise Failure("versioned keywords require the document parser")
    }
    guard options is Some(opt) else {
      raise Failure("missing option line before data")
    }
    for token in words(line) {
      pending.push(number(token))
      if pending.length() == width {
        let f = pending[0] * opt.factor
        if !freq.is_empty() && f <= freq[freq.length() - 1] {
          raise Failure(
            "network frequencies must increase; use document parser for noise",
          )
        }
        let m = Array::make(ports * ports, complex(0.0))
        for k in 0..<(ports * ports) {
          let index = if ports == 2 { k % 2 * 2 + k / 2 } else { k }
          let raw = pair(pending[1 + 2 * k], pending[2 + 2 * k], opt.format)
          m[index] = checked(
            raw.scale(
              legacy_factor(opt.kind, index / ports, index % ports, refs),
            ),
          )
        }
        freq.push(f)
        values.push(m)
        pending.clear()
        if freq.length() > 100000 || freq.length() > 2000000 / (ports * ports) {
          raise Failure("network exceeds point/value limit")
        }
      }
    }
  }
  guard options is Some(opt) else { raise Failure("missing option line") }
  if !pending.is_empty() {
    raise Failure("truncated network record or unsupported legacy noise")
  }
  network(ports, freq, values, refs, parameter=opt.kind)
}

///|
/// Write 1.0 (uniform reference) or 1.1 (per-port references), preserving SI
/// values by reversing legacy normalization. No metadata exists on Network.
pub fn Network::write_legacy(
  self : Network,
  format? : String = "RI",
  unit? : String = "HZ",
) -> String raise {
  let format = format.to_upper()
  if format != "RI" && format != "MA" && format != "DB" {
    raise Failure("format must be RI, MA or DB")
  }
  let factor = unit_factor(unit)
  let out = StringBuilder()
  out.write_string("# \{unit.to_upper()} \{self.kind} \{format} R")
  let uniform = self.reference.all(x => x == self.reference[0])
  if uniform {
    out.write_string(" \{self.reference[0]}")
  } else {
    for r in self.reference {
      out.write_string(" \{r}")
    }
  }
  out.write_string("\n")
  for p, f in self.frequencies {
    out.write_string("\{f / factor}")
    for k in 0..<(self.n * self.n) {
      let index = if self.n == 2 { k % 2 * 2 + k / 2 } else { k }
      let scale = legacy_factor(
        self.kind,
        index / self.n,
        index % self.n,
        self.reference,
      )
      if !finite(scale) || scale == 0.0 {
        raise Failure("legacy normalization outside numerical range")
      }
      write_pair(out, checked(self.values[p][index].scale(1.0 / scale)), format)
      if self.n > 2 &&
        ((k % self.n + 1) % 4 == 0 || k % self.n == self.n - 1) &&
        k + 1 < self.n * self.n {
        out.write_string("\n ")
      }
    }
    out.write_string("\n")
  }
  out.to_string()
}
