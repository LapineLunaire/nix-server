# sshd reachable only from the addresses in the two whitelist secrets: an nftables veto table that runs ahead of the nixos-fw table and drops anything else aimed at sshd's ports. For a system whose trusted clients are external addresses rather than a subnet.
# The counterpart to trusted-ssh-ingress.nix, which admits a fixed set of subnets instead. A system takes one or the other.
{
  config,
  lib,
  ...
}: let
  # Each secret holds an nftables elements statement, e.g. elements = { x.x.x.x, x.x.x.0/24 }. An empty file allows no source of that family.
  v4 = config.sops.secrets."ssh-allowed-ips-v4".path;
  v6 = config.sops.secrets."ssh-allowed-ips-v6".path;
  # sshd's own ports, so a change there cannot leave the whitelist behind.
  ports = lib.concatMapStringsSep ", " toString config.services.openssh.ports;
in {
  # Reload nftables when a whitelist changes, which re-reads the files the sets include.
  sops.secrets."ssh-allowed-ips-v4".reloadUnits = ["nftables.service"];
  sops.secrets."ssh-allowed-ips-v6".reloadUnits = ["nftables.service"];

  # The addresses are included from the runtime secret files so they stay out of the world-readable nix store.
  # This table only vetoes. The nixos-fw table still decides what is accepted, and runs after this one, since its input chain sits at priority filter. Nothing is exempt: loopback and tunnel traffic is dropped too unless listed.
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

  # The secret files do not exist in the build sandbox, so drop the include lines before the build-time ruleset check.
  networking.nftables.preCheckRuleset = ''
    sed -i '\|include "${v4}"|d; \|include "${v6}"|d' ruleset.conf
  '';
}
