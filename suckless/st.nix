{ config, lib, pkgs, sources, ... }:

{
  environment.systemPackages = with pkgs; [
  (st.overrideAttrs (oldAttrs: rec {
    # src = sources.st-custom.outPath;
    # Make sure you include whatever dependencies the fork needs to build properly!
    buildInputs = oldAttrs.buildInputs ++ [ ];
    patches = [
     /home/cale/suckless/st/st-cyberpunk-neon-20220703-baa9357.diff
    ];
  }))
  ];
}
