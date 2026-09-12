# Expose the local packages as pkgs.<name> in every nixpkgs instance.
{
  additions = final: _prev: import ../pkgs final;
}
