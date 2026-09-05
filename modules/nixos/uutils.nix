# GNU coreutils, findutils, and diffutils swapped for the uutils reimplementations across the system closure.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # replaceDependencies rewrites store paths in place, so each replacement name is padded to the exact length of the name it displaces.
  replace = old: base: new: {
    oldDependency = old;
    newDependency = pkgs.symlinkJoin {
      name = base + builtins.concatStringsSep "" (builtins.genList (_: "_") (builtins.stringLength old.name - builtins.stringLength base));
      paths = [new];
    };
  };

  replacementsFor = p: [
    (replace p.coreutils-full "coreuutils-full" p.uutils-coreutils-noprefix)
    (replace p.coreutils "coreuutils" p.uutils-coreutils-noprefix)
    (replace p.findutils "finduutils" p.uutils-findutils)
    (replace p.diffutils "diffuutils" p.uutils-diffutils)
  ];
in {
  # An entry matches one store path, and one absent from the closure is warned about on every eval. The 32-bit multilib tree exists only where the graphics stack enables it, and coreutils is the only one of the four that it pulls in.
  system.replaceDependencies.replacements =
    replacementsFor pkgs
    ++ lib.optional config.hardware.graphics.enable32Bit
    (replace pkgs.pkgsi686Linux.coreutils "coreuutils" pkgs.pkgsi686Linux.uutils-coreutils-noprefix);
}
