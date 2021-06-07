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
      solc-static-versions.solc_0_7_6
      nodejs
    ];
    DAPP_SOLC="solc-0.7.6";
    DAPP_REMAPPINGS=pkgs.lib.strings.fileContents ./remappings.txt;
    DAPP_LINK_TEST_LIBRARIES=0;
  }
