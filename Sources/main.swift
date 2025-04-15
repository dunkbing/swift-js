import Foundation

func main() {
    let cli = CLI()

    if CommandLine.arguments.count > 1 {
        cli.executeFile(path: CommandLine.arguments[1])
    } else {
        cli.startREPL()
    }
}

main()
