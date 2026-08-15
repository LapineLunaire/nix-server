# Per-guest addressing on the DMZ, derived from guest-registry.nix and dmz-net.nix, plus the client sets and ports the rules over the segment are written from. Import this for any 10.28.33.x address.
let
  registry = import ./guest-registry.nix;
  dmz = import ./dmz-net.nix;
  names = builtins.attrNames registry;
  vmAddress = builtins.mapAttrs (_: vm: "${dmz.guestPrefix}.${toString vm.index}") registry;
  # Guests allowed to reach postgres on 5432: the DB-backed apps, uptime-kuma for its health check, and pgadmin.
  postgresClients = ["authelia" "forgejo" "pgadmin" "uptime-kuma"];
  # Guests allowed to reach the vault guest's NFSv4 server. The exports name their own clients, since each gets a different export and mode; this list is what the two firewall sites read.
  nfsClients = ["proxy"];
in {
  inherit vmAddress;
  # Every guest's tap interface name, which is its guest name, comma-joined for nftables set literals. On a bridged segment the forward chain matches bridge ports, so these are what its rules name.
  tapsNft = builtins.concatStringsSep ", " (map (name: "\"${name}\"") names);
  # The postgres client addresses comma-joined for nftables set literals, read by the host forward chain and by the postgres guest's own input chain.
  postgresClientsNft = builtins.concatStringsSep ", " (map (name: vmAddress.${name}) postgresClients);
  # The port the postgres guest listens on: its own listen_addresses and input chain, the host forward rule admitting the clients above, and each client's connection string.
  postgresPort = 5432;
  # The NFS client addresses comma-joined for nftables set literals, read by the host forward chain and by the vault guest's own input chain.
  nfsClientsNft = builtins.concatStringsSep ", " (map (name: vmAddress.${name}) nfsClients);
  # The port the vault guest's NFSv4 server listens on. v4-only, so this is the whole surface: no rpcbind, statd or mountd.
  nfsPort = 2049;
  # The port every node_exporter on the segment listens on: sparkle's own, each guest's, the rules admitting the monitoring guest, and that guest's scrape targets.
  nodeExporterPort = 9100;
}
