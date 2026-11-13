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

The CI check signs the ARM64 simulator app and verifies its signature before
installation. `run_ios_check.py` selects a simulator compatible with the active
Xcode SDK and archives console output, execution stages, a screen capture and
available crash reports in the `skua-runtime-check` artifact. Reaching managed
startup or completing the build does not count as a script-execution pass; the
app must return a `PASS:` result after compiling, loading and invoking the script.

Before integrating the bot, this check must pass on iOS, then the managed runtime
must be hosted alongside AIR with a working AS3/native bridge. The existing
Windows ActiveX and ExternalInterface transport cannot be reused as-is.
Touch UI, game API integration, cooperative stop/pause and real farming validation
remain outstanding. No bot-enabled IPA has been produced.

Upstream inspected: NinjaXz/VibeSkua commit
`b8ed1797498a791648b04abfd1a4284870ef875d`.
