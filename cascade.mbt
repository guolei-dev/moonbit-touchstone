///|
// Chain scattering convention [b1,a1]^T = T [a2,b2]^T. Multiplication is
// left-to-right along the signal path; unlike Z this handles an ideal thru.
fn to_chain(m : Array[Complex]) -> Array[Complex] raise {
  let inverse = complex(1.0).divide(m[2])
  [
    checked(m[1].sub(m[0].mul(m[3]).mul(inverse))),
    checked(m[0].mul(inverse)),
    checked(m[3].scale(-1.0).mul(inverse)),
    inverse,
  ]
}

///|
fn from_chain(t : Array[Complex]) -> Array[Complex] raise {
  let inverse = complex(1.0).divide(t[3])
  [
    checked(t[1].mul(inverse)),
    checked(t[0].sub(t[1].mul(t[2]).mul(inverse))),
    inverse,
    checked(t[2].scale(-1.0).mul(inverse)),
  ]
}

///|
fn matching_grid(a : Network, b : Network) -> Unit raise {
  if a.n != 2 || b.n != 2 || a.frequencies.length() != b.frequencies.length() {
    raise Failure("two-port matching frequency grids required")
  }
  for i, f in a.frequencies {
    if b.frequencies[i] != f {
      raise Failure("frequency grids differ; interpolate explicitly")
    }
  }
}

///|
/// Cascade this two-port followed by right. Connected references must match.
/// Requires nonzero forward transmission; unilateral reverse transmission is OK.
pub fn Network::cascade(self : Network, right : Network) -> Network raise {
  matching_grid(self, right)
  if self.reference[1] != right.reference[0] {
    raise Failure("connected port references differ; renormalize explicitly")
  }
  let a = self.convert("S")
  let b = right.convert("S")
  let values = Array::makei(a.values.length(), p => {
    from_chain(product(2, to_chain(a.values[p]), to_chain(b.values[p])))
  })
  network(2, self.frequencies, values, [self.reference[0], right.reference[1]])
}

///|
/// measured = left * DUT * right. Return DUT using fixture inner references.
/// Fixture chain matrices must be invertible and grids exactly equal.
pub fn Network::deembed(
  self : Network,
  left : Network,
  right : Network,
) -> Network raise {
  matching_grid(self, left)
  matching_grid(self, right)
  if self.reference[0] != left.reference[0] ||
    self.reference[1] != right.reference[1] {
    raise Failure("fixture external references differ from measurement")
  }
  let measured = self.convert("S")
  let l = left.convert("S")
  let r = right.convert("S")
  let values = Array::makei(self.values.length(), p => {
    let lm = invert_matrix(2, to_chain(l.values[p]))
    let rm = invert_matrix(2, to_chain(r.values[p]))
    from_chain(product(2, product(2, lm, to_chain(measured.values[p])), rm))
  })
  network(2, self.frequencies, values, [left.reference[1], right.reference[0]])
}
