{
  dmz,
  net,
  web,
  config,
  lib,
  ...
}: {
  imports = [./sops.nix];

  microvm = {
    vcpu = 2;
    mem = 2048;
    initialBalloonMem = 1024;
  };

  # Grafana contact points, plugin and dashboard fetches are all configured at runtime.
  microvmGuest.egress = [
    {proto = "tcp";}
    {proto = "udp";}
    {proto = "icmp";}
  ];

  services.prometheus = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9090;
    retentionTime = "90d";
    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [
          {
            # node_exporter on sparkle plus every VM in the registry.
            targets = map (ip: "${ip}:${toString net.nodeExporterPort}") ([dmz.hostAddress] ++ lib.attrValues net.vmAddress);
          }
        ];
      }
    ];
  };

  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = net.vmAddress.monitoring;
        http_port = web.endpoints.monitoring.port;
        domain = web.vhost.monitoring;
        root_url = "${web.origin.monitoring}/";
      };
      security = {
        secret_key = "$__file{${config.sops.secrets."grafana-secret-key".path}}";
        # Seeds the admin account when grafana creates its database; an existing database keeps its stored password (rotate via the UI or grafana-cli admin reset-admin-password).
        admin_password = "$__file{${config.sops.secrets."grafana-admin-password".path}}";
      };
    };
  };
}
