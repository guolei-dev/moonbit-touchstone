///|
extern "js" fn fail_string(message : String) -> String =
  #| (message) => { throw new Error(message); }

///|
fn object(text : String) -> Map[String, Json] raise {
  if text.length() > 1000000 {
    raise Failure("options exceed one million characters")
  }
  match @json.parse(text) {
    Object(o) => o
    _ => raise Failure("options must be an object")
  }
}

///|
fn[T : @json.FromJson] required(o : Map[String, Json], key : String) -> T raise {
  match o.get(key) {
    Some(j) => @json.from_json(j)
    None => raise Failure("missing option: " + key)
  }
}

///|
fn[T : @json.FromJson] optional(
  o : Map[String, Json],
  key : String,
  fallback : T,
) -> T raise {
  match o.get(key) {
    Some(j) => @json.from_json(j)
    None => fallback
  }
}

///|
fn read_document(
  text : String,
  o : Map[String, Json],
  key : String,
) -> @lib.Document raise {
  match o.get(key) {
    Some(j) => @lib.parse(text, ports=@json.from_json(j))
    None => @lib.parse(text)
  }
}

///|
// Parsing, validation, transformations, metrics and serialization are MoonBit.
// The Node host only reads/writes files, supplies filename hints and arguments.
fn execute(
  text : String,
  options : String,
  left : String,
  right : String,
) -> String raise {
  let o = object(options)
  let command : String = optional(o, "command", "inspect")
  let doc = read_document(text, o, "ports")
  let raw = doc.raw_network()
  let result : Json = match command {
    "inspect" | "validate" =>
      {
        "ports": raw.ports().to_json(),
        "parameter": raw.parameter().to_json(),
        "points": raw.frequency_hz().length().to_json(),
        "frequency_hz": raw.frequency_hz().to_json(),
        "reference_ohms": raw.reference_ohms().to_json(),
        "noise": doc.noise_data().to_json(),
        "noise_reference_ohms": doc.noise_reference_ohms().to_json(),
        "mixed_mode_order": doc.mixed_mode_order().to_json(),
        "information": doc.information_lines().to_json(),
      }
    "dump" =>
      {
        "ports": raw.ports().to_json(),
        "parameter": raw.parameter().to_json(),
        "frequency_hz": raw.frequency_hz().to_json(),
        "reference_ohms": raw.reference_ohms().to_json(),
        "values": Array::makei(raw.frequency_hz().length(), i => raw.matrix(i)).to_json(),
        "mixed_mode_order": doc.mixed_mode_order().to_json(),
      }
    "normalize" => { "text": doc.write().to_json() }
    "legacy" => {
      if !doc.information_lines().is_empty() {
        raise Failure("legacy output cannot preserve information section")
      }
      {
        "text": doc
        .network_only()
        .write_legacy(
          format=optional(o, "format", "RI"),
          unit=optional(o, "unit", "HZ"),
        )
        .to_json(),
      }
    }
    "diagnostics" =>
      doc
      .network_only()
      .diagnostics(tolerance=optional(o, "tolerance", 1.0e-9))
      .to_json()
    "metrics" =>
      doc
      .network_only()
      .metrics(required(o, "output"), required(o, "input"))
      .to_json()
    "delay" =>
      doc
      .network_only()
      .group_delay(required(o, "output"), required(o, "input"))
      .to_json()
    _ => {
      let net = doc.network_only()
      let out = match command {
        "convert" => net.convert(required(o, "parameter"))
        "renormalize" => net.renormalize(required(o, "reference_ohms"))
        "select" => net.select_ports(required(o, "selection"))
        "interpolate" => net.interpolate(required(o, "frequency_hz"))
        "cascade" =>
          net.cascade(read_document(right, o, "right_ports").network_only())
        "deembed" =>
          net.deembed(
            read_document(left, o, "left_ports").network_only(),
            read_document(right, o, "right_ports").network_only(),
          )
        _ => raise Failure("unknown command")
      }
      {
        "text": @lib.document(out, information=doc.information_lines())
        .write()
        .to_json(),
      }
    }
  }
  result.stringify()
}

///|
pub fn run(
  text : String,
  options : String,
  left : String,
  right : String,
) -> String {
  execute(text, options, left, right) catch {
    e => fail_string(@debug.to_string(e))
  }
}
