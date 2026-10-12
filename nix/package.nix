{
  lib,
  bash,
  coreutils,
  file,
  findutils,
  gnugrep,
  gnused,
  perl,
  spotify,
  unzip,
  util-linux,
  zip,
  spotxSource,
  DarwinTools,
  rcodesign,
  stdenv,
  system_cmds,
  spotxArgs ? [ ],
}:
let
  spotxVersionLine =
    lib.findFirst (line: lib.hasPrefix "buildVer=" line)
      (throw "Unable to determine the SpotX-Bash supported version")
      (lib.splitString "\n" (builtins.readFile "${spotxSource}/spotx.sh"));
  spotxVersion = lib.removeSuffix "\"" (lib.removePrefix "buildVer=\"" spotxVersionLine);
  inherit (stdenv.hostPlatform) isDarwin;
  numericVersion =
    version:
    let
      match = builtins.match "([0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+).*" version;
    in
    if match == null then throw "Unable to parse version ${version}" else builtins.head match;
  spotxVersionNumber = numericVersion spotxVersion;
  spotifyVersionNumber = numericVersion spotify.version;
  clientPath = if isDarwin then "$out/Applications" else "$out/share/spotify";
  clientRoot = if isDarwin then "${clientPath}/Spotify.app/Contents" else clientPath;
  clientBinary = if isDarwin then "${clientRoot}/MacOS/Spotify" else "${clientRoot}/spotify";
  xpuiPath = if isDarwin then "${clientRoot}/Resources/Apps" else "${clientRoot}/Apps";
  platformArgs = lib.optionals isDarwin [
    # -B enables SpotX-Bash's blockUpdates patch, which NUL-corrupts the
    # desktop-update/v2/update URL string in the Spotify Mach-O so the
    # native HTTP update poll goes to a bogus endpoint and 404s. The
    # patch exists upstream but only runs when this flag is set.
    "-B"
    "-S"
    "-F"
    spotify.version
  ];
in
spotify.overrideAttrs (old: {
  pname = "spotify-spotx";

  dontStrip = isDarwin || (old.dontStrip or false);

  nativeBuildInputs =
    (old.nativeBuildInputs or [ ])
    ++ [
      bash
      coreutils
      findutils
      gnugrep
      gnused
      perl
      unzip
      util-linux
      zip
    ]
    ++ lib.optionals isDarwin [
      DarwinTools
      file
      rcodesign
      system_cmds
    ];

  postInstall =
    assert lib.assertMsg (lib.versionAtLeast spotxVersionNumber spotifyVersionNumber) ''
      Nixpkgs Spotify ${spotify.version} is newer than SpotX-Bash ${spotxVersion}.
      Update the SpotX-Bash input before building spotify-spotx.
    '';
    (old.postInstall or "")
    + ''
      export HOME="$TMPDIR/spotx-home"
      export SPOTX_BUILD_MODE=true
      mkdir -p "$HOME"

      install -m755 ${spotxSource}/spotx.sh "$NIX_BUILD_TOP/spotx.sh"
    ''
    + lib.optionalString isDarwin ''
      chmod -R u+w "$out/Applications/Spotify.app"

      # /usr/bin/xattr → true: clearing extended attributes is a
      # macOS-quarantine escape with no equivalent in the Nix sandbox.
      # /usr/bin/file + /usr/bin/tr → nixpkgs equivalents for arch
      # detection. nixpkgs `file` reports Mach-O arch BEFORE the word
      # "executable" (and with trailing flags), whereas Apple's `file`
      # reports it AFTER with no flags, so the case patterns in
      # macos_client_arch() are rewritten to match the nixpkgs format.
      substituteInPlace "$NIX_BUILD_TOP/spotx.sh" \
        --replace-fail /usr/bin/xattr true \
        --replace-fail /usr/bin/file ${lib.getExe file} \
        --replace-fail /usr/bin/tr ${lib.getExe' coreutils "tr"} \
        --replace-fail '"mach-o 64-bit executable arm64")' '"mach-o 64-bit arm64 executable"*)' \
        --replace-fail '"mach-o 64-bit executable x86_64")' '"mach-o 64-bit x86_64 executable"*)'
    ''
    + ''
      ${lib.getExe bash} "$NIX_BUILD_TOP/spotx.sh" -P "${clientPath}" \
        ${lib.escapeShellArgs (platformArgs ++ spotxArgs)}

      rm -f "${clientBinary}.bak"
      rm -f "${xpuiPath}/xpui.bak"
    '';

  postFixup =
    (old.postFixup or "")
    + lib.optionalString isDarwin ''
      ${lib.getExe rcodesign} sign "$out/Applications/Spotify.app"
    '';

  passthru = (old.passthru or { }) // {
    inherit spotxVersion;
    inherit spotxVersionNumber spotifyVersionNumber;
    spotifyVersion = spotify.version;
    unpatchedSpotify = spotify;
  };

  meta = (old.meta or { }) // {
    description = "Spotify patched with SpotX-Bash";
  };
})
