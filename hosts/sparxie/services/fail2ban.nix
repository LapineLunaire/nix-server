# fail2ban with an escalating ban time, jailing sshd.
{...}: {
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "10m";
    bantime-increment = {
      enable = true;
      multipliers = "2 4 8 16 32 64";
      maxtime = "168h"; # cap at 1 week
      overalljails = true;
    };
    jails.sshd.settings = {
      enabled = true;
      maxretry = 3;
    };
  };
}
