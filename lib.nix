{ system ? builtins.currentSystem, config ? {} }:
let
  sources = import ./nix/sources.nix;

  iohkNix = import sources.iohk-nix {
    inherit system config;
    # FIXME: should be 'nixpkgsOverride = sources.nixpkgs', but see https://github.com/input-output-hk/iohk-nix/pull/215
    nixpkgsJsonOverride = ./nixpkgs.json;
  };
  legacyIohkNix = import sources.iohk-nix-old {
    inherit system config;
    # FIXME: should be 'nixpkgsOverride = sources.nixpkgs', but see https://github.com/input-output-hk/iohk-nix/pull/215
    nixpkgsJsonOverride = ./nixpkgs.json;
  };

  nixpkgs = iohkNix.nixpkgs;
  pkgs = iohkNix.getPkgs { extraOverlays = [ (import ./nix/overlays/musl.nix) (import ./nix/overlays/nixpkgs-overrides.nix) ]; };
  lib = pkgs.lib;
  getPackages = { haskellPackages, filter , f ? null }:
    let filtered = lib.filterAttrs (name: drv: filter name) haskellPackages;
    in if f == null then filtered else lib.mapAttrs f filtered;

  # Haskell.nix versions of these are broken in some cases, see https://github.com/input-output-hk/haskell.nix/issues/457
  collectComponents = group: packageSel: haskellPackages:
    let packageToComponents = package:
          let components = package.components.${group} or {};
          in if lib.isDerivation components || components == {}
             then components
             else pkgs.recurseIntoAttrs components;
        packageFilter = package: (package.isHaskell or false) && packageSel package;
    in pkgs.recurseIntoAttrs (lib.filterAttrs (_: components: components != {}) (lib.mapAttrs (_: packageToComponents) (lib.filterAttrs (_: packageFilter) haskellPackages)));
  collectComponents' = group: collectComponents group (_: true);

  # List of all public (i.e. published Haddock, will go on Hackage) Plutus pkgs
  plutusPublicPkgList = [
    "language-plutus-core"
    "plutus-contract"
    "plutus-contract-tasty"
    "plutus-playground-lib"
    "plutus-exe"
    "plutus-ir"
    "plutus-tx"
    "plutus-tx-plugin"
    "plutus-wallet-api"
    "plutus-emulator"
    "plutus-scb"
    "iots-export"
    "marlowe-hspec"
  ];

  isPublicPlutus = name: builtins.elem name plutusPublicPkgList;

  # List of all Plutus packges in this repository.
  plutusPkgList = plutusPublicPkgList ++ [
    "plutus-playground-server"
    "plutus-tutorial"
    "plutus-book"
    "plutus-use-cases"
    "playground-common"
    "marlowe"
    "marlowe-playground-server"
    "deployment-server"
    "marlowe-symbolic"
  ];

  isPlutus = name: builtins.elem name plutusPkgList;

  regeneratePackages = legacyIohkNix.stack2nix.regeneratePackages { hackageSnapshot = "2020-01-13T00:00:00Z"; };

  unfreePredicate = pkg:
      let unfreePkgs = [ "kindlegen" ]; in
      if pkg ? name then builtins.elem (builtins.parseDrvName pkg.name).name unfreePkgs
      else if pkg ? pname then builtins.elem pkg.pname unfreePkgs
      else false;

  comp = f: g: (v: f(g v));

in lib // {
  inherit
  getPackages
  collectComponents
  collectComponents'
  iohkNix
  # FIXME: legacy iohk nix is needed to support the old haskell infrastructure.
  legacyIohkNix
  isPlutus
  isPublicPlutus
  plutusPublicPkgList
  plutusPkgList
  regeneratePackages
  unfreePredicate
  nixpkgs
  pkgs
  comp;
}
