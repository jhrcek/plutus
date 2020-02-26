let
  packageSet = import ./default.nix {};
  pkgs = packageSet.pkgs;
in {
  libs = packageSet.localLib.collectComponents' "library" packageSet.local-packages-new;
  tests = packageSet.localLib.collectComponents' "tests" packageSet.local-packages-new;
  benchmarks = packageSet.localLib.collectComponents' "benchmarks" packageSet.local-packages-new;
}
