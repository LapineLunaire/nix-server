let
  registry = import ./guest-registry.nix;
  dmz = import ./dmz-net.nix;
  names = builtins.attrNames registry;
  vmAddress = builtins.mapAttrs (_: vm: "${dmz.guestPrefix}.${toString vm.index}") registry;
in {
  inherit vmAddress;
  tapsNft = builtins.concatStringsSep ", " (map (name: "\"${name}\"") names);
  # Pin each tap to its assigned IPv4 address.
  guestIdentityNft = builtins.concatStringsSep ", " (map (name: "\"${name}\" . ${vmAddress.${name}}") names);
  postgresClientsNft = let
    postgresClients = ["authelia" "forgejo" "vaultwarden" "attic" "pgadmin"];
  in
    builtins.concatStringsSep ", " (map (name: vmAddress.${name}) postgresClients);
  postgresPort = 5432;
  # Exports specify paths and modes; this list controls network access.
  nfsClientsNft = let
    nfsClients = ["proxy" "kavita" "qbittorrent"];
  in
    builtins.concatStringsSep ", " (map (name: vmAddress.${name}) nfsClients);
  # NFSv4 needs only port 2049.
  nfsPort = 2049;
  nodeExporterPort = 9100;
}
