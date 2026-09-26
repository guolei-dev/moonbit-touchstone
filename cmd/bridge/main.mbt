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
    Some(j) => @lib.parse(text, ports=integer(j, key))
    None => @lib.parse(text)
  }
}

///|
// Core FromJson[Int] truncates fractions; CLI indices/budgets must not do so.
fn integer(value : Json, key : String) -> Int raise {
  let n : Double = @json.from_json(value)
  if n.is_nan() ||
    n.is_inf() ||
    n.floor() != n ||
    n < -2147483648.0 ||
    n > 2147483647.0 {
    raise Failure(key + " must be an exact Int32 integer")
  }
  n.to_int()
}

///|
fn required_int(o : Map[String, Json], key : String) -> Int raise {
  integer(required(o, key), key)
}

///|
fn optional_int(
  o : Map[String, Json],
  key : String,
  fallback : Int,
) -> Int raise {
  match o.get(key) {
    Some(j) => integer(j, key)
    None => fallback
  }
}

///|
fn bound(o : Map[String, Json], key : String) -> Double? raise {
  match o.get(key) {
    Some(j) => Some(@json.from_json(j))
    None => None
  }
}

///|
fn band_report(
  net : @lib.Network,
  options : Map[String, Json],
) -> @lib.BandReport raise {
  for key in options.keys() {
    if !(key == "command" ||
      key == "ports" ||
      key == "limits" ||
      key == "max_details") {
      raise Failure("unknown band check option: " + key)
    }
  }
  let items : Array[Json] = required(options, "limits")
  if items.is_empty() || items.length() > 256 {
    raise Failure("band check requires 1..256 rules")
  }
  let limits = items.map(item => {
    let o = match item {
      Object(o) => o
      _ => raise Failure("each band rule must be an object")
    }
    // A misspelled bound must not silently disable a requested check.
    for key in o.keys() {
      if !(key == "metric" ||
        key == "start_hz" ||
        key == "end_hz" ||
        key == "input" ||
        key == "output" ||
        key == "minimum" ||
        key == "maximum") {
        raise Failure("unknown band rule option: " + key)
      }
    }
    let name : String = required(o, "metric")
    let metric : @lib.BandMetric = match name {
      "reflection_magnitude" => ReflectionMagnitude
      "transmission_magnitude" => TransmissionMagnitude
      "return_loss_db" => ReturnLossDb
      "insertion_loss_db" => InsertionLossDb
      "vswr" => Vswr
      _ => raise Failure("unknown band metric: " + name)
    }
    @lib.band_limit(
      metric,
      required(o, "start_hz"),
      required(o, "end_hz"),
      input=required_int(o, "input"),
      output=required_int(o, "output"),
      minimum?=bound(o, "minimum"),
      maximum?=bound(o, "maximum"),
    )
  })
  net.check_bands(limits, max_details=optional_int(options, "max_details", 256))
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
      .metrics(required_int(o, "output"), required_int(o, "input"))
      .to_json()
    "delay" =>
      doc
      .network_only()
      .group_delay(required_int(o, "output"), required_int(o, "input"))
      .to_json()
    "ripple-check" => {
      for key in o.keys() {
        if !(key == "command" ||
          key == "ports" ||
          key == "start_hz" ||
          key == "end_hz" ||
          key == "input" ||
          key == "output" ||
          key == "maximum_ripple_db") {
          raise Failure("unknown ripple option: " + key)
        }
      }
      doc
      .network_only()
      .check_ripple(
        required(o, "start_hz"),
        required(o, "end_hz"),
        input=required_int(o, "input"),
        output=required_int(o, "output"),
        maximum_ripple_db=required(o, "maximum_ripple_db"),
      )
      .to_json()
    }
    "band-check" => band_report(doc.network_only(), o).to_json()
    "band-csv" => {
      let report = band_report(doc.network_only(), o)
      {
        "text": report.issues_csv().to_json(),
        "status": report.status.to_json(),
      }
    }
    _ => {
      let net = doc.network_only()
      let out = match command {
        "convert" => net.convert(required(o, "parameter"))
        "renormalize" => net.renormalize(required(o, "reference_ohms"))
        "select" => {
          let selection : Array[Json] = required(o, "selection")
          net.select_ports(selection.map(j => integer(j, "selection")))
        }
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
