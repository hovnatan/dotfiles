#!/usr/bin/env bash
#
# Build ~/Applications/Zathura.app: a Finder front end for the Nix zathura
# (nix/flake.nix), so documents open from Finder, "Open With" and `open`,
# and the running viewer has zathura's icon and name in the Dock.
#
#   Finder double-click / Open With / `open -a Zathura f.djvu`
#        |  (an Apple Event "open these files", not argv)
#        v
#   Zathura.app  -- AppleScript applet: `on open` gets the file list
#        |          (on run, with no files: an empty zathura)
#        |  Resources/open-viewer.sh <file>, per file: reads the store paths
#        |  out of the Nix wrapper, then
#        |  open -n -a Helpers/Zathura.app --env ... --args <file>
#        v
#   Helpers/Zathura.app  -- MacOS/zathura: compiled launcher, execv() to
#        |                  zathura's own binary wrapper (makeBinaryWrapper)
#        v
#   .zathura-wrapped     -- the viewer; still this bundle's process, so the
#                           Dock shows its icon and name
#
# The helper is needed because a zathura started straight from /nix/store has
# no bundle: macOS lists it as ".zathura-wrapped" with a generic icon. A
# process launched through LaunchServices stays tied to the bundle it was
# launched as, across exec (lsappinfo: bundleID set, executable in /nix/store).
#
# No shell may run inside the viewer's process: macOS asks for file access
# (Google Drive, Dropbox, Desktop, ...) in the name of whichever interpreter
# sits in that exec chain. With ~/.nix-profile/bin/zathura exec'd from the
# helper, the prompt read '"bash" wants to access files managed by "Google
# Drive"' (that wrapper is a Nix bash script), and allowing it would have
# given every Nix-bash script that access (2026-09-24). So the helper is a
# compiled launcher, and the outer wrapper's two settings (plugin dir, `file`
# on PATH) are passed in by open-viewer.sh, which runs outside the viewer.
#
# Why not homebrew-zathura's convert-into-app.sh: it finds zathura and its
# plugins with `brew --prefix` (none under Nix), and its bundle runs the
# zathura binary directly, which ignores the open event, so a double-click
# starts zathura with no document.
#
# Safe to re-run; it rebuilds the app from scratch, byte for byte the same
# when nothing changed, so macOS keeps a file-access grant across rebuilds.
# The paths are resolved per launch, so zathura upgrades need no rebuild.
# Needs clang (Xcode Command Line Tools, which Homebrew requires anyway).
# Usage: scripts/macos/build_zathura_app.sh

set -euo pipefail

[ "$(uname)" = "Darwin" ] || { echo "build_zathura_app.sh: macOS only" >&2; exit 1; }

app="$HOME/Applications/Zathura.app"
helper="$app/Contents/Helpers/Zathura.app"
plist="$app/Contents/Info.plist"
svg="$HOME/.nix-profile/share/icons/hicolor/scalable/apps/org.pwmt.zathura.svg"
buddy=/usr/libexec/PlistBuddy
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# Extensions per plugin in the Nix zathura (zathura --version lists them:
# pdf-mupdf, djvu, ps, cb), as in convert-into-app.sh's tables, plus epub:
# pdf-mupdf registers org.idpf.epub-container and opens EPUB 3 (tested
# 2026-09-24; MuPDF only warns "unknown epub version: 3.0").
exts=(pdf epub djvu djv ps eps cbr cbz cbt cba cb7)

[ -f "$svg" ] || { echo "build_zathura_app.sh: $svg missing; install zathura with dotup (nix/flake.nix)" >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# --- 1. icon ------------------------------------------------------------------

# From zathura's own SVG, so it tracks the installed version. rsvg-convert
# (librsvg, pinned nixpkgs) renders each size iconutil wants, e.g. 16x16 and
# 16x16@2x (32 px) up to 512x512@2x (1024 px).
mkdir "$work/AppIcon.iconset"
nix shell --inputs-from "path:$HOME/.dotfiles/nix" nixpkgs#librsvg --command bash -c '
  for s in 16 32 128 256 512; do
    rsvg-convert -w "$s" -h "$s" "$1" -o "$2/icon_${s}x${s}.png"
    rsvg-convert -w $((s * 2)) -h $((s * 2)) "$1" -o "$2/icon_${s}x${s}@2x.png"
  done' _ "$svg" "$work/AppIcon.iconset"
iconutil -c icns "$work/AppIcon.iconset" -o "$work/AppIcon.icns"

# --- 2. the applet ------------------------------------------------------------

# open-viewer.sh's errors (zathura missing, wrapper layout changed) surface as
# an AppleScript error dialog naming the fix, not as a silent no-op. -n: one
# zathura process (and Dock entry) per document, as zathura has one window
# per process.
cat >"$work/open-viewer.sh" <<'EOF'
#!/bin/sh
# Start one zathura viewer (Helpers/Zathura.app) for $1, or an empty one.
# Written by scripts/macos/build_zathura_app.sh in ~/.dotfiles.
set -eu
app=$(cd "$(dirname "$0")/../.." && pwd)
outer=$(realpath "$HOME/.nix-profile/bin/zathura" 2>/dev/null) \
  || { echo "zathura not found at ~/.nix-profile/bin/zathura: install it with dotup (nix/flake.nix)" >&2; exit 1; }
# The Nix wrapper (a bash script) ends in: exec "<store>-zathura-<v>-bin/bin/zathura"  "$@"
inner=$(sed -n 's/^exec "\(.*\)"  "\$@" *$/\1/p' "$outer")
filebin=$(grep -o "/nix/store/[^':]*-file-[^/']*/bin" "$outer" | head -n 1)
plugins="${outer%/bin/zathura}/lib/zathura"
if [ ! -x "$inner" ] || [ ! -d "$filebin" ] || [ ! -d "$plugins" ]; then
  echo "cannot read the Nix zathura wrapper $outer (exec target '$inner', file '$filebin', plugins '$plugins'); its layout changed: update open-viewer.sh in ~/.dotfiles/scripts/macos/build_zathura_app.sh" >&2
  exit 1
fi
open -n -a "$app/Contents/Helpers/Zathura.app" \
  --env ZATHURA_APP_EXEC="$inner" \
  --env ZATHURA_PLUGINS_PATH="$plugins" \
  --env PATH="$filebin:/usr/bin:/bin:/usr/sbin:/sbin" \
  ${1+--args "$1"}
EOF
cat >"$work/applet.applescript" <<'EOF'
on run
	do shell script quoted form of POSIX path of (path to resource "open-viewer.sh")
end run

on open theFiles
	set viewer to quoted form of POSIX path of (path to resource "open-viewer.sh")
	repeat with f in theFiles
		do shell script viewer & " " & quoted form of POSIX path of f
	end repeat
end open
EOF
mkdir -p "$(dirname "$app")"
rm -rf "$app"
osacompile -o "$app" "$work/applet.applescript"
install -m 755 "$work/open-viewer.sh" "$app/Contents/Resources/open-viewer.sh"

# --- 3. identity, icon and document types -------------------------------------

# osacompile writes some of these keys and not others (no CFBundleIdentifier),
# so each is deleted if present, then added. Its icon comes from Assets.car
# via CFBundleIconName, which beats CFBundleIconFile: drop both for ours.
for key in CFBundleIdentifier CFBundleName CFBundleIconName CFBundleIconFile \
  CFBundleDocumentTypes UTImportedTypeDeclarations; do
  "$buddy" -c "Delete :$key" "$plist" 2>/dev/null || true
done
rm -f "$app/Contents/Resources/Assets.car"
cp "$work/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
"$buddy" -c "Add :CFBundleIdentifier string com.hovnatan.zathura" \
  -c "Add :CFBundleName string Zathura" \
  -c "Add :CFBundleIconFile string AppIcon" "$plist"

# Rank Alternate: the app claims no type by itself; step 6 picks which types
# it is the default for.
"$buddy" -c "Add :CFBundleDocumentTypes array" \
  -c "Add :CFBundleDocumentTypes:0 dict" \
  -c "Add :CFBundleDocumentTypes:0:CFBundleTypeName string Documents" \
  -c "Add :CFBundleDocumentTypes:0:CFBundleTypeRole string Viewer" \
  -c "Add :CFBundleDocumentTypes:0:LSHandlerRank string Alternate" \
  -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions array" "$plist"
for i in "${!exts[@]}"; do
  "$buddy" -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions:$i string ${exts[$i]}" "$plist"
done

# macOS has no type identifier for DjVu, only a per-extension dyn.* one that
# LaunchServices will not take a default for (duti: error -50). Declare the
# conventional com.lizardtech.djvu, "imported" so a real owner's
# declaration still wins, and step 6 can then name it.
"$buddy" -c "Add :UTImportedTypeDeclarations array" \
  -c "Add :UTImportedTypeDeclarations:0 dict" \
  -c "Add :UTImportedTypeDeclarations:0:UTTypeIdentifier string com.lizardtech.djvu" \
  -c "Add :UTImportedTypeDeclarations:0:UTTypeDescription string DjVu document" \
  -c "Add :UTImportedTypeDeclarations:0:UTTypeConformsTo array" \
  -c "Add :UTImportedTypeDeclarations:0:UTTypeConformsTo:0 string public.data" \
  -c "Add :UTImportedTypeDeclarations:0:UTTypeConformsTo:1 string public.content" \
  -c "Add :UTImportedTypeDeclarations:0:UTTypeTagSpecification dict" \
  -c "Add :UTImportedTypeDeclarations:0:UTTypeTagSpecification:public.filename-extension array" \
  -c "Add :UTImportedTypeDeclarations:0:UTTypeTagSpecification:public.filename-extension:0 string djvu" \
  -c "Add :UTImportedTypeDeclarations:0:UTTypeTagSpecification:public.filename-extension:1 string djv" \
  -c "Add :UTImportedTypeDeclarations:0:UTTypeTagSpecification:public.mime-type string image/vnd.djvu" "$plist"

# --- 4. the helper app --------------------------------------------------------

# Declares no document types, so it never shows up under "Open With". Its
# executable is compiled, not a script: see the header on interpreters.
mkdir -p "$helper/Contents/MacOS" "$helper/Contents/Resources"
cp "$work/AppIcon.icns" "$helper/Contents/Resources/AppIcon.icns"
cat >"$work/launcher.c" <<'EOF'
/* Zathura.app viewer: become the Nix zathura binary wrapper named by
 * ZATHURA_APP_EXEC (set by open-viewer.sh), keeping this process and so this
 * bundle's identity. Written by scripts/macos/build_zathura_app.sh. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
  (void)argc;
  const char *target = getenv("ZATHURA_APP_EXEC");
  if (target == NULL || *target == '\0') {
    fprintf(stderr, "ZATHURA_APP_EXEC not set: start zathura via Zathura.app\n");
    return 1;
  }
  char *path = strdup(target);
  unsetenv("ZATHURA_APP_EXEC");
  argv[0] = "zathura";
  execv(path, argv);
  perror(path);
  return 1;
}
EOF
command -v clang >/dev/null \
  || { echo "build_zathura_app.sh: clang not found; xcode-select --install" >&2; exit 1; }
clang -O2 -Wall -Werror -o "$helper/Contents/MacOS/zathura" "$work/launcher.c"
"$buddy" -c "Add :CFBundleExecutable string zathura" \
  -c "Add :CFBundleIdentifier string com.hovnatan.zathura.viewer" \
  -c "Add :CFBundleName string Zathura" \
  -c "Add :CFBundlePackageType string APPL" \
  -c "Add :CFBundleIconFile string AppIcon" "$helper/Contents/Info.plist" >/dev/null

# --- 5. sign and register -----------------------------------------------------

# Editing the bundle breaks osacompile's ad-hoc signature, and Apple Silicon
# refuses to launch an app whose signature does not match ("damaged"). The
# nested helper is signed first, as the outer signature covers it.
codesign --force --sign - "$helper"
codesign --force --sign - "$app"
"$lsregister" -f "$app"
"$lsregister" -f "$helper"

# --- 6. default viewer --------------------------------------------------------

# zathura opens these on double-click (2026-09-24); the rest of exts only get
# "Open With". PDFs were Preview, EPUBs Books. Re-applied on every run, so
# dotup undoes a switch made in Finder's Get Info; change this list instead.
# duti comes from the Brewfile.
# By type identifier: duti's ".pdf" extension form resolves to a dyn.* type
# and fails with error -50.
default_for=(com.adobe.pdf org.idpf.epub-container com.lizardtech.djvu)
command -v duti >/dev/null \
  || { echo "build_zathura_app.sh: duti not found; brew bundle --file=~/.dotfiles/Brewfile" >&2; exit 1; }
for uti in "${default_for[@]}"; do
  duti -s com.hovnatan.zathura "$uti" all
done

echo "Built $app (opens: ${exts[*]}; default for: ${default_for[*]})"
