# Central guest registry. index becomes the vsock CID, the last MAC octet (behind the MAC prefix in modules/nixos/microvm/identity.nix), and the last address octet (10.28.33.<index>). deps order microvm@<name> after other guests.
# index must be between 10 and 99: it is spliced into the MAC as a two-digit octet, which identity.nix enforces at eval time, and vsock reserves CIDs 0, 1, and 2.
# 10-19 is the platform: resolution, ingress, data, identity, observability, storage. 20-29 is what the platform exists to serve.
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
}
