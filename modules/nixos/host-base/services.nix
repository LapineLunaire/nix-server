# The services every full host runs: fstrim, fwupd, NTS-authenticated chrony, and sshd, plus the sops age key derived from the persisted host key.
{...}: {
  services.fstrim.enable = true;
  services.fwupd.enable = true;

  # NTS (RFC 8915) authenticates the time source over TLS, which prevents an on-path attacker from spoofing responses.
  services.chrony = {
    enable = true;
    enableNTS = true;
    servers = ["time.cloudflare.com"];
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      AuthenticationMethods = "publickey";
    };
    # sops-nix derives its age decryption key from this host key.
    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  # Points at the persisted copy, which sits on a real filesystem marked neededForBoot, so the key is readable whenever sops-nix runs. Each host's sops.nix adds its own defaultSopsFile and secrets.
  sops.age.sshKeyPaths = ["/persist/etc/ssh/ssh_host_ed25519_key"];
}
