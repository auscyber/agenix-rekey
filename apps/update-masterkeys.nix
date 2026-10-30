{ pkgs, ... }@inputs:
let
  inherit (import ../nix/lib.nix inputs)
    ageMasterEncrypt
    ageMasterDecrypt
    validRelativeSecretPaths
    ;
in
pkgs.writeShellScriptBin "agenix-update-masterkeys" ''
  set -uo pipefail

  function die() { echo "[1;31merror:[m $*" >&2; exit 1; }
  function show_help() {
    echo 'Usage: agenix update-masterkeys'
    echo 'Update all stored secrets with a new set of masterkeys.'
  }

  if [[ ! -e flake.nix ]] ; then
    die "Please execute this script from your flake's root directory."
  fi

  # A source no master can decrypt is skipped and named at the end, rather
  # than aborting every file after it.
  UNREADABLE=()

  ${builtins.concatStringsSep "" (
    builtins.map (
      path: # bash
      ''
        CLEARTEXT_FILE=$(${pkgs.coreutils}/bin/mktemp)
        ENCRYPTED_FILE=$(${pkgs.coreutils}/bin/mktemp)

        function cleanup() {
          [[ -e "$CLEARTEXT_FILE" ]] && rm "$CLEARTEXT_FILE"
          [[ -e "$ENCRYPTED_FILE" ]] && rm "$ENCRYPTED_FILE"
        }; trap "cleanup" EXIT

        shasum_before="$(${pkgs.coreutils}/bin/sha512sum "${path}")"

        if ${ageMasterDecrypt} -o "$CLEARTEXT_FILE" "${path}"; then
        ${ageMasterEncrypt} -o "$ENCRYPTED_FILE" "$CLEARTEXT_FILE" \
            || die "Failed to re-encrypt file. Aborting."

        shasum_after="$(${pkgs.coreutils}/bin/sha512sum "$ENCRYPTED_FILE")"
        if [[ "$shasum_before" == "$shasum_after" ]]; then
          echo "[1;90m    Skipping[m [90m[already rekeyed] "${path}"[m"
        else
          ${pkgs.coreutils}/bin/cp --no-preserve=all "$ENCRYPTED_FILE" "${path}" # cp instead of mv preserves original attributes and permissions
          echo "[1;32m    Updated masterkeys of[m [34m"${path}"[m"
        fi
        else
          echo "    Unreadable [no master decrypts it] ${path}" >&2
          UNREADABLE+=("${path}")
        fi

        rm -f "$CLEARTEXT_FILE"
        rm -f "$ENCRYPTED_FILE"
      '') validRelativeSecretPaths
  )}
  if [[ ''${#UNREADABLE[@]} -gt 0 ]]; then
    echo "''${#UNREADABLE[@]} source(s) left unchanged, no master could decrypt them:" >&2
    printf '  %s\n' "''${UNREADABLE[@]}" >&2
    exit 1
  fi
  exit 0
''
