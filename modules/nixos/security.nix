{...}: {
  users.users.root.hashedPassword = "!";
  users.mutableUsers = false;

  security.protectKernelImage = true;
  # Force PTI even when the CPU reports itself unaffected by Meltdown.
  security.forcePageTableIsolation = true;

  boot.kernelParams = [
    # Prevents slab cache merging, which hardens against heap exploits.
    "slab_nomerge"
    # Randomises page allocator freelist order.
    "page_alloc.shuffle=1"
  ];

  boot.kernel.sysctl = {
    # Hide kernel pointers even from processes with CAP_SYSLOG.
    "kernel.kptr_restrict" = 2;
    # Restrict dmesg to root.
    "kernel.dmesg_restrict" = 1;
    "net.ipv4.tcp_syncookies" = 1;
    # Strict reverse-path filtering; log rejected sources.
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.conf.all.log_martians" = 1;
    "net.ipv4.conf.default.log_martians" = 1;
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
    # Disable redirects on existing and newly created interfaces.
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.secure_redirects" = 0;
    "net.ipv4.conf.default.secure_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
  };

  security.apparmor.enable = true;
  security.apparmor.enableCache = true;
  security.apparmor.killUnconfinedConfinables = true;

  security.sudo.enable = false;

  # Limit daemon access to local users; only root is trusted.
  nix.settings.allowed-users = ["@users"];
}
