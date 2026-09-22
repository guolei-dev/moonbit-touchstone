///|
fn integer(text : String) -> Int raise {
  if text.is_empty() || !text.iter().all(c => c >= '0' && c <= '9') {
    raise Failure("positive decimal integer expected")
  }
  let n = @string.parse_int(text)
  if n <= 0 {
    raise Failure("positive integer expected")
  }
  n
}

///|
fn keyword(line : String) -> (String, String) raise {
  guard line.find("]") is Some(end) else {
    raise Failure("unterminated keyword")
  }
  if end + 1 < line.length() && line[end + 1] != ' ' && line[end + 1] != '\t' {
    raise Failure("keyword argument needs whitespace")
  }
  (line[1:end].to_owned().to_upper(), line[end + 1:].trim().to_owned())
}

///|
/// Read a 1.x or 2.0/2.1 document. Legacy requires explicit ports. For 2.x a
/// supplied ports value is a consistency check, never an override of the file.
pub fn parse(text : String, ports? : Int) -> Document raise {
  let lines = text_lines(text)
  let mut first = ""
  for raw in lines {
    let line = uncomment(raw)
    if !line.is_empty() {
      first = line
      break
    }
  }
  if !first.to_upper().has_prefix("[VERSION]") {
    guard ports is Some(n) else {
      raise Failure("legacy file needs port count")
    }
    return legacy_document(text, n)
  }
  let headers : Map[String, String] = Map([])
  let numbers : Array[Double] = []
  let noise_text = []
  let information = []
  let mut mode = "header"
  let mut continuation = ""
  let mut opt : TextOptions? = None
  let mut info_size = 0
  for raw in lines {
    let line = uncomment(raw)
    if mode == "information" {
      if line.to_upper() == "[END INFORMATION]" {
        mode = "header"
      } else {
        info_size += raw.length()
        if info_size > 1000000 {
          raise Failure("information exceeds one million characters")
        }
        information.push(raw)
      }
      continue
    }
    if line.is_empty() {
      continue
    }
    if mode == "end" {
      raise Failure("content after End")
    }
    if line.has_prefix("#") {
      if opt is None {
        if !headers.contains("VERSION") || headers.contains("NUMBER OF PORTS") {
          raise Failure("option line out of order")
        }
        let o = read_options(line)
        if o.reference.length() != 1 {
          raise Failure("2.x per-port references require Reference keyword")
        }
        opt = Some(o)
      }
      continue
    }
    if line.has_prefix("[") {
      if raw[0] != '[' {
        raise Failure("keyword must start in column one")
      }
      let (key, value) = keyword(line)
      continuation = ""
      if headers.contains(key) {
        raise Failure("duplicate keyword: " + key)
      }
      match key {
        "VERSION" =>
          if !headers.is_empty() || (value != "2.0" && value != "2.1") {
            raise Failure("unsupported or misplaced Version")
          }
        "NUMBER OF PORTS" => {
          if opt is None || mode != "header" {
            raise Failure("Number of Ports requires option line")
          }
          let n = integer(value)
          if n > 32 {
            raise Failure("at most 32 ports")
          }
        }
        "NETWORK DATA" => {
          if mode != "header" ||
            !headers.contains("NUMBER OF FREQUENCIES") ||
            !value.is_empty() {
            raise Failure("invalid Network Data boundary")
          }
          mode = "data"
        }
        "NOISE DATA" => {
          if mode != "data" ||
            !headers.contains("NUMBER OF NOISE FREQUENCIES") ||
            !value.is_empty() {
            raise Failure("invalid Noise Data boundary")
          }
          mode = "noise"
        }
        "END" => {
          if (mode != "data" && mode != "noise") || !value.is_empty() {
            raise Failure("invalid End boundary")
          }
          mode = "end"
        }
        "NUMBER OF FREQUENCIES"
        | "NUMBER OF NOISE FREQUENCIES"
        | "REFERENCE"
        | "MATRIX FORMAT"
        | "TWO-PORT DATA ORDER"
        | "MIXED-MODE ORDER"
        | "BEGIN INFORMATION" => {
          if mode != "header" || !headers.contains("NUMBER OF PORTS") {
            raise Failure("header keyword out of order")
          }
          if key == "REFERENCE" || key == "MIXED-MODE ORDER" {
            continuation = key
          }
          if key == "BEGIN INFORMATION" {
            if !value.is_empty() {
              raise Failure("Begin Information takes no argument")
            }
            mode = "information"
          }
        }
        _ => raise Failure("unsupported keyword: " + key)
      }
      if (key == "REFERENCE" || key == "MIXED-MODE ORDER") &&
        value.length() > 4096 {
        raise Failure("reference/mode header exceeds 4096 characters")
      }
      headers[key] = value
      continue
    }
    match mode {
      "header" => {
        if continuation == "" {
          raise Failure("unexpected numeric header content")
        }
        if headers[continuation].length() + line.length() + 1 > 4096 {
          raise Failure("reference/mode header exceeds 4096 characters")
        }
        headers[continuation] = headers[continuation] + " " + line
      }
      "data" => {
        for token in words(line) {
          numbers.push(number(token))
        }
        if numbers.length() > 4100000 {
          raise Failure("network data exceeds value limit")
        }
      }
      "noise" => {
        noise_text.push(line)
        if noise_text.length() > 100000 {
          raise Failure("noise limit exceeded")
        }
      }
      _ => raise Failure("unexpected data")
    }
  }
  if mode != "end" {
    raise Failure("missing End or unterminated information")
  }
  guard opt is Some(o) else { raise Failure("missing option line") }
  guard headers.get("NUMBER OF PORTS") is Some(ntext) else {
    raise Failure("missing Number of Ports")
  }
  let n = integer(ntext)
  if ports is Some(p) && p != n {
    raise Failure("filename/caller port count conflicts with header")
  }
  let count = integer(headers["NUMBER OF FREQUENCIES"])
  if count > 100000 || count > 2000000 / (n * n) {
    raise Failure("point count exceeds resource limit")
  }
  let refs = if headers.get("REFERENCE") is Some(r) {
    let r = words(r).map(number)
    if r.length() != n {
      raise Failure("Reference needs exactly N values")
    }
    r
  } else {
    references(o.reference, n)
  }
  let format = headers.get("MATRIX FORMAT").unwrap_or("Full").to_upper()
  if format != "FULL" && format != "UPPER" && format != "LOWER" {
    raise Failure("unsupported matrix layout")
  }
  let order = headers.get("TWO-PORT DATA ORDER").unwrap_or("").to_upper()
  if (n == 2 && order != "12_21" && order != "21_12") || (n != 2 && order != "") {
    raise Failure("invalid/missing Two-Port Data Order")
  }
  let indices = []
  for row in 0..<n {
    for col in 0..<n {
      if format == "FULL" ||
        (format == "UPPER" && col >= row) ||
        (format == "LOWER" && col <= row) {
        indices.push(row * n + col)
      }
    }
  }
  if n == 2 && format == "FULL" && order == "21_12" {
    indices[1] = 2
    indices[2] = 1
  }
  let width = 1 + 2 * indices.length()
  if numbers.length() != count * width {
    raise Failure("Number of Frequencies does not match network data length")
  }
  let freq = []
  let matrices = []
  for p in 0..<count {
    freq.push(numbers[p * width] * o.factor)
    let m = Array::make(n * n, complex(0.0))
    for k, index in indices {
      let z = pair(
        numbers[p * width + 1 + k * 2],
        numbers[p * width + 2 + k * 2],
        o.format,
      )
      m[index] = z
      // Triangle means transpose symmetry, not Hermitian conjugate symmetry.
      if format != "FULL" {
        m[index % n * n + index / n] = z
      }
    }
    matrices.push(m)
  }
  let data = network(n, freq, matrices, refs, parameter=o.kind)
  let noise = noise_text.map(line => noise_line(line, o.factor, 1.0))
  if headers.get("NUMBER OF NOISE FREQUENCIES") is Some(c) {
    if integer(c) != noise.length() || !headers.contains("NOISE DATA") {
      raise Failure("noise count/boundary mismatch")
    }
  } else if !noise.is_empty() {
    raise Failure("unexpected noise")
  }
  let mixed = words(headers.get("MIXED-MODE ORDER").unwrap_or(""))
  if headers.contains("MIXED-MODE ORDER") && mixed.is_empty() {
    raise Failure("empty mixed-mode order")
  }
  document(
    data,
    noise~,
    noise_reference_ohms=o.reference[0],
    mixed_mode_order=mixed,
    information~,
  )
}

///|
/// Canonical 2.1 output in Hz/RI/full/12_21 form; preserves noise, mode order,
/// information and references. Comments and original whitespace are not kept.
pub fn Document::write(self : Document) -> String raise {
  let n = self.data.n
  let out = StringBuilder()
  out.write_string(
    "[Version] 2.1\n# Hz \{self.data.kind} RI R \{self.noise_reference}\n[Number of Ports] \{n}\n",
  )
  if n == 2 {
    out.write_string("[Two-Port Data Order] 12_21\n")
  }
  out.write_string(
    "[Number of Frequencies] \{self.data.frequencies.length()}\n[Reference]",
  )
  for r in self.data.reference {
    out.write_string(" \{r}")
  }
  out.write_string("\n[Matrix Format] Full\n")
  if !self.noise.is_empty() {
    out.write_string("[Number of Noise Frequencies] \{self.noise.length()}\n")
  }
  if !self.mixed.is_empty() {
    out.write_string("[Mixed-Mode Order] " + self.mixed.join(" ") + "\n")
  }
  if !self.information.is_empty() {
    out.write_string(
      "[Begin Information]\n" +
      self.information.join("\n") +
      "\n[End Information]\n",
    )
  }
  out.write_string("[Network Data]\n")
  for p, f in self.data.frequencies {
    out.write_string("\{f}")
    for k, z in self.data.values[p] {
      out.write_string(" \{z.re} \{z.im}")
      if n > 2 && ((k % n + 1) % 4 == 0 || k % n == n - 1) && k + 1 < n * n {
        out.write_string("\n ")
      }
    }
    out.write_string("\n")
  }
  if !self.noise.is_empty() {
    out.write_string("[Noise Data]\n")
    for p in self.noise {
      let magnitude = p.gamma_opt.magnitude()
      let phase = p.gamma_opt.phase() * 180.0 / @math.PI
      out.write_string(
        "\{p.frequency_hz} \{p.minimum_figure_db} \{magnitude} \{phase} \{p.resistance_ohms}\n",
      )
    }
  }
  out.write_string("[End]\n")
  bounded_output(out)
}
