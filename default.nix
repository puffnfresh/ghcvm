with import <nixpkgs> { };

let
  rootName = name: builtins.elemAt (lib.splitString "/" name) 0;
  isValidFile = name: files: builtins.elem (rootName name) files;
  relative = path: name: lib.removePrefix (toString path + "/") name;
  onlyFiles = files: path: builtins.filterSource (name: type: isValidFile (relative path name) files) path;

  eta-nix = fetchTarball "https://github.com/eta-lang/eta-nix/archive/1638c3f133a3931ec70bd0d4f579b67fd62897e2.tar.gz";

  rewriteRelative = top: path:
    let path' = lib.removePrefix top (builtins.toString path);
    in if lib.isStorePath path' then path' else ./. + path';

  overrides = self: super: {
    mkDerivation = args: super.mkDerivation (lib.overrideExisting args {
      src = rewriteRelative eta-nix args.src;
    });

    eta = haskell.lib.overrideCabal super.eta (drv: {
      # Makes the build a bit faster
      src = onlyFiles ["compiler" "include" "eta" "eta.cabal" "LICENSE" "tests"] drv.src;
    });
  };
  hpkgs = (import eta-nix { }).override { inherit overrides; };
  eta-hackage = fetchFromGitHub {
    owner = "typelead";
    repo = "eta-hackage";
    rev = "750c5db0b500b6da849406b6d02c06220f67e0f8";
    sha256 = "115qyqxniwq0sj7lbwp3yjbsz5vzha7jsjav8bjw7nr0gpfpcmk4";
  };

  patchedSource = { pname, version, sha256 }:
    stdenv.mkDerivation rec {
      name = "${pname}-${version}";
      src = fetchurl {
        url = "mirror://hackage/${name}.tar.gz";
        inherit sha256;
      };
      installPhase = ''
        patch -p1 --merge < "${eta-hackage}/patches/${name}.patch"
        cp "${eta-hackage}/patches/${name}.cabal" "${pname}.cabal"
        cp -r . "$out"
      '';
      dontBuild = true;
      dontFixup = true;
      passthru = { inherit pname; };
    };

  etlasConfig = writeText "etlas-config" ''
    auto-update: False
    send-metrics: False
    remote-build-reporting: none
  '';

  etaPkgWrapper = runCommandNoCC "eta-pkg-wrapper" {
    nativeBuildInputs = [ makeWrapper ];
  } ''
    makeWrapper ${hpkgs.eta-pkg}/bin/eta-pkg $out/bin/eta-pkg \
      --run 'extraFlagsArray=("--global-package-db=$TMPDIR/package.conf.d")'
    '';

  etlasWrapper = runCommandNoCC "etlas-wrapper" {
    nativeBuildInputs = [ makeWrapper ];
  } ''
    makeWrapper ${hpkgs.etlas}/bin/etlas $out/bin/etlas \
      --run 'export HOME=$TMPDIR/home' \
      --run 'mkdir -p "$HOME/.etlas/binaries"' \
      --run 'echo "\$PATH\n\$PATH\n\$PATH" > "$HOME/.etlas/binaries/eta"' \
      --run 'cat "${etlasConfig}" > $HOME/.etlas/config' \
      --prefix PATH : "${lib.makeBinPath [ hpkgs.eta etaPkgWrapper ]}"
    '';
in
hpkgs // {
  etaPackages = rec {
    callPackage = { pname, version, src, libraryHaskellDepends ? [], postInstall ? "" }:
      stdenv.mkDerivation ({
        name = "${pname}-${version}";
        inherit src;
        outputs = [ "out" "data" "doc" ];

        buildInputs = [ jdk etlasWrapper hpkgs.eta-pkg ];

        propagatedBuildInputs = libraryHaskellDepends;

        prePhases = [ "setupCompilerEnvironmentPhase" ];
        setupCompilerEnvironmentPhase = ''
          packageConfDir="$TMPDIR/package.conf.d"
          mkdir -p $packageConfDir

          for p in "''${pkgsHostHost[@]}" "''${pkgsHostTarget[@]}"; do
            if [ -d "$p/lib/${hpkgs.eta.name}/package.conf.d" ]; then
              cp -f "$p/lib/${hpkgs.eta.name}/package.conf.d/"*.conf "$packageConfDir/"
              continue
            fi
          done

          HOME=$TMPDIR/home eta-pkg --package-db="$packageConfDir" recache
        '';
        configurePhase = ''
          etlas configure \
             --allow-boot-library-installs
        '';
        buildPhase = ''
          etlas build \
             --allow-boot-library-installs \
             --package-db="$packageConfDir"
        '';
        installPhase = ''
          etlas install \
             --libdir="$out/lib" \
             --datadir="$data/share/${hpkgs.eta.name}" \
             --docdir="$doc/share/doc/${pname}-${version}" \
             --allow-boot-library-installs \
             --package-db="$packageConfDir"

          packageConfDir="$out/lib/${hpkgs.eta.name}/package.conf.d"
          packageConfFile="$packageConfDir/${pname}-${version}.conf"
          mkdir -p "$packageConfDir"
          etlas register --gen-pkg-config=$packageConfFile

          mkdir -p $doc $data

          runHook postInstall
        '';
      }
      // lib.optionalAttrs (postInstall != "")    { inherit postInstall; }
      );

    containers = callPackage rec {
      pname = "containers";
      version = "0.5.10.2";
      src = patchedSource {
        inherit pname version;
        sha256 = "08wc6asnyjdvabqyp15lsbccqwbjy77zjdhwrbg2q9xyj3rgwkm0";
      };
      libraryHaskellDepends = [ base deepseq ];
    };
    binary = callPackage rec {
      pname = "binary";
      version = "0.8.5.1";
      src = patchedSource {
        inherit pname version;
        sha256 = "15h5zqfw7xmcimvlq6bs8f20vxlfvz7g411fns5z7212crlimffy";
      };
      libraryHaskellDepends = [ base array containers bytestring ];
    };
    bytestring = callPackage rec {
      pname = "bytestring";
      version = "0.10.8.2";
      src = patchedSource {
        inherit pname version;
        sha256 = "0fjc5ybxx67l0kh27l6vq4saf88hp1wnssj5ka90ii588y76cvys";
      };
      libraryHaskellDepends = [ base deepseq ];
    };
    time = callPackage rec {
      pname = "time";
      version = "1.8.0.3";
      src = patchedSource {
        inherit pname version;
        sha256 = "0mbz76v74q938ramsgipgsvk8hvnplcnffplaq439z202zkyar1h";
      };
      libraryHaskellDepends = [ base deepseq ];
    };
    filepath = callPackage rec {
      pname = "filepath";
      version = "1.4.1.2";
      src = patchedSource {
        inherit pname version;
        sha256 = "1hrbi7ckrkqzw73ziqiyh00xp28c79pk0jrj1vqiq5nwfs3hryvv";
      };
      libraryHaskellDepends = [ base ];
    };
    directory = callPackage rec {
      pname = "directory";
      version = "1.3.1.0";
      src = patchedSource {
        inherit pname version;
        sha256 = "1wm738bqz8b8mpkviv0y6v6dypxjsm50silfvjwy64c3p9md1c4l";
      };
      libraryHaskellDepends = [ base filepath time ];
    };
    eta-boot = callPackage rec {
      pname = "eta-boot";
      version = "0.8.4";
      src = ./libraries/eta-boot;
      libraryHaskellDepends = [ base binary bytestring directory filepath eta-boot-meta ];
    };
    eta-meta = callPackage rec {
      pname = "eta-meta";
      version = "0.8.4.1";
      src = ./libraries/eta-meta;
      libraryHaskellDepends = [ base pretty eta-repl eta-boot ];
    };
    eta-boot-meta = callPackage rec {
      pname = "eta-boot-meta";
      version = "0.8.4";
      src = ./libraries/eta-boot-meta;
      libraryHaskellDepends = [ base ];
    };
    eta-repl = callPackage rec {
      pname = "eta-repl";
      version = "0.8.4.1";
      src = ./libraries/eta-repl;
      libraryHaskellDepends = [ base eta-boot-meta deepseq bytestring binary ];
    };
    deepseq = callPackage rec {
      pname = "deepseq";
      version = "1.4.3.0";
      src = patchedSource {
        inherit pname version;
        sha256 = "0fjdmsd8fqqv78m7111m10pdfswnxmn02zx1fsv2k26b5jckb0bd";
      };
      libraryHaskellDepends = [ base array ];
    };
    pretty = callPackage rec {
      pname = "pretty";
      version = "1.1.3.6";
      src = patchedSource {
        inherit pname version;
        sha256 = "1s363nax6zxqs4bnciddsfc2sanv1lp4x02y58z3yzdgrciwq4pb";
      };
      libraryHaskellDepends = [ base deepseq ];
    };
    template-haskell = callPackage rec {
      pname = "template-haskell";
      version = "2.11.1.0";
      src = patchedSource {
        inherit pname version;
        sha256 = "171ngdd93i9prp9d5a4ix0alp30ahw2dvdk7i8in9mzscnv41csz";
      };
      libraryHaskellDepends = [ base eta-meta ];
    };
    array = callPackage rec {
      pname = "array";
      version = "0.5.2.0";
      src = patchedSource {
        inherit pname version;
        sha256 = "12v83s2imxb3p2crnlzrpjh0nk6lpysw9bdk9yahs6f37csa5jaj";
      };
      libraryHaskellDepends = [ base ];
    };
    base = callPackage rec {
      pname = "base";
      version = "4.11.1.0";
      src = ./libraries/base;
      libraryHaskellDepends = [ rts ghc-prim integer ];
    };
    integer = callPackage rec {
      pname = "integer";
      version = "0.5.1.0";
      src = ./libraries/integer;
      libraryHaskellDepends = [ ghc-prim ];
    };
    ghc-prim = callPackage rec {
      pname = "ghc-prim";
      version = "0.4.0.0";
      src = ./libraries/ghc-prim;
      libraryHaskellDepends = [ rts ];
      postInstall = ''
        awk -i inplace \
          '{ if ( $1 !~ /GHC\./ ) { print $0 } else { gsub(/^ */, "", $0); print "    GHC.Prim " $0 } }' \
          $packageConfDir/*
      '';
    };
    rts = callPackage rec {
      pname = "rts";
      version = "0.1.0.0";
      src = ./libraries/rts;
    };
  };

  eta-build-shell = runCommand "eta-build-shell" {
    # Libraries don't pass -encoding to javac.
    LC_ALL = "en_US.utf8";
    buildInputs = [
      hpkgs.eta
      hpkgs.eta-build
      hpkgs.eta-pkg
      hpkgs.etlas
      gitMinimal
      jdk
      glibcLocales
    ];
  } "";

  shells = {
    ghc = hpkgs.shellFor {
      packages = p: [
        p.eta
        p.codec-jvm
        p.eta-boot
        p.eta-boot-meta
        p.eta-meta
        p.eta-repl
        p.eta-pkg
        p.etlas
        p.etlas-cabal
        p.hackage-security
        p.shake
        ];
    };
  };
}
