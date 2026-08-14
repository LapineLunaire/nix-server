# The host option namespace: deployment parameters each system defines for itself and modules read as config.host.*.
{lib, ...}: {
  options.host = {
    flakePath = lib.mkOption {
      type = lib.types.str;
      description = "Path of this system's flake checkout, which nh and system.autoUpgrade build from.";
    };
  };
}
