{config, ...}: let
  inherit (config.host) smtp;
in {
  imports = [../host.nix];

  sops.secrets.${smtp.passwordSecret} = {};

  programs.msmtp = {
    enable = true;
    setSendmail = true;
    accounts.default = {
      inherit (smtp) host port user;
      auth = true;
      tls = true;
      from = smtp.user;
      passwordeval = "cat ${config.sops.secrets.${smtp.passwordSecret}.path}";
    };
  };
}
