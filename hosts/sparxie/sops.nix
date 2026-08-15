{...}: {
  sops = {
    defaultSopsFile = ./secrets.yaml;

    secrets."carmilla-password-hash".neededForUsers = true;
    secrets."ejabberd-db-password" = {};
    secrets."carmilla-db-password" = {};
    secrets."redis-password".owner = "redis";
    secrets."tuwunel-registration-token" = {};
    secrets."ssh-allowed-ips-v4".reloadUnits = ["nftables.service"];
    secrets."ssh-allowed-ips-v6".reloadUnits = ["nftables.service"];
  };
}
