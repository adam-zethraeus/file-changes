# file-changes

`FileChangeStream` is an AsyncSequence which emits when there is a change to a file or folder within one of the specified directories.

![](https://github.com/user-attachments/assets/a66899f7-ba8e-4737-ac61-d0cc981005d1)

## Usage
```swift

let fileAndFolderPaths = getPaths()
let items = fileAndFolderPaths.map { URL(filePath: $0) }

let stream = try FileChangeStream(items)
for try await event in stream {
  print(event)
}
```

## Credits 
This package is based on [FileWatcher](https://github.com/eonist/FileWatcher/tree/master)
