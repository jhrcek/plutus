let
  systemBuilds = system:
    let
      packageSet = import ./default.nix { inherit system; };
      pkgs = packageSet.pkgs;
    in pkgs.recurseIntoAttrs {
      libs = packageSet.localLib.collectComponents' "library" packageSet.local-packages-new;
      tests = packageSet.localLib.collectComponents' "tests" packageSet.local-packages-new;
      benchmarks = packageSet.localLib.collectComponents' "benchmarks" packageSet.local-packages-new;
    };
  linux = ["x86_64-linux"];
  darwin = ["x86_64-darwin"];
  systems = linux ++ darwin;
in builtins.listToAttrs (builtins.map (system: { name = system; value = systemBuilds system; }) systems)
