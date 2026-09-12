# carmilla's home packages: the tooling reached for over ssh on any host.
{pkgs, ...}: {
  home.packages = with pkgs; [
    # The user profile precedes the system profile on PATH, so user commands prefer uutils.
    # GNU utilities remain available to system packages and supply commands uutils omits.
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
