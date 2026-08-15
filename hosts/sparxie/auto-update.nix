# sparxie's auto-update: the shared signed switch, keeping the module's default reboot on kernel changes.
{outputs, ...}: {
  imports = [outputs.nixosModules.auto-update];

  host.autoUpdate = {
    owner = "carmilla";
    branch = "main";
  };
}
