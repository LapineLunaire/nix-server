{...}: {
  sops = {
    defaultSopsFile = ./secrets.yaml;

    secrets."carmilla-password-hash".neededForUsers = true;
    secrets."ejabberd-db-password" = {};
    secrets."carmilla-db-password" = {};
    secrets."redis-password".owner = "redis";
    secrets."tuwunel-registration-token" = {};
  };
}
