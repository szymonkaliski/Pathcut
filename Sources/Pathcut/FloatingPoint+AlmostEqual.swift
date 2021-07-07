//
//  File.swift
//
//
//  Created by Valentin Radu on 16/01/2020.
//

import Foundation

extension FloatingPoint {
  public func isAlmostEqual(to other: Self, tolerance: Self = Self.ulpOfOne.squareRoot()) -> Bool {
    assert(tolerance >= .ulpOfOne && tolerance < 1)
    guard isFinite, other.isFinite else { return rescaledAlmostEqual(to: other, tolerance: tolerance) }
    let scale = max(abs(self), abs(other), .leastNormalMagnitude)
    return abs(self - other) < scale * tolerance
  }

  private func rescaledAlmostEqual(to other: Self, tolerance: Self) -> Bool {
    if isNaN || other.isNaN { return false }
    if isInfinite {
      if other.isInfinite { return self == other }
      let scaledSelf = Self(sign: sign,
                            exponent: Self.greatestFiniteMagnitude.exponent,
                            significand: 1)
      let scaledOther = Self(sign: .plus,
                             exponent: -1,
                             significand: other)
      return scaledSelf.isAlmostEqual(to: scaledOther, tolerance: tolerance)
    }
    return other.rescaledAlmostEqual(to: self, tolerance: tolerance)
  }
}
