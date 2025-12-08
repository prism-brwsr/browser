<div align="center">
  <img width="250" height="250" src="/assets/icon.png" alt="Prism Browser Logo">
  <h1><b>Prism Browser</b></h1>
  <p><i>Prism is an open-source fork of the <a href="https://github.com/the-ora/browser">Ora Browser</a>.</i></p>
  <p>
    Prism is a fast, secure, and beautiful browser built for macOS. Prism delivers a clean, native experience that feels at home on macOS — without unnecessary bloat.
    <br>
  </p>
</div>

<p align="center">
    <a href="https://www.apple.com/macos/"><img src="https://badgen.net/badge/macOS/14+/blue" alt="macOS"></a>
    <a href="https://developer.apple.com/xcode/"><img src="https://badgen.net/badge/Xcode/15+/blue" alt="Xcode"></a>
    <a href="https://swift.org"><img src="https://badgen.net/badge/Swift/5.9/orange" alt="Swift Version"></a>
    <a href="LICENSE.md"><img src="https://badgen.net/badge/License/GPL-2.0/green" alt="License: MIT"></a>
</p>

> **⚠️ Disclaimer**  
Prism is currently in early stages of development and **not yet ready for day-to-day use**. Some features are not available on all macOS versions yet.

## Features

### Core Capabilities

- Native macOS UI built with SwiftUI/AppKit
- Fast, responsive browsing powered by WebKit
- Privacy-first browsing with built-in content blocker for tracking prevention and ad blocking
- Multiple search engine support
- URL auto-completion and search suggestions
- Quick Launcher for instant navigation and search
- Developer mode 

## Installation

1. Clone the repository and run setup:
   ```bash
   git clone https://github.com/prism-brwsr/browser.git
   cd prism
   ./scripts/setup.sh
   ```

2. Open and build:
   ```bash
   open Prism.xcodeproj
   ```

## Contributing

Contributions are welcome! We are working on a contribution template and haven't published one yet! If you have any questions or ideas, feel free to show them off here.

### Regenerating the Xcode project

- Update `project.yml` as needed, then:
  ```bash
  xcodegen
  ```

### Running tests

- In Xcode: Product → Test (⌘U)
- Via CLI:
  ```bash
  xcodebuild test -scheme ora -destination "platform=macOS"
  ```


## Contact

Questions or support? Please open an issue or discussion in this repository.  
For help and support with setting up the development environment, contact us at **yourfriends@flareapps.eu**.

## License

Prism is open source and licensed under the [GPL-2.0 license](LICENSE).  
Feel free to use, modify, and distribute it under the terms of the GPL-2.0 license.
