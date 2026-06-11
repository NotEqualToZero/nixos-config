{ config, lib, pkgs, ... }:

{
  services.tailscale = {
    enable = true;
    interfaceName = "userspace-networking";

  };

}
