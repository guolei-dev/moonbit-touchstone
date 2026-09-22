///|
priv struct TextOptions {
  factor : Double
  kind : String
  format : String
  reference : Array[Double]
}

///|
// Validate before UTF-16 slicing: Touchstone is ASCII, not arbitrary Unicode.
// The cap bounds token allocation, not merely the final network array.
fn text_lines(text : String) -> Array[String] raise {
  if text.length() > 64000000 {
    raise Failure("text exceeds 64 million characters")
  }
  let normalized = StringBuilder()
  for c in text {
    if c == '\r' {
      normalized.write_char('\n')
    } else if c == '\n' || c == '\t' || (c >= ' ' && c <= '~') {
      normalized.write_char(c)
    } else {
      raise Failure("Touchstone requires printable ASCII, tab and line endings")
    }
  }
  normalized.to_string().split("\n").map(x => x.to_owned()).to_array()
}

///|
fn uncomment(line : String) -> String {
  let end = line.find("!").unwrap_or(line.length())
  line[:end].trim().to_owned()
}

///|
fn words(line : String) -> Array[String] {
  let result = []
  let mut start = 0
  for i in 0..<=line.length() {
    if i == line.length() || line[i] == ' ' || line[i] == '\t' {
      if start < i {
        result.push(line[start:i].to_owned())
      }
      start = i + 1
    }
  }
  result
}

///|
fn number(token : String) -> Double raise {
  if token.contains("_") {
    raise Failure("underscores are not Touchstone numbers")
  }
  let x = @string.parse_double(token)
  if !finite(x) {
    raise Failure("non-finite numeric field")
  }
  x
}

///|
fn unit_factor(unit : String) -> Double raise {
  match unit.to_upper() {
    "HZ" => 1.0
    "KHZ" => 1000.0
    "MHZ" => 1000000.0
    "GHZ" => 1000000000.0
    _ => raise Failure("unsupported frequency unit")
  }
}

///|
fn read_options(line : String) -> TextOptions raise {
  let tokens = words(line[1:].to_owned())
  let mut unit = "GHZ"
  let mut kind = "S"
  let mut format = "MA"
  let refs = []
  let seen : Map[String, Bool] = Map([])
  let mut i = 0
  while i < tokens.length() {
    let token = tokens[i].to_upper()
    let key = match token {
      "HZ" | "KHZ" | "MHZ" | "GHZ" => {
        unit = token
        "unit"
      }
      "S" | "Y" | "Z" | "H" | "G" => {
        kind = token
        "kind"
      }
      "RI" | "MA" | "DB" => {
        format = token
        "format"
      }
      "R" => {
        i += 1
        while i < tokens.length() {
          let next = tokens[i].to_upper()
          if next == "HZ" ||
            next == "KHZ" ||
            next == "MHZ" ||
            next == "GHZ" ||
            next == "S" ||
            next == "Y" ||
            next == "Z" ||
            next == "H" ||
            next == "G" ||
            next == "RI" ||
            next == "MA" ||
            next == "DB" ||
            next == "R" {
            break
          }
          let r = number(tokens[i])
          if r <= 0.0 {
            raise Failure("reference must be positive")
          }
          refs.push(r)
          if refs.length() > 32 {
            raise Failure("too many references")
          }
          i += 1
        }
        if refs.is_empty() {
          raise Failure("R requires a reference resistance")
        }
        if refs.length() > 1 && i != tokens.length() {
          raise Failure("per-port R must end option line")
        }
        i -= 1
        "reference"
      }
      _ => raise Failure("unknown option: " + token)
    }
    if seen.contains(key) {
      raise Failure("duplicate option category: " + key)
    }
    seen[key] = true
    i += 1
  }
  if refs.is_empty() {
    refs.push(50.0)
  }
  { factor: unit_factor(unit), kind, format, reference: refs, }
}

///|
fn references(refs : Array[Double], n : Int) -> Array[Double] raise {
  if refs.length() == 1 {
    Array::make(n, refs[0])
  } else if refs.length() == n {
    refs.copy()
  } else {
    raise Failure("reference count must be one or match ports")
  }
}

///|
fn pair(a : Double, b : Double, format : String) -> Complex raise {
  if format == "RI" {
    return checked(complex(a, im=b))
  }
  let magnitude = if format == "DB" { @math.pow(10.0, a / 20.0) } else { a }
  if magnitude < 0.0 || !finite(magnitude) {
    raise Failure("invalid magnitude")
  }
  let angle = b / 180.0 * @math.PI
  checked(
    complex(magnitude * @math.cos(angle), im=magnitude * @math.sin(angle)),
  )
}

///|
// IBIS 2.1 p8: legacy Y/Z/H/G are normalized. Scale voltages by sqrt(R)
// and currents by 1/sqrt(R); H maps (I1,V2) -> (V1,I2), G reverses that.
fn legacy_factor(
  kind : String,
  row : Int,
  col : Int,
  refs : Array[Double],
) -> Double {
  let dr = refs[row].sqrt()
  let dc = refs[col].sqrt()
  match kind {
    "Z" => dr * dc
    "Y" => 1.0 / dr / dc
    "H" =>
      (if row == 0 { dr } else { 1.0 / dr }) *
      (if col == 0 { dc } else { 1.0 / dc })
    "G" =>
      (if row == 0 { 1.0 / dr } else { dr }) *
      (if col == 0 { 1.0 / dc } else { dc })
    _ => 1.0
  }
}

///|
fn write_pair(
  out : StringBuilder,
  value : Complex,
  format : String,
) -> Unit raise {
  ignore(checked(value))
  if format == "RI" {
    out.write_string(" \{value.re} \{value.im}")
  } else {
    let mag = value.magnitude()
    // -Inf is not portable Touchstone numeric syntax. Use RI/MA for exact zero.
    if format == "DB" && mag == 0.0 {
      raise Failure(
        "zero magnitude cannot be encoded as finite DB; use RI or MA",
      )
    }
    let a = if format == "DB" { 20.0 * @math.log10(mag) } else { mag }
    let b = value.phase() * 180.0 / @math.PI
    if !finite(a) || !finite(b) {
      raise Failure("non-finite formatted value")
    }
    out.write_string(" \{a} \{b}")
  }
}
