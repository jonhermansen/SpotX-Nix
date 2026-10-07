{
  lib,
  bash,
  cctools,
  coreutils,
  findutils,
  gnugrep,
  gnused,
  makeBinaryWrapper,
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
      cctools
      DarwinTools
      makeBinaryWrapper
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

      substituteInPlace "$NIX_BUILD_TOP/spotx.sh" \
        --replace-fail /usr/bin/xattr true \
        --replace-fail /usr/bin/lipo ${lib.getExe' cctools "lipo"}
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
      # Wrap the Spotify binary so every launch includes --allow-upgrades=0,
      # a flag the native binary parses to skip the desktop auto-update
      # subsystem (strings: "Handling force-auto-update argument",
      # "Can't decode auto update parameters"). This stops the periodic
      # update poll that would otherwise raise the
      # AuthorizationExecuteWithPrivileges dialog and let Spotify swap the
      # SpotX-patched bundle for a vanilla download.
      chmod -R u+w "$out/Applications/Spotify.app/Contents/MacOS"
      mv "${clientBinary}" "${clientBinary}-real"
      makeBinaryWrapper "${clientBinary}-real" "${clientBinary}" \
        --add-flags "--allow-upgrades=0"

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
