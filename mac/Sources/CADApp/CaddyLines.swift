import Foundation

/// Everything Caddy says when a kid clicks him, and after a change, each with the pose he says it in.
/// Keep lines short and plain. No em dashes and no semicolons (a test checks this).
enum CaddyMoment: CaseIterable {
    case launch, home, process, processFailed, edit, afterChange
    // A build of parts.
    case split, added, copied, putAway, joined, cutHint, cutReady, cut, move, pickPart, partFailed
}

/// One thing Caddy says. `then` follows a moment later, so a sad line can end on a hopeful one.
struct CaddyLine: Equatable {
    let text: String
    let pose: CaddyView.Pose
    var then: [CaddyLine] = []

    init(_ text: String, _ pose: CaddyView.Pose, then: CaddyLine? = nil) {
        self.text = text
        self.pose = pose
        self.then = then.map { [$0] } ?? []
    }
}

enum CaddyLines {
    static func lines(_ moment: CaddyMoment) -> [CaddyLine] {
        switch moment {
        case .launch:
            [CaddyLine("Hi! I am waking up.", .hatching),
             CaddyLine("Almost ready. Stretching my wings!", .sleepy),
             CaddyLine("One moment, I am getting set up.", .thinking)]
        case .home:
            [CaddyLine("Hi there! Let's make something.", .hello),
             CaddyLine("Pick Start scanning to film a real thing.", .pointRight),
             CaddyLine("No camera? Try the sample cup.", .idea),
             CaddyLine("I love new ideas. What will you make?", .loveIt),
             CaddyLine("Tap me any time for a tip!", .talking)]
        case .process:
            [CaddyLine("I am building your model. Hang on!", .thinking),
             CaddyLine("Turning your video into 3D. Beep boop.", .talking),
             CaddyLine("Good things take a little time.", .sleepy),
             CaddyLine("Nearly there. I am counting the corners.", .thinking)]
        case .processFailed:
            [CaddyLine("Oops. That one did not work.", .sad, then: CaddyLine("Let's try again. You can do it!", .cheer)),
             CaddyLine("Hmm, too dark maybe?", .sad, then: CaddyLine("Try brighter light and a plain table.", .idea)),
             CaddyLine("You can always use the sample cup.", .idea)]
        case .edit:
            [CaddyLine("Drag the model to spin it around.", .pointLeft),
             CaddyLine("Try Taller to make it grow!", .pointRight),
             CaddyLine("Type your own idea in the box.", .idea),
             CaddyLine("Made a mistake? Undo takes it back.", .talking),
             CaddyLine("When you like it, press Save STL.", .pointRight),
             CaddyLine("Yawn. Pick a quick change to wake me up!", .sleepy)]
        case .afterChange:
            [CaddyLine("Looking good!", .cheer), CaddyLine("Nice change!", .cheer),
             CaddyLine("Ooh, I like it!", .loveIt), CaddyLine("Great job!", .loveIt)]
        case .split:
            [CaddyLine("I found more than one thing! Now they are parts.", .idea),
             CaddyLine("Ta da! Your scan is in pieces now.", .cheer)]
        case .added:
            [CaddyLine("Ta da! A new part.", .cheer),
             CaddyLine("New part! Pick Move and slide it.", .pointLeft)]
        case .copied:
            [CaddyLine("Two of them! Twice the fun.", .loveIt),
             CaddyLine("Copy made. Slide it where you like.", .cheer)]
        case .putAway:
            [CaddyLine("Put away. You can bring it back.", .talking),
             CaddyLine("Tidy! It waits in Put away.", .idea)]
        case .joined:
            [CaddyLine("Now they move together.", .loveIt),
             CaddyLine("Stuck together like best friends.", .cheer)]
        case .cutHint:
            [CaddyLine("Draw a line across a part to cut it.", .pointLeft),
             CaddyLine("Drag a line where you want the cut.", .idea)]
        case .cutReady:
            [CaddyLine("Snip ready! Tap Cut here.", .pointRight),
             CaddyLine("Happy with the line? Tap Cut here.", .idea)]
        case .cut:
            [CaddyLine("Snip snip! Two parts now.", .cheer),
             CaddyLine("Clean cut! Nice work.", .loveIt)]
        case .move:
            [CaddyLine("Grab a part and slide it.", .pointLeft),
             CaddyLine("Let go to drop it.", .talking)]
        case .pickPart:
            [CaddyLine("Pick a part first.", .pointLeft),
             CaddyLine("Click a part, then try again.", .idea)]
        case .partFailed:
            [CaddyLine("Oops. That did not work.", .sad, then: CaddyLine("Try again. You can do it!", .cheer)),
             CaddyLine("Hmm, that one was tricky.", .thinking)]
        }
    }

    /// Every line, follow ups included.
    static var all: [CaddyLine] { CaddyMoment.allCases.flatMap(lines).flatMap { [$0] + $0.then } }

    /// A random line for the moment, never the same as the last one.
    static func pick(_ moment: CaddyMoment, after last: CaddyLine?) -> CaddyLine {
        let options = lines(moment).filter { $0 != last }
        return options.randomElement() ?? lines(moment)[0]
    }
}
