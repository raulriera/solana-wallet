# Swift packages

Package layout and API signatures remain undecided.

- Each source target builds a module; one package can contain multiple modules.
- Targets can reuse settings defined once in `Package.swift`.
- Separate packages do not inherit app or dependency build settings.
- Tools version, Swift language mode, and deployment target are separate settings.

Sources: [Package structure](https://developer.apple.com/documentation/xcode/creating-a-standalone-swift-package-with-xcode.md), [target settings](https://developer.apple.com/documentation/packagedescription/target/swiftsettings.md), [feature scope](https://developer.apple.com/documentation/packagedescription/swiftsetting/enableupcomingfeature(_:_:).md).
