# StoryTold Installer

Build and install WordCraft, GridCraft, DeckCraft, PDFCraft, CADCraft and SolidCraft from source.

The Linux port provides a Zenity interface and a Bash command-line installer for Ubuntu, Linux Mint and Debian desktop systems. The Windows installer is kept separately in [`windows/`](windows/).

**Status: Linux preview — source and installer checks, not a certified distro release.** The six repositories, desktop package names, locked build commands and upstream Linux dependency declarations were checked on 2026-11-01. Full compilation and graphical startup on Ubuntu, Mint and Debian have not been run in this Windows authoring environment. See [verification](docs/VALIDATION.md) and [source evidence](docs/SOURCES.md).

## Linux quick start

Extract the ZIP, open a terminal in the extracted `StoryTold-Installer` directory, then run:

```bash
bash linux/launch-installer.sh
```

Run as your normal desktop user. The installer requests administrator authentication only for apt. Rust and the apps are installed in your user account. Zenity is installed automatically if missing. A graphical PolicyKit authentication agent is needed for apt prompts from the GUI; the command-line installer uses sudo when run from an interactive terminal.

Command-line example:

```bash
bash linux/storytold-installer.sh --apps wordcraft,gridcraft --jobs 2 --desktop
```

Preview the source revisions and app dependencies without changing the system (Python 3 required):

```bash
bash linux/storytold-installer.sh --apps all --dry-run
```

See [Linux instructions](linux/README.md) for requirements, build reuse, logging and troubleshooting.

## Windows

Run `windows/Launch-StoryTold-Installer.bat`. The original `.bat`, `.ps1` and Windows README were copied byte-for-byte from the [existing repository](https://github.com/liviobelegante/StoryTold-Installer/tree/88e6710047d270dee2d8220168ec09e282819be8/StoryTold-Craft-Installer). Its README identifies the package as based on the working v15 installer. Windows was not modified or retested. [Provenance](windows/PROVENANCE.md).

## Repository layout

```text
linux/       Linux GUI, Bash backend, manifest and launcher helper
windows/     Preserved Windows v15-derived installer
docs/        Source evidence and verification limits
tests/       Installer and launcher regression checks
.github/     Linux installer checks for GitHub Actions
LICENSE      Preserved project MIT license
SHA256SUMS   Checksums for all other packaged files
```

## Publishing on GitHub

The archive contains one `StoryTold-Installer/` root. Copy its contents into the repository root so `linux/` and `windows/` are siblings. Review any existing files before replacing them; this archive does not remove the old `StoryTold-Craft-Installer/` folder automatically. Commit the files and optionally attach the ZIP and its external SHA256 file to a preview release. Nothing was uploaded or published by this task.

On Linux, verify the extracted files from the project root:

```bash
sha256sum -c SHA256SUMS
```

The installer has the existing project's MIT license. Downloaded applications and their dependencies retain their own licenses. This package does not bundle their binaries or source trees and does not claim affiliation with their maintainers.
