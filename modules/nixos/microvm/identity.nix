# Guest-side identity: vsock CID, tap interface, MAC, hostname, static IP, and the default state share.
# Takes the guest's name, its registry index, and the addressing assigned to it, and returns that guest's identity module. macPrefix is the hypervisor's own five-octet MAC prefix and the index becomes the sixth octet, so each hypervisor brings its own prefix; two sharing a segment would collide at every index they have in common.
{
  name,
  index,
  address,
  prefixLength,
  macPrefix,
}: let
  # Indices below 10 would produce a one-digit MAC octet and vsock CIDs below 3 are reserved; above 99 overflows the octet.
  octet =
    if index >= 10 && index <= 99
    then toString index
    else throw "microVM index ${toString index} for ${name} is outside 10-99; it is spliced into the MAC as a two-digit octet";
in
  {...}: {
    microvm = {
      vsock.cid = index;
      interfaces = [
        {
          type = "tap";
          id = name;
          mac = "${macPrefix}:${octet}";
        }
      ];
      # State share for every VM; VM configs add extra shares (media, certs) on top.
      shares = [
        {
          tag = "state";
          source = "/persist/vms/${name}";
          mountPoint = "/persist";
          proto = "virtiofs";
        }
      ];
    };
    networking.hostName = name;
    networking.interfaces.eth0.ipv4.addresses = [
      {
        inherit address prefixLength;
      }
    ];
  }
