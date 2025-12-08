{
  description = "minimal yt-dlp OCI image with Deno";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        # read the pinned source info
        sourceData = builtins.fromJSON (builtins.readFile ./sources.json);

        # define the yt-dlp binary package using that info
        yt-dlp-bin = pkgs.runCommand "yt-dlp-bin" { } ''
          mkdir -p $out/bin
          # Fetch the binary using the hash from sources.json
          cp ${pkgs.fetchurl {
            url = sourceData.url;
            sha256 = sourceData.hash;
          }} $out/bin/yt-dlp
        '';

        # define the image definition here so we can reuse it
        image = pkgs.dockerTools.buildLayeredImage {
          name = "localhost/yt-dlp-image";
          tag = sourceData.version; 
          
          fakeRootCommands = ''
            mkdir -p ./tmp ./downloads
            chmod 1777 ./tmp
          '';

          contents = [
            yt-dlp-bin             # the binary we fetched
            pkgs.cacert            # required for HTTPS
            pkgs.python3           # runtime for yt-dlp
            pkgs.deno              # JS runtime
            pkgs.ffmpeg-headless   # for merging video/audio
            pkgs.unzip
            pkgs.coreutils
          ];

          config = {
            Entrypoint = [ "/bin/python3" "/bin/yt-dlp" ];
            WorkingDir = "/downloads";
            Env = [
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              "HOME=/tmp"
              "DENO_DIR=/tmp/deno_cache"
            ];
          };
        };

      in
      {
        packages = {
          # This allows you to just run: nix build
          default = image;
        };
      });
}
