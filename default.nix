{ lib, gnumake, swiftPackages }:

let
  inherit (swiftPackages) stdenv swift;
in
stdenv.mkDerivation {
  pname = "mtuprotect";
  version = "1.0";

  src = ./.;

  nativeBuildInputs = [ swift gnumake ];

  buildPhase = ''
    make
  '';

  installPhase = ''
    make install DESTDIR=$out
  '';

  meta = with lib; {
    description = "Automatically set MTU for broken VPNs like GlobalProtect.";
    homepage = "https://github.com/jdek/mtuprotect";
    license = licenses.wtfpl;
    maintainers = [ maintainers.jdek ];
    platforms = platforms.darwin;
  };
}
