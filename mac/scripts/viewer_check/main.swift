// Throwaway runner for ViewerSelfCheck. Built by scripts/viewer_check.sh, not part of the package.
import AppKit
import CADViewer

let args = CommandLine.arguments.dropFirst()
var pictures: URL?
var files = [URL]()
var it = args.makeIterator()
while let a = it.next() {
    if a == "--pictures", let d = it.next() { pictures = URL(fileURLWithPath: d) } else { files.append(URL(fileURLWithPath: a)) }
}
if let pictures { try? FileManager.default.createDirectory(at: pictures, withIntermediateDirectories: true) }
let ok = MainActor.assumeIsolated { ViewerSelfCheck.run(files: files, pictureDirectory: pictures) }
exit(ok ? 0 : 1)
