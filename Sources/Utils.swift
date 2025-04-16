import NIO
import Foundation

class TaskBox: NSObject {
    let task: RepeatedTask

    init(task: RepeatedTask) {
        self.task = task
        super.init()
    }
}
