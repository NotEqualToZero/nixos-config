{ config, lib, pkgs, sources, ... }:
let
  kde-over = self: super: {
    kdePackages = super.kdePackages.overrideScope(kdeFinal: kdePrev: {
      kwin = kdePrev.kwin.overrideAttrs (prevPdAttrs: {
        src = sources.kwin-vr.outPath; });
      qtquick3d = kdePrev.qtquick3d.overrideAttrs (prevPdAttrs: { #patches for AR glasses on qt6.10
        patches = [
          ../patches/qtquick3d/0001-XR-add-support-for-passthrough-on-standard-OpenXR-ru.patch
          ../patches/qtquick3d/0002-XR-OpenXR-add-support-for-XR_EXTX_overlay.patch
          ../patches/qtquick3d/0003-XR-OpenXR-OpenGL-use-as-SRGB-texture-format-for-swap.patch
          ../patches/qtquick3d/0004-XR-OpenXR-Add-async-rendering-support-for-OpenXR-bac.patch
          ../patches/qtquick3d/0005-XR-OpenXR-add-support-for-XR_VIEW_CONFIGURATION_TYPE.patch
          ../patches/qtquick3d/0006-XR-do-not-cache-QT_QUICK3D_XR_DISABLE_MULTIVIEW-env-.patch
        ];
      });
    });
  };
  pkgs-xr = import sources.nixpkgs-xr;
in {
  services.monado = {
    enable = true;
    defaultRuntime = true; # Register as default OpenXR runtime
    # package = pkgs.monado.overrideAttrs (finalAttrs: previousAttrs: { src = sources.monado.outPath; patches = []; }); #rayneo driver fork
  };
  systemd.user.services.monado.environment = {
    STEAMVR_LH_ENABLE = "1";
    XRT_COMPOSITOR_COMPUTE = "1";
  };

 nixpkgs.overlays = [
   # kde-over
   pkgs-xr.overlays.default
 ];

  environment.systemPackages = with pkgs; [
    wayvr
    kdePackages.qtquick3d
  ];
}
