#!/bin/bash
# A code signing identity of this Mac's own, for people without an Apple Development certificate
# (no Xcode or Apple ID). Ad-hoc signing changes with every build, so macOS asks for Screen
# Recording again after each update; a certificate that stays the same keeps the permissions.
#
#   scripts/local-signing.sh identity   # creates it once, prints its SHA-1 for codesign
#   scripts/local-signing.sh remove     # deletes it (part of uninstalling)
#
# The certificate lives in its own keychain, not in the login keychain, with a random password
# kept next to it (readable only by you). The keychain is added to your keychain search list,
# because codesign only looks there. It signs nothing but Bugbear builds on this Mac.
set -euo pipefail

FOLDER="$HOME/Library/Application Support/Bugbear/Signing"
KEYCHAIN="$FOLDER/bugbear-signing.keychain-db"
PASSWORD_FILE="$FOLDER/password"
NAME="Bugbear Local Signing"

# The user keychain search list, one path per line, without the quotes security prints.
search_list() {
    security list-keychains -d user | sed -E 's/^[[:space:]]*"(.*)"[[:space:]]*$/\1/'
}

is_in_search_list() {
    local entry
    while IFS= read -r entry; do
        if [ "$entry" = "$KEYCHAIN" ]; then
            return 0
        fi
    done < <(search_list)
    return 1
}

add_to_search_list() {
    if is_in_search_list; then
        return
    fi
    local keychains=()
    local entry
    while IFS= read -r entry; do
        if [ -n "$entry" ]; then
            keychains+=("$entry")
        fi
    done < <(search_list)
    keychains+=("$KEYCHAIN")
    security list-keychains -d user -s "${keychains[@]}"
}

remove_from_search_list() {
    if ! is_in_search_list; then
        return
    fi
    local keychains=()
    local entry
    while IFS= read -r entry; do
        if [ -n "$entry" ] && [ "$entry" != "$KEYCHAIN" ]; then
            keychains+=("$entry")
        fi
    done < <(search_list)
    security list-keychains -d user -s "${keychains[@]}"
}

create_identity() {
    mkdir -p "$FOLDER"
    chmod 700 "$FOLDER"
    local password
    password="$(/usr/bin/openssl rand -hex 24)"
    (umask 077 && printf '%s' "$password" > "$PASSWORD_FILE")

    local work
    work="$(mktemp -d)"
    cat > "$work/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 7300 -config "$work/cert.cnf" \
        -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
    /usr/bin/openssl pkcs12 -export -name "$NAME" -inkey "$work/key.pem" -in "$work/cert.pem" \
        -out "$work/identity.p12" -passout "pass:$password"

    rm -f "$KEYCHAIN"
    security create-keychain -p "$password" "$KEYCHAIN"
    # No auto-lock: builds unlock it with the saved password anyway.
    security set-keychain-settings "$KEYCHAIN"
    security unlock-keychain -p "$password" "$KEYCHAIN"
    security import "$work/identity.p12" -k "$KEYCHAIN" -P "$password" -T /usr/bin/codesign >/dev/null
    # Lets codesign use the key without a password dialog.
    security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$KEYCHAIN" >/dev/null
    rm -rf "$work"
}

identity_hash() {
    security find-certificate -c "$NAME" -Z "$KEYCHAIN" 2>/dev/null | awk '/^SHA-1 hash:/ { print $3 }' | head -1
}

case "${1:-}" in
    identity)
        if [ ! -f "$KEYCHAIN" ] || [ ! -f "$PASSWORD_FILE" ]; then
            create_identity >&2
        fi
        security unlock-keychain -p "$(cat "$PASSWORD_FILE")" "$KEYCHAIN"
        add_to_search_list
        hash="$(identity_hash)"
        if [ -z "$hash" ]; then
            echo "The local signing certificate is missing from $KEYCHAIN" >&2
            exit 1
        fi
        echo "$hash"
        ;;
    remove)
        remove_from_search_list
        rm -rf "$FOLDER"
        echo "Removed the local signing certificate."
        ;;
    *)
        echo "usage: scripts/local-signing.sh identity|remove" >&2
        exit 2
        ;;
esac
