{
  sops = {
    defaultSopsFile = ./secrets.yaml;
    secrets."grafana-secret-key" = {
      owner = "grafana";
      restartUnits = ["grafana.service"];
    };
    secrets."grafana-admin-password".owner = "grafana";
  };
}
