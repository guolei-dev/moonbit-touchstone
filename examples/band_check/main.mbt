///|
// A non-reciprocal synthetic attenuator: S21=0.5, S12=0.25. Band checking
// keeps these directions distinct and never interpolates between samples.
fn main raise {
  let doc = @touchstone.parse(
    "# MHz S RI R 50\n100 0.1 0 0.5 0 0.25 0 0.1 0\n200 0.2 0 0.5 0 0.25 0 0.1 0\n300 0.3 0 0.5 0 0.25 0 0.1 0\n",
    ports=2,
  )
  let net = doc.network_only()
  let limits = [
    @touchstone.band_limit(
      InsertionLossDb,
      100.0e6,
      300.0e6,
      input=0,
      output=1,
      minimum=6.0,
      maximum=6.1,
    ),
    @touchstone.band_limit(
      ReturnLossDb,
      100.0e6,
      300.0e6,
      input=0,
      output=1,
      minimum=15.0,
    ),
  ]
  let report = net.check_bands(limits, max_details=16)
  println(report.to_json().stringify())
  println(report.issues_csv())
}
