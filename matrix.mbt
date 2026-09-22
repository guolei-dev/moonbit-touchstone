///|
fn matrix_size(n : Int, m : Array[Complex]) -> Unit raise {
  if n < 1 || n > 32 || m.length() != n * n {
    raise Failure("expected square row-major matrix with 1..32 ports")
  }
  for z in m {
    ignore(checked(z))
  }
}

///|
fn identity(n : Int) -> Array[Complex] {
  Array::makei(n * n, i => complex(if i / n == i % n { 1.0 } else { 0.0 }))
}

///|
fn product(
  n : Int,
  a : Array[Complex],
  b : Array[Complex],
) -> Array[Complex] raise {
  Array::makei(n * n, ij => {
    let i = ij / n
    let j = ij % n
    let mut sum = complex(0.0)
    for k in 0..<n {
      sum = sum.add(a[i * n + k].mul(b[k * n + j]))
    }
    checked(sum)
  })
}

///|
/// Invert a finite row-major complex matrix by scaled partial pivoting.
/// Reject near-singular pivots relative to their row scale (1e-12).
/// Returns a new array. This is a numerical guard, not a condition estimator.
pub fn invert_matrix(n : Int, matrix : Array[Complex]) -> Array[Complex] raise {
  matrix_size(n, matrix)
  let a = matrix.copy()
  let b = identity(n)
  let scales = Array::makei(n, r => {
    let mut scale = 0.0
    for c in 0..<n {
      scale = scale.max(a[r * n + c].magnitude())
    }
    scale
  })
  for col in 0..<n {
    let mut pivot = col
    let mut score = 0.0
    for row in col..<n {
      let ratio = if scales[row] == 0.0 {
        0.0
      } else {
        a[row * n + col].magnitude() / scales[row]
      }
      if ratio > score {
        score = ratio
        pivot = row
      }
    }
    if score <= 1.0e-12 {
      raise Failure("singular or numerically unsafe matrix")
    }
    if pivot != col {
      for k in 0..<n {
        let t = a[col * n + k]
        a[col * n + k] = a[pivot * n + k]
        a[pivot * n + k] = t
        let u = b[col * n + k]
        b[col * n + k] = b[pivot * n + k]
        b[pivot * n + k] = u
      }
      let s = scales[col]
      scales[col] = scales[pivot]
      scales[pivot] = s
    }
    let diagonal = a[col * n + col]
    for k in 0..<n {
      a[col * n + k] = a[col * n + k].divide(diagonal)
      b[col * n + k] = b[col * n + k].divide(diagonal)
    }
    for row in 0..<n {
      if row != col {
        let coefficient = a[row * n + col]
        for k in 0..<n {
          a[row * n + k] = checked(
            a[row * n + k].sub(coefficient.mul(a[col * n + k])),
          )
          b[row * n + k] = checked(
            b[row * n + k].sub(coefficient.mul(b[col * n + k])),
          )
        }
      }
    }
  }
  b
}

///|
/// Multiply finite row-major square matrices. Neither input is mutated.
pub fn multiply_matrices(
  n : Int,
  a : Array[Complex],
  b : Array[Complex],
) -> Array[Complex] raise {
  matrix_size(n, a)
  matrix_size(n, b)
  product(n, a, b)
}
