#if os(iOS) || os(tvOS)
import UIKit
import XCTest

extension Diffing where Value == UIImage {
  /// A pixel-diffing strategy for UIImage's which requires a 100% match.
  public static let image = Diffing.image(precision: 1)

  /// A pixel-diffing strategy for UIImage that allows customizing how precise the matching must be.
  ///
  /// - Parameter precision: A value between 0 and 1, where 1 means the images must match 100% of their pixels.
  /// - Returns: A new diffing strategy.
  public static func image(precision: Float) -> Diffing {
    return Diffing(
      toData: { $0.pngData()! },
      fromData: { UIImage(data: $0, scale: UIScreen.main.scale)! }
    ) { old, new in
      guard !compare(old, new, precision: precision) else { return nil }
      let difference = SnapshotTesting.diff(old, new)
      let message = new.size == old.size
        ? "Newly-taken snapshot does not match reference."
        : "Newly-taken snapshot@\(new.size) does not match reference@\(old.size)."
      let oldAttachment = XCTAttachment(image: old)
      oldAttachment.name = "reference"
      let newAttachment = XCTAttachment(image: new)
      newAttachment.name = "failure"
      let differenceAttachment = XCTAttachment(image: difference)
      differenceAttachment.name = "difference"
      return (
        message,
        [oldAttachment, newAttachment, differenceAttachment]
      )
    }
  }
}

extension Snapshotting where Value == UIImage, Format == UIImage {
  /// A snapshot strategy for comparing images based on pixel equality.
  public static var image: Snapshotting {
    return .image(precision: 1)
  }

  /// A snapshot strategy for comparing images based on pixel equality.
  ///
  /// - Parameter precision: The percentage of pixels that must match.
  public static func image(precision: Float) -> Snapshotting {
    return .init(
      pathExtension: "png",
      diffing: .image(precision: precision)
    )
  }
}

private func compare(_ old: UIImage, _ new: UIImage, precision: Float) -> Bool {
  guard let oldCgImage = old.cgImage else { return false }
  guard let newCgImage = new.cgImage else { return false }
  guard oldCgImage.width != 0 else { return false }
  guard newCgImage.width != 0 else { return false }
  guard oldCgImage.width == newCgImage.width else { return false }
  guard oldCgImage.height != 0 else { return false }
  guard newCgImage.height != 0 else { return false }
  guard oldCgImage.height == newCgImage.height else { return false }
  let maxBytesPerRow = max(oldCgImage.bytesPerRow, newCgImage.bytesPerRow)
  let byteCount = maxBytesPerRow * oldCgImage.height
  var oldBytes = [UInt8](repeating: 0, count: byteCount)
  guard let oldContext = context(for: oldCgImage, data: &oldBytes) else { return false }
  guard let oldData = oldContext.data else { return false }
  if let newContext = context(for: newCgImage), let newData = newContext.data {
    if memcmp(oldData, newData, byteCount) == 0 { return true }
  }
  let newer = UIImage(data: new.pngData()!)!
  guard let newerCgImage = newer.cgImage else { return false }
  var newerBytes = [UInt8](repeating: 0, count: byteCount)
  guard let newerContext = context(for: newerCgImage, data: &newerBytes) else { return false }
  guard let newerData = newerContext.data else { return false }
  if memcmp(oldData, newerData, byteCount) == 0 { return true }
  if precision >= 1 { return false }
  var differentPixelCount = 0
  let threshold = 1 - precision
  for byte in 0..<byteCount {
    if oldBytes[byte] != newerBytes[byte] { differentPixelCount += 1 }
    if Float(differentPixelCount) / Float(byteCount) > threshold { return false}
  }
  return true
}

private func context(for cgImage: CGImage, data: UnsafeMutableRawPointer? = nil) -> CGContext? {
  guard
    let space = cgImage.colorSpace,
    let context = CGContext(
      data: data,
      width: cgImage.width,
      height: cgImage.height,
      bitsPerComponent: cgImage.bitsPerComponent,
      bytesPerRow: cgImage.bytesPerRow,
      space: space,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
    else { return nil }

  context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
  return context
}

private func cgDiff(_ old: UIImage, _ new: UIImage) -> UIImage {
  let width = max(old.size.width, new.size.width)
  let height = max(old.size.height, new.size.height)
  UIGraphicsBeginImageContextWithOptions(CGSize(width: width, height: height), true, 0)
  new.draw(at: .zero)
  old.draw(at: .zero, blendMode: .difference, alpha: 1)
  let differenceImage = UIGraphicsGetImageFromCurrentImageContext()!
  UIGraphicsEndImageContext()
  return differenceImage
}

private func diff(_ old: UIImage, _ new: UIImage) -> UIImage {
  let oldCiImage = CIImage(cgImage: old.cgImage!)
  let newCiImage = CIImage(cgImage: new.cgImage!)
  let differenceFilter = CIFilter(name: "CIDifferenceBlendMode")!
  differenceFilter.setValue(oldCiImage, forKey: kCIInputImageKey)
  differenceFilter.setValue(newCiImage, forKey: kCIInputBackgroundImageKey)
  let differenceCiImage = differenceFilter.outputImage!
  let context = CIContext()
  let differenceCgImage = context.createCGImage(differenceCiImage, from: differenceCiImage.extent)!
  return UIImage(cgImage: differenceCgImage)
}
#endif
