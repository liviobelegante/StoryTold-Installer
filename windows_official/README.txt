StoryTold Craft installer 3.5 - 7 November 2026

QUICK START
Extract the entire windows_official folder. Keep all eight files together.
Double-click Install-StoryTold-Signed.bat. Select applications and installation scope,
then choose Check versions or Install / update selected.
Replace the complete folder when upgrading from 3.4, not just the BAT file.
Save documents before installation; application closure is graceful, never forced.

HOST REQUIREMENTS
Windows 10 build 17763 or later, working Windows PowerShell 5.1, and .NET Framework
4.8 or later are the supported launcher baseline in this version.
The BAT verifies that PowerShell starts. The startup helper checks the Framework
Release value in both registry views. On x86/x64, an older Framework is upgraded
with Microsoft's signed 4.8 offline installer. No automatic reboot is requested.
If a reboot is needed, restart Windows and run the BAT again.
ARM64 Framework repair uses Windows Update. If Windows PowerShell cannot start
because Windows components are missing/damaged, the BAT gives a visible repair
message. A PowerShell script cannot repair its own entirely absent runtime before
that runtime can start. Modern .NET Runtime/SDK and Framework 3.5 are not installed.

APPLICATION DEPENDENCIES
WordCraft, GridCraft, DeckCraft, PDFCraft and CADCraft use official signed MSI
packages. Current upstream packaging embeds the C/C++ runtime with +crt-static.
They do not require a separate .NET Runtime. WiX/.NET used to produce those MSI
packages is a publisher build dependency, not needed to install the finished MSI.
Windows system libraries and graphics drivers remain Windows-managed components.

SolidCraft is compiled locally from its latest stable release and exact Git commit.
It is unsigned. Our inherited Cargo compilation uses the dynamic MSVC CRT.
The installer checks the matching x86/x64/ARM64 Visual C++ v14 redistributable before
publication, including for an already-current detected installation. It downloads
Microsoft's signed current package to determine the required version, installs
only if the registered version is older/missing, and verifies registration again.
An already-current application is not rebuilt merely to check its runtime.

When a source build is required, the default-enabled build-tool option checks:
- Working Git and Rustup; missing/unusable tools are installed through WinGet.
- Working WinGet when Git/Rust setup needs it; Microsoft's documented PowerShell
  bootstrap is used if unavailable (NuGet provider and Microsoft.WinGet.Client).
- C++ compiler, linker, headers/libraries and a complete architecture-matching SDK.
- Rust stable meeting Cargo.toml's full minimum version, including its patch level.
- Required MSVC Rust target, installed only when missing.
Incomplete VS 2022 Build Tools installations are modified to add missing components;
otherwise the signed Microsoft Build Tools bootstrapper is used. SDK 10.0.26100
is requested when the existing SDK/compiler setup is incomplete.
Tools are verified after setup. A dependency failure blocks the affected build.
Disabling build-tool setup prevents automatic Git/Rust/C++/SDK setup; runtime checks
remain automatic. Internet is required. Policy restrictions/UAC refusal can prevent
setup. Package-manager checksum checks are never bypassed.

SCOPE AND EXISTING INSTALLATIONS
Unchecked scope: current user. Checked: all users, with administrator approval.
Choose the scope matching the copy you want to update. Detection is scope-specific.
Version-named SolidCraft folders and personal/public desktop links are searched.
A CLI-only folder is not considered an installed SolidCraft desktop app.
Same/newer existing versions are skipped; managed builds also verify receipt/hash
and commit. Older installations outside the managed destination are preserved.
The new source build uses the managed destination and updates the desktop shortcut;
the log explains when an older copy remains in another location. Arbitrary folders
discovered through shortcuts are not replaced.

Managed SolidCraft current-user destination:
%LOCALAPPDATA%\Programs\StoryToldCraft\SolidCraft\solidcraft.exe
Managed all-users destination (Program Files fallback on 32-bit Windows):
C:\Program Files (x86)\StoryTold\solid-main\target\release\solidcraft.exe
Official MSI packages choose their own folders and retain the existing scope rules.
Changing an installed MSI's scope requires uninstalling that copy first, as before.

TEMPORARY FILES, LOGS AND BACKUPS
Work roots: D:\Temp, then C:\Temp, then %LOCALAPPDATA%\Temp.
Only an operation's uniquely named, ownership-marked folder is removed.
Missing drives no longer break validation/cleanup. Reparse-point and exact-path
checks remain enabled. Git trusts only the checked source folder per command;
no global safe.directory exception or wildcard is installed.
Persistent Git/Rust tools are not installed in disposable Cargo dependency storage.
App download/source/build files are removed after processing. Available VS setup
logs are copied out before temporary cleanup.
Logs: %LOCALAPPDATA%\StoryToldSignedInstaller\logs
Startup logs: startup-<date-time>-<id> under the same logs folder.
Managed SolidCraft updates keep a timestamped previous release and roll back the
directory swap on publication failure. Unrelated applications/data are preserved.

PROGRESS AND RESTARTS
The circle animates on its own UI timer while the worker runs, including cleanup.
It stops when work ends or the worker exits with an error. It indicates activity,
not a fabricated percentage or guaranteed network progress.
Progress reads newly appended complete UTF-8 events instead of rereading all logs.
Dependency restart requests remain visible in the final status. No forced reboot.
Automatic sleep/display-timeout prevention and operation locking are retained.

VALIDATION
43 checks passed under Windows PowerShell 5.1 on x64: absent-drive fallback, owned
cleanup, real local Git ownership regression, version/scope detection, current
SolidCraft skip, missing Rust stable, mocked dependency setup, signature rejection,
restart tracking, UTF-8 partial events, publication rollback and spinner start/stop.
The real form was rendered and inspected with fixture data.
No real prerequisite install, MSI upgrade, UAC elevation or SolidCraft compilation
was performed for 3.5. ARM64/x86 install/reboot paths remain untested on hardware.
Test-Installer.ps1 and official sources/change locations are in the package.
docs/README-3.4-HISTORY.txt is historical, not current requirements.