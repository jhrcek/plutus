############################################################################
# Extra Haskell packages which we build with haskell.nix, but which aren't
# part of our project's package set themselves.
#
# These are for e.g. developer usage, or for running formatting tests.
############################################################################
{ pkgs }:
{
  cabal-install = pkgs.haskell-nix.hackage-package { name = "cabal-install"; version = "2.4.1.0"; };
  stylish-haskell = pkgs.haskell-nix.hackage-package { name = "stylish-haskell"; version = "0.9.2.2"; };
  hlint = pkgs.haskell-nix.hackage-package { name = "hlint"; version = "2.1.12"; };
  purty =
    let hspkgs = pkgs.haskell-nix.stackProject {
        src = pkgs.fetchFromGitLab {
          owner = "joneshf";
          repo = "purty";
          rev = "3c073e1149ecdddd01f1d371c70d5b243d743bf2";
          sha256 = "0j8z9661anisp4griiv5dfpxarfyhcfb15yrd2k0mcbhs5nzhni0";
        };
        pkg-def-extras = [
          # Workaround for https://github.com/input-output-hk/haskell.nix/issues/214
          (hackage: {
            packages = {
              "hsc2hs" = (((hackage.hsc2hs)."0.68.4").revisions).default;
            };
          })
        ];
      };
    in hspkgs.purty;
}
