{
  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets."attic-db-password".restartUnits = ["postgresql-passwords.service"];
    secrets."authelia-db-password".restartUnits = ["postgresql-passwords.service"];
    secrets."forgejo-db-password".restartUnits = ["postgresql-passwords.service"];
    secrets."vaultwarden-db-password".restartUnits = ["postgresql-passwords.service"];
    secrets."carmilla-db-password".restartUnits = ["postgresql-passwords.service"];
  };
}
