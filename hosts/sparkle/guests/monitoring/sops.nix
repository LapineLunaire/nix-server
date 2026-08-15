{...}: {
  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets."grafana-secret-key".owner = "grafana";
    secrets."grafana-admin-password".owner = "grafana";
  };
}
