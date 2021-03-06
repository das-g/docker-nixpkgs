{ writeText, lib }:
# Build a user environment purely with nix.
#
# The original implementation is a mix of C++ and nix code.
#
# See https://github.com/nixos/nix/blob/f4b94958543138671bc3641fc126589a5cffb24b/src/nix-env/user-env.cc
#
# TODO:
# * also add the drvPath if the keepDerivations nix settings is set
# * support "disabled" mode that breaks nix-env?
# * remove the use of writeText. builtins.toFile forbits the use of references
#   to derivations, which makes it impossible to create exactly the same
#   manifest file as `nix-env`.
#
# Arguments:
# * derivations: a list of derivations
{
  # A list of derivations to install
  derivations
}:
# Supporting code
with builtins;
let
  # Copied from https://github.com/nixos/nix/blob/e02481ded216ffb5b06b413e3695d4e11e62e02f/corepkgs/buildenv.nix
  #
  # This was available at <nix/buildenv.nix>, until it got removed in Nix.
  buildenv = { derivations, manifest }:
    derivation {
      name = "user-environment";
      system = "builtin";
      builder = "builtin:buildenv";

      inherit manifest;

      # !!! grmbl, need structured data for passing this in a clean way.
      derivations =
        map
          (d:
            [
              (d.meta.active or "true")
              (d.meta.priority or 5)
              (builtins.length d.outputs)
            ] ++ map (output: builtins.getAttr output d) d.outputs)
          derivations;

      # Building user environments remotely just causes huge amounts of
      # network traffic, so don't do that.
      preferLocalBuild = true;

      # Also don't bother substituting.
      allowSubstitutes = false;
    };

  # back-compat
  isPath = builtins.isPath or (x: builtins.typeOf x == "path");

  # Escape Nix strings
  stringEscape = str:
    "\"" + (
      replaceStrings
        [ "\\" "\"" "\n" "\r" "\t" ]
        [ "\\\\" "\\" "\\n" "\\r" "\\t" ]
        str
    )
    + "\"";

  # Like builtins.JSON but to output Nix code
  toNix = value:
    if isString value then stringEscape value
    else if isInt value then toString value
    else if isPath value then toString value
    else if true == value then "true"
    else if false == value then "false"
    else if null == value then "null"
    else if isAttrs value then
      "{ " + concatStringsSep " " (lib.mapAttrsToList (k: v: "${k} = ${toNix v};") value) + " }"
    else if isList value then
      "[ ${ concatStringsSep " " (map toNix value) } ]"
    else throw "type ${typeOf value} not supported";

  # Generate a nix-env compatible manifest.nix file
  genManifest = drv:
    let
      outputs =
        drv.meta.outputsToInstall or
          # install the first output
          [ (head drv.outputs) ];

      base = {
        inherit (drv) meta name outPath system type;
        out = { inherit (drv) outPath; };
        inherit outputs;
      };

      toOut = name: {
        outPath = drv.${name}.outPath;
      };

      outs = lib.genAttrs outputs toOut;
    in
    base // outs;

  writeManifest = derivations:
    writeText "env-manifest.nix" (
      toNix (map genManifest derivations)
    );
in
buildenv {
  inherit derivations;
  manifest = writeManifest derivations;
}
