StoryTold Craft Installer 3.6.1
17 November 2026

INSTALL
1) Extract the entire ZIP.
2) Open Install-StoryTold.bat.
3) SolidCraft is selected by default. Select other apps if wanted.
4) Click Install / update selected.
5) Wait for Finished and check the Status column. Use the desktop shortcut to open the app.

Save your work and close selected apps before installing.
Accept Windows administrator approval if requested.
Keep all files together. Do not run files from inside the ZIP.

WHAT CHANGED
SolidCraft now uses the official Windows MSI from tangency-labs/solidcraft.
It is downloaded ready to install. Rust, Git and Visual Studio Build Tools are no longer installed.
The other five apps continue to use their official signed MSI packages.
All interface text is in English.

UPDATES
Run this installer again to check for and install new stable releases.
Check versions only checks: it does not install an application.
The script does not enable or promise updates inside SolidCraft.
Same or newer installed MSI versions are skipped.
A detected loose/local SolidCraft build can be migrated to the official MSI.
The MSI controls its installation folder and Windows Apps registration.
The desktop shortcut points to the MSI-installed application.

INSTALLATION SCOPE
Installed only for your account: automatically update that copy.
Installed only for all users: automatically update that copy.
Installed in both scopes: the checkbox selects which copy to update.
New application: the checkbox selects where to install it.
Unchecked Install for all users means your account; checked means all users.
The rule is applied separately to each selected application, including version checks.
Scroll right to see Target scope. The log also shows the scope used for each app.
Windows may request administrator approval for an all-users installation.

DOWNLOAD VERIFICATION
Only assets from the expected official GitHub release are accepted.
Each MSI must match its entry in the release SHA256SUMS.txt.
WordCraft, GridCraft, DeckCraft, PDFCraft and CADCraft require a valid
Learning Machines Inc digital signature.
SolidCraft may be unsigned, as documented by its publisher.
An invalid or damaged signature is rejected. SHA-256 remains mandatory.
A checksum confirms the download matches the published package; it is not a publisher signature.

REQUIREMENTS AND ERRORS
Internet, Windows 10 version 1809 or later, Windows PowerShell 5.1,
and .NET Framework 4.8 or later. The launcher checks these and can
install Microsoft's signed Framework package if needed.
Windows updates and graphics drivers remain managed by Windows.
If an app fails, read its Status and the error in the window, then Open logs.
Logs: %LOCALAPPDATA%\StoryToldSignedInstaller\logs
Temporary downloads are removed after processing. No forced restart.
If Windows requests a restart, restart and run the installer again.

OFFICIAL SOLIDCRAFT DOWNLOADS
https://github.com/tangency-labs/solidcraft/releases/latest

