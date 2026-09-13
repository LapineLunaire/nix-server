{
  config,
  lib,
  ...
}: let
  # Each secret contains an nftables elements statement; an empty file permits no addresses.
  v4 = config.sops.secrets."ssh-allowed-ips-v4".path;
  v6 = config.sops.secrets."ssh-allowed-ips-v6".path;
  ports = lib.concatMapStringsSep ", " toString config.services.openssh.ports;
in {
  sops.secrets."ssh-allowed-ips-v4".reloadUnits = ["nftables.service"];
  sops.secrets."ssh-allowed-ips-v6".reloadUnits = ["nftables.service"];

  # Keep client addresses out of the store. This table vetoes SSH before nixos-fw runs.
  # Loopback and tunnel clients must also be listed.
  networking.nftables.tables.ssh-ip-whitelist = {
    family = "inet";
    content = ''
      set allowed4 {
        type ipv4_addr
        flags interval
        auto-merge
        include "${v4}"
      }

      set allowed6 {
        type ipv6_addr
        flags interval
        auto-merge
        include "${v6}"
      }

      chain input {
        type filter hook input priority filter - 1;
        tcp dport { ${ports} } ip saddr != @allowed4 drop
        tcp dport { ${ports} } ip6 saddr != @allowed6 drop
      }
    '';
  };

  # Runtime secrets are unavailable during the build-time ruleset check.
  networking.nftables.preCheckRuleset = ''
    sed -i '\|include "${v4}"|d; \|include "${v6}"|d' ruleset.conf
  '';
}
