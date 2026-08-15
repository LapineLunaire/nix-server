# Host-side wiring for the microVM guests: one autostarted guest per registry entry, each guest's tap interface attached to the bridge, and startup ordering taken from the registry's deps.
# Takes the guest registry and the bridge its taps join and returns the host-side module; the bridge itself and the forward policy over it are the host's own network config.
{
  registry,
  bridge,
}: {
  lib,
  outputs,
  ...
}: {
  # Offer the host key when microvm -s connects to a guest as root over VSOCK; guests authorize it for root (see guest.nix).
  programs.ssh.extraConfig = ''
    Host vsock/* vsock-mux/*
      IdentityFile /etc/ssh/ssh_host_ed25519_key
      IdentitiesOnly yes
  '';

  microvm.vms =
    lib.mapAttrs (name: _: {
      autostart = true;
      evaluatedConfig = outputs.nixosConfigurations.${name};
    })
    registry;

  # Attach each VM's tap interface to the bridge. The 20-vm- prefix namespaces these away from the host's own network units, so a VM whose name matches one of the host's interfaces can't land on the same attribute.
  systemd.network.networks = lib.mapAttrs' (name: _:
    lib.nameValuePair "20-vm-${name}" {
      matchConfig.Name = name;
      networkConfig.Bridge = bridge;
    })
  registry;

  systemd.services = lib.mapAttrs' (name: vm:
    lib.nameValuePair "microvm@${name}" {
      after = map (dep: "microvm@${dep}.service") (vm.deps or []);
      wants = map (dep: "microvm@${dep}.service") (vm.deps or []);
    })
  registry;
}
