#!/bin/bash
set -u

SOURCES_ONLY=0
[[ ${1:-} == "--sources" ]] && SOURCES_ONLY=1

has_system=0
has_flatpak=0

emit() {
    case "$1" in
        system) has_system=1 ;;
        flatpak) has_flatpak=1 ;;
    esac
    (( SOURCES_ONLY )) && return 0
    printf '%s\t%s\t%s\n' "$1" "$2" "$3"
}

if command -v dnf >/dev/null 2>&1; then
    # Preferred: machine-readable upgrade list (name|version|repo).
    # NOTE: an *empty* result with exit 0 means "no upgrades" — only fall
    # back to `dnf check-upgrade` when repoquery itself FAILS. The fallback
    # refreshes metadata and is slow (broken-repo retries), so it must not
    # run on every check when the system is simply up to date.
    # -y answers any repo GPG-import prompt non-interactively (no stdin hang).
    if upgrades="$(timeout 120 dnf -y repoquery --upgrades --queryformat '%{NAME}|%{VERSION}-%{RELEASE}|%{REPONAME}\n' -q < /dev/null 2>/dev/null)"; then
        while IFS='|' read -r package new_version repo; do
            [[ -n ${package:-} ]] && emit system "$package" "-> ${new_version:-?}${repo:+ ($repo)}"
        done <<< "$upgrades"
    else
        # Fallback: human-readable `dnf check-upgrade` (name.arch version repo).
        while read -r package new_version repo; do
            [[ $package == "Last" || $package == "Keine" || $package == "No" ]] && continue
            [[ $package != *.* ]] && continue
            name="${package%.*}"
            [[ -n ${name:-} ]] && emit system "$name" "-> ${new_version:-?}${repo:+ ($repo)}"
        done < <(timeout 120 dnf -y check-upgrade -q < /dev/null 2>/dev/null || true)
    fi
fi

if command -v flatpak >/dev/null 2>&1; then
    while IFS=$'\t' read -r app version size; do
        [[ -n ${app:-} ]] && emit flatpak "$app" "${version:-Update available}${size:+ · $size}"
    done < <(timeout 60 flatpak remote-ls --updates --columns=application,version,download-size 2>/dev/null || true)
fi

if (( SOURCES_ONLY )); then
    if (( has_system )); then echo system; fi
    if (( has_flatpak )); then echo flatpak; fi
fi
