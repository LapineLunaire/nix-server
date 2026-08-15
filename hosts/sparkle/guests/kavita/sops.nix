{...}: {
  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets."kavita-token-key".owner = "kavita";
  };
}
