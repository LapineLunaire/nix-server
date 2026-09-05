# The nixpkgs overlays every instance carries: additions exposes pkgs/ as pkgs.<name>, and modifications overrides nixpkgs packages.
{
  additions = final: _prev: import ../pkgs final;

  modifications = _final: prev: {
    # uutils mv prompts before overwriting a read-only or symlinked destination where GNU mv stays silent, and activation replaces /bin/sh and /usr/bin/env that way as root. uutils-coreutils-noprefix inherits the patch through its own override.
    uutils-coreutils = prev.uutils-coreutils.overrideAttrs (old: {
      patches = (old.patches or []) ++ [./patches/uutils-mv-writable-destination.patch];
    });
  };
}
