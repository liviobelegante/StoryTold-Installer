# StoryTold Craft Installer

A Windows graphical installer for building and installing six open-source Craft applications from their upstream source repositories.

## Supported applications

| Application | Desktop shortcut | Source repository |
| --- | --- | --- |
| WordCraft | Word (WordCraft) | [storytold/wordcraft](https://github.com/storytold/wordcraft) |
| GridCraft | Excel (GridCraft) | [storytold/gridcraft](https://github.com/storytold/gridcraft) |
| DeckCraft | PowerPoint (DeckCraft) | [storytold/deckcraft](https://github.com/storytold/deckcraft) |
| PDFCraft | PDF (PDFCraft) | [storytold/pdfcraft](https://github.com/storytold/pdfcraft) |
| CADCraft | AutoCAD (CADCraft) | [storytold/cadcraft](https://github.com/storytold/cadcraft) |
| SolidCraft | SolidWorks (SolidCraft) | [tangency-labs/solidcraft](https://github.com/tangency-labs/solidcraft) |

The shortcut names are convenient labels, not claims of affiliation with Microsoft, Autodesk, or Dassault Systemes.

## Requirements

- Windows with Windows PowerShell 5.1 and a graphical desktop.
- Internet access to download upstream sources and any missing build tools.
- Enough disk space for Rust source builds and dependencies.
- Administrator approval (UAC) for system-wide installation.
- Rust/Cargo and Microsoft C++ Build Tools, or permission for the installer to install missing prerequisites.

## Quick start

1. Download and extract this repository ZIP into a folder.
2. Double-click **`Launch-StoryTold-Installer.bat`**. Keep the `.bat` and both `.ps1` files together.
3. Select the applications you want and click **Start installation**.
4. Allow any requested prerequisite installation or Windows restart.
5. When Windows requests administrator approval, click **Yes** to finish installation and create desktop shortcuts.

Do not close the installer or leave a UAC prompt unattended. Building all six applications may take considerable time, depending on the PC.

## How it works

- Downloads the upstream `main` branch ZIP archives and builds selected Rust packages in release mode.
- Uses `RUSTFLAGS=-C target-cpu=native` to optimize builds for the current processor. These binaries are not necessarily portable to older CPUs.
- Uses `D:\temp\StoryTold` when drive D: exists; otherwise `C:\temp\StoryTold`.
- Displays build milestones, progress and an animated ASCII indicator.
- Requests elevation for installation and desktop shortcut creation.
- Prevents automatic system sleep and display timeout while the GUI is running; normal Windows behavior resumes when the GUI exits. Manual sleep and lid-close policies are not overridden.
- Removes temporary build files and logs after a successful installation; retains them when an error occurs.

## Troubleshooting and resuming

If compilation succeeds but the final installation fails, inspect the logs in the temporary StoryTold folder and rerun the launcher. The installer records resume state and can reuse completed builds where its state is intact. Keep the temporary folder until installation succeeds.

If UAC was canceled or missed, launch again and approve the elevation request. For errors, review `installer_*.log`, `installer_*.log.errors.txt`, per-application Cargo logs, and `elevated_install.log` where present. The **Open log folder** button opens the working directory.

A restart may be needed after installing Visual Studio Build Tools. The installer can register a one-time resume for the next Windows sign-in.

## Security and third-party software

This installer downloads and executes code from upstream GitHub repositories and may install development prerequisites. Review those repositories and their licenses before running. The source archives follow the upstream `main` branches rather than pinned releases, so builds may change over time. The upstream projects retain their own licenses and trademarks.

This repository contains installer scripts only, not the upstream application source code. No license is asserted for these installer scripts in this package; add a `LICENSE` file if you choose to publish them under a specific license.

## Files

- `Launch-StoryTold-Installer.bat`: Windows launcher.
- `StoryTold-GUI.ps1`: graphical interface, progress display and sleep prevention.
- `StoryTold-Installer.ps1`: prerequisites, source download, build, elevation and installation logic.
- `.gitignore`: excludes local logs and temporary build artifacts.

**Packaged from the working v15 installer.** The original installation logic is preserved; only filenames and cross-file references were updated.
