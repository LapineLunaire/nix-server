{
  config,
  web,
  outputs,
  pkgs,
  ...
}: let
in {
  imports = [outputs.nixosModules.microvm-docker-common ./sops.nix];

  microvm = {
    vcpu = 8;
    mem = 12288;
    # Evaluating whole-host toplevels needs the full allocation, so the balloon starts at zero.
    initialBalloonMem = 0;
    # Dedicated XFS volume for Docker; overlayfs can't run on virtiofs.
    volumes = [
      {
        image = "/persist/vms/ci-runner/volumes/docker.img";
        size = 20480;
        mountPoint = "/var/lib/docker";
        fsType = "xfs";
      }
    ];
  };

  # Workflow content is arbitrary by definition.
  microvmGuest.egress = [
    {proto = "tcp";}
    {proto = "udp";}
    {proto = "icmp";}
  ];

  sops.templates."runner-token.env".content = ''
    TOKEN=${config.sops.placeholder."forgejo-runner-token"}
  '';

  services.gitea-actions-runner = {
    package = pkgs.forgejo-runner;
    instances.sparkle = {
      enable = true;
      name = "sparkle";
      url = web.origin.forgejo;
      tokenFile = config.sops.templates."runner-token.env".path;
      labels = ["debian:docker://node:25@sha256:78839ac448c23517f8eab2e8f7943d9b4f73979eb7f8bed2c73dbf72ff869e7b"];
      settings = {
        runner.capacity = 2;
        container = {
          network = "bridge";
          docker_host = "-";
          pull_policy = "if-not-present";
        };
      };
    };
  };

  systemd.services.gitea-runner-sparkle.serviceConfig.SupplementaryGroups = ["docker"];
}
