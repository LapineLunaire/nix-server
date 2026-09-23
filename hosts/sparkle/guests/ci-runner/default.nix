{
  config,
  lib,
  pkgs,
  web,
  ...
}: {
  imports = [../../binary-cache.nix ./sops.nix];

  microvm = let
    swapImage = "/persist/vms/ci-runner/volumes/swap.img";
  in {
    vcpu = 8;
    # Reserve 20 GiB for builds; size future changes from measured usage.
    mem = 20480;
    # Keep the full allocation available from startup.
    initialBalloonMem = 0;
    volumes = [
      # Keep the writable store on disk across guest reboots.
      {
        image = "/persist/vms/ci-runner/volumes/nix-store.img";
        size = 131072;
        mountPoint = "/nix/.rw-store";
        fsType = "xfs";
      }
      # Keep build scratch off the tmpfs root.
      {
        image = "/persist/vms/ci-runner/volumes/nix-build.img";
        size = 65536;
        mountPoint = "/var/nixbuild";
        fsType = "xfs";
      }
      # Create raw swap on the host; microvm's filesystem creator cannot format it.
      {
        image = swapImage;
        mountPoint = null;
        autoCreate = false;
      }
    ];
    # Create swap before cloud-hypervisor opens it, including on a fresh host.
    preStart = ''
      if [ ! -e ${swapImage} ]; then
        ${pkgs.coreutils}/bin/truncate -s 32768M ${swapImage}
        ${pkgs.util-linux}/bin/mkswap -L ci-swap ${swapImage}
      fi
    '';
  };

  # Jobs can fetch dependencies from arbitrary public endpoints.
  microvmGuest.egress = [
    {proto = "tcp";}
    {proto = "udp";}
    {proto = "icmp";}
  ];

  # Use disk swap after zram. Labels survive changes in disk declaration order.
  swapDevices = [{label = "ci-swap";}];

  # Persist the database with the writable store.
  environment.persistence."/persist".directories = ["/nix/var"];

  # Allow the runner's DynamicUser to connect to the Nix daemon.
  nix.settings.allowed-users = ["gitea-runner"];

  nix.settings = {
    extra-substituters = lib.mkAfter ["https://cache.lunaire.moe/desktop?priority=10"];
    extra-trusted-public-keys = lib.mkAfter ["desktop:QBHQfUrDyPKWwQolz4KiaJ1NlC+dGZLP4m29qgvkYs4="];

    # Do not GC this overlay: whiteouts can hide paths needed by the next guest generation.
    # ci-runner-store.nix recreates the store and database together.
    build-dir = "/var/nixbuild";
    # Limit concurrent builds to fit the guest's memory budget.
    max-jobs = 3;
  };

  sops.templates."runner-token.env" = {
    restartUnits = ["gitea-runner-sparkle.service"];
    content = ''
      TOKEN=${config.sops.placeholder."forgejo-runner-token"}
    '';
  };

  services.gitea-actions-runner = {
    package = pkgs.forgejo-runner;
    instances.sparkle = {
      enable = true;
      name = "sparkle";
      url = web.origin.forgejo;
      tokenFile = config.sops.templates."runner-token.env".path;
      labels = ["nixos:host"];
      # hostPackages replaces the defaults, so include the runner tools as well as build tools.
      hostPackages = with pkgs; [
        bash
        coreutils
        curl
        gawk
        gitMinimal
        gnused
        nodejs
        wget
        attic-client
        gnugrep
        nix
        openssh
        skopeo
      ];
      # Serialize the server and desktop builds on this runner.
      settings.runner.capacity = 1;
      settings.runner.timeout = "6h";
    };
  };
}
