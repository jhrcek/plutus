############################################################################
# Builds Haskell packages with Haskell.nix
############################################################################
{ lib
, stdenv
, pkgs
, haskell-nix
, buildPackages
, metatheory
}:

let
  pkgSet = haskell-nix.stackProject {
    src = ../.;
    # This turns the output into a fixed-output derivation, which speeds things
    # up, but means we need to invalidate this hash when we change things.
    stack-sha256 = "0k603r1x8waq8a22ph92vpchkisf6n8q1nbmpg6vm8j2dqf8lp1s";
    modules = [
        {
          nonReinstallablePkgs =
            [ "rts" "ghc-heap" "ghc-prim" "integer-gmp" "integer-simple" "base"
              "deepseq" "array" "ghc-boot-th" "pretty" "template-haskell"
              "ghc-boot"
              "ghc" "Cabal" "Win32" "array" "binary" "bytestring" "containers"
              "directory" "filepath" "ghc-boot" "ghc-compact" "ghc-prim"
              "ghci" "haskeline"
              "hpc"
              "mtl" "parsec" "process" "text" "time" "transformers"
              "unix" "xhtml"
              "stm" "terminfo"
            ];
          # See https://github.com/input-output-hk/plutus/issues/1213
          packages.marlowe.doHaddock = false;
          packages.plutus-use-cases.doHaddock = false;
          packages.plutus-scb.doHaddock = false;
          # HACK to get z3 on the path for these tests
          packages.marlowe-hspec.components.tests.marlowe-hspec-test.preCheck = ''
            PATH=${lib.makeBinPath [ pkgs.z3 ]}:$PATH
          '';
          # plc-agda is compiled from the Haskell source files generated from the Agda
          packages.plc-agda.src = "${metatheory.plutus-metatheory-compiled}/share/agda";
        }
     ];
    pkg-def-extras = [
      # Workaround for https://github.com/input-output-hk/haskell.nix/issues/214
      (hackage: {
        packages = {
          "hsc2hs" = (((hackage.hsc2hs)."0.68.4").revisions).default;
        };
      })
    ];
  };

in
  pkgSet
