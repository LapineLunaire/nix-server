{...}: {
  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets."forgejo-runner-token" = {};
  };
}
