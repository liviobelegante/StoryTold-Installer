# Verification report — 2026-11-01

## Completed locally

- Retrieved metadata and full commit IDs for all six repositories from GitHub's API.
- Read each workspace and desktop Cargo manifest, Linux packaging script, relevant CI configuration and build scripts. Confirmed the desktop package names, `src/main.rs` targets, Cargo.lock availability and absence of Git submodules in the pinned trees.
- Confirmed that upstream Linux packaging uses release, locked Cargo builds. The installer selects only each desktop binary and explicitly targets the native Linux Rust host.
- Checked all five Bash files with ShellCheck 0.11.0, including its parser: no warnings or errors.
- Ran six Python regression tests: all passed. Coverage includes manifest identities, ALSA selection, invalid IDs, desktop-path escaping, Desktop copies and disabled Desktop handling.
- Compared the four preserved Windows files byte-for-byte with the pinned GitHub source. The original README identifies the v15 origin; the Windows installer was not executed.
- ZIP validation checks every entry's CRC, SHA256 and bytes against the source file, rejects unsafe archive paths, checks LF-only shell files, and verifies Unix executable attributes for `.sh` files. `SHA256SUMS` covers all other packaged files; the external checksum covers the ZIP itself.

## Not completed here

This host is Windows. No usable Linux distribution was available through WSL. Git Bash could not start because the host denied creation of its signal pipe. Consequently, local `bash -n`, CLI execution tests, apt resolution, rustup installation, all six full Cargo builds, GUI authentication, systemd inhibition and graphical application startup were **not** executed. ShellCheck parsing and Python tests do not replace these checks.

The included GitHub Actions workflow has **not been run or published**. It provides Bash parsing, ShellCheck, CLI validation and desktop-file tests on Ubuntu 22.04/24.04, plus dependency resolution on Ubuntu and Debian 12/13. It does not compile the applications or certify Linux Mint. Distribution versions in that workflow are test targets, not verified support claims.

## Required before a stable release

On each intended Ubuntu, Linux Mint and Debian desktop version and each advertised architecture:

1. Run the GUI from a clean account; check app selection and authentication.
2. Build all six pinned revisions, preserve logs, and launch every installed application from the menu.
3. Verify X11/Wayland as applicable, font fallback, audio in DeckCraft, and basic PDF/CAD workflows.
4. Repeat an unchanged build and confirm Cargo reuses artifacts. Interrupt a build and verify recovery. Check that an existing installation remains usable after a failed replacement build.
5. Confirm `systemd-inhibit --list` shows the installer during work and no longer shows it after exit or interruption. Test refusal when inhibition is denied.
6. Test low-memory failure, unavailable apt packages, network failure, spaces/non-ASCII characters in paths and a disabled Desktop directory.
7. Record actual distro, CPU, Rust version, log paths and outcomes. Only then remove the preview label for configurations that passed.

No successful Linux build or runtime result is implied by the verified ZIP.
