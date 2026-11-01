#!/usr/bin/env python3
"""Data-only manifest reader and correctly escaped desktop launchers (Python 3.8+)."""
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys

NAMES = dict(wordcraft='WordCraft', gridcraft='GridCraft', deckcraft='DeckCraft',
             pdfcraft='PDFCraft', cadcraft='CADCraft', solidcraft='SolidCraft')


def desktop(data, app, binary, copy_desktop):
    data = Path(data)
    launcher = data / 'storytold' / 'launchers' / app
    launcher.parent.mkdir(parents=True, exist_ok=True)
    # No shell expansion of user-controlled path characters.
    launcher.write_text('#!/bin/sh\nexec ' + shlex.quote(binary) + ' "$@"\n', encoding='utf-8')
    launcher.chmod(0o755)
    # Exec is parsed twice: desktop string escapes, then quoted Exec argument escapes.
    arg = str(launcher).replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$')
    arg = arg.replace('\\', '\\\\').replace('%', '%%')
    category = 'Graphics;Engineering;' if app in ('cadcraft', 'solidcraft') else 'Office;'
    entry = data / 'applications' / ('storytold-' + app + '.desktop')
    entry.parent.mkdir(parents=True, exist_ok=True)
    entry.write_text('[Desktop Entry]\nType=Application\nName=' + NAMES[app] +
                     '\nExec="' + arg + '" %F\nIcon=applications-other\nTerminal=false\nCategories=' +
                     category + '\nStartupNotify=true\n', encoding='utf-8')
    if copy_desktop == '1':
        folder = subprocess.check_output(['xdg-user-dir', 'DESKTOP'], text=True).strip()
        if not folder or Path(folder) == Path.home() or not Path(folder).is_dir():
            print('Desktop directory is disabled or missing; menu entry was still installed.')
        else:
            target = Path(folder) / entry.name
            shutil.copyfile(entry, target)
            target.chmod(0o755)
            print('Desktop shortcut created; the file manager may require Allow Launching: ' + str(target))


def main():
    mode = sys.argv[1]
    if mode == 'desktop':
        desktop(*sys.argv[2:])
        return
    manifest = json.loads(Path(sys.argv[2]).read_text(encoding='utf-8'))
    requested = sys.argv[3].split(',')
    by_id = {a['id']: a for a in manifest['apps']}
    apps = [by_id[name] for name in requested]
    if mode == 'packages':
        print(' '.join(sorted({p for a in apps for p in a['apt']})))
    elif mode == 'row':
        a = apps[0]
        print('\t'.join(a[k] for k in ('repo', 'commit', 'package', 'binary')))
    elif mode == 'plan':
        for a in apps:
            print(a['id'] + ': https://github.com/' + a['repo'] + ' @ ' + a['commit'])
            print('  cargo +stable build --release --locked -p ' + a['package'] + ' --bin ' + a['binary'])
            print('  apt: ' + ' '.join(a['apt']))
        print('RUSTFLAGS=-C target-cpu=native; Cargo validates and reuses build artifacts.')
    else:
        raise ValueError('Unknown operation: ' + mode)


if __name__ == '__main__':
    main()
