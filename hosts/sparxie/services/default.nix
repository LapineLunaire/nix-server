{
  lib,
  outputs,
  ...
}: {
  imports = [
    (outputs.lib.mkBorgBackup {
      pool = "sparxie";
      startAt = "03:00";
    })
    outputs.nixosModules.acme
    outputs.nixosModules.caddy
    ./database.nix
    ./ejabberd.nix
    ./proxy.nix
    ./tuwunel.nix
  ];

  # sparxie is a VPS with no firmware to manage. host-base enables fwupd unconditionally, so overriding it needs mkForce.
  services.fwupd.enable = lib.mkForce false;
}
