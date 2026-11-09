# Tests for the programs.brave policy module, a declarative reimplementation of
# the BraveOptimizer PowerShell tool. Each node boots a minimal machine and the
# test asserts on the generated Chromium policy JSON under /etc/brave/policies/.
{ ...
}:

let
  uBlockOriginLite = "ddkjiahejlhfcafbddmgiahcphecmpfh;https://clients2.google.com/service/update2/crx";
  uBlockOrigin = "cjpalhdlnbpafiamejdnhcphjbkeiagm;https://clients2.google.com/service/update2/crx";
in
{
  name = "brave";

  nodes = {
    privacy =
      { ... }:
      {
        programs.brave = {
          enable = true;
          preset = "privacy";
        };
      };

    performance =
      { ... }:
      {
        programs.brave = {
          enable = true;
          preset = "performance";
          dnsOverHttpsMode = "custom";
          dnsOverHttpsTemplates = "https://cloudflare-dns.com/dns-query";
          extensions = [ uBlockOrigin ];
        };
      };

    recommended =
      { ... }:
      {
        programs.brave = {
          enable = true;
          preset = "performance-and-privacy";
          recommended = true;
          extraPolicies = {
            PrintingEnabled = true;
          };
        };
      };

    disabled =
      { ... }:
      {
        programs.brave = {
          enable = false;
          preset = "privacy";
        };
      };
  };

  testScript = ''
    import json

    start_all()

    # The "privacy" preset writes a managed (locked) policy file.
    privacy = json.loads(
        privacy.succeed("cat /etc/brave/policies/managed/brave-optimizer.json"))
    assert privacy["MetricsReportingEnabled"] is False
    assert privacy["QuicAllowed"] is False
    assert privacy["DnsOverHttpsMode"] == "off"
    assert privacy["ExtensionInstallForcelist"] == ["${uBlockOriginLite}"]
    # The privacy preset keeps Safe Browsing, incognito and Brave Shields.
    assert "SafeBrowsingProtectionLevel" not in privacy
    assert "IncognitoModeAvailability" not in privacy
    assert "BraveShieldsDisabledForUrls" not in privacy

    # dnsOverHttpsMode/extensions override the preset; the forcelist is appended.
    performance = json.loads(
        performance.succeed("cat /etc/brave/policies/managed/brave-optimizer.json"))
    assert performance["DnsOverHttpsMode"] == "custom"
    assert performance["DnsOverHttpsTemplates"] == "https://cloudflare-dns.com/dns-query"
    assert performance["IncognitoModeAvailability"] == 1
    assert performance["BraveShieldsDisabledForUrls"] == [
        "https://*",
        "http://*",
    ]
    assert performance["PrintingEnabled"] is False
    assert performance["DeveloperToolsDisabled"] is True
    assert performance["ExtensionInstallForcelist"] == [
        "${uBlockOriginLite}",
        "${uBlockOrigin}",
    ]
    # The performance preset does not disable QUIC or open PDFs externally.
    assert "QuicAllowed" not in performance
    assert "AlwaysOpenPdfExternally" not in performance

    # recommended=true writes a user-changeable policy instead of a managed one.
    recommended.succeed(
        "test ! -e /etc/brave/policies/managed/brave-optimizer.json")
    rec = json.loads(
        recommended.succeed("cat /etc/brave/policies/recommended/brave-optimizer.json"))
    assert rec["AlwaysOpenPdfExternally"] is True
    assert rec["QuicAllowed"] is False
    # extraPolicies take precedence over the preset.
    assert rec["PrintingEnabled"] is True
    assert "DeveloperToolsDisabled" not in rec
    assert "IncognitoModeAvailability" not in rec

    # enable=false writes nothing, even with a preset selected.
    disabled.succeed(
        "test ! -e /etc/brave/policies/managed/brave-optimizer.json")
    disabled.succeed(
        "test ! -e /etc/brave/policies/recommended/brave-optimizer.json")
  '';
}
