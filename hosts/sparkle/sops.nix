{
  config,
  lib,
  ...
}: let
  # Pin interface names by their SOPS-held MAC addresses.
  interfaces = ["ipmi0" "sfp0" "sfp1"];
in {
  sops = {
    defaultSopsFile = ./secrets.yaml;
    age.sshKeyPaths = ["/persist/etc/ssh/ssh_host_ed25519_key"];

    secrets =
      {
        "carmilla-password-hash".neededForUsers = true;

        "smartd-smtp-password" = {};
      }
      // lib.genAttrs (map (name: "network/${name}-mac") interfaces) (_: {});

    templates = lib.listToAttrs (map (name:
      lib.nameValuePair "10-${name}.link" {
        content = ''
          [Match]
          MACAddress=${config.sops.placeholder."network/${name}-mac"}

          [Link]
          Name=${name}
        '';
      })
    interfaces);
  };

  environment.etc = lib.listToAttrs (map (name:
    lib.nameValuePair "systemd/network/10-${name}.link" {
      source = config.sops.templates."10-${name}.link".path;
    })
  interfaces);
}
