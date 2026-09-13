{
  dmz,
  net,
  web,
  zoneSerial,
  lib,
  ...
}: let
  # Use the same DoT upstreams in CoreDNS and the firewall.
  dotResolvers = ["1.1.1.1" "1.0.0.1"];
  # Advance both zone serials with the flake timestamp.
  serial = toString zoneSerial;
  camellyaAddress = "10.28.64.96";
  proxiedNames = (map (e: e.sub) (lib.attrValues web.endpoints)) ++ ["misc"];
  cnames = lib.concatMapStrings (sub: "${sub} IN CNAME proxy.${web.domain}.\n") proxiedNames;
  # 10.28.x.y becomes y.x in the 28.10.in-addr.arpa zone.
  ptrLabel = ip: let
    octets = lib.splitString "." ip;
  in "${lib.elemAt octets 3}.${lib.elemAt octets 2}";
in {
  microvm = {
    vcpu = 1;
    mem = 384;
    initialBalloonMem = 128;
  };

  microvmGuest.egress = [
    {
      proto = "tcp";
      ports = [853];
      destinations = dotResolvers;
    }
  ];

  networking.nameservers = lib.mkForce ["127.0.0.1"];

  # Free port 53 for CoreDNS's wildcard listener.
  services.resolved.enable = false;

  # Resolve for every client inside the network perimeter.
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

  services.coredns = let
    dotServername = "cloudflare-dns.com";
    dotForward = lib.concatMapStringsSep " " (ip: "tls://${ip}") dotResolvers;
  in {
    enable = true;
    config = ''
      # Answer local names here; forward other names in the public zone.
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

      # Keep reverse lookups inside the network.
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
