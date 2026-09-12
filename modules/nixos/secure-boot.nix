# Lanzaboote uses signing keys prepared before installation, under the /var/lib that host-base/persistence.nix persists. Firmware enrollment follows installation; README.md describes the bootstrap sequence.
{pkgs, ...}: {
  boot.loader.systemd-boot.enable = false;

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };

  environment.systemPackages = with pkgs; [
    sbctl
    tpm2-tools
  ];

  # tctiEnvironment sets TPM2TOOLS_TCTI and TPM2_PKCS11_TCTI, so the tooling works without being given a TCTI string.
  security.tpm2 = {
    enable = true;
    pkcs11.enable = true;
    tctiEnvironment.enable = true;
  };
}
