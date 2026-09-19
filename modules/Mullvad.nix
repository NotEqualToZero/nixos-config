{ config, lib, pkgs, ... }:
### Not configured, this has just been pulled from https://wiki.nixos.org/wiki/Mullvad_VPN

let
  mullvadConfig =
  let
      mkCountryList = id: countries: name: {
        inherit id name;
        locations = map (country: { inherit country; }) countries;
      };
  in
    pkgs.writeText "mullvad-settings" (
      builtins.toJSON {
        allow_lan = true;
        auto_connect = true;
        block_when_disconnected = true;

        api_access_methods = {
          custom = [ ];
          direct = {
            access_method.built_in = "direct";
            enabled = true;
            id = "00000000-0000-0000-0000-000000000008";
            name = "Direct";
          };
          mullvad_bridges = {
            access_method.built_in = "bridge";
            enabled = true;
            id = "00000000-0000-0000-0000-000000000009";
            name = "Mullvad Bridges";
          };
          encrypted_dns_proxy = {
            access_method.built_in = "encrypted_dns_proxy";
            enabled = true;
            id = "00000000-0000-0000-0000-000000000010";
            name = "Encrypted DNS proxy";
          };
        };

        # The bridge options are only useful for OpenVPN. You can configure Wireguard under Shadowsocks with `obfuscation_settings` below.
        bridge_state = "auto";
        bridge_settings = {
          bridge_type = "normal";
          custom = null;
          normal = {
            location = "any";
            ownership = "any";
            providers = "any";
          };
        };

        custom_lists.custom_lists =
          let
            northAmerica = [
              "ca"
              "mx"
              "us"
            ];
            southAmerica = [
              "br"
              "cl"
              "co"
              "pe"
            ];
            europe = [
              "al"
              "at"
              "be"
              "bg"
              "ch"
              "cy"
              "cz"
              "de"
              "dk"
              "ee"
              "es"
              "fi"
              "fr"
              "gb"
              "gr"
              "hr"
              "hu"
              "ie"
              "it"
              "lv"
              "nl"
              "no"
              "pl"
              "pt"
              "ro"
              "rs"
              "se"
              "si"
              "sk"
              "tr"
              "ua"
            ];
            africa = [
              "ng"
              "za"
            ];
            asia = [
              "hk"
              "id"
              "il"
              "jp"
              "my"
              "ph"
              "sg"
              "th"
            ];
            oceania = [
              "au"
              "nz"
            ];
          in
          [
            (mkCountryList "00000000-0000-0000-0000-000000000000" (
              northAmerica ++ southAmerica ++ europe ++ africa ++ asia ++ oceania
            ) "All Countries")
            (mkCountryList "00000000-0000-0000-0000-000000000002" northAmerica "North America")
            (mkCountryList "00000000-0000-0000-0000-000000000003" southAmerica "South America")
            (mkCountryList "00000000-0000-0000-0000-000000000004" europe "Europe")
            (mkCountryList "00000000-0000-0000-0000-000000000005" africa "Africa")
            (mkCountryList "00000000-0000-0000-0000-000000000006" asia "Asia")
            (mkCountryList "00000000-0000-0000-0000-000000000007" oceania "Oceania")
          ];

        # This is where you would configure IP overrides for Mullvad's servers, if you have any.
        relay_overrides = [
          /*
            {
              hostname = "se-sto-wg-001";
              ipv4_addr_in = "[remote IPv4]";
              ipv6_addr_in = "[remote IPv6]";
            }
          */
        ];
        relay_settings = {
          normal = {
            location.only.custom_list.list_id = "00000000-0000-0000-0000-000000000000"; # This selects all countries by default, so you get a random exit country every time you connect to your VPN.
            openvpn_constraints.port = "any";
            ownership = "any";
            providers = "any";
            tunnel_protocol = "any";
            wireguard_constraints = {
              entry_location.only.custom_list.list_id = "00000000-0000-0000-0000-000000000000"; # This will be ignored if DAITA is enabled, or if `use_multihop` is set to false.
              ip_version = "any";
              port = "any";
              use_multihop = true;
            };
          };
        };

        obfuscation_settings = {
          selected_obfuscation = "auto"; # This can be set to `shadowsocks`, for instance.
          udp2tcp.port = "any";
        };

        tunnel_options = {
          openvpn.mssfix = null;
          generic.enable_ipv6 = true;
          wireguard = {
            mtu = null;
            quantum_resistant = "auto";
            rotation_interval = null;
            # DAITA (https://mullvad.net/en/vpn/daita) can be configured here.
            daita = {
              enabled = true;
              use_multihop_if_necessary = true;
            };
          };
          dns_options = {
            state = "default";
            custom_options.addresses = [ ]; # Configure custom DNS providers here.
            default_options = {
              # Configure your DNS blocking. (Only usable if the option above is an empty list.)
              block_ads = true;
              block_trackers = true;
              block_malware = true;
              block_gambling = true; # Yes, this is exactly what you think it is. The Wiki's protection filter blocks this word. TODO: Someone in the trusted group needs to add the word.
              block_adult_content = true;
              block_social_media = true;
            };
          };
        };

        settings_version = 10; # This configuration is up to date as of Mullvad VPN 2025.2. Usually, Mullvad will automatically migrate your configuration imperatively, but you may occasionally need to edit it here.
        show_beta_releases = false;
      }
    );
in
{
  systemd = {
    services."mullvad-daemon".environment.MULLVAD_SETTINGS_DIR = "/var/lib/mullvad-vpn"; # This is necessary if `system.etc.overlay.mutable` is set to false, because Mullvad expects the settings directory to be writable.
    tmpfiles.settings."10-mullvad-settings"."/var/lib/mullvad-vpn/settings.json"."C+" = {
      group = "root";
      mode = "0700"; # This isn't necessary for the settings file itself, but Mullvad will store your WireGuard private key on the same directory as the settings file, so ensure that /var/lib/mullvad-vpn or /etc/mullvad-vpn is owned by `root` and has -rwx------ permissions.
      user = "root";
      argument = "${mullvadConfig}";
    };
  };
}
