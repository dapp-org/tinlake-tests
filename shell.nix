let
  sources = import ./nix/sources.nix;
  pkgs = import sources.dapptools {};
in
  pkgs.mkShell {
    buildInputs = with pkgs; [
      dapp
      seth
      hevm
      niv
      solc-static-versions.solc_0_6_12
    ];
    DAPP_SOLC="solc-0.6.12";
    DAPP_REMAPPINGS=pkgs.lib.strings.fileContents ./remappings.txt;
  }
