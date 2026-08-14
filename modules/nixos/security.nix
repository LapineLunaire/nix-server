# Kernel, network, and user-account hardening shared by full hosts and microVM guests. Host-only pieces such as polkit and doas live with their consumers.
{...}: {
  # "!" locks the root account, so no password login is possible.
  users.users.root.hashedPassword = "!";
  users.mutableUsers = false;

  security.protectKernelImage = true;
  # Passes pti=on, forcing page table isolation even on CPUs reporting themselves unaffected by Meltdown.
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
    # Mitigate SYN flood attacks.
    "net.ipv4.tcp_syncookies" = 1;
    # Strict reverse path filtering: do not route packets whose source address is not reachable through the interface they arrived on. Dropped packets are logged as martians.
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.conf.all.log_martians" = 1;
    "net.ipv4.conf.default.log_martians" = 1;
    # Ignore broadcast ICMP, which mitigates SMURF amplification.
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
    # Ignore incoming ICMP redirects. The default keys are needed as well, so that interfaces added after these sysctls are applied inherit the setting.
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.secure_redirects" = 0;
    "net.ipv4.conf.default.secure_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    # Ignore outgoing ICMP redirects. IPv4 only; there is no IPv6 equivalent.
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
  };

  security.apparmor.enable = true;
  security.apparmor.enableCache = true;
  security.apparmor.killUnconfinedConfinables = true;

  security.sudo.enable = false;

  # The nixpkgs default is "*". Restricting to the users group means only its members can connect to the nix daemon.
  nix.settings.allowed-users = ["@users"];
}
