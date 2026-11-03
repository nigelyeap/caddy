import Foundation

/// Everything Caddiy says when a kid clicks him, and after a change, each with the pose he says it in.
/// Keep lines short and plain. No em dashes and no semicolons (a test checks this).
enum CaddiyMoment: CaseIterable {
    case launch, home, process, processFailed, edit, afterChange
}

/// One thing Caddiy says. `then` follows a moment later, so a sad line can end on a hopeful one.
struct CaddiyLine: Equatable {
    let text: String
    let pose: CaddiyView.Pose
    var then: [CaddiyLine] = []

    init(_ text: String, _ pose: CaddiyView.Pose, then: CaddiyLine? = nil) {
        self.text = text
        self.pose = pose
        self.then = then.map { [$0] } ?? []
    }
}

enum CaddiyLines {
    static func lines(_ moment: CaddiyMoment) -> [CaddiyLine] {
        switch moment {
        case .launch:
            [CaddiyLine("Hi! I am waking up.", .hatching),
             CaddiyLine("Almost ready. Stretching my wings!", .sleepy),
             CaddiyLine("One moment, I am getting set up.", .thinking)]
        case .home:
            [CaddiyLine("Hi there! Let's make something.", .hello),
             CaddiyLine("Pick Start scanning to film a real thing.", .pointRight),
             CaddiyLine("No camera? Try the sample cup.", .idea),
             CaddiyLine("I love new ideas. What will you make?", .loveIt),
             CaddiyLine("Tap me any time for a tip!", .talking)]
        case .process:
            [CaddiyLine("I am building your model. Hang on!", .thinking),
             CaddiyLine("Turning your video into 3D. Beep boop.", .talking),
             CaddiyLine("Good things take a little time.", .sleepy),
             CaddiyLine("Nearly there. I am counting the corners.", .thinking)]
        case .processFailed:
            [CaddiyLine("Oops. That one did not work.", .sad, then: CaddiyLine("Let's try again. You can do it!", .cheer)),
             CaddiyLine("Hmm, too dark maybe?", .sad, then: CaddiyLine("Try brighter light and a plain table.", .idea)),
             CaddiyLine("You can always use the sample cup.", .idea)]
        case .edit:
            [CaddiyLine("Drag the model to spin it around.", .pointLeft),
             CaddiyLine("Try Taller to make it grow!", .pointRight),
             CaddiyLine("Type your own idea in the box.", .idea),
             CaddiyLine("Made a mistake? Undo takes it back.", .talking),
             CaddiyLine("When you like it, press Save STL.", .pointRight),
             CaddiyLine("Yawn. Pick a quick change to wake me up!", .sleepy)]
        case .afterChange:
            [CaddiyLine("Looking good!", .cheer), CaddiyLine("Nice change!", .cheer),
             CaddiyLine("Ooh, I like it!", .loveIt), CaddiyLine("Great job!", .loveIt)]
        }
    }

    /// Every line, follow ups included.
    static var all: [CaddiyLine] { CaddiyMoment.allCases.flatMap(lines).flatMap { [$0] + $0.then } }

    /// A random line for the moment, never the same as the last one.
    static func pick(_ moment: CaddiyMoment, after last: CaddiyLine?) -> CaddiyLine {
        let options = lines(moment).filter { $0 != last }
        return options.randomElement() ?? lines(moment)[0]
    }
}
