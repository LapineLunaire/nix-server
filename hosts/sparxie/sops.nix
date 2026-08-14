{...}: {
  sops = {
    defaultSopsFile = ./secrets.yaml;

    secrets."carmilla-password-hash".neededForUsers = true;
  };
}
