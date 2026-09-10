# The Forgejo Actions runner. Jobs run natively rather than in containers, so the Nix store persists between runs and a daily build is incremental.
{
  config,
  outputs,
  pkgs,
  web,
  ...
}: let
  # Named once: the volume declaration and the preStart that creates it both take it.
  swapImage = "/persist/vms/ci-runner/volumes/swap.img";
in {
  imports = [outputs.nixosModules.binary-cache ./sops.nix];

  microvm = {
    vcpu = 8;
    # The evaluator alone holds close to 6 GB realising every guest closure through the uutils IFD, and builds run alongside it. The other fifteen guests declare 32 GB alone against sparkle's 64, so this leaves room for the host and the ZFS ARC.
    mem = 20480;
    # Evaluating whole-host toplevels needs the full allocation, so the balloon starts at zero rather than relying on deflateOnOOM, which reacts only once the guest is already out of memory.
    initialBalloonMem = 0;
    volumes = [
      # The writable half of the store overlay. Without a volume here it lands on the tmpfs root, where a kernel build would consume memory and be lost on reboot. microvm creates the image only when it is absent, so this size is the size of a recreated one.
      {
        image = "/persist/vms/ci-runner/volumes/nix-store.img";
        size = 131072;
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
      # Raw swap, carrying the allocations no plausible guest size covers: a single link step can want tens of gigabytes, and the evaluator alone holds several. autoCreate is off because there is no mkfs for swap, so preStart below makes the image instead.
      {
        image = swapImage;
        mountPoint = null;
        autoCreate = false;
      }
    ];
    # The swap image, which nothing else creates: cloud-hypervisor fails to open a disk that is not there, so without this a sparkle rebuilt from bare metal has a guest that never starts. mkswap runs on the host rather than once by hand in the guest, since the label the guest mounts by is written by the same command.
    preStart = ''
      if [ ! -e ${swapImage} ]; then
        ${pkgs.coreutils}/bin/truncate -s 32768M ${swapImage}
        ${pkgs.util-linux}/bin/mkswap -L ci-swap ${swapImage}
      fi
    '';
  };

  # Workflow content is arbitrary by definition.
  microvmGuest.egress = [
    {proto = "tcp";}
    {proto = "udp";}
    {proto = "icmp";}
  ];

  # zram from guest.nix stays at priority 100 so small pressure compresses in RAM; this takes what spills past it. Labelled rather than named by device letter, since the letters follow declaration order.
  swapDevices = [{label = "ci-swap";}];

  # The Nix database sits on the tmpfs root, so without this a reboot leaves a full store the guest believes is empty.
  environment.persistence."/persist".directories = ["/nix/var"];

  # The runner both fills these caches and reads them; without the read, every nightly run rebuilds what the previous one pushed. Two of them, because the desktop repository builds on this runner and pushes camellya's closure to its own.
  host.binaryCache = {
    caches = [
      {
        url = "https://cache.lunaire.moe/server";
        publicKey = "server:oFkIrocLJr2oRVgeOqJ1TUUPwTYLWKm0Lpg9aRKU5zU=";
      }
      {
        url = "https://cache.lunaire.moe/desktop";
        publicKey = "desktop:QBHQfUrDyPKWwQolz4KiaJ1NlC+dGZLP4m29qgvkYs4=";
      }
    ];
    tokenSecret = "attic-pull-token";
  };

  # security.nix restricts daemon access to @users, and the runner is a DynamicUser with a transient group outside it, so the daemon refuses its connections. Named here rather than widening the shared rule; the list definitions merge.
  nix.settings.allowed-users = ["gitea-runner"];

  nix.settings = {
    # No collection runs here. This store is an overlay whose lower layer is sparkle's store over virtiofs, so deleting a path the host owns writes a whiteout rather than freeing anything: the space stays, and the path is masked from this guest permanently. min-free made that a boot failure. The update workflow builds sparkle's toplevel with --no-link, which covers every guest runner, so this guest's own next generation is an unrooted build output; pressure collected it, and the boot that followed found init= masked. The volume is the bound, and ci-runner-store.nix on the host recreates it daily.
    build-dir = "/var/nixbuild";
    # 20 GiB guest: max-jobs=auto (the default) with cores=0 lets as many concurrent derivations as
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
