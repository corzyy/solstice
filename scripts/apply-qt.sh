#!/usr/bin/env bash
# apply-qt.sh — point qt5ct/qt6ct at the matugen-generated colors (jhqs).
# Adapted from DankMaterialShell quickshell/scripts/qt.sh:
# DMS points qt*ct at ~/.local/share/color-schemes/DankMatugen.colors,
# jhqs generates ~/.config/qt{5,6}ct/colors/matugen.conf via matugen instead,
# so we only flip qt*ct.conf to custom_palette + color_scheme_path.
set -u

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"

apply_qt_colors() {
    local qt5_conf="$CONFIG_DIR/qt5ct/qt5ct.conf"
    local qt6_conf="$CONFIG_DIR/qt6ct/qt6ct.conf"
    local qt5_scheme="$CONFIG_DIR/qt5ct/colors/matugen.conf"
    local qt6_scheme="$CONFIG_DIR/qt6ct/colors/matugen.conf"

    update_qt_config() {
        local config_file="$1"
        local scheme_path="$2"

        if [ ! -f "$scheme_path" ]; then
            echo "Note: color scheme not found yet at $scheme_path (run matugen first)" >&2
        fi

        if [ -f "$config_file" ]; then
            if grep -q '^\[Appearance\]' "$config_file"; then
                if grep -q '^custom_palette=' "$config_file"; then
                    sed -i 's/^custom_palette=.*/custom_palette=true/' "$config_file"
                else
                    sed -i '/^\[Appearance\]/a custom_palette=true' "$config_file"
                fi
                if grep -q '^color_scheme_path=' "$config_file"; then
                    sed -i "s|^color_scheme_path=.*|color_scheme_path=$scheme_path|" "$config_file"
                else
                    sed -i "/^\\[Appearance\\]/a color_scheme_path=$scheme_path" "$config_file"
                fi
            else
                {
                    echo ""
                    echo "[Appearance]"
                    echo "custom_palette=true"
                    echo "color_scheme_path=$scheme_path"
                } >>"$config_file"
            fi
        else
            mkdir -p "$(dirname "$config_file")"
            printf '[Appearance]\ncustom_palette=true\ncolor_scheme_path=%s\n' "$scheme_path" >"$config_file"
        fi
    }

    local qt5_applied=false
    local qt6_applied=false

    if command -v qt5ct >/dev/null 2>&1 || [ -f "$qt5_conf" ] || [ -f "$qt5_scheme" ]; then
        mkdir -p "$CONFIG_DIR/qt5ct"
        update_qt_config "$qt5_conf" "$qt5_scheme"
        echo "Applied Qt5ct configuration"
        qt5_applied=true
    fi

    if command -v qt6ct >/dev/null 2>&1 || [ -f "$qt6_conf" ] || [ -f "$qt6_scheme" ]; then
        mkdir -p "$CONFIG_DIR/qt6ct"
        update_qt_config "$qt6_conf" "$qt6_scheme"
        echo "Applied Qt6ct configuration"
        qt6_applied=true
    fi

    if [ "$qt5_applied" = false ] && [ "$qt6_applied" = false ]; then
        echo "Warning: neither qt5ct nor qt6ct found" >&2
        echo "Install qt5ct or qt6ct for Qt application theming" >&2
        exit 1
    fi
}

apply_qt_colors

echo "Qt colors applied successfully"
