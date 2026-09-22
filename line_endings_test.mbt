///|
test "CRLF does not duplicate preserved information lines" {
  let text = "[Version] 2.1\r\n# Hz S RI R 50\r\n[Number of Ports] 1\r\n[Number of Frequencies] 1\r\n[Begin Information]\r\nmeasured fixture\r\n[End Information]\r\n[Network Data]\r\n1 0.2 0\r\n[End]\r\n"
  let doc = @touchstone.parse(text)
  assert_eq(doc.information_lines().length(), 1)
  assert_eq(doc.information_lines()[0], "measured fixture")
}
