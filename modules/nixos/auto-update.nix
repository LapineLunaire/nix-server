# Daily auto-update on top of system.autoUpgrade. An ExecStartPre verifies the origin branch head against the trusted signers before the module builds and switches. allowReboot defaults on so kernel changes take effect, and hosts can override it.
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (config.host) flakePath;
  inherit (config.host.autoUpdate) owner branch;
in {
  # The format requires a principals field. Git decides trust on the key being present in this file and reports back whatever principal sits beside it, so the wildcard states the scope the verification actually has.
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
    # nixpkgs splices this into flags as an unquoted --flake argument, and the unit script interpolates flags with toString, so $rev is expanded by the shell from the value set in the mkBefore block below.
    flake = "git+file://${flakePath}?rev=$rev";
    allowReboot = lib.mkDefault true;
    # Drops the --upgrade flag, which is for channels. This flake is upgraded by its own lockfile.
    upgrade = false;
    dates = "03:00";
    randomizedDelaySec = "15min";
    persistent = true;
  };

  systemd.services.nixos-upgrade.script = let
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

  # The upgrade runs git and nix's flake fetcher as root against this user-owned checkout, so the path has to be trusted or both refuse it.
  environment.etc."gitconfig".text = ''
    [safe]
    directory = ${flakePath}
  '';
}
