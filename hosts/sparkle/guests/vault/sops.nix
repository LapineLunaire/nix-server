{...}: {
  sops = {
    defaultSopsFile = ./secrets.yaml;
    # The pool's passphrase, read by vault-unlock.service. The same string the pool prompts for when imported anywhere else.
    secrets."vault-zfs-key" = {};
    # smartd's alerts leave through msmtp, which reads this at send time.
    secrets."smartd-smtp-password" = {};
  };
}
