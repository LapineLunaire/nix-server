{
  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets."forgejo-db-password".restartUnits = ["forgejo.service"];
    secrets."forgejo-smtp-password".restartUnits = ["forgejo.service"];
  };
}
