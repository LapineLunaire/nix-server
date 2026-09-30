{
  sops = {
    defaultSopsFile = ./secrets.yaml;
    # Also keep this passphrase available for recovery outside the guest.
    secrets."vault-zfs-key" = {};
  };
}
