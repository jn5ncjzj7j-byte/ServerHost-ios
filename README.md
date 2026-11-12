# ServerHost iOS

A SwiftUI Minecraft server installer and multi-server profile manager for iPhone and iPad.

## Implemented

- Java and Bedrock software catalog with searchable version lists
- Compact, scrollable version selector (three-row viewport)
- Multiple saved server profiles
- Automatic Java requirement detection for Java 8, 17, 21 and 25
- Real server-file downloads for Mojang Vanilla, Paper, PocketMine-MP and official Linux Bedrock Dedicated Server
- Bedrock Dedicated Server downloads use Mojang's published download-link metadata and extract the Linux ZIP
- Live download progress with percentage and downloaded/total MB
- App icon asset catalog ready for your custom 1024×1024 PNG
- Bedrock plugin server release discovery from GitHub Releases where available
- Downloaded files stored in the app's Documents directory
- GitHub Actions unsigned IPA build

## Platform limitations

This iOS app does not yet execute Java or Bedrock server processes. Standard desktop/Linux Java distributions are not iOS-compatible runtimes, and official Bedrock Dedicated Server binaries target supported desktop/server operating systems. Java requirement detection is implemented, but installing a desktop/server JVM into iOS is not. Starting servers and dependable background hosting need a compatible runtime host, typically a Linux machine or VPS.

The official Bedrock Dedicated Server download source exposes the current stable build, not a complete public archive of every historical release. Third-party Bedrock server projects expose release tags where available.

Vanilla Java, Paper, PocketMine-MP and the official Linux Bedrock Dedicated Server have file-download handlers. Other listed software types remain catalog entries and will show an unsupported-installer error rather than a fake success.

The Bedrock download is the Linux server package for transfer to a supported Linux host. It is not executable on iOS. Java runtime status is informational only. RAM, Online Mode and max-player preferences are not applied to a running server yet.

## Build

Install XcodeGen, run `xcodegen generate`, then build the ServerHost scheme with Xcode. GitHub Actions builds an unsigned IPA artifact. Installing it requires signing or a compatible sideloading workflow.
