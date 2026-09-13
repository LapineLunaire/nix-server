{
  dns = {index = 10;};
  proxy = {
    index = 11;
    deps = ["dns"];
  };
  postgres = {index = 12;};
  pgadmin = {index = 13;};
  authelia = {
    index = 14;
    deps = ["postgres"];
  };
  monitoring = {index = 15;};
  uptime-kuma = {index = 16;};
  vault = {index = 17;};
  attic = {
    index = 18;
    deps = ["postgres"];
  };
  forgejo = {
    index = 20;
    deps = ["postgres"];
  };
  ci-runner = {
    index = 21;
    deps = ["forgejo"];
  };
  vaultwarden = {
    index = 22;
    deps = ["postgres"];
  };
  kavita = {index = 23;};
  qbittorrent = {index = 24;};
  homeassistant = {index = 25;};
  unifi = {index = 26;};
}
