import CoreGraphics
// Prints the id of the biggest on-screen CADDIY window. Window only, never the full screen.
var best = (0, 0.0)
for w in (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? [] {
  guard (w["kCGWindowOwnerName"] as? String) == "CADDIY", let b = w["kCGWindowBounds"] as? [String: Double] else { continue }
  let a = (b["Width"] ?? 0) * (b["Height"] ?? 0)
  if a > best.1 { best = (w["kCGWindowNumber"] as? Int ?? 0, a) }
}
print(best.0)
