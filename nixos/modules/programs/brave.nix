# Brave Browser policy management.
#
# A declarative reimplementation of the `BraveOptimizer` PowerShell tool
# (https://github.com/insovs/BraveOptimizer). That tool toggles Brave Browser
# policies by writing the Windows registry; on Linux the *same* Chromium policy
# keys are read from JSON files under `/etc/brave/policies/managed/` (locked,
# "Managed by your organization").
#
# This module reproduces the tool's curated catalog, its three presets, its
# DNS-over-HTTPS mode, and its uBlock Origin force-install. It writes a single
# `brave-optimizer.json` file so it can coexist with the overlapping
# `programs.chromium` module.
#
# Policy catalog (key -> value applied when the key is enabled):
#
#   Telemetry and reporting
#     MetricsReportingEnabled                      false
#     SafeBrowsingExtendedReportingEnabled         false
#     UrlKeyedAnonymizedDataCollectionEnabled      false
#     FeedbackSurveysEnabled                       false
#     UserFeedbackAllowed                          false
#   Privacy and security
#     SafeBrowsingProtectionLevel                  0
#     AutofillAddressEnabled                       false
#     AutofillCreditCardEnabled                    false
#     PaymentMethodQueryEnabled                    false
#     PasswordManagerEnabled                       false
#     BrowserSignin                                0
#     WebRtcIPHandling                             "disable_non_proxied_udp"
#     QuicAllowed                                  false
#     BlockThirdPartyCookies                       true
#     EnableDoNotTrack                             true
#     ForceGoogleSafeSearch                        true
#     IncognitoModeAvailability                    1
#     IPFSEnabled                                  false
#   Brave features
#     BraveRewardsDisabled                         true
#     BraveWalletDisabled                          true
#     BraveVPNDisabled                             true
#     BraveAIChatEnabled                           false
#     BraveNewsDisabled                            true
#     BraveTalkDisabled                            true
#     TorDisabled                                  true
#     SyncDisabled                                 true
#     BraveShieldsDisabledForUrls                  [ "https://*" "http://*" ]
#   New tab and UI
#     NTPCardsVisible                              false
#     TopSitesToRestrictions                       [ "*.com" "*.org" "*.net" "*.fr" "*" ]
#     TranslateEnabled                             false
#     SpellcheckEnabled                            false
#     SpellCheckServiceEnabled                     false
#     SearchSuggestEnabled                         false
#     PromotionsEnabled                            false
#     DefaultBrowserSettingEnabled                 false
#   Performance and bloat
#     BackgroundModeEnabled                        false
#     MediaRecommendationsEnabled                  false
#     ShoppingListEnabled                          false
#     AlwaysOpenPdfExternally                      true
#     PrintingEnabled                              false
#     DeveloperToolsDisabled                       true
#
# Note: several keys (BraveRewardsDisabled, BraveWalletDisabled, TorDisabled,
# IPFSEnabled, PromotionsEnabled, NTPCardsVisible, …) are Brave-specific and do
# not exist in stock Chromium; and a few may be renamed or removed in future
# Brave releases. Chromium ignores unrecognized policy keys, logging a warning
# on `brave://policy`, so unknown keys are harmless but may be a no-op.
{ config
, lib
, ...
}:

let
  inherit (lib) literalExpression mkEnableOption mkIf mkOption types;

  cfg = config.programs.brave;

  chromeWebStoreUpdateUrl = "https://clients2.google.com/service/update2/crx";

  # Extension IDs taken verbatim from the upstream tool.
  uBlockOriginLite = "ddkjiahejlhfcafbddmgiahcphecmpfh;${chromeWebStoreUpdateUrl}";
  uBlockOrigin = "cjpalhdlnbpafiamejdnhcphjbkeiagm;${chromeWebStoreUpdateUrl}";

  # The fixed value each policy key is set to, as applied by BraveOptimizer.
  catalog = {
    # Telemetry and reporting
    MetricsReportingEnabled = false;
    SafeBrowsingExtendedReportingEnabled = false;
    UrlKeyedAnonymizedDataCollectionEnabled = false;
    FeedbackSurveysEnabled = false;
    UserFeedbackAllowed = false;

    # Privacy and security
    SafeBrowsingProtectionLevel = 0;
    AutofillAddressEnabled = false;
    AutofillCreditCardEnabled = false;
    PaymentMethodQueryEnabled = false;
    PasswordManagerEnabled = false;
    BrowserSignin = 0;
    WebRtcIPHandling = "disable_non_proxied_udp";
    QuicAllowed = false;
    BlockThirdPartyCookies = true;
    EnableDoNotTrack = true;
    ForceGoogleSafeSearch = true;
    IncognitoModeAvailability = 1;
    IPFSEnabled = false;

    # Brave features
    BraveRewardsDisabled = true;
    BraveWalletDisabled = true;
    BraveVPNDisabled = true;
    BraveAIChatEnabled = false;
    BraveNewsDisabled = true;
    BraveTalkDisabled = true;
    TorDisabled = true;
    SyncDisabled = true;
    BraveShieldsDisabledForUrls = [
      "https://*"
      "http://*"
    ];

    # New tab and UI
    NTPCardsVisible = false;
    TopSitesToRestrictions = [
      "*.com"
      "*.org"
      "*.net"
      "*.fr"
      "*"
    ];
    TranslateEnabled = false;
    SpellcheckEnabled = false;
    SpellCheckServiceEnabled = false;
    SearchSuggestEnabled = false;
    PromotionsEnabled = false;
    DefaultBrowserSettingEnabled = false;

    # Performance and bloat
    BackgroundModeEnabled = false;
    MediaRecommendationsEnabled = false;
    ShoppingListEnabled = false;
    AlwaysOpenPdfExternally = true;
    PrintingEnabled = false;
    DeveloperToolsDisabled = true;
  };

  # The policy keys shared by every preset: telemetry, autofill, the password
  # manager, WebRTC IP leaks, the Brave Rewards/Wallet/VPN/AI/News/Talk/Tor/Sync
  # features, new-tab clutter and background bloat are all disabled or locked.
  corePolicyKeys = [
    "MetricsReportingEnabled"
    "SafeBrowsingExtendedReportingEnabled"
    "UrlKeyedAnonymizedDataCollectionEnabled"
    "FeedbackSurveysEnabled"
    "UserFeedbackAllowed"
    "AutofillAddressEnabled"
    "AutofillCreditCardEnabled"
    "PaymentMethodQueryEnabled"
    "PasswordManagerEnabled"
    "BrowserSignin"
    "WebRtcIPHandling"
    "BlockThirdPartyCookies"
    "EnableDoNotTrack"
    "IPFSEnabled"
    "BraveRewardsDisabled"
    "BraveWalletDisabled"
    "BraveVPNDisabled"
    "BraveAIChatEnabled"
    "BraveNewsDisabled"
    "BraveTalkDisabled"
    "TorDisabled"
    "SyncDisabled"
    "NTPCardsVisible"
    "TopSitesToRestrictions"
    "TranslateEnabled"
    "SpellcheckEnabled"
    "SpellCheckServiceEnabled"
    "SearchSuggestEnabled"
    "PromotionsEnabled"
    "DefaultBrowserSettingEnabled"
    "BackgroundModeEnabled"
    "MediaRecommendationsEnabled"
    "ShoppingListEnabled"
  ];

  # Presets reproduce upstream `Presets/*.json`. They differ only in a few
  # extra policy keys and their DNS-over-HTTPS mode, and every preset
  # force-installs uBlock Origin Lite (MV3), matching the tool's behaviour.
  presets = lib.mapAttrs
    (name: preset: {
      inherit (preset) dnsOverHttpsMode;
      extensionInstallForcelist = [ uBlockOriginLite ];
      policies = lib.genAttrs preset.policyKeys (k: catalog.${k});
    })
    {
      privacy = {
        dnsOverHttpsMode = "off";
        policyKeys = corePolicyKeys ++ [ "QuicAllowed" ];
      };

      performance = {
        dnsOverHttpsMode = "custom";
        policyKeys = corePolicyKeys ++ [
          "IncognitoModeAvailability"
          "BraveShieldsDisabledForUrls"
          "PrintingEnabled"
          "DeveloperToolsDisabled"
        ];
      };

      performance-and-privacy = {
        dnsOverHttpsMode = "off";
        policyKeys = corePolicyKeys ++ [
          "QuicAllowed"
          "BraveShieldsDisabledForUrls"
          "AlwaysOpenPdfExternally"
          "PrintingEnabled"
        ];
      };
    };

  preset = if cfg.preset == null then null else presets.${cfg.preset};

  dnsOverHttpsMode =
    if cfg.dnsOverHttpsMode != null then
      cfg.dnsOverHttpsMode
    else if preset != null then
      preset.dnsOverHttpsMode
    else
      null;

  extensionInstallForcelist = (if preset != null then preset.extensionInstallForcelist else [ ]) ++ cfg.extensions;

  finalPolicies =
    (if preset != null then preset.policies else { })
    // (lib.optionalAttrs (dnsOverHttpsMode != null) { DnsOverHttpsMode = dnsOverHttpsMode; })
    // (lib.optionalAttrs (cfg.dnsOverHttpsTemplates != null) { DnsOverHttpsTemplates = cfg.dnsOverHttpsTemplates; })
    // (lib.optionalAttrs (extensionInstallForcelist != [ ]) { ExtensionInstallForcelist = extensionInstallForcelist; })
    // cfg.extraPolicies;

  policyText = builtins.toJSON finalPolicies;
in
{
  options.programs.brave = {
    enable = mkEnableOption "Brave Browser policies";

    preset = mkOption {
      type = types.nullOr (types.enum [
        "privacy"
        "performance"
        "performance-and-privacy"
      ]);
      default = null;
      example = "privacy";
      description = ''
        Apply one of the presets shipped by
        [BraveOptimizer](https://github.com/insovs/BraveOptimizer). All three
        presets disable telemetry, autofill, the password manager, browser
        sign-in, WebRTC IP leaks, and the Brave Rewards/Wallet/VPN/AI/News/Talk/
        Tor/Sync features, and force-install uBlock Origin Lite:

        - `"privacy"`: plain DNS (`off`), keeps Safe Browsing and incognito.
        - `"performance"`: custom DNS-over-HTTPS, also disables incognito,
          Brave Shields, printing and DevTools.
        - `"performance-and-privacy"`: plain DNS (`off`), disables Brave
          Shields and printing, opens PDFs externally.

        Individual keys can be overridden or added with {option}`programs.brave.extraPolicies`,
        which takes precedence over the preset.
      '';
    };

    dnsOverHttpsMode = mkOption {
      type = types.nullOr (types.enum [
        "automatic"
        "off"
        "custom"
      ]);
      default = null;
      example = "off";
      description = ''
        DNS-over-HTTPS mode, corresponding to the `DnsOverHttpsMode` policy.
        Overrides the preset's default when set. `"custom"` additionally
        requires {option}`programs.brave.dnsOverHttpsTemplates` to point at a
        resolver.
      '';
    };

    dnsOverHttpsTemplates = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "https://cloudflare-dns.com/dns-query";
      description = ''
        URI template for `DnsOverHttpsTemplates`, used when
        {option}`programs.brave.dnsOverHttpsMode` is `"custom"`.
      '';
    };

    extensions = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = literalExpression ''
        [
          "ddkjiahejlhfcafbddmgiahcphecmpfh;https://clients2.google.com/service/update2/crx" # uBlock Origin Lite
          "cjpalhdlnbpafiamejdnhcphjbkeiagm;https://clients2.google.com/service/update2/crx" # uBlock Origin
        ]
      '';
      description = ''
        Additional extensions to force-install via `ExtensionInstallForcelist`,
        appended to any extensions added by {option}`programs.brave.preset`.
        Each entry is either a bare extension id or an
        `"id;updateUrl"` pair. To replace the preset's extension list entirely,
        set `ExtensionInstallForcelist` in {option}`programs.brave.extraPolicies`.
      '';
    };

    extraPolicies = mkOption {
      type = types.attrs;
      default = { };
      example = literalExpression ''
        {
          PasswordManagerEnabled = true;
          SafeBrowsingProtectionLevel = 1;
        }
      '';
      description = ''
        Extra Brave policy options, merged on top of the selected
        {option}`programs.brave.preset` (and taking precedence over it). See
        the module's source or the Chrome Enterprise documentation for the
        available keys:
        <https://cloud.google.com/docs/chrome-enterprise/policies/>.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."brave/policies/managed/brave-optimizer.json" =
      lib.mkIf (finalPolicies != { })
        {
          text = policyText;
        };
  };
}
