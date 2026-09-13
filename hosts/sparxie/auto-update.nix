{
  imports = [../../modules/nixos/auto-update.nix];

  host.autoUpdate = {
    owner = "carmilla";
    branch = "main";
  };
}
