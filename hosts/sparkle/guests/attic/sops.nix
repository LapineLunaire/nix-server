{...}: {
  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets."attic-token-rs256-secret-base64" = {};
    secrets."attic-db-password" = {};
  };
}
