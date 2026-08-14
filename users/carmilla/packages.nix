# carmilla's home packages: the tooling reached for over ssh on any host.
{pkgs, ...}: {
  home.packages = with pkgs; [
    curl
    fd
    git
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
