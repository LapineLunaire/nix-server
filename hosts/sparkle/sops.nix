{
  config,
  lib,
  ...
}: let
  # Interfaces pinned to stable names by MAC-matched .link files (see the networks in default.nix). Each gets a network/<name>-mac secret, a sops-rendered 10-<name>.link template, and an /etc/systemd/network symlink to it.
  interfaces = ["ipmi0" "sfp0" "sfp1"];
in {
  sops = {
    defaultSopsFile = ./secrets.yaml;

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
