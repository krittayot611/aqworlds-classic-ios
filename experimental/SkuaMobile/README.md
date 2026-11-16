# Mobile script runtime

Experimental work for the Unstable channel. This directory does not change the
Stable app, release files, game renderer or bundle ID. It is not a working bot release.

## Implemented

- Read existing C# files and recursively resolve `//cs_include` and `//cs_ref`.
- Handle Windows separators, case-insensitive paths and duplicate/cyclic includes.
- Compile with explicit assembly metadata, preserving source filenames in errors.
- Select `ScriptMain` from the entry file rather than an included helper.
- Execute the compiled entry using a supplied bot interface.
- Adapt CoreBots' optional April Fools desktop prank in memory; imported files stay unchanged.

The compiler does not substitute fake gameplay methods. Windows process launching,
desktop developer tools and multi-client Army scripts are not implemented on mobile.
Compilation is not evidence that all referenced APIs work at runtime.

## Validation

Run `dotnet run --project Checks -c Release` with .NET 10. The checks exercise
compilation, entry invocation, include resolution, errors and source preservation.

To compile an imported script against an existing VibeSkua distribution:

```sh
dotnet run --project Checks -c Release -- /path/to/package /path/to/Assemblies Scripts/Farm/Leveling.cs
```

This command only compiles; it never executes the imported bot script or connects
to a game account. The package root contains the `Scripts` directory. The assembly
directory must contain the user's matching VibeSkua DLLs. Third-party DLLs and
uploaded scripts are not copied into this repository.

On 2026-11-12, the supplied Leveling, Legion Revenant and Verus DoomKnight scripts
compiled with zero errors against the supplied VibeSkua assemblies on Linux,
including respectively 4, 9 and 24 source files. This is a host compilation check.

## iOS execution gate

`iOS` is a developer-only runtime check, not a second public game download.
Copy .NET 10 reference DLLs from the SDK's
`packs/Microsoft.NETCore.App.Ref/<version>/ref/net10.0` directory to `iOS/Metadata`
before building. It compiles an imported C# file to IL and executes it with the
Mono interpreter enabled in Release. The result is written to
`Documents/runtime-result.txt`. A simulator pass still needs physical-device confirmation.

On 2026-11-16, [CI run 43765503067](https://github.com/krittayot611/aqworlds-classic-ios/actions/runs/43765503067)
passed the iOS 26.0 simulator execution check on ARM64 and Intel. Both runs
compiled the imported test file, loaded its IL, invoked `ScriptMain` and verified
the result was `42`. Physical-device validation remains pending.

The native static registrar, explicit Objective-C initializer and launch-selector
check ensure the app delegate can receive UIKit callbacks before the compiler
check starts. The CI matrix signs and verifies each simulator app before
installation. `run_ios_check.py` records launch output, execution stages and
system logs, and attempts to capture a screenshot and any available crash reports.
Artifacts are named `skua-runtime-check-macos-15` and
`skua-runtime-check-macos-15-intel`. A pass requires the app to return `PASS:`
after compiling, loading and invoking the script.

## Game command bridge

`Runtime/GameBridge.cs` provides a bounded worker-to-AIR command mailbox with
request correlation, session isolation, cancellation, timeouts and explicit
error propagation. Synchronous calls are rejected on the game thread.
`MobileFlashClient` exposes the basic Skua Flash method names and preserves
JSON-string results; it is not the complete VibeSkua bot interface.

`native/SkuaGameBridge.as` dispatches dotted game-property reads, indexed reads,
null checks and function calls against the loaded game object. Function calls
retain their owning object. `Main.as` exposes attach, dispatch and detach hooks,
and discards an old attachment when a game client is loaded. These hooks do not
change the viewport, touch handling or artwork, and no bridge is attached by
default.

The message envelope is versioned and contains a session, numeric request ID,
method and argument array. A response echoes the session and ID, with either a
JSON-string result or an error. The future native host must drain commands on
the AIR thread and deliver responses to the managed mailbox. It must detach and
release pending calls when the game or script session ends. The host must never
block the AIR thread while waiting for managed execution.

## Bridge validation

On 2026-11-16, [runtime run 43786250677, attempt 2](https://github.com/krittayot611/aqworlds-classic-ios/actions/runs/43786250677)
passed imported C# execution and the bridge mailbox checks on both ARM64 and
Intel iOS simulators. The first ARM64 attempt timed out during simulator boot
before launching the app; the retry passed. This gate does not execute AIR
commands or connect to a game server.

The managed checks cover out-of-order replies, duplicates, cancellation, late
responses, stale sessions, malformed replies, worker errors, UI-thread rejection
and disposal. The iOS target runs these same mailbox checks after its imported
C# execution check. This validates the managed protocol on iOS, not a connection
to AIR or a game server.

On 2026-11-16, [AIR bridge run 43785752587](https://github.com/krittayot611/aqworlds-classic-ios/actions/runs/43785752587)
passed all twelve dispatcher fixture checks. The first run exposed ActionScript
Error #1066 from invoking the `Function` constructor; dispatch now uses the
existing function through `as Function` and calls it with its owning object.

The separate `Experimental AIR bridge` workflow executes twelve dispatcher
checks against local fixture objects. It exercises JSON result encoding,
indexed reads, function ownership, invalid paths, errors, session correlation
and detachment. Run it locally on a supported AIR desktop host with:

```sh
python3 experimental/SkuaMobile/run_air_bridge_check.py --sdk /path/to/air-sdk
```

## Native hosting experiment

`NativeHost` tests a separate native Objective-C iOS app calling an exported
managed method from a Mono library. The native app owns `UIApplicationMain` and
runs the managed check on a worker. The experiment attempts the existing mailbox
checks followed by compilation and execution of an imported C# file.

The library target uses AOT to produce native exports and a custom runtime
initializer to enable interpretation of imported IL. The initial interpreter-only
library build failed to generate the export symbol files. This host is still
under validation; its presence is not evidence that runtime embedding works.
`Experimental native Mono host` is a development gate and produces no public
IPA. It does not yet connect to an AIR native extension or implement a command pump.

## Remaining integration

The managed runtime still needs to be embedded alongside AIR through a native
extension. A standalone .NET iOS test app does not supply that host. No native
command pump connects the two implementations yet. Full `IScriptInterface`
coverage, script import UI for iPhone and iPad, cooperative stop/pause and live
farming validation remain outstanding. Physical-device validation is also pending.
No bot-enabled IPA has been produced.

Upstream inspected: NinjaXz/VibeSkua commit
`b8ed1797498a791648b04abfd1a4284870ef875d`.
