# sparkle's auto-update: the shared signed switch with no reboot, then a restart of the guests whose config the switch changed.
{
  config,
  outputs,
  pkgs,
  ...
}: let
  # Restart only guests whose booted runner differs from the one the switch installed.
  restartGuests = pkgs.writeShellScript "restart-microvm-guests" ''
    set -euo pipefail
    systemctl() { ${config.systemd.package}/bin/systemctl "$@"; }
    for unit in $(systemctl list-units --state=active --plain --no-legend 'microvm@*.service' | ${pkgs.gawk}/bin/awk '{print $1}'); do
      name=''${unit#microvm@}
      name=''${name%.service}
      dir=/var/lib/microvms/$name
      if [ "$(readlink -f "$dir/booted" 2>/dev/null)" != "$(readlink -f "$dir/current" 2>/dev/null)" ]; then
        systemctl restart "$unit"
      fi
    done
  '';
in {
  imports = [outputs.nixosModules.auto-update];

  host.autoUpdate = {
    owner = "carmilla";
    branch = "main";
  };

  # No reboot: a kernel change is applied deliberately, since rebooting takes the whole fleet down with the host.
  system.autoUpgrade.allowReboot = false;
  systemd.services.nixos-upgrade.serviceConfig.ExecStartPost = restartGuests;
}
