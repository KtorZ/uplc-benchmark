{ fetchFromGitHub
, rustPlatform
, openssl
, pkg-config
, stdenv
, writeShellApplication
, python3
, lib
, fetchzip
, yj
, jq
, aiken-src ? {
    version = "1.0.23-alpha";
    hash = "sha256-MmEQVX66zXaK+rOOhaSHQm5kSDIfQTzmWozfsJIzt/M=";
  }
}:

let
  aiken = rustPlatform.buildRustPackage rec {
    pname = "aiken";
    inherit (aiken-src) version;

    src = fetchFromGitHub {
      owner = "aiken-lang";
      repo = "aiken";
      rev = aiken-src.rev or "v${aiken-src.version}";
      inherit (aiken-src) hash;
    };

    cargoLock = {
      lockFile = "${src}/Cargo.lock";
    };

    buildInputs = [
      openssl
    ];

    nativeBuildInputs = [
      pkg-config
    ];
  };

  mkPythonApplication = name: path: writeShellApplication {
    inherit name;

    runtimeInputs = [
      python3
    ];

    text = "python3 ${path}";
  };

  aiken2nix = mkPythonApplication "aiken2nix" ./aiken2nix.py;
  aiken2bin = mkPythonApplication "aiken2bin" ./aiken2bin.py;

  mkPackage = args:
    let
      fetchPackage = { url, hash }: fetchzip {
        inherit url hash;
      };

      vendorPackage = name: p: ''
        cp --no-preserve=all -r ${fetchPackage p} ./build/packages/${name}
      '';

      aikenNixLockPath = "${args.src}/aiken-nix.lock";

      aikenNixLock =
        if builtins.pathExists aikenNixLockPath
        then builtins.readFile aikenNixLockPath
        else throw "File ${aikenNixLockPath} does not exist. Run `aiken2nix` in root of your Aiken project to create it. Make sure to add it to git when using flakes.";
    in
    stdenv.mkDerivation (args // {
      nativeBuildInputs = [
        aiken
        aiken2bin
        yj
        jq
      ] ++ (args.nativeBuildInputs or [ ]);

      configurePhase = ''
        runHook preConfigure

        mkdir -p ./build/packages
        cat aiken.lock | yj -tj | jq '{packages: .requirements}' | yj -jt > ./build/packages/packages.toml
        ${builtins.concatStringsSep "\n"
          (lib.mapAttrsToList vendorPackage (builtins.fromJSON aikenNixLock))}
        
        runHook postConfigure
      '';

      buildPhase = ''
        runHook preBuild

        aiken build

        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall

        mkdir -p $out
        aiken2bin
        mv plutus.json $out

        runHook postInstall
      '';
    });

  preCommitAikenFmt = args: {
    name = "aiken-fmt";
    files = "\\.ak$";
    entry = "${aiken}/bin/aiken fmt";
  } // args;
in
{
  inherit mkPackage;

  packages = {
    inherit aiken aiken2nix aiken2bin;
  };

  preCommit = {
    aikenFmt = preCommitAikenFmt;
  };
}
