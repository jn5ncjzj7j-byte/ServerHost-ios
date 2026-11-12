# ServerHost iOS

A SwiftUI Minecraft server installer and multi-server profile manager for iPhone and iPad.

## Implemented

- Java and Bedrock software catalog with searchable version lists
- Compact, scrollable version selector (three-row viewport)
- Multiple saved server profiles
- Automatic Java requirement detection for Java 8, 17, 21 and 25
- Real server-file downloads for Mojang Vanilla, Paper and PocketMine-MP
- Bedrock plugin server release discovery from GitHub Releases where available
- Downloaded files stored in the app's Documents directory
- GitHub Actions unsigned IPA build

## Platform limitations

This iOS app does not yet execute Java or Bedrock server processes. Standard desktop/Linux Java distributions are not iOS-compatible runtimes, and official Bedrock Dedicated Server binaries target supported desktop/server operating systems. Java requirement detection is implemented, but installing a desktop/server JVM into iOS is not. Starting servers and dependable background hosting need a compatible runtime host, typically a Linux machine or VPS.

The official Bedrock Dedicated Server download source exposes the current stable build, not a complete public archive of every historical release. Third-party Bedrock server projects expose release tags where available.

Only Vanilla Java, Paper and PocketMine-MP currently have working file-download handlers. Other listed software types remain catalog entries and will show an unsupported-installer error rather than a fake success.

## Build

Install XcodeGen, run `xcodegen generate`, then build the ServerHost scheme with Xcode. GitHub Actions builds an unsigned IPA artifact. Installing it requires signing or a compatible sideloading workflow.
