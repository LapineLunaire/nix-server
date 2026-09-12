# Nix settings shared by full hosts and microVM guests.
{...}: {
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      # Disable the global flake registry. The system nixpkgs pin and user registry entries still apply.
      flake-registry = "";
      # Replaces store files with identical contents by hard links.
      auto-optimise-store = true;
      # Build from source if a substitute download fails, regardless of which caches are configured.
      fallback = true;
    };
    channel.enable = false;
  };
}
