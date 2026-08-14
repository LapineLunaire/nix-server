# Nix settings shared by full hosts and microVM guests.
{...}: {
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      # An empty value disables the global flake registry, leaving only this flake's pinned inputs.
      flake-registry = "";
      # Replaces store files with identical contents by hard links.
      auto-optimise-store = true;
    };
    channel.enable = false;
  };
}
