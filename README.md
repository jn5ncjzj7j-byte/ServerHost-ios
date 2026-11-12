# ServerHost iOS

A SwiftUI Minecraft server manager for iPhone and iPad.

## Current build

- Java and Bedrock software catalog
- Software-first installer flow
- Searchable version lists
- Live version discovery for Mojang Vanilla, Paper, Purpur and Fabric
- Server dashboard and configurable RAM, online mode, player limit and port
- iPhone and iPad layouts
- GitHub Actions workflow that builds an unsigned iOS IPA artifact

## Runtime limitation

This is an early manager UI, not yet a functioning host. Start and Stop are intentionally disabled. Arbitrary Java server software needs a compatible JVM runtime. Official Bedrock Dedicated Server binaries target supported desktop/server operating systems rather than iOS. iOS also does not guarantee indefinite background execution.

The next engineering milestone is a tested runtime strategy for specific server software, followed by real download/install, process management, console, persistence and background behavior. Remote Linux hosting can provide reliable 24/7 operation.

## Build

Install XcodeGen, run xcodegen generate, then build the ServerHost scheme with Xcode. GitHub Actions builds an unsigned IPA artifact. Installing it on a device requires signing or a compatible sideloading workflow.
