{
  config,
  lib,
  pkgs,
  ...
}: {
  # Samba uses its own passdb; this Unix account needs no login access.
  users.users.carmilla = {
    isNormalUser = true;
    uid = 1000;
    group = "users";
    home = "/var/empty";
    createHome = false;
    shell = "${pkgs.shadow}/bin/nologin";
    hashedPassword = "!";
  };

  services.avahi = {
    enable = true;
    openFirewall = false;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      domain = true;
      hinfo = true;
      userServices = true;
      workstation = true;
    };
  };

  services.samba = {
    enable = true;
    openFirewall = false;
    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "server string" = "vault";
        "netbios name" = "vault";
        "security" = "user";
        "hosts allow" = "${lib.concatStringsSep " " config.host.trustedSubnets} 127.0.0.0/8 ::1";
        "hosts deny" = "0.0.0.0/0";
        "guest account" = "nobody";
        "map to guest" = "never";
      };
      carmilla = {
        "path" = "/vault/carmilla";
        "valid users" = "carmilla";
        "writeable" = "yes";
        "force user" = "carmilla";
        "force group" = "users";
        "create mask" = "0644";
        "directory mask" = "0755";
        # Fruit VFS module: macOS compatibility for extended attributes and metadata.
        "fruit:aapl" = "yes";
        "vfs objects" = "catia fruit streams_xattr";
      };
      misc = {
        "path" = "/vault/misc";
        "valid users" = "carmilla";
        "writeable" = "no";
        "force user" = "carmilla";
        "force group" = "users";
        "fruit:aapl" = "yes";
        "vfs objects" = "catia fruit streams_xattr";
      };
      torrents = {
        "path" = "/vault/torrents";
        "valid users" = "carmilla";
        "writeable" = "no";
        "fruit:aapl" = "yes";
        "vfs objects" = "catia fruit streams_xattr";
      };
    };
  };

  # wsdd makes the server discoverable in Windows Network without NetBIOS.
  services.samba-wsdd = {
    enable = true;
    openFirewall = false;
  };

  # Mount the library child dataset before serving its parent share.
  systemd.services.samba-smbd.unitConfig.RequiresMountsFor = [
    "/vault/carmilla"
    "/vault/misc"
    "/vault/misc/library"
    "/vault/torrents"
  ];
}
