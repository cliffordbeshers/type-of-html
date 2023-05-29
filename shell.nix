with (import <nixpkgs> { });
let
  cabalName = "type-of-html";
  client =
       haskell.packages.ghcjs86.developPackage
        { root = ./.;
          name = cabalName;
          modifier = drv: haskell.lib.addBuildDepends drv
            (with haskell.packages.ghcjs86;
              # add extra ghc libraries here
              [acme-iot]);
        };
  server =
       haskell.packages.ghc865.developPackage
        { root = ./.;
          name = cabalName;
          modifier = drv: haskell.lib.addBuildDepends drv
            (with haskell.packages.ghc865;
              # add extra ghc libraries here
              [shelly sr-build cabal-install cabal-plan raw-strings-qq acme-iot forest data-forest aeson-pretty aeson hsass hjsmin]);
        };
  merge = { mk ? stdenv.mkDerivation, client, server}:
      mk
       { name = client.name + "-and-" + server.name;
         buildInputs = [ client.buildInputs server.buildInputs ];
         nativeBuildInputs = [ client.nativeBuildInputs server.nativeBuildInputs ];
       };
  in merge {client=client; server=server; }
