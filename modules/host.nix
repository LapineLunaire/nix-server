# The host option namespace: deployment parameters each system defines for itself and modules read as config.host.*.
{
  config,
  lib,
  ...
}: {
  options.host = {
    trustedSubnets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "Client subnets trusted to reach this system's admin surfaces.";
    };

    trustedSubnetsNft = lib.mkOption {
      type = lib.types.str;
      default = builtins.concatStringsSep ", " config.host.trustedSubnets;
      readOnly = true;
      description = "The trusted subnets comma-joined for nftables set literals.";
    };

    flakePath = lib.mkOption {
      type = lib.types.str;
      description = "Path of this system's flake checkout, which nh and system.autoUpgrade build from.";
    };

    smtp = {
      host = lib.mkOption {
        type = lib.types.str;
        description = "SMTP submission host for outgoing service mail.";
      };

      port = lib.mkOption {
        type = lib.types.str;
        description = "SMTP submission port, a string for config-file interpolation.";
      };

      user = lib.mkOption {
        type = lib.types.str;
        description = "SMTP account name, also used as the sender address.";
      };
    };

    acmeEmail = lib.mkOption {
      type = lib.types.str;
      description = "Account email for ACME certificate registration.";
    };

    dnsApiTokenSecret = lib.mkOption {
      type = lib.types.str;
      description = "Name of the sops secret holding this system's zone-scoped Cloudflare DNS API token, read by the acme and caddy modules.";
    };

    autoUpdate = {
      owner = lib.mkOption {
        type = lib.types.str;
        description = "User owning the checkout; git runs as this user.";
      };

      branch = lib.mkOption {
        type = lib.types.str;
        description = "Branch whose origin head is verified and reset to before each upgrade.";
      };

      allowedSigners = lib.mkOption {
        type = lib.types.lines;
        description = "gpg.ssh allowed-signers entries trusted to sign the update branch. Definitions merge, so a system can trust a signer beyond the shared set.";
      };
    };

    wireguardTunnel = {
      prefixLength = lib.mkOption {
        type = lib.types.str;
        description = "Prefix length of the tunnel's point-to-point subnet, a string for address interpolation.";
      };

      listenPort = lib.mkOption {
        type = lib.types.nullOr lib.types.port;
        default = null;
        description = "UDP port this system listens on for the tunnel, null when this end only dials out.";
      };

      local.ip = lib.mkOption {
        type = lib.types.str;
        description = "This system's address inside the tunnel.";
      };

      peer = {
        ip = lib.mkOption {
          type = lib.types.str;
          description = "The peer's address inside the tunnel.";
        };

        publicKey = lib.mkOption {
          type = lib.types.str;
          description = "The peer's WireGuard public key.";
        };

        endpoint = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "host:port this system dials the peer at, null when the peer dials in.";
        };
      };
    };
  };
}
