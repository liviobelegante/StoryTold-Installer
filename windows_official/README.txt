StoryTold Craft | Selective installer and source builder | Version 3.4

VERSION 3.4: CORRECT MSI CONTEXT DETECTION
The previous version incorrectly inferred installation scope from the uninstall registry
hive. An HKLM uninstall entry is not sufficient evidence of a per-machine MSI installation.
The script now uses Windows Installer ProductsEx and the Product.Context property:
1 or 2 = current user; 4 = all users. Only installed products (State 5) are included.
COM properties are read explicitly through reflection for PowerShell compatibility.
The MSI inventory is cached per operation and refreshed after each installation.
Registry entries remain useful for locating executables, but do not determine MSI scope.
Reference: https://learn.microsoft.com/en-us/windows/win32/msi/product-object

The supplied November 2 logs show successful per-user installations of WordCraft 0.14.0,
GridCraft 0.15.0 and DeckCraft 0.14.1, all with MSI exit/status 0, MSIINSTALLPERUSER=1
and installation folders under the user's AppData\Local\Programs\ArtCraft.
Windows Installer also reported WordCraft Context=2 during read-only diagnosis.
The displayed Scope verification failed message was caused by our previous verification,
not a failed installation in those three logs. Those installations do not need reinstalling
because of that message. Finish any active operation before replacing the script files.
No installation or additional test suite was run for this correction.

INSTALLATION SCOPE (VERSION 3.3)
The Install for all users checkbox applies to every checked application:
- Unchecked (default, recommended for one Windows account): current-user installation.
- Checked: installation for all Windows accounts, requiring administrator approval.
The selected scope is saved in request.json and recorded in the operation log.
Changing the checkbox refreshes detected versions and paths for the selected scope.
No additional tests or application installations were run for version 3.3, as requested.

For the five signed MSI applications, the official release sources declare dual-scope
support. The script also checks the downloaded MSI ALLUSERS property before installation.
Current-user MSI arguments: ALLUSERS=2 MSIINSTALLPERUSER=1.
All-users MSI arguments: ALLUSERS=1 MSIINSTALLPERUSER="".
The official MSI chooses its directory, registers the chosen context and handles UAC.
After MSI success, the script checks Windows Installer's actual context for the selected scope.
If that scope cannot be confirmed, the row reports Scope verification failed.

IMPORTANT FOR EXISTING MSI INSTALLATIONS
The official packages refuse an installation in another scope while the old copy exists.
The GUI reports Scope change required. Uninstall that application in Windows Settings > Apps,
then run the installer again with the desired checkbox setting. No automatic uninstall,
settings migration or deletion of the existing installation is performed.
Legacy source builds are separate from MSI installations and are not removed automatically.
Reference: https://github.com/storytold/wordcraft/blob/v0.14.0/packaging/windows/INSTALLATION.md
The corresponding policies were also consulted for GridCraft v0.15.0, DeckCraft v0.14.1,
PDFCraft v0.17.0 and CADCraft v0.16.0.

SolidCraft current-user destination:
%LOCALAPPDATA%\Programs\StoryToldCraft\SolidCraft\solidcraft.exe
SolidCraft all-users destination (the original location):
C:\Program Files (x86)\StoryTold\solid-main\target\release\solidcraft.exe
SolidCraft uses a separate build/installation for the requested scope; a different-scope
copy is not deleted. An existing same-scope current version is skipped as before.

Desktop shortcuts follow the choice: personal desktop for current-user mode; the Windows
Public desktop for all-users mode. Shared shortcut creation may request an additional UAC
prompt. An existing correct shared shortcut is reused.
All previous standby prevention, temporary cleanup, logging and backup behavior remains.

VERSION 3.2
Automatic standby prevention now keeps both the system and display awake during the
entire operation: downloads, compilation, prerequisite setup, UAC, installation and
temporary cleanup. The request is released on completion or error, restoring normal
Windows behavior without permanently changing the power plan. If Windows refuses the
request, the operation stops before installation. Explicit manual sleep, shutdown,
critical battery actions and enforced administrator policies are not overridden.

When an update needs an application closed, the installer requests normal window closure
and waits up to 30 seconds. Respond to any unsaved-document dialog in the application.
If it remains open, that update stops without forced termination. SolidCraft is checked
again after compilation in case it was reopened during the build.
The final status explicitly reports whether a Windows restart is required.

The previously discussed functions remain: selective installation, local/latest version
checks, source commit verification, compilation only when needed, missing build-tool
setup, signed MSI verification for the five StoryTold applications, UAC for protected
installation paths, desktop shortcuts, SolidCraft backup/rollback, persistent logs,
per-user operation locking, D:\Temp with C:\Temp fallback and owned temporary cleanup.
SolidCraft remains rooted at C:\Program Files (x86)\StoryTold\solid-main, with its
executable at target\release\solidcraft.exe. The GUI and documentation remain in English.
No additional tests or compilations were run for version 3.2, as requested.
The complete original v15 BAT is not included in the available source material, so this
feature list follows the requirements recorded in this chat rather than a full v15 diff.

QUICK START
1. Extract all five files into the same folder.
2. Double-click Install-StoryTold-Signed.bat.
3. Check the applications you want.
4. Click Check versions to compare installed and available versions without installing.
5. Click Install / update selected.

Save your documents and close the selected applications before installing.
No console selection or typed confirmation is required.
Windows may request UAC approval for MSI installers, build tools or publishing SolidCraft.
The GUI and this documentation are in English.

WHERE APPLICATIONS ARE INSTALLED
In all-users mode, SolidCraft uses the original installer location:
C:\Program Files (x86)\StoryTold\solid-main\target\release\solidcraft.exe
On systems without Program Files (x86), Program Files is used instead.
Compiling does not require administrator privileges. The completed executable is copied
into Program Files by a separate helper after a Windows UAC prompt, if needed.
The shortcut is created for the original desktop user after that helper completes.

WordCraft, GridCraft, DeckCraft, PDFCraft and CADCraft use their official MSI installation
locations. The packages control their own installation and upgrade rules.
On this computer, the official installations were found under:
C:\Users\beleg\AppData\Local\Programs\ArtCraft\<Application>\<application>.exe
They are not moved into the old StoryTold source-build folders.
In current-user mode, SolidCraft uses this destination:
%LOCALAPPDATA%\Programs\StoryToldCraft\SolidCraft
No executable was found in that per-user SolidCraft folder during this verification.
Older copies in that folder remain discoverable. Existing separate installations are not
silently deleted or migrated during a version check.

To see an application's actual location, hover its row or scroll right to Installed path.
Select its row and click Open app folder to open its installation directory.
The detector now includes the original <application>-main\target\release layout,
with solid-main\target\release for SolidCraft. This fixes the previous missing detection.

TEMPORARY FILES AND AUTOMATIC CLEANUP
The installer creates its own uniquely named work folder under:
D:\Temp\StoryToldCraft\<operation-id>
If D: is absent or that location cannot be used, it tries:
C:\Temp\StoryToldCraft\<operation-id>
The chosen folder is shown in the log.

Downloaded MSI packages, checksum files, Git source files, Cargo dependency downloads,
compiled objects and temporary process files are stored inside this work folder.
Cargo's CARGO_HOME and child-process TEMP/TMP point inside it for the operation.
The folder is removed after processing the selected applications, on success or failure.
Cleanup happens after all installer processes finish and file handles have been closed.
It retries temporary cleanup failures and reports a warning if files could not be removed.

Only the operation's own folder is deleted. The D:\Temp / C:\Temp root, unrelated files,
installed applications and rollback backups are preserved.
An operation ID, ownership marker, resolved path checks and reparse-point checks protect
against deleting another directory or following a junction outside the work folder.
Do not place your own files or directory links inside the installer's work folder.
If Windows or the worker is forcibly terminated, final cleanup may not run.

Source and dependency build caches are no longer retained between operations.
A current installed version is still skipped, so it does not trigger compilation.
A future source update may need a full build and dependency download again.
Installed Git/Rust/C++ tools and Windows Installer's system-managed caches are not removed;
they are installed prerequisites or Windows-managed data, not this installer's work folder.

LOGS AND BACKUPS ARE RETAINED
Operation logs are kept separately at:
%LOCALAPPDATA%\StoryToldSignedInstaller\logs\<date-time-operation-id>
Open logs opens this persistent folder after temporary cleanup.

request.json: selected applications and operation settings.
events.jsonl: versions, paths, verification, progress, cleanup and results.
<application>-msi.log: Windows Installer diagnostics.
<command>-output.log and <command>-error.log: Git, Cargo and prerequisite diagnostics.
worker-output.log and worker-error.log: background worker diagnostics.
publication-*.json: the result of copying SolidCraft into Program Files.
Normal Cargo compilation progress appears mainly in cargo-build-error.log.

Before replacing a managed SolidCraft release folder, it is renamed to a timestamped
SolidCraft-backup-* sibling under its target directory. The staging folder then takes
its place. If this directory swap fails, the backup is restored.
Backups remain available for recovery and their paths are logged. They are not temporary
downloads and are not deleted by the automatic cleanup.
A failed download or build does not replace the installed executable.
There is no automatic rollback after a later runtime crash or across multiple applications.

VERSION CHECKS AND BUILD MODES
All applications use the latest stable release at the time the operation runs.
Newer installed versions are preserved, avoiding automatic downgrades.
The detector reads actual executable versions without launching the applications.
It checks registry entries, standard installation folders, old StoryTold source-build
folders, the preceding managed folder and desktop shortcuts.
Unregistered copies outside those locations without a matching shortcut may not be found.
Unknown versions are shown as unknown rather than assumed to be current.

The five official StoryTold applications use signed MSI releases from:
https://github.com/storytold/wordcraft/releases/latest
https://github.com/storytold/gridcraft/releases/latest
https://github.com/storytold/deckcraft/releases/latest
https://github.com/storytold/pdfcraft/releases/latest
https://github.com/storytold/cadcraft/releases/latest
A downloaded MSI must match SHA256SUMS.txt and have a Valid Windows Authenticode signature
with the Learning Machines Inc certificate organization. Invalid packages are blocked.

SolidCraft uses https://github.com/tangency-labs/solidcraft/releases/latest.
The stable tag is resolved to an exact 40-character Git commit, fetched and verified.
The desktop package is built with stable Rust, --locked, --release and an explicit
Windows MSVC target and target directory. The executable version must match the release.
The build receipt records release, commit, architecture and executable SHA-256.
An unchanged managed installation is skipped after version, commit and checksum checks.
An unmanaged same/newer installation is accepted by version; its original source commit
cannot be inferred from its executable.
Locally compiled SolidCraft is UNSIGNED. It is not presented as a digitally signed build.

BUILD TOOLS
Set up missing build tools enables prerequisite setup only when a source build is needed.
It may download several GB, require UAC approval and request a Windows restart.
The installer uses winget package IDs Git.Git, Rustlang.Rustup and
Microsoft.VisualStudio.2022.BuildTools, with C++ tools and a Windows SDK.
Rust stable is updated only if missing or older than Cargo.toml requires.
The required Windows MSVC Rust target is added through rustup.
If winget is unavailable or setup is disabled, missing tools produce a clear error.
Existing ARM64 C++ installations need the ARM64 MSVC component.
Check versions does not install tools, applications or shortcuts.

DESKTOP SHORTCUTS AND GUI
Shortcuts are created or updated after successful installation and for selected current
applications. Current-user mode uses the actual user desktop, including redirected desktops;
all-users mode uses the Windows Public desktop and requests UAC if needed.
The executable supplies the icon and its folder supplies the working directory.
A shortcut failure is reported separately from installation success.
Only checked applications are processed. Select all / Select none change the selection.
The background worker keeps the GUI responsive, prevents overlapping operations for the
same user and requests sleep prevention. Normal closing is blocked until it finishes.

VERIFICATION SNAPSHOT, NOVEMBER 2, 2026
SolidCraft 0.28.0 was found at:
C:\Program Files (x86)\StoryTold\solid-main\target\release\solidcraft.exe
The previous detector missed this legacy layout; version 3.1 detects it.
Latest stable SolidCraft checked earlier in this session: v0.30.0.
Release commit: afd81380ab06b0e77e03fdf68185d4b484d0e84e.
The five official installed versions detected earlier were:
WordCraft 0.14.0, GridCraft 0.15.0, DeckCraft 0.14.1, PDFCraft 0.17.0, CADCraft 0.16.0.
These observations are not hardcoded; the installer checks again on each operation.

A real Windows x64 build of SolidCraft v0.30.0 succeeded during previous verification.
Initial build: 11 minutes 40 seconds. Executable ProductVersion/FileVersion: 0.30.0.
Executable size: 171396608 bytes. Authenticode: NotSigned.
SHA-256: DC6416CA0231FDAA865E254BBE703AB646B3434193146C7D1F374F4B0A2E9238.
The executable was not launched or installed during that verification.
The ZIP contains scripts, not that test binary. x86/ARM64 builds were not exercised.

Version 3.1 checks covered preferred/fallback work roots, actual recursive cleanup of
owned test folders, preservation of unrelated files/logs, rejection of root/wrong-ID
cleanup and junction traversal, and worker cleanup after success and injected failure.
The exact encoded publication helper ran without elevation against a workspace folder
simulating Program Files; its syntax, copied payload and checksum verification passed.
An actual UAC prompt and replacement of the real Program Files installation were not tested.
Earlier checks cover selection, GUI rendering, shortcuts, version comparisons, MSI
verification/exit codes, staged backup and real rollback using test fixtures.

CODE LOCATIONS
Version 3.4 inserts Get-ComInstallProperty and Get-MsiRegistrations before
Get-LocalApplication in SolidCraft-Source.ps1. Get-RegisteredMsiScopes now consumes this
inventory instead of inferring scope from HKLM/HKCU. Get-LocalApplication uses the same
real context for matched MSI entries. Install-OfficialApp and Invoke-InstallWorker reset
the MSI inventory alongside the registry snapshot after installation.
Version 3.3 adds New-ApplicationShortcut and Assert-MsiScopeSupport before
Close-RunningApplication. Install-OfficialApp now compares same-scope installations,
blocks cross-scope MSI copies, adds explicit scope properties and confirms registration.
Get-PathInstallScope precedes Get-LocalApplication, which now accepts a scope filter;
Get-RegisteredMsiScopes follows it. Check-AppVersion and Install-SolidCraftSource use the
requested scope. Refresh-InstallScope precedes Show-Installer; the scope checkbox appears
above the application table. Start-Installation saves Scope in request.json, and the worker
validates and applies it. Install-SolidCraftSource selects its destination before publication.
In version 3.2, Close-RunningApplication is inserted after New-DesktopShortcut and before
Install-OfficialApp. It replaces the running-process rejection immediately before MSI
launch and is called before SolidCraft compilation and before publication. In
Invoke-InstallWorker, the standby request follows the native API declaration and its
release remains in finally after temporary cleanup. Update-Progress adds restart status.
No manual code insertion is required. Extract all five files from this ZIP.
Installer-Storage.ps1 is loaded after the HTTP headers and before SolidCraft-Source.ps1.
In Install-OfficialApp, downloads now go into WorkFolder\downloads rather than RunFolder.
Start-Installation creates the work folder before writing request.json; RunFolder holds logs.
Invoke-InstallWorker sets temporary environment paths, then removes only its owned work
folder in finally before reporting completion and releasing the operation mutex.
Get-LocalApplication adds the legacy target\release paths before registry discovery.
Install-SolidCraftSource builds under WorkFolder\source and publishes into the old
StoryTold release folder through Invoke-SourcePublication, instead of the per-user folder.
Invoke-SourcePublication sits after Publish-SourceBuild and before Install-SolidCraftSource.
Show-Installer and Update-Progress display the installed path and cleanup warnings.
Every named function has the requested opening and closing comment markers.
