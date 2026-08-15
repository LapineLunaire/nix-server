{...}: {
  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets."forgejo-db-password" = {};
    secrets."forgejo-smtp-password" = {};
  };
}
