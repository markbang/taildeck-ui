import Foundation

// The Go bridge and libghostty-vt ship as static archives. Referencing their
// entry points here (plus `-force_load` in the Runner target) turns a missing
// archive into a link error instead of an app that silently runs on mock data.
@_silgen_name("td_start")
func td_start(_ config: UnsafePointer<CChar>?) -> UnsafePointer<CChar>?

@_silgen_name("td_term_create")
func td_term_create(
  _ cols: Int32, _ rows: Int32, _ scrollback: Int32,
  _ fg: Int32, _ bg: Int32, _ cursor: Int32
) -> UnsafeMutableRawPointer?

enum NativeLink {
  static let linked = (td_start, td_term_create)

  /// Reads both addresses through a runtime mask so the optimizer cannot fold
  /// them away; true when both archives linked.
  @inline(never)
  static func verify() -> Bool {
    let mask = UInt(bitPattern: ObjectIdentifier(NativeLink.self))
    let start = unsafeBitCast(linked.0, to: UInt.self)
    let term = unsafeBitCast(linked.1, to: UInt.self)
    return (start ^ mask) != mask && (term ^ mask) != mask
  }
}
