{
  sops = {
    defaultSopsFile = ./secrets.yaml;
    # Also keep this passphrase available for recovery outside the guest.
    secrets."vault-zfs-key" = {};
    # smartd's alerts leave through msmtp, which reads this at send time.
    secrets."smartd-smtp-password" = {};
  };
}
