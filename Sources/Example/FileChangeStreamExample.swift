
import Foundation
import FileChangeStream

@main
public struct FileChangeStreamExample {

    public static func main() async throws {
        let arguments = CommandLine.arguments
        if arguments.count < 2 {
            print("Provide one or more files or folders to watch for changes.")
            print("\(arguments.first!) <first file or folder> [<subsequent files or folders>...]")
            exit(1)
        }
        _ = arguments.dropFirst()
        let items = arguments.map { URL(filePath: $0) }
        let stream = try FileChangeStream(items)
        for try await event in stream {
            print(event)
        }
    }
}
