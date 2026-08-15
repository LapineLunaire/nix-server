# The authoritative DNS for the LAN: the lunaire.moe forward zone and the 28.10.in-addr.arpa reverse zone, with every other query forwarded to Cloudflare over DoT. The proxied names are generated from guest-web.nix and both serials from the flake's last-modified timestamp.
{
  dmz,
  net,
  web,
  inputs,
  lib,
  ...
}: let
  # Zone serial for both zones: the flake's last-modified timestamp, so every commit that touches a record also advances the serial.
  serial = toString inputs.self.lastModified;
  # camellya's static LAN address, resolved by both zones below.
  camellyaAddress = "10.28.64.96";
  # One CNAME to the proxy per name it serves: every web endpoint, plus the misc file server it hosts itself.
  proxiedNames = (map (e: e.sub) (lib.attrValues web.endpoints)) ++ ["misc"];
  cnames = lib.concatMapStrings (sub: "${sub} IN CNAME proxy.${web.domain}.\n") proxiedNames;
  # 10.28.x.y to its "y.x" owner label in the 28.10.in-addr.arpa zone.
  ptrLabel = ip: let
    octets = lib.splitString "." ip;
  in "${lib.elemAt octets 3}.${lib.elemAt octets 2}";
  # Read by both the egress rule and the two forward stanzas, so a change of upstream cannot leave the firewall behind.
  dotResolvers = ["1.1.1.1" "1.0.0.1"];
  dotServername = "cloudflare-dns.com";
  dotForward = lib.concatMapStringsSep " " (ip: "tls://${ip}") dotResolvers;
in {
  microvm = {
    vcpu = 1;
    mem = 384;
    initialBalloonMem = 128;
  };

  # The DoT forwarders in the CoreDNS config below, which are fixed addresses.
  microvmGuest.egress = [
    {
      proto = "tcp";
      ports = [853];
      destinations = dotResolvers;
    }
  ];

  # This guest resolves through its own CoreDNS on loopback.
  networking.nameservers = lib.mkForce ["127.0.0.1"];

  # networkd turns systemd-resolved on by default and its stub listener takes 127.0.0.53:53, which is enough to make CoreDNS's wildcard bind fail.
  services.resolved.enable = false;

  # The resolver for the whole network: 53 is open to any source that can reach it, as it was on the host. CoreDNS forwards the root zone, so this is a recursive resolver for anyone inside the perimeter.
  networking.firewall = {
    allowedUDPPorts = [53];
    allowedTCPPorts = [53];
  };

  environment.etc."coredns/zones/db.${web.domain}".text = ''
    $ORIGIN ${web.domain}.
    $TTL 3600

    @       IN SOA  dns.${web.domain}. hostmaster.${web.domain}. (
                    ${serial} ; serial
                    3600       ; refresh
                    900        ; retry
                    604800     ; expire
                    86400      ; minimum
            )

    @       IN NS   dns.${web.domain}.

    sparkle  IN A    ${dmz.hostAddress}
    camellya IN A    ${camellyaAddress}
    git-ssh  IN A    ${net.vmAddress.forgejo}
    unifi    IN A    ${net.vmAddress.unifi}
    vault    IN A    ${net.vmAddress.vault}
    proxy    IN A    ${net.vmAddress.proxy}
    dns      IN A    ${net.vmAddress.dns}
    ${cnames}
  '';

  environment.etc."coredns/zones/db.28.10".text = ''
    $ORIGIN 28.10.in-addr.arpa.
    $TTL 3600

    @       IN SOA  dns.${web.domain}. hostmaster.${web.domain}. (
                    ${serial} ; serial
                    3600       ; refresh
                    900        ; retry
                    604800     ; expire
                    86400      ; minimum
            )

    @       IN NS   dns.${web.domain}.

    ${ptrLabel dmz.hostAddress}   IN PTR  sparkle.${web.domain}.
    ${ptrLabel camellyaAddress}   IN PTR  camellya.${web.domain}.
    ${ptrLabel net.vmAddress.forgejo}   IN PTR  git-ssh.${web.domain}.
    ${ptrLabel net.vmAddress.unifi}   IN PTR  unifi.${web.domain}.
    ${ptrLabel net.vmAddress.vault}   IN PTR  vault.${web.domain}.
    ${ptrLabel net.vmAddress.proxy}   IN PTR  proxy.${web.domain}.
    ${ptrLabel net.vmAddress.dns}   IN PTR  dns.${web.domain}.
  '';

  services.coredns = {
    enable = true;
    config = ''
      # The file is an overlay on the public ${web.domain} zone. A name the file answers wins locally, and any other name falls through to the forwarder below and resolves out on the internet.
      ${web.domain} {
        file /etc/coredns/zones/db.${web.domain} {
          fallthrough
        }
        forward . ${dotForward} {
          tls_servername ${dotServername}
        }
        log
        errors
      }

      # No fallthrough, so reverse lookups for this space are answered here and stay inside the network.
      28.10.in-addr.arpa {
        file /etc/coredns/zones/db.28.10
        log
        errors
      }

      . {
        forward . ${dotForward} {
          tls_servername ${dotServername}
        }
        cache 3600
        log
        errors
      }
    '';
  };
}
