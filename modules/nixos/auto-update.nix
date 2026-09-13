{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (config.host) flakePath;
in {
  # Trust these keys regardless of the principal Git reports.
  host.autoUpdate.allowedSigners = let
    ciKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPVAUGIq89EoX6Edi6iE8tghHeRqbmUmQJJJXcWfa5Nm";
  in ''
    # YubiKey resident keys
    ${lib.concatMapStringsSep "\n" (key: "* ${key}") (import ../../users/carmilla/ssh-keys.nix)}
    # CI signing key (Forgejo Actions)
    * ${ciKey}
  '';

  system.autoUpgrade = {
    enable = true;
    # The upgrade script expands $rev to the verified commit below.
    flake = "git+file://${flakePath}?rev=$rev";
    allowReboot = lib.mkDefault true;
    # Use the flake lock rather than channel upgrades.
    upgrade = false;
    dates = "03:00";
    randomizedDelaySec = "15min";
    persistent = true;
  };

  systemd.services.nixos-upgrade.script = let
    inherit (config.host.autoUpdate) owner branch;
    allowedSigners = pkgs.writeText "git-allowed-signers" config.host.autoUpdate.allowedSigners;
    verifyOriginBranch = pkgs.writeShellScript "verify-origin-${branch}" ''
      set -euo pipefail
      export HOME=/home/${owner}
      # Run git as the checkout's owner, not root.
      git() { ${pkgs.util-linux}/bin/runuser -u ${owner} -- ${pkgs.gitMinimal}/bin/git -C ${flakePath} "$@"; }

      git fetch --prune origin ${branch}
      rev=$(git rev-parse origin/${branch})
      # gpg.ssh.program is pinned to the ssh-keygen store path, so the unit resolves it from the store.
      if ! git -c gpg.format=ssh -c gpg.ssh.allowedSignersFile=${allowedSigners} -c gpg.ssh.program=${pkgs.openssh}/bin/ssh-keygen verify-commit "$rev"; then
        echo "refusing to upgrade: origin/${branch} $rev is not signed by a trusted key" >&2
        exit 1
      fi
      git reset --hard "$rev" > /dev/null
      printf '%s\n' "$rev"
    '';
  in
    lib.mkBefore ''
      rev=$(${verifyOriginBranch})
    '';

  # Allow root to read the user-owned checkout when building the verified revision.
  environment.etc."gitconfig".text = ''
    [safe]
    directory = ${flakePath}
  '';
}
