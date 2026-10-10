# AGENTS.md

Working notes for agents contributing to this nixpkgs fork, distilled from the
craft app-suite packaging effort (2026-10). Read this before touching
`pkgs/by-name/`.

## Repository layout

This is a reorganized nixpkgs fork. `pkgs/top-level/all-packages.nix` is
slimmed; most packages live in the standard `pkgs/by-name/<two letters>/<name>/`
shard tree, wired up by `pkgs/topplevel/by-name-overlay.nix` via
`self.callPackage file {}`. Consequences:

- The top-level attribute name is exactly the directory basename.
- There is NO kebab-to-camel aliasing: a hyphenated sibling such as
  `craft-fonts` is only reachable through its explicit all-packages entry
  (e.g. `craftFonts = callPackage ../by-name/cr/craft-fonts/package.nix { };`).
  Add the alias line if another package consumes it via callPackage args.
- Any top-level attr is a valid callPackage argument, so prefer referencing
  sibling packages as bare args instead of re-fetching.

## Packaging a new craft app (workflow)

1. Clone the source (`github.com/storytold/<app>`) and inspect: binaries in
   `cargoBuildFlags` (app + `<app>-cli`), whether `build.rs` reads
   `CRAFT_FONTS_DIR` (font embedding at compile time — no runtime Env= needed),
   desktop file in `packaging/linux/`, icons in `assets/app-icon/hicolor/`,
   and which C libraries its Rust stack dlopens at runtime.
2. Write `pkgs/by-name/<xx>/<app>/package.nix` using
   `pkgs/by-name/gr/gridcraft/package.nix` as the template.
3. Fetch src with `fetchFromGitHub`; set `cargoLock = { lockFile = ... }`.
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

## Verification checklist (per app)

- `bin/<app>` and `bin/<app>-cli` present; `<app>-cli --version` exits 0.
- `readelf -d bin/<app> | grep RUNPATH` lists every library from the rule above
  (store dir names are lowercase, e.g. `libxi-1.8.3`).
- Desktop file at `$out/share/applications/<app>.desktop`: bare `Exec=`/
  `TryExec=`, `StartupWMClass`, `GenericName`, icon entries present.
- Icons installed under `share/icons/hicolor/` (count matches upstream assets;
  deckcraft ships one fewer size than the others).
- Font licences: `share/doc/<app>-<ver>/OFL-<family>.txt` per bundled family
  (photocraft pins an older craft-fonts rev and carries exactly three Japanese
  families; the rest carry five).
- Fake-display launch: `DISPLAY=:99 bin/<app>` must fail only with
  `WinitEventLoop(... XOpenDisplayFailed)` — no "opening library failed".

## Formatting & commits

- Format touched `package.nix` files with nixpkgs-fmt
  (`(import /home/gaj/nixpkgs {}).nixpkgs-fmt`, currently 1.3.0). Do NOT run it
  over `pkgs/top-level/all-packages.nix`: the committed baseline is not clean
  under this fmt version and a full-file format churns ~700 unrelated lines —
  hand-apply your single entry in the surrounding style instead.
- Commit style: one focused commit per package, subject `<name>: init at <version>`
  (or `<name>: <imperative change>`), body explaining non-obvious choices, and a
  closing `Assisted-by: <model>` trailer when AI-assisted. Do not reformat
  unrelated files inside functional commits.
