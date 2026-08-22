# Impermanence baseline for full hosts. The root is a tmpfs, and /var/lib and /var/log are persisted whole, so a service keeps its state directory and its ownership across reboots. host-base/services.nix derives the sops age key from the SSH host key persisted here, and hosts add anything outside /var in their own persistence.nix.
{...}: {
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/lib"
      "/var/log"
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
    ];
  };
}
