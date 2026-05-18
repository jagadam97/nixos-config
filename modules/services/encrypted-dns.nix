{ config, lib, ... }:

let
  cfg = config.services.encryptedDns;
in
{
  options.services.encryptedDns = {
    enable = lib.mkEnableOption "encrypted DNS via dnscrypt-proxy2 (DoH + DoT to AGH on beast)";

    dohStamp = lib.mkOption {
      type = lib.types.str;
      description = "DNS stamp (sdns://...) for the DoH endpoint, including /dns-query/<clientid> path.";
    };

    dotStamp = lib.mkOption {
      type = lib.types.str;
      description = "DNS stamp (sdns://...) for the DoT endpoint at <clientid>.jagadam97.uk:853.";
    };

    rawDotFallback = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "152.70.69.235#razorback.jagadam97.uk";
      description = ''
        Optional raw DoT fallback for systemd-resolved itself. Format is
        `IP#hostname` (hostname is used as SNI for cert validation and as the
        AGH ClientID first-label). When set, resolved is configured with
        DNSOverTLS=opportunistic and uses this server as FallbackDNS — so if
        dnscrypt-proxy is down, resolved still does encrypted DoT directly.
      '';
    };

    listenPort = lib.mkOption {
      type = lib.types.port;
      # 5353 is mDNS (Avahi), don't use. 53053 is unassigned and clearly DNS-ish.
      default = 53053;
      description = "Loopback port that dnscrypt-proxy listens on for systemd-resolved to query.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.dnscrypt-proxy2 = {
      enable = true;
      settings = {
        listen_addresses = [ "127.0.0.1:${toString cfg.listenPort}" ];
        server_names = [ "home-doh" "home-dot" ];
        require_dnssec = false;
        lb_strategy = "p2";
        cache = true;
        cache_size = 4096;
        # Bootstrap resolvers — used once at startup to resolve the stamp hostnames.
        bootstrap_resolvers = [ "1.1.1.1:53" "8.8.8.8:53" ];
        ignore_system_dns = true;
        static = {
          "home-doh".stamp = cfg.dohStamp;
          "home-dot".stamp = cfg.dotStamp;
        };
      };
    };

    # Make resolved talk to dnscrypt-proxy and override any per-link DNS that
    # NetworkManager/DHCP pushes by claiming the global as the catch-all route.
    # If rawDotFallback is set, also configure resolved itself with DoT so a
    # dnscrypt-proxy outage still leaves us with encrypted DNS.
    services.resolved = {
      enable = true;
      settings.Resolve = {
        DNS = "127.0.0.1:${toString cfg.listenPort}";
        Domains = "~.";
      } // lib.optionalAttrs (cfg.rawDotFallback != null) {
        DNSOverTLS = "opportunistic";
        FallbackDNS = cfg.rawDotFallback;
      };
    };

    # Belt-and-braces: clear any stray nameservers so resolved only uses our DNS=.
    networking.nameservers = lib.mkForce [ ];
  };
}
