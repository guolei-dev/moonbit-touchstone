///|
/// Cartesian complex value. Values admitted to a Network must be finite.
pub(all) struct Complex {
  re : Double
  im : Double
} derive(ToJson)

///|
pub extend Complex with ToJson::{to_json}

///|
pub fn complex(re : Double, im? : Double = 0.0) -> Complex {
  { re, im, }
}

///|
pub fn Complex::add(a : Complex, b : Complex) -> Complex {
  { re: a.re + b.re, im: a.im + b.im, }
}

///|
pub fn Complex::sub(a : Complex, b : Complex) -> Complex {
  { re: a.re - b.re, im: a.im - b.im, }
}

///|
pub fn Complex::mul(a : Complex, b : Complex) -> Complex {
  { re: a.re * b.re - a.im * b.im, im: a.re * b.im + a.im * b.re, }
}

///|
pub fn Complex::scale(a : Complex, x : Double) -> Complex {
  { re: a.re * x, im: a.im * x, }
}

///|
pub fn Complex::conjugate(a : Complex) -> Complex {
  { re: a.re, im: -a.im, }
}

///|
pub fn Complex::magnitude(a : Complex) -> Double {
  @math.hypot(a.re, a.im)
}

///|
pub fn Complex::phase(a : Complex) -> Double {
  @math.atan2(a.im, a.re)
}

///|
fn finite(x : Double) -> Bool {
  !x.is_nan() && !x.is_inf()
}

///|
fn checked(z : Complex) -> Complex raise {
  if !finite(z.re) || !finite(z.im) {
    raise Failure("non-finite complex result")
  }
  z
}

///|
/// Scaled division avoids squaring the denominator. Overflow is reported,
/// never silently installed in a network. Zero is not replaced by an epsilon.
pub fn Complex::divide(a : Complex, b : Complex) -> Complex raise {
  if !finite(a.re) || !finite(a.im) || !finite(b.re) || !finite(b.im) {
    raise Failure("division requires finite complex values")
  }
  let scale = b.re.abs().max(b.im.abs())
  if scale == 0.0 {
    raise Failure("zero complex denominator")
  }
  let br = b.re / scale
  let bi = b.im / scale
  let ar = a.re / scale
  let ai = a.im / scale
  let den = br * br + bi * bi
  checked({ re: (ar * br + ai * bi) / den, im: (ai * br - ar * bi) / den, })
}
