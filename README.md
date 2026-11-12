# ServerHost iOS

A SwiftUI Minecraft server installer and multi-server profile manager for iPhone and iPad.

## Implemented

- Java and Bedrock software catalog with searchable version lists
- Compact, scrollable version selector (three-row viewport)
- Multiple saved server profiles
- Automatic Java requirement detection for Java 8, 17, 21 and 25
- Device-aware RAM limit based on physical device memory, reserving at least 1.5 GB or 37.5% for iPadOS and other apps
- Editable maximum-player setting from 1 to 1,000,000
- Real server-file downloads for Mojang Vanilla, Paper, PocketMine-MP and official Linux Bedrock Dedicated Server
- Bedrock Dedicated Server includes selectable stable historical releases and downloads the selected Linux ZIP
- Java 8, 17, 21 and 25 iOS ARM64 runtime archives are fetched from the same runtime distribution used by Amethyst during CI builds
- Java Vanilla and Paper server JARs launch through a native JLI bridge with a live console and stop command
- Java server properties are updated from the RAM, Online Mode, player and port settings
- Live download progress with percentage and downloaded/total MB
- App icon asset catalog ready for your custom 1024×1024 PNG
- Bedrock plugin server release discovery from GitHub Releases where available
- Downloaded files stored in the app's Documents directory
- GitHub Actions unsigned IPA build

## Platform limitations

The Java launcher uses the iOS ARM64 OpenJDK runtimes distributed for Amethyst and calls the runtime's JLI entry point. JIT must be available through the app's sideloading setup for practical server performance. Java server execution on iPadOS is experimental and depends on runtime signing, JIT availability and the server JAR's native dependencies.

The official Bedrock Dedicated Server is a Linux executable. ServerHost can download and extract selected historical Linux releases, but cannot execute that Linux binary on iPadOS. Use a compatible Linux host to run those files.

Minecraft requires the EULA to be reviewed and accepted before starting a Java server. ServerHost creates eula.txt with eula=false; a parent or guardian should review the terms before the value is changed. RAM, Online Mode, max players and port are written to server.properties when the Java server starts.

Purpur, Fabric, Forge, NeoForge, Quilt, Nukkit and PowerNukkitX are catalog entries without installer handlers. Java server launch currently supports downloaded Vanilla and Paper JARs.

## Build

Install XcodeGen, run `xcodegen generate`, then build the ServerHost scheme with Xcode. GitHub Actions builds an unsigned IPA artifact. Installing it requires signing or a compatible sideloading workflow.
