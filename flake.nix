{
  description = "NixOS module for Koel music streaming server";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: {
    nixosModules.default = import ./module.nix;

    # Alias for convenience
    nixosModules.koel = self.nixosModules.default;
  };
}
