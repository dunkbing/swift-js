import Foundation

// Main entry point
func main() {
    let cli = JSRuntimeCLI()

    if CommandLine.arguments.count > 1 {
        // Execute a JavaScript file
        cli.executeFile(path: CommandLine.arguments[1])
    } else {
        // Start REPL mode
        cli.startREPL()
    }
}

main()
