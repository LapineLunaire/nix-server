{pkgs, ...}: {
  home.packages = with pkgs; [
    # Prefer uutils interactively; GNU supplies missing commands.
    uutils-coreutils-noprefix
    uutils-findutils
    uutils-diffutils
    curl
    fd
    iperf3
    jq
    ldns
    mtr
    nvimpager
    rclone
    ripgrep
    rsync
    socat
    sops
    ssh-to-age
    traceroute
    whois
    xh
  ];
}
