# Source verification

Checked on 2026-11-01 against GitHub API and raw files. These are source-level checks, not successful local Linux builds.

## wordcraft

Repository: https://github.com/storytold/wordcraft

Commit: `a88e005256087285bc7d34310cc0f5f932bc8562`

- [Workspace manifest](https://github.com/storytold/wordcraft/blob/a88e005256087285bc7d34310cc0f5f932bc8562/Cargo.toml): Rust 1.95 minimum.
- [Desktop package](https://github.com/storytold/wordcraft/blob/a88e005256087285bc7d34310cc0f5f932bc8562/apps/wordcraft/Cargo.toml).
- [Linux packaging](https://github.com/storytold/wordcraft/blob/a88e005256087285bc7d34310cc0f5f932bc8562/packaging/linux/package.sh): release, locked Cargo build of `wordcraft` and the separate CLI. This installer builds only the desktop binary.
- [CI dependencies](https://github.com/storytold/wordcraft/blob/a88e005256087285bc7d34310cc0f5f932bc8562/.github/workflows/ci.yml).
- Cargo.lock SHA256: `83e2ce9650ab3ada176dc256b4d9effbeb84076e5b4e0cfe5cb37a013e5ad8e6`.
- apt build dependencies: `libfontconfig1-dev libfreetype-dev libgl1-mesa-dev libgtk-3-dev libwayland-dev libx11-dev libxcursor-dev libxi-dev libxkbcommon-dev libxrandr-dev mesa-vulkan-drivers pkg-config`.

## gridcraft

Repository: https://github.com/storytold/gridcraft

Commit: `5e415cdd34d287b90a4a9df67eb4f532f6f72d96`

- [Workspace manifest](https://github.com/storytold/gridcraft/blob/5e415cdd34d287b90a4a9df67eb4f532f6f72d96/Cargo.toml): Rust 1.95 minimum.
- [Desktop package](https://github.com/storytold/gridcraft/blob/5e415cdd34d287b90a4a9df67eb4f532f6f72d96/apps/gridcraft/Cargo.toml).
- [Linux packaging](https://github.com/storytold/gridcraft/blob/5e415cdd34d287b90a4a9df67eb4f532f6f72d96/packaging/linux/package.sh): release, locked Cargo build of `gridcraft` and the separate CLI. This installer builds only the desktop binary.
- [CI dependencies](https://github.com/storytold/gridcraft/blob/5e415cdd34d287b90a4a9df67eb4f532f6f72d96/.github/workflows/ci.yml).
- Cargo.lock SHA256: `7afd607e153ddf63c72819f8eacdb90dd97814c571c227ed5b0ef908f68b7204`.
- apt build dependencies: `libfontconfig1-dev libfreetype-dev libgl1-mesa-dev libgtk-3-dev libwayland-dev libx11-dev libxcursor-dev libxi-dev libxkbcommon-dev libxrandr-dev mesa-vulkan-drivers pkg-config`.

## deckcraft

Repository: https://github.com/storytold/deckcraft

Commit: `5fb694d9917d232fbf5b2e0f42ac15d73febde7c`

- [Workspace manifest](https://github.com/storytold/deckcraft/blob/5fb694d9917d232fbf5b2e0f42ac15d73febde7c/Cargo.toml): Rust 1.95 minimum.
- [Desktop package](https://github.com/storytold/deckcraft/blob/5fb694d9917d232fbf5b2e0f42ac15d73febde7c/apps/deckcraft/Cargo.toml).
- [Linux packaging](https://github.com/storytold/deckcraft/blob/5fb694d9917d232fbf5b2e0f42ac15d73febde7c/packaging/linux/package.sh): release, locked Cargo build of `deckcraft` and the separate CLI. This installer builds only the desktop binary.
- [CI dependencies](https://github.com/storytold/deckcraft/blob/5fb694d9917d232fbf5b2e0f42ac15d73febde7c/.github/workflows/ci.yml).
- Cargo.lock SHA256: `784e4cb608334ea8d523f1592deb2545ef8eb3cb162bd482c2ba6cc76346efd5`.
- apt build dependencies: `libasound2-dev libgl1-mesa-dev libwayland-dev libx11-dev libxi-dev libxkbcommon-dev libxrandr-dev pkg-config`.

## pdfcraft

Repository: https://github.com/storytold/pdfcraft

Commit: `47f42ba07b61553da50ca2df91b070519bd3386e`

- [Workspace manifest](https://github.com/storytold/pdfcraft/blob/47f42ba07b61553da50ca2df91b070519bd3386e/Cargo.toml): Rust 1.95 minimum.
- [Desktop package](https://github.com/storytold/pdfcraft/blob/47f42ba07b61553da50ca2df91b070519bd3386e/apps/pdfcraft/Cargo.toml).
- [Linux packaging](https://github.com/storytold/pdfcraft/blob/47f42ba07b61553da50ca2df91b070519bd3386e/packaging/linux/package.sh): release, locked Cargo build of `pdfcraft` and the separate CLI. This installer builds only the desktop binary.
- [CI dependencies](https://github.com/storytold/pdfcraft/blob/47f42ba07b61553da50ca2df91b070519bd3386e/.github/workflows/ci.yml).
- Cargo.lock SHA256: `67f4c9361c93ee7f5203572013d7bb58dda28c4f22937ea1ea1c2c2392e1a25c`.
- apt build dependencies: `libgl1-mesa-dev libgtk-3-dev libwayland-dev libx11-dev libxi-dev libxkbcommon-dev libxrandr-dev pkg-config`.

## cadcraft

Repository: https://github.com/storytold/cadcraft

Commit: `258c89fbb021fd22cf25ef519e5caf018b692093`

- [Workspace manifest](https://github.com/storytold/cadcraft/blob/258c89fbb021fd22cf25ef519e5caf018b692093/Cargo.toml): Rust 1.95 minimum.
- [Desktop package](https://github.com/storytold/cadcraft/blob/258c89fbb021fd22cf25ef519e5caf018b692093/apps/cadcraft/Cargo.toml).
- [Linux packaging](https://github.com/storytold/cadcraft/blob/258c89fbb021fd22cf25ef519e5caf018b692093/packaging/linux/package.sh): release, locked Cargo build of `cadcraft` and the separate CLI. This installer builds only the desktop binary.
- [CI dependencies](https://github.com/storytold/cadcraft/blob/258c89fbb021fd22cf25ef519e5caf018b692093/.github/workflows/ci.yml).
- Cargo.lock SHA256: `dd36d108d76022c7e16116ca45f09ee025a0eab96e0626e324ed6be01c6caa74`.
- apt build dependencies: `libfontconfig1-dev libfreetype-dev libgl1-mesa-dev libwayland-dev libx11-dev libxcb1-dev libxcursor-dev libxi-dev libxkbcommon-dev libxrandr-dev mesa-vulkan-drivers pkg-config`.

## solidcraft

Repository: https://github.com/tangency-labs/solidcraft

Commit: `e77c55549f96e806ca206945efb5f4afcf61cd14`

- [Workspace manifest](https://github.com/tangency-labs/solidcraft/blob/e77c55549f96e806ca206945efb5f4afcf61cd14/Cargo.toml): Rust 1.95 minimum.
- [Desktop package](https://github.com/tangency-labs/solidcraft/blob/e77c55549f96e806ca206945efb5f4afcf61cd14/apps/solidcraft/Cargo.toml).
- [Linux packaging](https://github.com/tangency-labs/solidcraft/blob/e77c55549f96e806ca206945efb5f4afcf61cd14/packaging/linux/package.sh): release, locked Cargo build of `solidcraft` and the separate CLI. This installer builds only the desktop binary.
- [CI dependencies](https://github.com/tangency-labs/solidcraft/blob/e77c55549f96e806ca206945efb5f4afcf61cd14/.github/workflows/ci.yml).
- Cargo.lock SHA256: `f98682a8b466efb7205698adf526892aaacd6940fe2d2aa90a5f192e737e8048`.
- apt build dependencies: `libasound2-dev libgl1-mesa-dev libwayland-dev libx11-dev libxi-dev libxkbcommon-dev libxrandr-dev pkg-config`.

## Direct Git dependency revision checks

The following distinct Git sources were extracted from the six Cargo.lock files and resolved through the GitHub API. Registry crate downloads and a complete Cargo resolution/build were not run.

- [https://github.com/storytold/craft-libs @ 92d392cff132](https://github.com/storytold/craft-libs/commit/92d392cff132eaf53e13afff77f38b5c11b73aa0): commit exists.
- [https://github.com/storytold/craft-libs @ c5a1cbfb5f90](https://github.com/storytold/craft-libs/commit/c5a1cbfb5f9049f9270955caffb5bee5997aebf7): commit exists.
- [https://github.com/storytold/egui @ 6d518fc79968](https://github.com/storytold/egui/commit/6d518fc799681571963842f95b55a6b68431b15a): commit exists.
- [https://github.com/storytold/winit @ a517b3846ee8](https://github.com/storytold/winit/commit/a517b3846ee8457d84ee4975110bfda6797c44dc): commit exists.
- [https://github.com/storytold/winprint.rs @ 417ac3c4d14d](https://github.com/storytold/winprint.rs/commit/417ac3c4d14d3da5485a99c7d5ce8f05664ec312): commit exists.
- [https://github.com/storytold/winprint.rs @ 5f80b9baf6b5](https://github.com/storytold/winprint.rs/commit/5f80b9baf6b58937c401656634e42d33f00ddf49): commit exists.

## Dependency interpretation

SolidCraft headers follow its Linux CI cross-target recipe (architecture suffixes removed for native apt), not an executed native apt test. The common graphics/pkg-config headers form a conservative superset; WordCraft and GridCraft also receive GL development headers. PDFCraft CI includes qpdf and poppler-utils for independent test oracles, intentionally excluded from this desktop build. General installer tools and Mesa runtime packages are added separately by the backend.

## Command references

- [Zenity options on Ubuntu](https://manpages.ubuntu.com/manpages/noble/man1/zenity.1.html): checklist, entry and streamed text dialog. Live log following uses GNU tail; Zenity has no `--tail` option.
- [systemd-inhibit](https://www.freedesktop.org/software/systemd/man/latest/systemd-inhibit.html): sleep/idle block lock and child exit status.
- [Cargo configuration](https://doc.rust-lang.org/cargo/reference/config.html): RUSTFLAGS and target directory behavior.
