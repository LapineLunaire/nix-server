{
  config,
  lib,
  ...
}: {
  services.openssh.openFirewall = false;
  networking.firewall.extraInputRules = let
    ports = lib.concatMapStringsSep ", " toString config.services.openssh.ports;
  in ''
    ip saddr { ${config.host.trustedSubnetsNft} } tcp dport { ${ports} } accept
  '';
}
