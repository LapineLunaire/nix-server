{lib, ...}: {
  imports = [
    (import ../../../modules/nixos/borg-backup.nix {
      pool = "sparxie";
      startAt = "03:00";
    })
    ../../../modules/nixos/acme.nix
    ../../../modules/nixos/caddy.nix
    ../../../modules/nixos/wireguard-tunnel.nix
    ./database.nix
    ./ejabberd.nix
    ./fail2ban.nix
    ./proxy.nix
    ./tuwunel.nix
  ];

  # The VPS has no firmware to manage.
  services.fwupd.enable = lib.mkForce false;
}
