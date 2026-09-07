# The Forgejo Actions runner. Jobs run natively rather than in containers, so the Nix store persists between runs and a daily build is incremental.
{
  config,
  pkgs,
  web,
  ...
}: {
  imports = [./sops.nix];

  microvm = {
    vcpu = 8;
    mem = 12288;
    # Evaluating whole-host toplevels needs the full allocation, so the balloon starts at zero.
    initialBalloonMem = 0;
    volumes = [
      # The writable half of the store overlay. Without a volume here it lands on the tmpfs root, where a kernel build would consume memory and be lost on reboot.
      {
        image = "/persist/vms/ci-runner/volumes/nix-store.img";
        size = 65536;
        mountPoint = "/nix/.rw-store";
        fsType = "xfs";
      }
      # Build scratch, for the same reason: a kernel unpacks and compiles in TMPDIR, which is otherwise the tmpfs root.
      {
        image = "/persist/vms/ci-runner/volumes/nix-build.img";
        size = 32768;
        mountPoint = "/var/nixbuild";
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

  # The Nix database sits on the tmpfs root, so without this a reboot leaves a full store the guest believes is empty.
  environment.persistence."/persist".directories = ["/nix/var"];

  # security.nix restricts daemon access to @users, and the runner is a DynamicUser with a transient group outside it, so the daemon refuses its connections. Named here rather than widening the shared rule; the list definitions merge.
  nix.settings.allowed-users = ["gitea-runner"];

  nix.settings = {
    # Jobs build with --no-link, so nothing is rooted and a scheduled collection would empty the store weekly. Freeing on disk pressure instead keeps it warm and bounded by the volume: a triggered collection frees a slice of the 64 GiB volume rather than gutting it.
    min-free = 5 * 1024 * 1024 * 1024;
    max-free = 15 * 1024 * 1024 * 1024;
    build-dir = "/var/nixbuild";
    # 12 GiB guest: max-jobs=auto (the default) with cores=0 lets as many concurrent derivations as
    # cores each run make -jN, and a kernel build alongside a few others would exhaust memory. Capped
    # well under the 8 vcpu.
    max-jobs = 3;
  };

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
      labels = ["nixos:host"];
      # hostPackages replaces the module's default rather than extending it, so the defaults are repeated here. Beyond them: nix and attic-client for the builds and pushes, skopeo for the digest refresh, gnugrep for the workflows' parsing, and openssh for the ssh-keygen the commit signing uses.
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
      # One job at a time. Two concurrent builds contend for the same cores and store, and serialising here is what makes the desktop repository's run queue behind this one.
      settings.runner.capacity = 1;
    };
  };
}
