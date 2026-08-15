# sshd reachable only from the trusted client subnets: closes the firewall's ssh port and accepts port 22 from host.trustedSubnets instead.
{config, ...}: {
  services.openssh.openFirewall = false;
  networking.firewall.extraInputRules = ''
    ip saddr { ${config.host.trustedSubnetsNft} } tcp dport 22 accept
  '';
}
