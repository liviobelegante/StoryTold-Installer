# Linux installer

## Requirements and scope

- Ubuntu, Linux Mint or Debian with apt, a normal desktop account and a graphical X11 or Wayland session for Zenity and the apps.
- Native x86_64 or aarch64. Other architectures are deliberately rejected by this preview.
- Bash 4+, util-linux (`flock`, `lscpu`), and systemd-logind with permission to inhibit sleep. These normally come with the desktop OS.
- Internet access to distro package mirrors, GitHub, crates.io and Rust distribution servers.
- Administrator authentication through sudo (interactive CLI) or pkexec plus a desktop PolicyKit authentication agent (GUI).
- Sufficient RAM and free disk space for large Rust workspaces. No measured minimum or compile-time promise is available. Start with `--jobs 1` on memory-constrained machines.

The distro names are detected, but no version is advertised as fully tested. Upstream manifests currently require Rust 1.95; the installer installs/updates the rustup **stable** toolchain, leaves the default toolchain unchanged, and explicitly invokes `cargo +stable`. Cargo enforces the actual minimum version. If the stable toolchain available from your mirror is too old, installation fails with the compiler's diagnostic.

## What is installed

`launch-installer.sh` bootstraps Zenity. The GUI lets you select apps, compiler parallelism and optional Desktop shortcuts. It runs the same backend as the command line. Close the log viewer without stopping the build; the GUI reports the backend's final exit status. There is no GUI cancellation during apt. To interrupt a CLI build, use Ctrl+C and rerun later.

The backend installs build tools, selected upstream Linux headers, Mesa Vulkan runtime support and basic system fonts with apt. It does not change repositories or run a distro upgrade. apt performs a dependency-resolution simulation for the selected app headers before installing them. This checks package availability on the actual machine, rather than assuming that all releases have identical package sets.

The manifest pins one verified Git commit per app. Each desktop package is compiled with default features, `--release --locked`, an explicit `--bin`, and `RUSTFLAGS=-C target-cpu=native`. Web and separate CLI programs are not installed. These CPU-specific executables are intended for this computer; rebuild on another CPU or distribution.

DeckCraft requires ALSA development headers. SolidCraft has its own repository, `tangency-labs/solidcraft`, and keeps its default CPU raytracing/render-library features. PDFCraft's upstream qpdf/poppler test-oracle tools are not required by this desktop-only build and are not installed. Optional `craft-fonts` checkout assets are not bundled: local builds use their upstream fallback/system font behavior. The dependencies and differences are documented in [SOURCES](../docs/SOURCES.md).

## Paths and reuse

| Content | Default path |
| --- | --- |
| Source checkouts, pinned by revision | `~/.cache/storytold/sources/APP/COMMIT/` |
| Cargo artifacts | `~/.cache/storytold/targets/APP/ENVIRONMENT/` |
| Installed programs and build information | `~/.local/share/storytold/apps/APP/` |
| Launch wrappers | `~/.local/share/storytold/launchers/` |
| Application-menu entries | `~/.local/share/applications/storytold-APP.desktop` |
| Installer and GUI logs | `~/.local/state/storytold/logs/` |

`XDG_CACHE_HOME`, `XDG_DATA_HOME` and `XDG_STATE_HOME` are respected and must be absolute paths without line breaks or tabs. `CARGO_HOME` is respected for the Rust installation. Use a normal local filesystem with executable-file support.

Cargo runs on every attempt and decides which existing build artifacts are still fresh; a binary's existence alone is never treated as proof of a successful current build. Artifact directories are separated by app and a fingerprint of the compiler, CPU model/features, distro and installed package versions. Repeating an unchanged build reuses its artifacts. An interrupted compile resumes through Cargo. A checkout with local modifications is rejected, not reset. If a fetch was interrupted, retry; if a checkout is damaged before Git was initialized, move that specific directory aside and retry.

Completed applications remain installed if a later app fails. A new executable replaces the old one only after a successful build and runtime-library check. Rerun the same selection after fixing the logged error. A lock prevents two simultaneous installer runs.

Do not move caches to a different CPU to avoid recompilation. To force a full rebuild, move the relevant app's target directory aside. This installer does not clean caches automatically.

## Sleep and shortcuts

The backend runs under `systemd-inhibit --what=sleep:idle --mode=block` for the full operation, including dependency setup. If inhibition is unavailable or denied, it stops. To deliberately proceed without this protection, use `--allow-sleep` from the CLI. Inhibition is released when the process exits. It does not protect against power loss, forced shutdown, or every desktop's lid-close policy.

Menu shortcuts are always created. `--desktop` also copies them to an existing XDG Desktop directory. Some file managers require **Allow Launching**. No default file associations are changed. Generic system icons are used; application branding assets are not redistributed.

## Troubleshooting and removal

- Permission prompt missing: use the CLI in a terminal with sudo, or enable your desktop's PolicyKit agent.
- apt error: resolve the named package/repository/lock issue and rerun; no alternate package names are guessed silently.
- Compiler killed: reduce `--jobs` to 1 and check available RAM and disk space.
- Missing runtime library: installation stops before replacing that app. Inspect the `ldd` output in the log.
- Application does not open: run its installed executable from a terminal to see driver/runtime diagnostics. An installed binary and a clean `ldd` check do not prove successful graphical startup.

To remove an app, remove its specific `storytold-APP.desktop` menu/Desktop entries, its wrapper and its directory under `storytold/apps/`. Cache removal is optional. The installer does not remove shared apt packages, Rust, or application documents/settings.
