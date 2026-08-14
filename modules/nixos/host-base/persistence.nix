# Impermanence baseline for full hosts. The root is a tmpfs, and /var/lib and /var/log are persisted whole, so a service keeps its state directory and its ownership across reboots.
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
