#!/bin/bash
#================================================================================================
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of the make OpenWrt for Amlogic s9xxx tv box
# https://github.com/ophub/amlogic-s9xxx-openwrt
#
# Description: Build OpenWrt with Image Builder
# Copyright (C) 2021~ https://github.com/unifreq/openwrt_packit
# Copyright (C) 2021~ https://github.com/ophub/amlogic-s9xxx-openwrt
# Copyright (C) 2021~ https://downloads.openwrt.org/releases
# Copyright (C) 2023~ https://downloads.immortalwrt.org/releases
#
# Download from: https://downloads.openwrt.org/releases
#                https://downloads.immortalwrt.org/releases
#
# Documentation: https://openwrt.org/docs/guide-user/additional-software/imagebuilder
# Instructions:  Download OpenWrt firmware from the official OpenWrt,
#                Use Image Builder to add packages, lib, theme, app and i18n, etc.
#
# Command: ./config/imagebuilder/imagebuilder.sh <source:branch>
#          ./config/imagebuilder/imagebuilder.sh openwrt:21.02.3
#
#======================================== Functions list ========================================
#
# error_msg               : Output error message
# download_imagebuilder   : Downloading OpenWrt ImageBuilder
# adjust_settings         : Adjust related file settings
# custom_packages         : Add custom packages
# custom_config           : Add custom config
# custom_files            : Add custom files
# rebuild_firmware        : rebuild_firmware
#
#================================ Set make environment variables ================================
#
# Set default parameters
openwrt_hostname="Secretlab"

root_path="${PWD}"
openwrt_dir="OpenWrt"
openwrt_path="${root_path}/${openwrt_dir}"
imagebuilder_archive_path="${openwrt_path}/archive"
imagebuilder_path="${openwrt_path}/build"
imagebuilder_bin="${imagebuilder_path}/bin"
rebuild_path="${openwrt_path}/dist"

out_path="${root_path}/build"
tmp_path="${root_path}/.tmp"
resources_path="${root_path}/src"
config_path="${resources_path}/config.default.conf"
packages_path="${resources_path}/packages.conf"
packages_uri_path="${resources_path}/packages.ipk.conf"
repositories_path="${resources_path}/repositories.conf"
files_path="${resources_path}/files"
common_files_path="$openwrt_path/openwrt-files/common-files"
platform_files_path="$openwrt_path/openwrt-files/platform-files"
different_files_path="$openwrt_path/openwrt-files/different-files"

model_conf="${resources_path}/model/database.conf"
model_txt="${resources_path}/model/database.txt"

depends_path="${openwrt_path}/ophub/amlogic-s9xxx-armbian"
uboot_path="${openwrt_path}/ophub/u-boot"
firmware_path="${openwrt_path}/ophub/firmware"
script_path="${openwrt_path}/ophub/luci-app-amlogic"
kernel_path="${openwrt_path}/ophub/kernel"

# Repository
depends_repo="ophub/amlogic-s9xxx-armbian"
uboot_repo="ophub/u-boot"
firmware_repo="ophub/firmware"
script_repo="ophub/luci-app-amlogic"
kernel_repo="ophub/kernel"

# System operation environment
arch_info="$(uname -m)"
host_release="$(cat /etc/os-release | grep '^VERSION_CODENAME=.*' | cut -d'=' -f2)"
op_release="etc/flippy-openwrt-release"

default_tags="stable"
kernel_usage=""
stable_kernel=("6.6.y")
flippy_kernel=(${stable_kernel[@]})
dev_kernel=(${stable_kernel[@]})
beta_kernel=(${stable_kernel[@]})
rk3588_kernel=("5.10.y")
rk35xx_kernel=("5.10.y")
h6_kernel=("6.6.y")
specific_6xy=("6.6.y" "6.1.y")
specific_5xy=("5.15.y" "5.10.y" "5.4.y")
auto_kernel="true"
declare -A tags_list

openwrt_packages=()
openwrt_rootfs_file="*rootfs.tar.gz"
# Initialize the build device
openwrt_version="latest"
openwrt_board="s905x"
# Set OpenWrt firmware size (Unit: MiB, boot_mb >= 256, root_mb >= 512)
boot_mb="256"
root_mb="1024"
# Set OpenWrt builder signature
builder_name="nsmle"

is_on_wsl=$(grep -qE "(Microsoft|WSL)" /proc/version 2>/dev/null && echo "true" || echo "false")

# Set default parameters
PROCESS="[ 🌿 ]"
STEP="[\033[95m STEP \033[0m]"
INFO="[\033[94m INFO \033[0m]"
SUCCESS="[\033[92m SUCCESS \033[0m]"
WARNING="[\033[93m WARNING \033[0m]"
ERROR="[\033[91m ERROR \033[0m]"

# Set default parameters
#
#================================================================================================

# Error message

error_msg() {
    echo -e "[ 💔 ] ${1}"
    exit 1
}

# Process message
process_msg() {
    echo -e "${PROCESS} ${1}"
}

# Initializing variables
init_var() {
    echo -e "${STEP} Start Initializing Variables..."

    # If it is followed by [ : ], it means that the option requires a parameter value
    get_all_ver="$(getopt "b:r:u:k:a:s:n:v:" "${@}")"

    while [[ -n "${1}" ]]; do
        case "${1}" in
        -o | --output)
            if [[ -n "${2}" ]]; then
                out_path="${2// /}"
                shift
            else
                error_msg "Invalid -o parameter [ ${2} ]!"
            fi
            ;;
        -b | --board)
            if [[ -n "${2}" ]]; then
                openwrt_board="${2// /}"
                shift
            else
                error_msg "Invalid -b parameter [ ${2} ]!"
            fi
            ;;
        -r | --kernel-repository)
            if [[ -n "${2}" ]]; then
                kernel_repo="${2}"
                shift
            else
                error_msg "Invalid -r parameter [ ${2} ]!"
            fi
            ;;
        -u | --kernel-usage)
            if [[ -n "${2}" ]]; then
                kernel_usage="${2//kernel_/}"
                shift
            else
                error_msg "Invalid -u parameter [ ${2} ]!"
            fi
            ;;
        -k | --kernel)
            if [[ -n "${2}" ]]; then
                oldIFS="${IFS}"
                IFS="_"
                flippy_kernel=(${2})
                stable_kernel=(${2})
                dev_kernel=(${2})
                beta_kernel=(${2})
                IFS="${oldIFS}"
                shift
            else
                error_msg "Invalid -k parameter [ ${2} ]!"
            fi
            ;;
        -a | --auto-kernel)
            if [[ -n "${2}" ]]; then
                auto_kernel="${2}"
                shift
            else
                error_msg "Invalid -a parameter [ ${2} ]!"
            fi
            ;;
        -s | --size)
            if [[ -n "${2}" ]]; then
                img_mb="${2}"
                shift
            else
                error_msg "Invalid -s parameter [ ${2} ]!"
            fi
            ;;
        -v | --openwrt-version)
            if [[ -n "${2}" ]]; then
                openwrt_version="${2}"
                shift
            else
                error_msg "Invalid -v parameter [ ${2} ]!"
            fi
            ;;
        -n | --builder-name)
            if [[ -n "${2}" ]]; then
                builder_name="${2// /}"
                shift
            else
                error_msg "Invalid -n parameter [ ${2} ]!"
            fi
            ;;
        *)
            error_msg "Invalid option [ ${1} ]!"
            ;;
        esac
        shift
    done

    # Set the image size, such as [ -s 512/2560 ] or [ -s 2560 ]
    [[ -n "${img_mb}" ]] && {
        if [[ "${img_mb}" =~ / ]]; then
            boot_mb="${img_mb%%/*}"
            root_mb="${img_mb##*/}"
        else
            root_mb="${img_mb}"
        fi
    }
}

# Check latest version of OpenWrt
get_latest_openwrt_version() {
    echo -e "${STEP} Getting latest version of OpenWrt"
    local openwrt_release_uri="https://api.github.com/repos/openwrt/openwrt/releases"

    local versions=$(curl -s "$openwrt_release_uri" | grep '"tag_name":' | awk -F '"' '{print $4}')
    local latest_version=""

    tput civis
    for version in $versions; do
        tput cuu1 && tput el
        echo -e "${PROCESS} OpenWrt $version"
        sleep .1
        [[ $version == *"-rc"* || $version == *"-beta"* || $version == *"-alpha"* ]] && continue
        [[ -z "$latest_version" || "$version" > "$latest_version" ]] && latest_version="$version"
    done
    tput cvvis

    tput cuu1 && tput el
    if [[ -n "$latest_version" ]]; then
        openwrt_version=$(echo "$latest_version" | sed 's/^v//')
        echo -e "${INFO} Latest version of OpenWrt is $latest_version"
    else
        error_msg "Failed get latest version of OpenWrt\nPlease specify the OpenWrt Branch, such as [ ${0} openwrt:23.05.4 ]"
    fi
}

# Downloading OpenWrt ImageBuilder
download_imagebuilder() {
    cd ${root_path}
    [[ "$openwrt_version" == "latest" ]] && get_latest_openwrt_version

    # Determine the target system (Imagebuilder files naming has changed since 23.05.0)
    if [[ "${openwrt_version:0:2}" -ge "23" && "${openwrt_version:3:2}" -ge "05" ]]; then
        target_system="armsr/armv8"
        target_name="armsr-armv8"
        target_profile=""
    else
        target_system="armvirt/64"
        target_name="armvirt-64"
        target_profile="Default"
    fi

    # Downloading imagebuilder files
    download_filename="openwrt-imagebuilder-${openwrt_version}-${target_name}.Linux-x86_64.tar.xz"
    download_uri="https://downloads.openwrt.org/releases/${openwrt_version}/targets/${target_system}/$download_filename"

    [[ ! -d "$imagebuilder_archive_path" ]] && mkdir -p "$imagebuilder_archive_path"
    if [[ ! -f "$imagebuilder_archive_path/$download_filename" ]]; then
        echo -e "${PROCESS} Start downloading OpenWrt image builder..."
        curl -# -fSL ${download_uri} -o "$imagebuilder_archive_path/$download_filename"
        [[ "${?}" -eq "0" ]] || error_msg "Download failed: [ ${download_file} ]"
        tput cuu1 && tput el
        echo -e "${STEP} Downloaded OpenWrt image builder..."
    else
        echo -e "${STEP} Using cache OpenWrt image builder..."
    fi

    if [[ ! -d "${imagebuilder_path}/$(echo "$download_filename" | sed 's/.tar.xz//')" ]]; then
        local spin='|/-\'
        local i=0
        {
            while :; do
                echo -ne "\r${PROCESS} Extracting (${spin:i++%${#spin}:1})"
                sleep 0.1
            done
        } &
        spin_pid=$!

        # Unzip and change the directory name
        [[ ! -d "${imagebuilder_path}" ]] && mkdir -p $imagebuilder_path
        tar -xJf "$imagebuilder_archive_path/$download_filename" -C "$imagebuilder_path" --overwrite

        # Stop loading
        kill "$spin_pid"
        wait "$spin_pid" 2>/dev/null
        echo -e "${PROCESS} Extracted"
        tput cuu1 && tput el && sync
    fi

    imagebuilder_path="${imagebuilder_path}/$(echo "$download_filename" | sed 's/.tar.xz//')"
    imagebuilder_bin="$imagebuilder_path/bin/targets/$target_system"
    echo -e "${INFO} Use image builder ${imagebuilder_path}"
}

# Adjust related files in the ImageBuilder directory
adjust_settings() {
    cd ${imagebuilder_path}
    echo -e "${STEP} Start adjusting .config file settings..."

    local config_file="${config_path}"
    [[ -f "${root_path}/config.conf" ]] && config_file="${root_path}/config.conf"
    [[ -f "${root_path}/.config.conf" ]] && config_file="${root_path}/.config.conf"
    [[ -f "${root_path}/.config" ]] && config_file="${root_path}/.config"

    # For .config file
    if [[ -s ".config" ]]; then
        local config_hash="# $(md5sum "$config_file")"
        local config_sync_hash=$(tail -n 1 ".config")

        if [[ "$config_hash" != "$config_sync_hash" ]]; then
            tput civis
            echo -e "${PROCESS} Sync config file"
            while read config; do
                # [[ $config =~ ^CONFIG_PACKAGE_ || $config =~ ^\#\ CONFIG_PACKAGE_ ]] && continue
                if [[ $config =~ ^CONFIG_ ]]; then
                    sleep 0.01
                    tput cuu1 && tput el
                    config_key="${config%%=*}"
                    config_value="${config#*=}"

                    # Update (# CONFIG_*)
                    sed -i "s|^#.*$config_key.*|$config_key=$config_value|g" .config
                    # Update (CONFIG_*)
                    sed -i "s|^$config_key=.*|$config_key=$config_value|g" .config
                    echo -e "${PROCESS} Sync $config_key=$config_value"
                elif [[ $config =~ ^\#\ CONFIG_ ]]; then
                    sleep 0.01
                    tput cuu1 && tput el
                    config_key="${config#\#\ }"
                    config_key="${config_key%\ is\ not\ set}"
                    sed -i "s|^$config_key=.*|# $config_key is not set|g" .config
                    echo -e "${PROCESS} Sync $config_key for unset"
                fi
            done <$config_file
            tput cvvis
            tput cuu1 && tput el
            echo -e "\n# ======================\n# Last Config Sync $(date +"%Y-%m-%d %H:%M:%S")\n$config_hash" >>".config"
        fi

        # Root filesystem archives
        sed -i "s|CONFIG_TARGET_ROOTFS_CPIOGZ=.*|# CONFIG_TARGET_ROOTFS_CPIOGZ is not set|g" .config
        # Root filesystem images
        sed -i "s|CONFIG_TARGET_ROOTFS_EXT4FS=.*|# CONFIG_TARGET_ROOTFS_EXT4FS is not set|g" .config
        sed -i "s|CONFIG_TARGET_ROOTFS_SQUASHFS=.*|# CONFIG_TARGET_ROOTFS_SQUASHFS is not set|g" .config
        sed -i "s|CONFIG_TARGET_IMAGES_GZIP=.*|# CONFIG_TARGET_IMAGES_GZIP is not set|g" .config
    else
        error_msg "There is no .config file in the [ $imagebuilder_path ]"
    fi

    sync
    echo -e "${INFO} File .config is adjusted"
    cd ${root_path}
}

# Add custom packages
# If there is a custom package or ipk you would prefer to use create a [ packages ] directory,
# If one does not exist and place your custom ipk within this directory.
custom_packages() {
    cd ${imagebuilder_path}
    echo -e "${STEP} Start adding custom packages..."
    local tmp_path_dl="${openwrt_path}/packages"

    # Create a [ packages ] directory
    [[ -d "$tmp_path_dl" ]] || mkdir -p $tmp_path_dl
    [[ -d "packages" ]] || mkdir -p packages
    cd packages

    while read package_uri; do
        [[ ! "$package_uri" =~ ^http ]] && continue
        package_name="$(basename "$package_uri")"
        if [[ ! -f "$package_name" ]]; then
            if [[ ! -f "$tmp_path_dl/$package_name" ]]; then
                echo -e "${PROCESS} Downloading [ $package_name ]..."
                curl -# -fSL "$package_uri" --output "$tmp_path_dl/$package_name"
                ln -sf "$tmp_path_dl/$package_name" "$package_name"
                # cp "$tmp_path_dl/$package_name" "$package_name"
                sleep .1
                tput cuu1 && tput el
                tput cuu1 && tput el
                sleep .2
                echo -e "${INFO} $package_name is downloaded"
            else
                ln -sf "$tmp_path_dl/$package_name" "$package_name"
                # cp "$tmp_path_dl/$package_name" "$package_name"
                echo -e "${INFO} ($package_name) using cache"
            fi
        else
            echo -e "${INFO} ($package_name) already added!"
        fi
    done <$packages_uri_path

    # Symbolic link downloaded packages .ipk
    cd ${imagebuilder_path}
    [[ ! -d "dl" ]] && ln -sf "$tmp_path_dl" "dl"

    sync
    cd ${root_path}
}

# Add custom packages, lib, theme, app and i18n, etc.
custom_config() {
    cd ${imagebuilder_path}
    echo -e "${STEP} Start adding custom config..."

    local config_file="${config_path}"
    [[ -f "${root_path}/config.conf" ]] && config_file="${root_path}/config.conf"
    [[ -f "${root_path}/.config.conf" ]] && config_file="${root_path}/.config.conf"
    [[ -f "${root_path}/.config" ]] && config_file="${root_path}/.config"

    config_list=""
    if [[ -s "${config_file}" ]]; then
        config_list="$(grep -E "^CONFIG_PACKAGE_.*=(y|m)$" "${config_file}" 2>/dev/null | sed -e 's/CONFIG_PACKAGE_//g' -e 's/=[ym]//g' -e 's/[ ][ ]*//g' | tr '\n' ' ')"

        echo -e "${INFO} Custom config list:"
        echo -e "$config_list"
        # for config in $config_list; do
        #     echo -e "${INFO} $config"
        # done
    else
        echo -e "${INFO} No custom config was added."
    fi

    cd ${root_path}
}

# Add custom repositories
custom_repositories() {
    cd ${imagebuilder_path}
    echo -e "${STEP} Start adding custom repositories..."

    local repositories_file="$repositories_path"
    [[ -f "${root_path}/repositories.conf" ]] && repositories_file="${root_path}/repositories.conf"
    [[ -f "${root_path}/.repositories.conf" ]] && repositories_file="${root_path}/.repositories.conf"
    [[ -f "${root_path}/.repositories" ]] && repositories_file="${root_path}/.repositories"

    # For repositories file
    if [[ -s "repositories.conf" ]]; then
        local repositories_hash="# $(md5sum "$repositories_file")"
        local repositories_sync_hash=$(tail -n 1 "repositories.conf")

        if [[ "$repositories_hash" != "$repositories_sync_hash" ]]; then
            # tput civis
            echo -e "${PROCESS} Sync repositories"

            local repositories="$(grep -E "^src/.*$" "${repositories_file}" 2>/dev/null)"
            echo -e "${INFO} Repositories: \n$repositories"
            repositories="## Custom remote repositories\n$repositories\n"

            # Add repositories
            awk -v insert="$repositories" '/## This is the local package repository/ { print insert }{ print }' repositories.conf >repositories.conf.new
            mv repositories.conf.new repositories.conf

            # Disabling check repo signature
            sed -i "s|^option check_signature|# option check_signature|g" repositories.conf

            echo -e "\n# ======================\n# Last Repo Sync $(date +"%Y-%m-%d %H:%M:%S")\n$repositories_hash" >>"repositories.conf"
        fi

        echo -e "${INFO} Repositories is sync"
    else
        error_msg "There is no repositories.conf file in the [ $imagebuilder_path ]"
    fi

    cd ${root_path}
}

# Add custom files
# The FILES variable allows custom configuration files to be included in images built with Image Builder.
# The [ files ] directory should be placed in the Image Builder root directory where you issue the make command.
custom_files() {
    cd ${imagebuilder_path}
    echo -e "${STEP} Start adding custom files..."

    if [[ -d "${files_path}" ]]; then
        # Copy custom files
        [[ -d "files" ]] || mkdir -p files
        cp -rf ${files_path}/* files
        echo -e "${INFO} [ files ] directory status: $(ls files -al 2>/dev/null)"
    else
        echo -e "${INFO} No customized files were added."
    fi

    cd ${root_path}
}

# Prepare packages list from file
prepare_packages() {
    cd ${imagebuilder_path}
    echo -e "${STEP} Start add packages list...\n"

    local packages_file="${packages_path}"
    [[ -f "${root_path}/packages.conf" ]] && packages_file="${root_path}/packages.conf"
    [[ -f "${root_path}/.packages.conf" ]] && packages_file="${root_path}/.packages.conf"
    [[ -f "${root_path}/.packages" ]] && packages_file="${root_path}/.packages"

    # Read package from file list
    if [[ -f "$packages_file" ]]; then
        while read package; do
            if [[ "$package" != "" && ! "$package" =~ ^# && ! " ${openwrt_packages[@]} " =~ " ${package} " ]]; then
                tput cuu1 && tput el
                echo -e "${INFO} $package"
                openwrt_packages+=("$package")
            fi
        done <"$packages_file"
        echo "${openwrt_packages[*]}"

        tput cuu1 && tput el
    fi

    cd ${root_path}
}

# Custom Profile
custom_profile() {
    cd ${imagebuilder_path}
    echo -e "${STEP} Start custom profile image builder..."

    local profile_file=".profiles.mk"
    sed -i "s|^DEVICE_generic_NAME:=.*|DEVICE_generic_NAME:=Secretlab OpenWrt Builder|g" "$profile_file"
    sed -i "s|^DEVICE_generic_PACKAGES:=.*|DEVICE_generic_PACKAGES:=${openwrt_packages[*]}|g" "$profile_file"

    cd $root_path
}

# Rebuild OpenWrt firmware
build_firmware() {
    cd ${imagebuilder_path}
    echo -e "${STEP} Start building OpenWrt with Image Builder..."

    imagebuilder_bin=$(ls $imagebuilder_bin/$openwrt_rootfs_file 2>/dev/null)
    if [[ -f "$imagebuilder_bin" ]]; then
        echo -e "${SUCCESS} image builder already builded..."
    else
        # Build firmware
        # PACKAGES="${openwrt_packages[*]}" \
        make image V=s PROFILE="${target_profile}" \
            FILES="files"
        [[ "${?}" -eq 0 ]] || error_msg "Build image builder firmware failed"

        imagebuilder_bin=$(ls $imagebuilder_bin/$openwrt_rootfs_file 2>/dev/null)

        sync
        echo -e "${SUCCESS} The build is successful, the current path: [ ${PWD} ]"
    fi

    cd ${root_path}
}

rebuild_firmware() {
    sudo ./rebuild.sh

}

server_remaining_space() {
    if [[ "$is_on_wsl" == "true" ]]; then
        df -k "/mnt/c" | tail -n1 | awk '{print $4}' | echo $(($(xargs) / 1024 / 1024))
    else
        df -Tk ${make_path} | tail -n1 | awk '{print $5}' | echo $(($(xargs) / 1024 / 1024))
    fi
}

server_space() {
    if [[ "$is_on_wsl" == "true" ]]; then
        df -hT | grep "Mounted on"
        df -hT | grep "/mnt" | tail -n2
    else
        df -hT ${make_path}
    fi
}

cleanup() {
    rm -rf "$imagebuilder_path"
}

# Show welcome message
echo -e "${STEP} Secretlab Builder OpenWrt for Rebuild Secretlab-WRT."
[[ -x "${0}" ]] || error_msg "Please give the script permission to run: [ chmod +x ${0} ]"

echo -e "${INFO} Build path: [ ${PWD} ]"
echo -e "${INFO} Build Branch: [ ${openwrt_version} ]"
echo -e "\n${INFO} Host space usage before starting to compile: \n$(server_space) \n"

# Perform related operations
init_var "${@}"
download_imagebuilder

adjust_settings
custom_repositories
custom_packages
custom_config
custom_files
prepare_packages
custom_profile
build_firmware

echo -e "\n${INFO} Host space usage after starting to compile: \n$(server_space) \n"

# rebuild_firmware
# cleanup
# cp

# All process completed
wait
