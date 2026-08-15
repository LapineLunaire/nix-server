# Lanzaboote secure boot for hosts with an enrolled key set, replacing systemd-boot, plus the sbctl and TPM2 tooling. The PKI bundle sits under the persisted /var/lib.
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

  # tctiEnvironment sets TPM2TOOLS_TCTI, so tpm2-tools commands work without being given a TCTI string.
  security.tpm2 = {
    enable = true;
    tctiEnvironment.enable = true;
  };
}
