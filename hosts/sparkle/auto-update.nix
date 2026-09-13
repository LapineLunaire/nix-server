{
  config,
  pkgs,
  ...
}: {
  imports = [../../modules/nixos/auto-update.nix];

  host.autoUpdate = {
    owner = "carmilla";
    branch = "main";
  };

  # The encrypted root pool requires an interactive unlock; reboot manually for kernel updates.
  system.autoUpgrade.allowReboot = false;
  systemd.services.nixos-upgrade.serviceConfig.ExecStartPost =
    # Restart guests whose installed runner differs from the booted one.
    pkgs.writeShellScript "restart-microvm-guests" ''
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
}
