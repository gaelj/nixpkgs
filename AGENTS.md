# AGENTS.md

Working notes for agents contributing to this nixpkgs fork, distilled from the
craft app-suite packaging effort (2026-10) and extended with the non-craft
update fixes for open-terminal and ovumcy (2026-11). Read this before touching
`pkgs/by-name/`.

## Repository layout

This is a reorganized nixpkgs fork. `pkgs/top-level/all-packages.nix` is
slimmed; most packages live in the standard `pkgs/by-name/<two letters>/<name>/`
shard tree, wired up by `pkgs/topplevel/by-name-overlay.nix` via
`self.callPackage file {}`. Consequences:

- The top-level attribute name is exactly the directory basename.
- Any top-level attr is a valid callPackage argument, so prefer referencing
  sibling packages as bare args instead of re-fetching.

## Packaging a new craft app (workflow)

When unsure how to package something, find inspiration on existing packages
first — sibling `pkgs/by-name/...` packages and established nixpkgs patterns
usually already encode the answer for this tree.

1. Clone the source (`github.com/storytold/<app>`) and inspect: binaries in
   `cargoBuildFlags` (app + `<app>-cli`), whether `build.rs` reads
   `CRAFT_FONTS_DIR` (font embedding at compile time — no runtime Env= needed),
   desktop file in `packaging/linux/`, icons in `assets/app-icon/hicolor/`,
   and which C libraries its Rust stack dlopens at runtime.
2. Write `pkgs/by-name/<xx>/<app>/package.nix` using
   `pkgs/by-name/gr/gridcraft/package.nix` as the template.
3. Fetch src with `fetchFromGitHub`; pin dependencies with `cargoHash` (see
   "Obtaining a cargoHash" below).
4. Evaluate locally: `nix eval --impure --raw --expr '(import /home/gaj/nixpkgs {}).<app>.drvPath'`.
5. Rsync the changed files to `aero-server:/home/gaj/nixpkgs/` (remote builds
   evaluate the remote tree), build there, fetch the result back locally via
   the substituter (below).
6. Verify with the checklist at the bottom.

### Fork-specific source/hook quirks

- `fetchFromGitHub` here is a fetchzip wrapper with `recursiveHash = true`
  hardcoded: `hash` must be the *recursive* hash of the unpacked tree, not the
  tarball's. Recipe: download the tarball, extract, `nix hash path <topdir>`,
  prefix with `sha256-`.
- There is no `stdenvNoWrap`; use `stdenvNoCC` for data-only derivations.
- `${pname}` and `${finalAttrs.name}` are NOT in scope inside string
  interpolation in these packages; use
  `"${finalAttrs.pname}-${finalAttrs.version}"`.
- Sibling attributes inside an attrset are not resolvable as bare names; pass
  them as callPackage arguments or reference `finalAttrs.<name>`.

### Obtaining a cargoHash

Use `cargoHash`, not `cargoLock = { lockFile = ... }`. It is the *recursive*
hash of the entire vendored dependency tree (what `fetch-cargo-vendor-util
create-vendor-staging` downloads per `Cargo.lock`) — NOT the sha256 of the
`Cargo.lock` file. Recipe:

1. Write `cargoHash = "";` in the package (an empty string; do not type an
   AAAAA placeholder by hand). Never commit the empty value.
2. Rsync and start a build on a remote. Nix builds the vendor tree as a
   fixed-output derivation against a placeholder hash, then aborts with
   `error: hash mismatch in fixed-output derivation ... got: sha256-...`.
3. The `got:` line IS the cargoHash — pin it and rebuild.

Recursive path hashes depend only on content + nix version (2.34.8 on all
machines), so a hash revealed on any remote is valid everywhere. One empty-hash
build per package reveals its value; it downloads the crates but compiles
nothing, so several can run concurrently per machine.

## Go packages: vendorHash, and a `go.mod` newer than our toolchain

Same reveal recipe for `vendorHash = "";` (the `go-modules` fixed-output
derivation aborts and prints `got: sha256-...`). If a Go package also builds an
npm frontend, keep the two hashes straight: `vendorHash` is the Go vendor
closure and `frontend.npmDepsHash` is the npm closure — they are never equal,
so an identical pair is a copy-paste bug worth re-revealing (this happened to
ovumcy 2.2.1).

When upstream's `go.mod` asks for a patch release newer than the tree's `go`
(`go: go.mod requires go >= 1.27.4 (running go 1.27.3; GOTOOLCHAIN=local)`),
do not chase a toolchain bump: a patch release adds no language or stdlib
features, so trim the directive in `postPatch`:

```nix
  postPatch = ''
    substituteInPlace go.mod --replace-fail 'go 1.27.4' 'go 1.27.3'
  '';
```

That single hook is enough because `pkgs/build-support/go/module.nix` forwards
`prePatch`/`patches`/`patchFlags`/`postPatch`/`preBuild`/`modPostBuild`/
`sourceRoot`/`setSourceRoot`/`env` into the separate `go-modules` derivation, so
the vendor fetch sees the patched `go.mod` too — no `overrideModAttrs` needed.
Precedent in-tree: grafana-image-renderer and talm (`--replace-fail 'go 1.26.4'
'go 1.26.3'`), athens and immich-kiosk (sed down to the minor version).

## Runtime dlopen / RUNPATH rule (important)

The craft apps link their entire Rust UI stack statically. Their only DT_NEEDED
entries are the basics (libc, libm, libgcc_s, asound); every C library is
dlopen'd at runtime by bare soname through the binary's DT_RUNPATH (set by our
`patchelf --set-rpath "${lib.makeLibraryPath [...] }"` in postFixup).

Therefore **every dlopen target must be in buildInputs** so it lands in both
the build closure and the RUNPATH. Known set:

- winit 0.30 via x11-dl: `libX11.so.6` (hard fail if missing), `libXcursor.so.1`,
  `libXi.so.6`, `libX11-xcb.so.1`. This fork's `libx11` ships
  `libX11-xcb.so.1` in the same `/lib` dir, so no separate x11-xcb package is
  needed; there is no such attr in this tree.
- x11rb (feature dl-libxcb): `libxcb`; xkbcommon-dl: `libxkbcommon`.
- wgpu: `libvulkan.so.1` (needs `vulkan-loader`).
- g-desktop-portal: `dbus` (soft-fails, but include it).
- lightcraft additionally probes `libXinerama.so.1` and `libXt.so.6`.

Symptom of a miss at launch: `opening library failed: <soname> ... No such file
or directory`, or winit aborting with "Failed to load one of xlib's shared
libraries".

## Test / check-phase gotchas in this tree

- **stdenv sets no LD_LIBRARY_PATH** during builds (only musl/freebsd/bootstrap
  variants mention it; rustPlatform never touches it). Any test that dlopens a
  store library at runtime must get an explicit export. Photocraft's
  wgpu/egui_kittest check needs in `preCheck`:
  `VK_ICD_FILENAMES` pointing at the lavapipe ICD json and
  `LD_LIBRARY_PATH="<vulkan-loader>/lib:<mesa>/lib"`. Use plain `mesa` for
  lavapipe — a slimmed `mesa.override { vulkanDrivers = [ "swrast" ]; }` breaks
  this tree's multi-output mesa builder ("failed to produce output path for
  output 'spirv2dxil'").
- To iterate on a failing test without rebuilding: build with `--keep-failed`,
  read the kept directory from the `.err` file, and run the test binary under
  `<dir>/source/target/<triple>/release/deps/<crate>-<hash>` directly over ssh.
  Note: running it outside the sandbox makes any test that reads
  `env!(CARGO_MANIFEST_DIR)` fixtures fail spuriously — only trust in-sandbox
  results for those.
- Tests that flock and spawn children race on high-core machines: a child
  spawned by one test inherits the flock file descriptors of concurrently
  running sibling tests (POSIX fd inheritance), so an open right after a drop
  can still be refused (lightcraft catalog lock tests). Serialize with
  `cargoTestFlags = [ "--" "--test-threads=1" ];`.
- As a last resort, `doCheck = false` with a comment explaining why (precedent:
  soundcraft — its clap-host tests spawn nested out-of-workspace cargo builds of
  a fixture cdylib and cannot run in the sandboxed release-profile check env).
- Python bumps fail in `pythonRuntimeDepsCheck` (not `buildPhase`) when upstream
  turns an optional dependency into a hard one. Read the new `pyproject.toml`
  `dependencies` and declare exactly what is missing — respect markers (`pillow`,
  `mss`, `pyautogui`, `pyperclip` are unconditional in open-terminal 0.17.13
  while `pywinpty` is `sys_platform == 'win32'`, so it stays out of a
  linux-only package), and remember that `uvicorn[standard]` already supplies
  `watchfiles`/`psutil`/`websockets` through
  `++ uvicorn.optional-dependencies.standard`.
  If the check then rejects a *version* nixpkgs genuinely does not have, do not
  set `dontCheckRuntimeDeps` (it disables every other check): relax that one
  bound in `postPatch` with a comment saying why, after confirming the APIs used
  exist in the packaged version. Precedent: open-terminal needs
  `pyautogui>=0.9.54`, but 0.9.54 was never tagged on GitHub (PyPI sdist only —
  and its CRLF line endings break this tree's `fix-locateOnWindow-and-xlib.patch`),
  so nixpkgs still ships 0.9.53 everywhere and the bound is trimmed instead.

## Desktop item gotchas

- `makeDesktopItem` names the installed file `$out/share/applications/<name>.desktop`
  where `<name>` is the derivation's name, not the desktop app-id.
- Tree convention: `exec`/`tryExec` are bare binary names.
- This tree's `desktop-file-validate` rejects FDO extension keys that do not
  start with `X-`, including `Environment=`. To inject environment into a
  packaged launch, patch the installed file in postFixup instead (the
  copyDesktopItems hook runs earlier, in installPhase):
  `sed -i '1a Environment=...' $out/share/applications/<app>.desktop`.
- buildRustPackage auto-adds the `copyDesktopItems` hook when `desktopItems`
  is set.
- App icons: `install -d $out/share/icons` then
  `cp -r assets/app-icon/hicolor $out/share/icons`. The `hicolor` component
  must be kept (`share/icons/hicolor/<size>/apps/<id>.png`) — installing the
  size dirs directly under `share/icons/` makes launchers fall back to a
  generic icon. No `index.theme` is needed (upstream ships none and the
  merged-profile lookup works without one). Do not set `Inherits=hicolor`:
  this tree's hicolor-icon-theme setup hook would self-symlink the theme.

## Updating an existing package

`nix-update` rewrites `version`/`src.hash` (and `cargoHash`/`vendorHash`/
`npmDepsHash` when it can), but it does not repair a package whose *build or
check* breaks after the bump. With `--build` those failures surface immediately
and need the manual work described above: declare dependency sets upstream made
hard (Python, see the check-phase gotchas), trim a too-new `go.mod` directive,
or re-reveal a hash it left stale or copied from the wrong field. Build the
result and run the verification checklist before committing, one commit per
package, in the `<name>: <old> -> <new>` shape described under Formatting &
commits.

## Building & fetching (infrastructure)

- Heavy builds run on **aero-server** (user `gaj`, ~24 cores/91GB RAM, nix
  2.34.8 = same as local → identical drv hashes) and **mjolnir** (user `gaj`, 32
  cores/64GB, nix 2.34.8). Both trees live at `~/nixpkgs` — always rsync changed
  files there first; the remote build evaluates the remote copy. Spread heavy
  builds across both machines so they run in parallel. aero-server's committed
  HEAD may lag the local one (it relies on rsync'd working files), which is fine.
- Launch detached and poll for completion:
  `ssh aero-server 'nohup sh -c "nix build --impure --keep-failed --expr \"(import /home/gaj/nixpkgs {}).<app>\" --json > /tmp/<run>.json 2> /tmp/<run>.err; echo \$? > /tmp/<run>.rc" >/dev/null 2>&1 & echo launched'`
  Judge completion from the `--json` output (non-empty = success) and the
  `.err` text, not the rc file. A trailing `nix log ...` line in `.err` is a
  failure footer, not "in progress".
- Finished outs come back locally in seconds because each remote's store is
  exposed as a signed substituter: aero-server as **bc-ga.eljam.es** (also
  configured as `binarycache.steam.home.arpa`) and mjolnir as
  **https://binarycache.mjolnir.home.arpa** (nginx in front of nix-serve on
  :8095; verify with
  `nix path-info --store 'https://binarycache.mjolnir.home.arpa' /nix/store/<path>`).
  Just run `nix build --impure --expr '(import /home/gaj/nixpkgs {}).<app>'` on
  this machine. Plain `nix copy --from ssh://...` fails on signature checks — do
  not bother.
- nix 2.34 CLI quirks here: no `--build-host`; expressions using callPackage
  args need `--impure`; there is no `import . {}` in `--expr` — use the
  absolute tree path; `nix-instantiate --check` does not exist, use `--eval`.
- Remote shell is zsh: quote all globs and brackets (NOMATCH aborts the whole
  command), escape `$?` when embedding in remote double quotes, and avoid words
  like `echo ===X===` (`=cmd` expansion). No system bunzip/python on the remote;
  drv logs are `/nix/var/log/nix/drvs/<2>/<rest>.drv.bz2` — scp them locally
  and `bzip2 -dc`.
- The local shell is zsh as well, so an unquoted command substitution is NOT
  word-split: `nixfmt --check $(git ls-files 'pkgs/by-name/*/*.nix')` hands the
  whole newline-separated list over as ONE argument and dies with
  `openFile: does not exist`. Pipe file lists through `xargs` (or use `${(f)"$(...)"}`).
- `./update.sh` at the repo root is the bump driver: one
  `nix-update --build --commit -u <attr>` per package, and `nix-update --commit`
  writes the `<name>: <old> -> <new>` subject the tree already uses (so a manual
  fix-up commit should use the same shape). A commented-out line is a deliberate
  skip, not damage — libunibreak, for instance, is already at its newest tag
  (`libunibreak_8_0`, version 8.0) and builds fine, so verify before "fixing" it.
  `update.sh` is tracked (added by `860df5f70605`); keep it in sync with the tree.

## Verification checklist (per app)

- `bin/<app>` and `bin/<app>-cli` present; `<app>-cli --version` exits 0.
- `readelf -d bin/<app> | grep RUNPATH` lists every library from the rule above
  (store dir names are lowercase, e.g. `libxi-1.8.3`).
- Desktop file at `$out/share/applications/<app>.desktop`: bare `Exec=`/
  `TryExec=`, `StartupWMClass`, `GenericName`, icon entries present.
- Icons installed under `share/icons/hicolor/<size>/apps/` (count matches
  upstream assets; cadcraft lacks a `scalable` dir).
- Font licences: `share/doc/<app>-<ver>/OFL-<family>.txt` per bundled family
  (photocraft pins an older craft-fonts rev and carries exactly three Japanese
  families; the rest carry five).
- Fake-display launch: `DISPLAY=:99 bin/<app>` must fail only with
  `WinitEventLoop(... XOpenDisplayFailed)` — no "opening library failed".

## Formatting & commits

- **IMPORTANT: after ANY change — including rebase conflict resolutions — run
  `nixfmt` (the rfc-style formatter) over every modified `.nix` file before
  continuing the rebase, committing, or pushing.** Hand-resolved conflicts and
  auto-merged files both count; never push an unformatted file. Get the binary
  (currently 1.5.0) with:

  ```
  nix build --impure --no-link --print-out-paths --expr '(import /home/gaj/nixpkgs {}).nixfmt-rfc-style'
  ```

  then check per file: `<bin>/bin/nixfmt --check pkgs/by-name/.../package.nix`
  (exit 0 = clean; drop `--check` to rewrite). This is the formatter the
  committed tree satisfies: over the first 200 `pkgs/by-name/*/*.nix` files, and
  over `pkgs/top-level/all-packages.nix`, `nixfmt --check` reports zero changes.
  Do NOT use `nixpkgs-fmt` (1.3.0) any more — it rewrites top parameter blocks
  into leading-comma style and flags 197 of those 200 by-name files as needing a
  reformat, and a full-file run over `all-packages.nix` churns ~700 unrelated
  lines. If a formatter disagrees with a file's existing style, hand-apply your
  change in the surrounding style instead of reformatting.
- Commit style: one focused commit per package, subject `<name>: init at <version>`
  (or `<name>: <imperative change>`), body explaining non-obvious choices, and a
  closing `Assisted-by: <model>` trailer when AI-assisted. Do not reformat
  unrelated files inside functional commits.
