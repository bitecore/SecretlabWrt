#!/bin/bash
#================================================================================================
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of the make OpenWrt
# https://github.com/ophub/amlogic-s9xxx-openwrt
#
# Description: Automatically Packaged OpenWrt
# Copyright (C) 2020~ https://github.com/openwrt/openwrt
# Copyright (C) 2020~ https://github.com/coolsnowwolf/lede
# Copyright (C) 2020~ https://github.com/immortalwrt/immortalwrt
# Copyright (C) 2020~ https://github.com/unifreq/openwrt_packit
# Copyright (C) 2021~ https://github.com/ophub/amlogic-s9xxx-armbian/blob/main/CONTRIBUTORS.md
# Copyright (C) 2020~ https://github.com/ophub/amlogic-s9xxx-openwrt
#
# Command: sudo ./make
# Command optional parameters please refer to the source code repository
#
#======================================== Functions list ========================================
#
# error_msg          : Output error message
# process_msg        : Output process message
# mount_try          : Mount the image file, fail again
# get_textoffset     : Get kernel TEXT_OFFSET
#
# init_var           : Initialize all variables
# check_data         : Check the validity of the data
# find_openwrt       : Find OpenWrt file (openwrt-armvirt/*rootfs.tar.gz)
# git_pull_dir       : Download the files from the git repository
# download_depends   : Download the dependency files
# query_kernel       : Query the latest kernel version
# check_kernel       : Check kernel files integrity
# download_kernel    : Download the latest kernel
#
# confirm_version    : Confirm version type
# make_image         : Making OpenWrt file
# extract_openwrt    : Extract OpenWrt files
# replace_kernel     : Replace the kernel
# refactor_bootfs    : Refactor bootfs files
# refactor_rootfs    : Refactor rootfs files
# clean_tmp          : Clear temporary files
#
# loop_make          : Loop to make OpenWrt files
#
#================================ Set make environment variables ================================
#
# Related file storage path
# current_path="${PWD}"
current_dir=$(dirname "$(realpath "$BASH_SOURCE")")
current_path=$(dirname "$current_dir")

make_path="${current_path}/OpenWrt"
out_path="${current_path}/build"
tmp_path="${make_path}/tmp"

imagebuilder_path="${make_path}/build/$(ls $make_path/build 2>/dev/null)"
imagebuilder_target="$(ls $imagebuilder_path/bin/targets 2>/dev/null)"
imagebuilder_target_arch="$(ls $imagebuilder_path/bin/targets/$imagebuilder_target 2>/dev/null)"

openwrt_path="${imagebuilder_path}/bin/targets/$imagebuilder_target/$imagebuilder_target_arch"
openwrt_rootfs_file="*rootfs.tar.gz"
resource_path="${make_path}/ophub"
resource_custom_path="${current_path}/src"
kernel_path="${resource_path}/kernel"
uboot_path="${resource_path}/u-boot"
common_files="${resource_path}/files/common-files"
common_files_custom="${resource_custom_path}/files"
platform_files="${resource_path}/files/platform-files"
different_files="${resource_path}/files/different-files"
firmware_path="${common_files}/lib/firmware"
model_conf="${common_files}/etc/model_database.conf"
model_txt="${common_files}/etc/model_database.txt"
[[ -d "${make_path}" ]] || mkdir -p ${make_path}

# System operation environment
arch_info="$(uname -m)"
host_release="$(cat /etc/os-release | grep '^VERSION_CODENAME=.*' | cut -d'=' -f2)"
# Add custom OpenWrt firmware information
op_release="etc/flippy-openwrt-release"

github_url="https://github.com"
github_raw_url="https://raw.githubusercontent.com"
# Dependency files download repository
resources_repo="ophub/amlogic-s9xxx-openwrt"
depends_repo="ophub/amlogic-s9xxx-armbian"
uboot_repo="ophub/u-boot"
firmware_repo="ophub/firmware"
script_repo="ophub/luci-app-amlogic"
kernel_repo="ophub/kernel"

# Set the tags(kernel_xxx) of the default kernel that can be replaced via the [ -u ] parameter
default_tags="stable"
kernel_usage=""
# Set the list of kernels used by default(Selectable version)
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

delete_temporary_files="false"
is_on_wsl=$(grep -qE "(Microsoft|WSL)" /proc/version 2>/dev/null && echo "true" || echo "false")
limit_remaining_space="15"

# Initialize the kernel array
declare -A tags_list

# Initialize the build device
# make_board="all"
make_board="s905x"

# Set OpenWrt firmware size (Unit: MiB, boot_mb >= 256, root_mb >= 512)
boot_mb="256"
root_mb="1024"
# Set OpenWrt builder signature
builder_name="nsmle"

# Set font color
STEPS="[\033[95m STEPS \033[0m]"
INFO="[\033[94m INFO \033[0m]"
NOTE="[\033[93m NOTE \033[0m]"
WARNING="[\033[93m WARNING \033[0m]"
SUCCESS="[\033[92m SUCCESS \033[0m]"
ERROR="[\033[91m ERROR \033[0m]"
#
#================================================================================================

error_msg() {
    echo -e " [💔] ${1}"
    exit 1
}

process_msg() {
    echo -e " [🌿] ${1}"
}

mount_try() {
    # Check mount parameters
    m_type="${1}"
    m_dev="${2}"
    m_target="${3}"
    [[ -n "${m_type}" && -n "${m_dev}" && -n "${m_target}" ]] || {
        error_msg "Mount parameter is missing: [ ${m_type}, ${m_dev}, ${m_target} ]"
    }

    t="1"
    max_try="10"
    while [[ "${t}" -le "${max_try}" ]]; do
        # Mount according to the image partition format
        if [[ "${m_type}" == "btrfs" ]]; then
            mount -t ${m_type} -o discard,compress=zstd:6 ${m_dev} ${m_target}
        else
            mount -t ${m_type} -o discard ${m_dev} ${m_target}
        fi

        # Mount failed and continue trying
        if [[ "${?}" -eq 0 ]]; then
            break
        else
            sync && sleeps 3
            umount -f ${m_target} 2>/dev/null
            t="$((t + 1))"
        fi
    done
    [[ "${t}" -gt "${max_try}" ]] && error_msg "[ ${t} ] attempts to mount failed."
}

get_textoffset() {
    vmlinuz_name="${1}"
    need_overload="yes"
    # With TEXT_OFFSET patch is [ 0108 ], without TEXT_OFFSET patch is [ 0000 ]
    [[ "$(hexdump -n 15 -x "${vmlinuz_name}" 2>/dev/null | head -n 1 | awk '{print $7}')" == "0108" ]] && need_overload="no"
}

init_command() {
    local command=${1:-"ls"}
    local err_msg=${2}

    if ! command -v "$command" >/dev/null 2>&1; then
        error_msg "Command [$command] not exists. $err_msg"
    fi
}

init_var() {
    echo -e "${STEPS} Start Initializing Variables..."

    # If it is followed by [ : ], it means that the option requires a parameter value
    get_all_ver="$(getopt "b:r:u:k:a:s:n:" "${@}")"

    while [[ -n "${1}" ]]; do
        case "${1}" in
        -b | --Board)
            if [[ -n "${2}" ]]; then
                make_board="${2// /}"
                shift
            else
                error_msg "Invalid -b parameter [ ${2} ]!"
            fi
            ;;
        -r | --kernelRepository)
            if [[ -n "${2}" ]]; then
                kernel_repo="${2}"
                shift
            else
                error_msg "Invalid -r parameter [ ${2} ]!"
            fi
            ;;
        -u | --kernelUsage)
            if [[ -n "${2}" ]]; then
                kernel_usage="${2//kernel_/}"
                shift
            else
                error_msg "Invalid -u parameter [ ${2} ]!"
            fi
            ;;
        -k | --Kernel)
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
        -a | --Autokernel)
            if [[ -n "${2}" ]]; then
                auto_kernel="${2}"
                shift
            else
                error_msg "Invalid -a parameter [ ${2} ]!"
            fi
            ;;
        -s | --Size)
            if [[ -n "${2}" ]]; then
                img_mb="${2}"
                shift
            else
                error_msg "Invalid -s parameter [ ${2} ]!"
            fi
            ;;
        -n | --BuilderName)
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

    # Initialize commands
    init_command "pv" "Instal with: sudo apt-get install pv"
}

init_files() {
    cd ${current_path}

    [[ ! -d "$resource_path" ]] && mkdir -p ${resource_path}
    [[ ! -d "$resource_path/files" ]] && mkdir -p ${resource_path}/files
    [[ ! -d "$common_files" ]] && mkdir -p "$common_files"
    [[ ! -d "$platform_files" ]] && mkdir -p "$platform_files"
    [[ ! -d "$different_files" ]] && mkdir -p "$different_files"

    [[ ! -d "$common_files" ]] && cp -af --no-preserve=ownership "$common_files_custom" "$common_files"

    if [[ ! -f ${model_conf} ]]; then
        local remote_model_conf="model_database.conf"
        local model_conf_uri="$github_raw_url/$resources_repo/main/make-openwrt/openwrt-files/common-files/etc/$remote_model_conf"
        curl -fsSL "${model_conf_uri}" -o "${model_conf}"
    fi
}

check_data() {
    # Columns of ${model_conf}:
    # 1.ID  2.MODEL  3.SOC  4.FDTFILE  5.UBOOT_OVERLOAD  6.MAINLINE_UBOOT  7.BOOTLOADER_IMG  8.DESCRIPTION
    # 9.KERNEL_TAGS  10.PLATFORM  11.FAMILY  12.BOOT_CONF  13.CONTRIBUTORS  14.BOARD  15.BUILD
    [[ -f "${model_conf}" ]] || error_msg "Missing model config file: [ ${model_conf} ]"

    # Convert ${model_conf} to ${model_txt} for [ openwrt-install-amlogic ], Just the first 8 columns.
    cat ${model_conf} |
        sed -e 's/NULL/NA/g' -e 's/[ ][ ]*//g' |
        grep -E "^[^#ar].*" |
        awk -F':' '{if ($6 != "NA") $6 = "/lib/u-boot/"$6; if ($7 != "NA") $7 = "/lib/u-boot/"$7; NF = 8; print}' OFS=':' \
            >${model_txt}

    # Get a list of build devices
    if [[ "${make_board}" == "all" ]]; then
        board_list=":(yes)"
        make_openwrt=($(
            cat ${model_conf} |
                sed -e 's/NA//g' -e 's/NULL//g' -e 's/[ ][ ]*//g' |
                grep -E "^[^#].*:yes$" | awk -F':' '{print $14}' |
                sort -u | xargs
        ))
    else
        board_list=":($(echo ${make_board} | sed -e 's/_/\|/g')):(yes|no)"
        make_openwrt=($(echo ${make_board} | sed -e 's/_/ /g'))
    fi
    [[ "${#make_openwrt[@]}" -eq 0 ]] && error_msg "The board is missing, stop making."

    # Get the kernel array
    kernel_from=($(
        cat ${model_conf} |
            sed -e 's/NA//g' -e 's/NULL//g' -e 's/[ ][ ]*//g' |
            grep -E "^[^#].*${board_list}$" | awk -F':' '{print $9}' |
            sort -u | xargs
    ))
    [[ "${#kernel_from[@]}" -eq 0 ]] && error_msg "Missing [ KERNEL_TAGS ] settings, stop building."
    # Replace custom kernel tags
    [[ -n "${kernel_usage}" ]] && {
        for ((i = 0; i < ${#kernel_from[@]}; i++)); do
            if [[ ${kernel_from[${i}]} == "${default_tags}/"* ]]; then
                kernel_from[${i}]="${kernel_from[${i}]//${default_tags}/${kernel_usage}}"
            fi
        done
    }

    # Convert the kernel_from to the kernel array
    for item in "${kernel_from[@]}"; do
        # Split the key and value
        IFS='/' read -r key value <<<"${item}"

        # Check if the value is "all".
        if [[ "${value}" == "all" ]]; then
            # If the value is "all", assign the value of ${key}_kernel. such as [ stable_kernel, rk3588_kernel, etc. ]
            eval "value=\"\${${key}_kernel[@]}\""
        elif [[ "${value}" =~ ^[1-9]+ ]]; then
            if [[ "${value}" == "5.x.y" ]]; then
                value="${specific_5xy[@]}"
            elif [[ "${value}" == "6.x.y" ]]; then
                value="${specific_6xy[@]}"
            else
                IFS='_' read -ra value <<<"${value}"
                value="${value[@]}"
            fi
        fi

        # Merge the same key values
        if [[ -n "${tags_list[${key}]}" ]]; then
            tags_list[${key}]+=" ${value}"
        else
            tags_list[${key}]="${value}"
        fi
    done

    # Convert the tags_list array to the kernel array (remove duplicates)
    for key in "${!tags_list[@]}"; do
        # Convert the space-separated string to an array and remove duplicates
        read -ra unique_values <<<"$(echo "${tags_list[${key}]}" | tr ' ' '\n' | sort -u | tr '\n' ' ')"
        # Assign the unique values back to the tags_list
        tags_list[${key}]="${unique_values[@]}"
    done

    # Check the kernel tags list
    [[ "${#tags_list[@]}" -eq 0 ]] && error_msg "The [ tags_list ] is missing, stop building."
    echo -e "${INFO} The kernel tags list: [ ${!tags_list[@]} ]"

    # Convert kernel repository address to api format
    [[ "${kernel_repo}" =~ ^https: ]] && kernel_repo="$(echo ${kernel_repo} | awk -F'/' '{print $4"/"$5}')"
    kernel_api="https://github.com/${kernel_repo}"
}

find_openwrt() {
    cd ${current_path}
    echo -e "${STEPS} Start searching for OpenWrt file..."

    # Find whether the OpenWrt file exists
    openwrt_default_file="$(ls ${openwrt_path}/${openwrt_rootfs_file} 2>/dev/null | head -n 1 | awk -F "/" '{print $NF}')"
    if [[ -n "${openwrt_default_file}" ]]; then
        echo -e "${INFO} OpenWrt file: [ ${openwrt_default_file} ]"
    else
        error_msg "There is no [ ${openwrt_rootfs_file} ] file in the [ ${openwrt_path} ] directory."
    fi

    # Extract the OpenWrt release information file
    source_codename=""
    source_release_file="etc/openwrt_release"
    temp_dir="$(mktemp -d)"
    (cd ${temp_dir} && tar -mxzf "${openwrt_path}/${openwrt_default_file}" "./${source_release_file}" 2>/dev/null)
    # Find custom DISTRIB_SOURCECODE, such as [ official/lede ]
    [[ -f "${temp_dir}/${source_release_file}" ]] && {
        source_codename="$(cat ${temp_dir}/${source_release_file} 2>/dev/null | grep -oE "^DISTRIB_SOURCECODE=.*" | head -n 1 | cut -d"'" -f2)"

        [[ -n "${source_codename}" ]] && {
            # Record OpenWrt source codes repository
            case "${source_codename}" in
            official) OPENWRT_SOURCECODE="github.com/openwrt/openwrt" ;;
            lede) OPENWRT_SOURCECODE="github.com/coolsnowwolf/lede" ;;
            immortalwrt) OPENWRT_SOURCECODE="github.com/immortalwrt/immortalwrt" ;;
            *) OPENWRT_SOURCECODE="unknown" ;;
            esac

            # Complete filename
            [[ "${source_codename:0:1}" != "_" ]] && source_codename="_${source_codename}"
        } || {
            source_codename="$(cat ${temp_dir}/${source_release_file} 2>/dev/null | grep -oE "^DISTRIB_ID=.*" | head -n 1 | cut -d"'" -f2)"
            source_version="$(cat ${temp_dir}/${source_release_file} 2>/dev/null | grep -oE "^DISTRIB_RELEASE=.*" | head -n 1 | cut -d"'" -f2)"
            source_revision="$(cat ${temp_dir}/${source_release_file} 2>/dev/null | grep -oE "^DISTRIB_REVISION=.*" | head -n 1 | cut -d"'" -f2)"

            [[ -n "${source_codename}" ]] && {
                # Record OpenWrt source codes repository
                case "${source_codename}" in
                OpenWrt) OPENWRT_SOURCECODE="github.com/openwrt/openwrt" ;;
                Lede) OPENWRT_SOURCECODE="github.com/coolsnowwolf/lede" ;;
                ImmortalWrt) OPENWRT_SOURCECODE="github.com/immortalwrt/immortalwrt" ;;
                *) OPENWRT_SOURCECODE="unknown" ;;
                esac
            }

            # Complete filename
            [[ "${source_codename:0:1}" != "_" ]] && source_codename="_${source_codename}-${source_version}(${source_revision})"
        }
        echo -e "${INFO} The source_codename: [ ${source_codename} ], OpenWrt source code repository: [ ${OPENWRT_SOURCECODE} ]"
    }
    # Remove temporary directory
    rm -rf ${temp_dir}
}

clear_line() {
    local max=${1:-1}

    for ((i = 1; i <= max; i++)); do
        tput cuu1 && tput el
    done
}

sleeps() {
    local duration=${1:-0}
    local message=${2:-"Please Wait"}

    while [ $duration -gt 0 ]; do
        echo -ne "${INFO}\x1b[0;33m $message \x1b[1;33m$duration \x1b[0m\x1b[0;33mseconds...\x1b[0m\r"
        sleep 1
        duration=$((duration - 1))
    done
    echo -e ""
    clear_line
}

git_pull_dir() {
    cd ${current_path}

    # Check git_pull_dir parameters
    git_repo="${1}"
    git_branch="${2}"
    git_path="${3}"

    [[ ! $git_repo =~ ^http ]] && git_repo="$github_url/$git_repo"

    [[ -n "${git_repo}" && -n "${git_branch}" && -n "${git_path}" ]] || {
        error_msg "git_pull_dir parameter is missing: [ ${git_repo}, ${git_branch}, ${git_path} ]"
    }

    repo_name=$(basename "$git_repo")
    user_name=$(basename "$(dirname "$git_repo")")
    user_repo="${user_name}/${repo_name}"

    # Clone the repository to the temporary directory. If it fails, wait 10 seconds and try again, try 10 times.
    for i in {1..10}; do
        if [[ -d $git_path ]]; then
            cd ${git_path}
            git pull origin ${git_branch} --rebase 2>&1 |
                pv -l -s $(git ls-remote $git_repo | wc -l) -N "$user_repo" >/dev/null
            cd ${current_path}
        else
            git clone --progress --single-branch --depth=1 --branch=${git_branch} ${git_repo} ${git_path} 2>&1 |
                pv -l -s $(git ls-remote $git_repo | wc -l) -N "$user_repo" >/dev/null
        fi

        [[ "${?}" -eq 0 ]] && clear_line
        [[ "${?}" -eq 0 ]] && break || sleeps 10 "Retry clone in"
    done
    [[ "${?}" -eq 0 ]] || error_msg "Failed to clone the [ ${user_repo} ] repository."
}

download_depends() {
    cd ${current_path}
    echo -e "${STEPS} Start downloading dependency files..."
    [[ ! -d $tmp_path ]] && mkdir -p $tmp_path

    # Download Armbian u-boot files
    git_path="$tmp_path/$uboot_repo"
    git_pull_dir ${uboot_repo} main ${git_path}
    # Move the files to the storage directory
    [[ ! -d ${uboot_path} ]] && mkdir -p ${uboot_path}
    cp -af --no-preserve=ownership ${git_path}/u-boot/* ${uboot_path}
    [[ "${?}" -eq 0 ]] || error_msg "Failed to move the [ u-boot ] files to the [ ${uboot_path} ] directory."
    # Delete temporary files
    [[ "$delete_temporary_files" == "true" ]] && rm -rf "${git_path}"

    # Download Armbian firmware files
    git_path="$tmp_path/$firmware_repo"
    git_pull_dir ${firmware_repo} main ${git_path}
    # Move the files to the storage directory
    [[ ! -d ${firmware_path} ]] && mkdir -p ${firmware_path}
    cp -af --no-preserve=ownership ${git_path}/firmware/* ${firmware_path}
    [[ "${?}" -eq 0 ]] && echo -e "${INFO} firmware download completed." || error_msg "firmware download failed."
    # Delete temporary files
    [[ "$delete_temporary_files" == "true" ]] && rm -rf ${git_path}

    # Download platform files amlogic openwrt
    git_path="$tmp_path/$resources_repo"
    git_pull_dir ${resources_repo} main ${git_path}
    # Move the files to the storage directory
    cp -af --no-preserve=ownership ${git_path}/make-openwrt/openwrt-files/platform-files/* ${platform_files}
    [[ "${?}" -eq 0 ]] && echo -e "${INFO} platform-files openwrt download completed." || error_msg "platform-files openwrt download failed."
    # Download different files
    cp -af --no-preserve=ownership ${git_path}/make-openwrt/openwrt-files/different-files/* ${different_files}
    [[ "${?}" -eq 0 ]] && echo -e "${INFO} different-files openwrt download completed." || error_msg "different-files openwrt download failed."
    # Delete temporary files
    [[ "$delete_temporary_files" == "true" ]] && rm -rf ${git_path}

    # Download platform files
    git_path="$tmp_path/$depends_repo"
    git_pull_dir ${depends_repo} main ${git_path}
    # Move the files to the storage directory
    cp -af --no-preserve=ownership ${git_path}/build-armbian/armbian-files/platform-files/* ${platform_files}
    [[ "${?}" -eq 0 ]] && echo -e "${INFO} platform-files armbian download completed." || error_msg "platform-files armbian download failed."
    # Remove the special files in the [ sbin ] directory of the Armbian system
    rm -rf $(find ${platform_files} -type d -name "sbin")
    # Download different files
    cp -af --no-preserve=ownership ${git_path}/build-armbian/armbian-files/different-files/* ${different_files}
    [[ "${?}" -eq 0 ]] && echo -e "${INFO} different-files armbian download completed." || error_msg "different-files armbian download failed."
    # Download balethirq related files
    cp -f --no-preserve=ownership ${git_path}/build-armbian/armbian-files/common-files/usr/sbin/balethirq.pl ${common_files}/usr/sbin
    cp -f --no-preserve=ownership ${git_path}/build-armbian/armbian-files/common-files/etc/balance_irq ${common_files}/etc
    [[ "${?}" -eq 0 ]] && echo -e "${INFO} balethirq download completed." || error_msg "balethirq download failed."
    # Delete temporary files
    [[ "$delete_temporary_files" == "true" ]] && rm -rf ${git_path}

    # Download install/update and other related files
    git_path="$tmp_path/$script_repo"
    git_pull_dir ${script_repo} main ${git_path}
    # Move the files to the storage directory
    cp -af --no-preserve=ownership ${git_path}/luci-app-amlogic/root/usr/sbin/* ${common_files}/usr/sbin
    [[ "${?}" -eq 0 ]] && echo -e "${INFO} app/sbin download completed." || error_msg "app/sbin download failed."
    chmod +x ${common_files}/usr/sbin/*
    # Move the files to the storage directory
    mkdir -p ${common_files}/usr/share/amlogic
    cp -af --no-preserve=ownership ${git_path}/luci-app-amlogic/root/usr/share/amlogic ${common_files}/usr/share/amlogic
    [[ "${?}" -eq 0 ]] && echo -e "${INFO} app/share download completed." || error_msg "app/share download failed."
    chmod +x ${common_files}/usr/share/amlogic/*
    # Delete temporary files
    [[ "$delete_temporary_files" == "true" ]] && rm -rf ${git_path}
}

query_kernel() {
    echo -e "${STEPS} Start querying the latest kernel version..."

    # Check the version on the kernel repository
    x="1"
    for key in "${!tags_list[@]}"; do
        {
            # Query the name of the latest kernel version
            tmp_arr_kernels=()
            down_kernel_list=(${tags_list[${key}]})
            i=1
            for kernel_var in "${down_kernel_list[@]}"; do
                echo -e "${INFO} (${x}.${i}) Auto query the latest kernel version for [ ${key} - ${kernel_var} ]"

                # Identify the kernel <VERSION> and <PATCHLEVEL>, such as [ 6.1 ]
                kernel_verpatch="$(echo ${kernel_var} | awk -F '.' '{print $1"."$2}')"

                # Query the latest kernel version
                latest_version="$(
                    curl -fsSL \
                        ${kernel_api}/releases/expanded_assets/kernel_${key} |
                        grep -oE "${kernel_verpatch}.[0-9]+.tar.gz" | sed 's/.tar.gz//' |
                        sort -urV | head -n 1
                )"

                if [[ "${?}" -eq 0 && -n "${latest_version}" ]]; then
                    tmp_arr_kernels[${i}]="${latest_version}"
                else
                    tmp_arr_kernels[${i}]="${kernel_var}"
                fi

                echo -e "${INFO} (${x}.${i}) [ ${key} - ${tmp_arr_kernels[$i]} ] is latest kernel."

                let i++
            done

            # Assign the latest kernel version to the array
            tags_list[${key}]="${tmp_arr_kernels[@]}"

            let x++
        }
    done
}

check_kernel() {
    [[ -n "${1}" ]] && check_path="${1}" || error_msg "Invalid kernel path to check."
    check_files=($(cat "${check_path}/sha256sums" | awk '{print $2}'))
    for cf in "${check_files[@]}"; do
        {
            # Check if file exists
            [[ -s "${check_path}/${cf}" ]] || error_msg "The [ ${cf} ] file is missing."
            # Check if the file sha256sum is correct
            tmp_sha256sum="$(sha256sum "${check_path}/${cf}" | awk '{print $1}')"
            tmp_checkcode="$(cat ${check_path}/sha256sums | grep ${cf} | awk '{print $1}')"
            [[ "${tmp_sha256sum}" == "${tmp_checkcode}" ]] || error_msg "[ ${cf} ]: sha256sum verification failed."
        }
    done
    echo -e "${INFO} All [ ${#check_files[@]} ] kernel files are sha256sum checked to be complete.\n"
}

download_kernel() {
    cd ${current_path}
    echo -e "${STEPS} Start downloading the kernel files..."

    x="1"
    for key in "${!tags_list[@]}"; do
        {
            down_kernel_list=(${tags_list[${key}]})
            # Download the kernel to the storage directory
            i="1"
            for kernel_var in "${down_kernel_list[@]}"; do
                if [[ ! -d "${kernel_path}/${key}/${kernel_var}" ]]; then
                    kernel_down_from="https://github.com/${kernel_repo}/releases/download/kernel_${key}/${kernel_var}.tar.gz"
                    echo -e "${INFO} (${x}.${i}) [ ${key} - ${kernel_var} ] Kernel download from [ ${kernel_down_from} ]"

                    # Download the kernel files. If the download fails, try again 10 times.
                    [[ -d "${kernel_path}/${key}" ]] || mkdir -p ${kernel_path}/${key}

                    if [[ ! -d "${kernel_path}/${key}/${kernel_var}.tar.gz" ]]; then
                        for t in {1..10}; do
                            curl -# -fSL "${kernel_down_from}" -o "${kernel_path}/${key}/${kernel_var}.tar.gz"
                            [[ "${?}" -eq 0 ]] && clear_line
                            [[ "${?}" -eq 0 ]] && break || sleeps 10 "Retry downloading kernel in"
                        done
                        [[ "${?}" -eq 0 ]] || error_msg "Failed to download the kernel files from the server."
                    fi

                    # Decompress the kernel files
                    tar -mxzf "${kernel_path}/${key}/${kernel_var}.tar.gz" -C "${kernel_path}/${key}"
                    [[ "${?}" -eq 0 ]] || error_msg "[ ${kernel_var} ] kernel decompression failed."
                else
                    echo -e "${INFO} (${x}.${i}) [ ${key} - ${kernel_var} ] Kernel is in the local directory."
                fi

                # If the kernel contains the sha256sums file, check the files integrity
                [[ -f "${kernel_path}/${key}/${kernel_var}/sha256sums" ]] && check_kernel "${kernel_path}/${key}/${kernel_var}"

                let i++
            done

            # Delete downloaded kernel temporary files
            [[ "$delete_temporary_files" == "true" ]] && rm -f ${kernel_path}/${key}/*.tar.gz
            sync

            let x++
        }
    done
}

confirm_version() {
    cd ${current_path}

    # Columns of ${model_conf}:
    # 1.ID  2.MODEL  3.SOC  4.FDTFILE  5.UBOOT_OVERLOAD  6.MAINLINE_UBOOT  7.BOOTLOADER_IMG  8.DESCRIPTION
    # 9.KERNEL_TAGS  10.PLATFORM  11.FAMILY  12.BOOT_CONF  13.CONTRIBUTORS  14.BOARD  15.BUILD
    # Column 5, called <UBOOT_OVERLOAD> in Amlogic, <TRUST_IMG> in Rockchip, Not used in Allwinner.

    # Find [ the first ] configuration information with [ the same BOARD name ] and [ BUILD as yes ] in the ${model_conf} file.
    board_conf="$(
        cat ${model_conf} |
            sed -e 's/NA//g' -e 's/NULL//g' -e 's/[ ][ ]*//g' |
            grep -E "^[^#].*:${board}:(yes|no)$" |
            head -n 1
    )"
    [[ -n "${board_conf}" ]] || error_msg "[ ${board} ] config is missing!"

    # Get device settings options
    MODEL_ID="$(echo ${board_conf} | awk -F':' '{print $1}')"
    MODEL_NAME="$(echo ${board_conf} | awk -F':' '{print $2}')"
    SOC="$(echo ${board_conf} | awk -F':' '{print $3}')"
    FDTFILE="$(echo ${board_conf} | awk -F':' '{print $4}')"
    UBOOT_OVERLOAD="$(echo ${board_conf} | awk -F':' '{print $5}')"
    TRUST_IMG="${UBOOT_OVERLOAD}"
    MAINLINE_UBOOT="$(echo ${board_conf} | awk -F':' '{print $6}')"
    BOOTLOADER_IMG="$(echo ${board_conf} | awk -F':' '{print $7}')"
    KERNEL_TAGS="$(echo ${board_conf} | awk -F':' '{print $9}')"
    PLATFORM="$(echo ${board_conf} | awk -F':' '{print $10}')"
    FAMILY="$(echo ${board_conf} | awk -F':' '{print $11}')"
    BOOT_CONF="$(echo ${board_conf} | awk -F':' '{print $12}')"
    CONTRIBUTORS="$(echo ${board_conf} | awk -F':' '{print $13}')"

    # Check whether the key parameters are correct
    [[ -n "${PLATFORM}" ]] || error_msg "Invalid PLATFORM parameter: [ ${PLATFORM} ]"
    # Set supported platform name
    support_platform=("amlogic" "rockchip" "allwinner")
    [[ -n "$(echo "${support_platform[@]}" | grep -w "${PLATFORM}")" ]] || error_msg "[ ${PLATFORM} ] not supported."

    # Add u-boot files record information
    [[ -n "${MAINLINE_UBOOT}" ]] && RECORD_MAINLINE_UBOOT="/lib/u-boot/${MAINLINE_UBOOT}" || RECORD_MAINLINE_UBOOT=""
    [[ -n "${BOOTLOADER_IMG}" ]] && RECORD_BOOTLOADER_IMG="/lib/u-boot/${BOOTLOADER_IMG}" || RECORD_BOOTLOADER_IMG=""
    [[ -n "${TRUST_IMG}" ]] && RECORD_TRUST_IMG="/lib/u-boot/${TRUST_IMG}" || RECORD_TRUST_IMG=""

    # Get the kernel tags and version
    conf_kernel_tags="${KERNEL_TAGS%%/*}"
    conf_kernel_list="${KERNEL_TAGS##*/}"
    # Replace the default kernel tags with the custom kernel tags
    [[ -n "${kernel_usage}" && "${conf_kernel_tags}" == "${default_tags}" ]] && conf_kernel_tags="${kernel_usage}"

    # Set the kernel version array
    build_kernel=()
    if [[ "${conf_kernel_list}" == "all" ]]; then
        build_kernel=(${tags_list[${conf_kernel_tags}]})
    else
        conf_kernel_list="${conf_kernel_list//[a-z]/[0-9]+}"
        # Convert the string into an array, using "_" as the delimiter.
        IFS='_' read -ra conf_kernel_list <<<"${conf_kernel_list}"
        model_kernel=(${conf_kernel_list[@]})
        latest_kernel=(${tags_list[${conf_kernel_tags}]})
        # Find the kernel version that matches the custom version
        for ck in "${model_kernel[@]}"; do
            for lk in "${latest_kernel[@]}"; do
                [[ "${lk}" =~ ^${ck}$ ]] && build_kernel+=("${lk}")
            done
        done
    fi

    # Check the kernel tags and version
    [[ -n "${conf_kernel_tags}" || "${#conf_kernel_list[@]}" -eq 0 ]] || error_msg "The [ KERNEL_TAGS ] is invalid: [ ${KERNEL_TAGS} ]."
    [[ "${#build_kernel[@]}" -eq 0 ]] && error_msg "The [ KERNEL_TAGS ] is invalid: [ ${KERNEL_TAGS} ]."
}

make_image() {
    process_msg "(1/6) Make OpenWrt image."
    cd ${current_path}

    # Set Armbian image file parameters
    [[ "${PLATFORM}" == "amlogic" ]] && {
        skip_mb="4"
        partition_table_type="msdos"
        bootfs_type="fat32"
    }
    [[ "${PLATFORM}" == "rockchip" ]] && {
        skip_mb="16"
        partition_table_type="gpt"
        bootfs_type="ext4"
    }
    [[ "${PLATFORM}" == "allwinner" ]] && {
        skip_mb="16"
        partition_table_type="msdos"
        bootfs_type="fat32"
    }

    # Set OpenWrt filename
    [[ -d "${out_path}" ]] || mkdir -p ${out_path}
    openwrt_filename="SecretlabWrt${source_codename}_${PLATFORM}_${board}_k${kernel}_$(date +"%Y.%m.%d").img"
    build_image_file="${out_path}/${openwrt_filename}"
    rm -f ${build_image_file}

    IMG_SIZE="$((skip_mb + boot_mb + root_mb))"
    truncate -s ${IMG_SIZE}M ${build_image_file} >/dev/null 2>&1

    parted -s ${build_image_file} mklabel ${partition_table_type} 2>/dev/null
    parted -s ${build_image_file} mkpart primary ${bootfs_type} $((skip_mb))MiB $((skip_mb + boot_mb - 1))MiB 2>/dev/null
    parted -s ${build_image_file} mkpart primary btrfs $((skip_mb + boot_mb))MiB 100% 2>/dev/null

    # Mount the OpenWrt image file
    loop_new="$(losetup -P -f --show "${build_image_file}")"
    [[ -n "${loop_new}" ]] || error_msg "losetup ${build_image_file} failed."

    # Confirm BOOT_UUID
    BOOT_UUID="$(cat /proc/sys/kernel/random/uuid)"
    [[ -z "${BOOT_UUID}" ]] && BOOT_UUID="$(uuidgen)"
    [[ -z "${BOOT_UUID}" ]] && error_msg "The uuidgen is invalid, cannot continue."
    # Confirm ROOTFS_UUID
    ROOTFS_UUID="$(cat /proc/sys/kernel/random/uuid)"
    [[ -z "${ROOTFS_UUID}" ]] && ROOTFS_UUID="$(uuidgen)"
    [[ -z "${ROOTFS_UUID}" ]] && error_msg "The uuidgen is invalid, cannot continue."

    # Format bootfs partition
    if [[ "${bootfs_type}" == "fat32" ]]; then
        mkfs.vfat -F 32 -n "BOOT" ${loop_new}p1 >/dev/null 2>&1
    else
        mkfs.ext4 -F -q -U ${BOOT_UUID} -L "BOOT" -b 4k -m 0 ${loop_new}p1 >/dev/null 2>&1
    fi

    # Format rootfs partition
    mkfs.btrfs -f -U ${ROOTFS_UUID} -L "ROOTFS" -m single ${loop_new}p2 >/dev/null 2>&1

    # Write the specific bootloader for [ Amlogic ] boxes
    [[ "${PLATFORM}" == "amlogic" ]] && {
        bootloader_path="${uboot_path}/${PLATFORM}/bootloader"
        if [[ -n "${MAINLINE_UBOOT}" && -f "${bootloader_path}/${MAINLINE_UBOOT}" ]]; then
            dd if="${bootloader_path}/${MAINLINE_UBOOT}" of="${loop_new}" conv=fsync bs=1 count=444 2>/dev/null
            dd if="${bootloader_path}/${MAINLINE_UBOOT}" of="${loop_new}" conv=fsync bs=512 skip=1 seek=1 2>/dev/null
            #echo -e "${INFO} 01. For [ ${board} ] write bootloader: ${MAINLINE_UBOOT}"
        elif [[ -n "${BOOTLOADER_IMG}" && -f "${bootloader_path}/${BOOTLOADER_IMG}" ]]; then
            dd if="${bootloader_path}/${BOOTLOADER_IMG}" of="${loop_new}" conv=fsync bs=1 count=444 2>/dev/null
            dd if="${bootloader_path}/${BOOTLOADER_IMG}" of="${loop_new}" conv=fsync bs=512 skip=1 seek=1 2>/dev/null
            #echo -e "${INFO} 02. For [ ${board} ] write bootloader: ${BOOTLOADER_IMG}"
        fi
    }

    # Write the specific bootloader for [ Rockchip ] boxes
    [[ "${PLATFORM}" == "rockchip" ]] && {
        bootloader_path="${uboot_path}/${PLATFORM}/${board}"
        if [[ -n "${BOOTLOADER_IMG}" && -f "${bootloader_path}/${BOOTLOADER_IMG}" ]] &&
            [[ -n "${MAINLINE_UBOOT}" && -f "${bootloader_path}/${MAINLINE_UBOOT}" ]] &&
            [[ -n "${TRUST_IMG}" && -f "${bootloader_path}/${TRUST_IMG}" ]]; then
            dd if="${bootloader_path}/${BOOTLOADER_IMG}" of="${loop_new}" conv=fsync,notrunc bs=512 seek=64 2>/dev/null
            dd if="${bootloader_path}/${MAINLINE_UBOOT}" of="${loop_new}" conv=fsync,notrunc bs=512 seek=16384 2>/dev/null
            dd if="${bootloader_path}/${TRUST_IMG}" of="${loop_new}" conv=fsync,notrunc bs=512 seek=24576 2>/dev/null
            #echo -e "${INFO} 01. For [ ${board} ] write bootloader: ${TRUST_IMG}"
        elif [[ -n "${BOOTLOADER_IMG}" && -f "${bootloader_path}/${BOOTLOADER_IMG}" ]] &&
            [[ -n "${MAINLINE_UBOOT}" && -f "${bootloader_path}/${MAINLINE_UBOOT}" ]]; then
            dd if="${bootloader_path}/${BOOTLOADER_IMG}" of="${loop_new}" conv=fsync,notrunc bs=512 seek=64 2>/dev/null
            dd if="${bootloader_path}/${MAINLINE_UBOOT}" of="${loop_new}" conv=fsync,notrunc bs=512 seek=16384 2>/dev/null
            #echo -e "${INFO} 02. For [ ${board} ] write bootloader: ${MAINLINE_UBOOT}"
        elif [[ -n "${BOOTLOADER_IMG}" && -f "${bootloader_path}/${BOOTLOADER_IMG}" ]]; then
            dd if="${bootloader_path}/${BOOTLOADER_IMG}" of="${loop_new}" conv=fsync,notrunc bs=512 skip=64 seek=64 2>/dev/null
            #echo -e "${INFO} 03. For [ ${board} ] write bootloader: ${BOOTLOADER_IMG}"
        fi
    }

    # Write the specific bootloader for [ Allwinner ] boxes
    [[ "${PLATFORM}" == "allwinner" ]] && {
        bootloader_path="${uboot_path}/${PLATFORM}/${board}"
        if [[ -n "${BOOTLOADER_IMG}" && -f "${bootloader_path}/${BOOTLOADER_IMG}" ]] &&
            [[ -n "${MAINLINE_UBOOT}" && -f "${bootloader_path}/${MAINLINE_UBOOT}" ]]; then
            dd if="${bootloader_path}/${BOOTLOADER_IMG}" of="${loop_new}" conv=fsync,notrunc bs=8k seek=1 2>/dev/null
            dd if="${bootloader_path}/${MAINLINE_UBOOT}" of="${loop_new}" conv=fsync,notrunc bs=8k seek=5 2>/dev/null
            #echo -e "${INFO} 01. For [ ${board} ] write bootloader: ${MAINLINE_UBOOT}"
        elif [[ -n "${BOOTLOADER_IMG}" && -f "${bootloader_path}/${BOOTLOADER_IMG}" ]]; then
            dd if="${bootloader_path}/${BOOTLOADER_IMG}" of="${loop_new}" conv=fsync,notrunc bs=8k seek=1 2>/dev/null
            #echo -e "${INFO} 02. For [ ${board} ] write bootloader: ${BOOTLOADER_IMG}"
        fi
    }
}

extract_openwrt() {
    process_msg "(2/6) Extract OpenWrt files."
    cd ${current_path}

    # Create a dual-partition general directory
    tag_bootfs="${tmp_path}/${kernel}/${board}/bootfs"
    tag_rootfs="${tmp_path}/${kernel}/${board}/rootfs"
    mkdir -p ${tag_bootfs} ${tag_rootfs}
    chown root:root ${tag_bootfs} ${tag_rootfs}

    # Mount bootfs
    if [[ "${bootfs_type}" == "fat32" ]]; then
        mount_try vfat ${loop_new}p1 ${tag_bootfs}
    else
        mount_try ext4 ${loop_new}p1 ${tag_bootfs}
    fi

    # Mount rootfs
    mount_try btrfs ${loop_new}p2 ${tag_rootfs}

    # Create snapshot directory
    btrfs subvolume create ${tag_rootfs}/etc >/dev/null 2>&1

    # Unzip the OpenWrt rootfs file
    tar -mxzf ${openwrt_path}/${openwrt_default_file} -C ${tag_rootfs}
    rm -rf ${tag_rootfs}/lib/modules/*
    rm -f ${tag_rootfs}/rom/sbin/firstboot

    # Copy the common files
    [[ -d "${common_files}" ]] && cp -af --no-preserve=ownership ${common_files}/* ${tag_rootfs}

    # Copy the platform files
    platform_bootfs="${platform_files}/${PLATFORM}/bootfs"
    platform_rootfs="${platform_files}/${PLATFORM}/rootfs"
    [[ -d "${platform_bootfs}" ]] && cp -rf ${platform_bootfs}/* ${tag_bootfs}
    [[ -d "${platform_rootfs}" ]] && cp -af --no-preserve=ownership ${platform_rootfs}/* ${tag_rootfs}

    # Copy the different files
    different_bootfs="${different_files}/${board}/bootfs"
    different_rootfs="${different_files}/${board}/rootfs"
    [[ -d "${different_bootfs}" ]] && cp -rf ${different_bootfs}/* ${tag_bootfs}
    [[ -d "${different_rootfs}" ]] && cp -af --no-preserve=ownership ${different_rootfs}/* ${tag_rootfs}

    # Copy the bootloader files
    [[ -d "${tag_rootfs}/lib/u-boot" ]] || mkdir -p "${tag_rootfs}/lib/u-boot"
    rm -rf ${tag_rootfs}/lib/u-boot/*
    [[ -d "${bootloader_path}" ]] && cp -af --no-preserve=ownership ${bootloader_path}/* ${tag_rootfs}/lib/u-boot

    # Copy the overload files
    [[ "${PLATFORM}" == "amlogic" ]] && cp -rf ${uboot_path}/${PLATFORM}/overload/* ${tag_bootfs}

    # Remove the .git directories
    rm -rf $(find ${tmp_path} -type d -name '.git')
}

replace_kernel() {
    process_msg "(3/6) Replace the kernel."
    cd ${current_path}

    # Determine custom kernel filename
    kernel_boot="$(ls ${kernel_path}/${conf_kernel_tags}/${kernel}/boot-${kernel}*.tar.gz 2>/dev/null | head -n 1)"
    kernel_name="${kernel_boot##*/}" && kernel_name="${kernel_name:5:-7}"
    [[ -n "${kernel_name}" ]] || error_msg "Missing kernel files for [ ${kernel} ]"
    kernel_dtb="${kernel_path}/${conf_kernel_tags}/${kernel}/dtb-${PLATFORM}-${kernel_name}.tar.gz"
    kernel_modules="${kernel_path}/${conf_kernel_tags}/${kernel}/modules-${kernel_name}.tar.gz"
    [[ -s "${kernel_boot}" && -s "${kernel_dtb}" && -s "${kernel_modules}" ]] || error_msg "The 3 kernel missing."

    # 01. For /boot five files
    tar -mxzf ${kernel_boot} -C ${tag_bootfs}
    [[ "${PLATFORM}" == "allwinner" ]] && (cd ${tag_bootfs} && cp -f uInitrd-${kernel_name} uInitrd && cp -f vmlinuz-${kernel_name} Image)
    [[ "${PLATFORM}" == "amlogic" ]] && (cd ${tag_bootfs} && cp -f uInitrd-${kernel_name} uInitrd && cp -f vmlinuz-${kernel_name} zImage)
    [[ "${PLATFORM}" == "rockchip" ]] && (cd ${tag_bootfs} && ln -sf uInitrd-${kernel_name} uInitrd && ln -sf vmlinuz-${kernel_name} Image)
    [[ "$(ls ${tag_bootfs}/*${kernel_name} -l 2>/dev/null | grep "^-" | wc -l)" -ge "2" ]] || error_msg "The /boot files is missing."
    [[ "${PLATFORM}" == "amlogic" ]] && get_textoffset "${tag_bootfs}/zImage"

    # 02. For /boot/dtb/${PLATFORM}/*
    [[ -d "${tag_bootfs}/dtb/${PLATFORM}" ]] || mkdir -p ${tag_bootfs}/dtb/${PLATFORM}
    tar -mxzf ${kernel_dtb} -C ${tag_bootfs}/dtb/${PLATFORM}
    [[ "${PLATFORM}" == "rockchip" ]] && ln -sf dtb ${tag_bootfs}/dtb-${kernel_name}
    [[ "$(ls ${tag_bootfs}/dtb/${PLATFORM} -l 2>/dev/null | grep "^-" | wc -l)" -ge "2" ]] || error_msg "/boot/dtb/${PLATFORM} files is missing."

    # 03. For /lib/modules/${kernel_name}
    tar -mxzf ${kernel_modules} -C ${tag_rootfs}/lib/modules
    (cd ${tag_rootfs}/lib/modules/${kernel_name}/ && rm -f build source *.ko 2>/dev/null && find ./ -type f -name '*.ko' -exec ln -s {} ./ \;)
    [[ "$(ls ${tag_rootfs}/lib/modules/${kernel_name} -l 2>/dev/null | grep "^d" | wc -l)" -eq "1" ]] || error_msg "/usr/lib/modules kernel folder is missing."
}

refactor_bootfs() {
    process_msg "(4/6) Refactor bootfs files."
    cd ${tag_bootfs}

    # Process Amlogic series boot partition files
    [[ "${PLATFORM}" == "amlogic" && "${need_overload}" == "yes" ]] && {
        # Add u-boot.ext for Amlogic 5.10 kernel
        if [[ -n "${UBOOT_OVERLOAD}" && -f "${UBOOT_OVERLOAD}" ]]; then
            cp -f ${UBOOT_OVERLOAD} u-boot.ext
            chmod +x u-boot.ext
        elif [[ -z "${UBOOT_OVERLOAD}" || ! -f "${UBOOT_OVERLOAD}" ]]; then
            error_msg "${board} Board does not support using ${kernel} kernel, missing u-boot."
        fi
    }

    # Set uEnv.txt & extlinux.conf mount parameters
    uenv_rootdev="UUID=${ROOTFS_UUID} rootflags=compress=zstd:6 rootfstype=btrfs"
    # Set armbianEnv.txt mount parameters
    armbianenv_rootdev="UUID=${ROOTFS_UUID}"
    armbianenv_rootflags="compress=zstd:6"

    # Edit the uEnv.txt
    uenv_conf_file="uEnv.txt"
    [[ -f "${uenv_conf_file}" ]] && {
        sed -i "s|LABEL=ROOTFS|${uenv_rootdev}|g" ${uenv_conf_file}
        sed -i "s|meson.*.dtb|${FDTFILE}|g" ${uenv_conf_file}
        sed -i "s|sun.*.dtb|${FDTFILE}|g" ${uenv_conf_file}
        sed -i "s|rk.*.dtb|${FDTFILE}|g" ${uenv_conf_file}
    }

    # Add an alternate file (/boot/extlinux/extlinux.conf)
    boot_extlinux_file="extlinux/extlinux.conf.bak"
    rename_extlinux_file="extlinux/extlinux.conf"
    [[ -f "${boot_extlinux_file}" ]] && {
        sed -i "s|LABEL=ROOTFS|${uenv_rootdev}|g" ${boot_extlinux_file}
        sed -i "s|meson.*.dtb|${FDTFILE}|g" ${boot_extlinux_file}
        sed -i "s|sun.*.dtb|${FDTFILE}|g" ${boot_extlinux_file}
        sed -i "s|rk.*.dtb|${FDTFILE}|g" ${boot_extlinux_file}
        # If needed, such as t95z(s905x), rename delete .bak
        [[ "${BOOT_CONF}" == "extlinux.conf" ]] && mv -f ${boot_extlinux_file} ${rename_extlinux_file}
    }

    # Edit the armbianEnv.txt
    armbianenv_conf_file="armbianEnv.txt"
    [[ -f "${armbianenv_conf_file}" ]] && {
        sed -i "s|\(fdtfile=.*\/\)[^/]*$|\1${FDTFILE}|g" ${armbianenv_conf_file}
        sed -i "s|^rootdev=.*|rootdev=${armbianenv_rootdev}|g" ${armbianenv_conf_file}
        sed -i "s|^rootfstype=.*|rootfstype=btrfs|g" ${armbianenv_conf_file}
        sed -i "s|^rootflags=.*|rootflags=${armbianenv_rootflags}|g" ${armbianenv_conf_file}
        sed -i "s|^overlay_prefix=.*|overlay_prefix=${FAMILY}|g" ${armbianenv_conf_file}
    }

    # Check device configuration files
    [[ -f "${uenv_conf_file}" || -f "${rename_extlinux_file}" || -f "${armbianenv_conf_file}" ]] || error_msg "Missing [ /boot/*Env.txt ]"
}

refactor_rootfs() {
    process_msg "(5/6) Refactor rootfs files."
    cd ${tag_rootfs}

    # Add directory
    mkdir -p .reserved boot run

    # Edit fstab
    [[ -f "etc/fstab" && -f "etc/config/fstab" ]] || error_msg "The [ fstab ] files does not exist."
    sed -i "s|LABEL=ROOTFS|UUID=${ROOTFS_UUID}|g" etc/fstab
    sed -i "s|option label 'ROOTFS'|option uuid '${ROOTFS_UUID}'|g" etc/config/fstab

    # Set the keyword for tags in Releases
    [[ -n "${source_codename}" ]] && {
        sed -i "s|option amlogic_firmware_tag.*|option amlogic_firmware_tag '${source_codename}'|g" etc/config/amlogic
    }

    # Modify the default script to [ bash ] for [ cpustat ]
    [[ -x "bin/bash" ]] && {
        sed -i "s/\/bin\/ash/\/bin\/bash/" etc/passwd
        sed -i "s/\/bin\/ash/\/bin\/bash/" usr/libexec/login.sh
    }

    # Turn off hw_flow by default
    [[ -f "etc/config/turboacc" ]] && {
        sed -i "s|option hw_flow.*|option hw_flow '0'|g" etc/config/turboacc
        sed -i "s|option sw_flow.*|option sw_flow '0'|g" etc/config/turboacc
    }

    # Add custom startup script
    custom_startup_script="etc/custom_service/start_service.sh"
    [[ -x "${custom_startup_script}" && -f "etc/rc.local" ]] && {
        sed -i '/^exit 0/i\bash /etc/custom_service/start_service.sh' etc/rc.local
    }

    # Modify the cpu mode to schedutil
    [[ -f "etc/config/cpufreq" ]] && sed -i "s/ondemand/schedutil/" etc/config/cpufreq

    # Turn off speed limit by default
    [[ -f "etc/config/nft-qos" ]] && sed -i "s|option limit_enable.*|option limit_enable '0'|g" etc/config/nft-qos

    # Add USB and wireless network drivers
    [[ -f "etc/modules.d/usb-net-rtl8150" ]] || echo "rtl8150" >etc/modules.d/usb-net-rtl8150
    # USB RTL8152/8153/8156 network card Driver
    [[ -f "etc/modules.d/usb-net-rtl8152" ]] || echo "r8152" >etc/modules.d/usb-net-rtl8152
    # USB AX88179 network card Driver
    [[ -f "etc/modules.d/usb-net-asix-ax88179" ]] || echo "ax88179_178a" >etc/modules.d/usb-net-asix-ax88179
    # brcmfmac built-in wireless network card Driver
    echo "brcmfmac" >etc/modules.d/brcmfmac
    echo "brcmutil" >etc/modules.d/brcmutil
    echo "bcmdhd" >etc/modules.d/bcmdhd
    # USB Realtek RTL8188EU Wireless LAN Driver
    echo "r8188eu" >etc/modules.d/rtl8188eu
    # Realtek RTL8189FS Wireless LAN Driver
    echo "8189fs" >etc/modules.d/8189fs
    # Realtek RTL8188FU Wireless LAN Driver
    echo "rtl8188fu" >etc/modules.d/rtl8188fu
    # Realtek RTL8822CS Wireless LAN Driver
    echo "88x2cs" >etc/modules.d/88x2cs
    # USB Ralink Wireless LAN Driver
    echo "rt2500usb" >etc/modules.d/rt2500-usb
    echo "rt2800usb" >etc/modules.d/rt2800-usb
    echo "rt2x00usb" >etc/modules.d/rt2x00-usb
    # USB Mediatek Wireless LAN Driver
    echo "mt7601u" >etc/modules.d/mt7601u
    echo "mt7663u" >etc/modules.d/mt7663u
    echo "mt76x0u" >etc/modules.d/mt76x0u
    echo "mt76x2u" >etc/modules.d/mt76x2u
    echo "mt76x2e" >etc/modules.d/mt76x2e
    echo "mt7921e" >etc/modules.d/mt7921e
    echo "mt7915e" >etc/modules.d/mt7915e

    # GPU Driver
    echo "panfrost" >etc/modules.d/panfrost
    # PWM Driver
    echo "pwm_meson" >etc/modules.d/pwm_meson
    # Ath10k Driver
    echo "ath10k_core" >etc/modules.d/ath10k_core
    echo "ath10k_sdio" >etc/modules.d/ath10k_sdio
    echo "ath10k_usb" >etc/modules.d/ath10k_usb
    echo "ath10k_pci" >etc/modules.d/ath10k-pci
    echo "ath10k_core frame_mode=2" >etc/modules.d/ath10k
    # Enable watchdog driver
    echo "meson_gxbb_wdt" >etc/modules.d/watchdog
    # For rk3588
    echo "bifrost_kbase" >etc/modules.d/rk_gpu
    echo "rknpu" >etc/modules.d/rk_npu
    # For rk3568
    echo "rockchipdrm" >etc/modules.d/drm-rockchip
    echo "rk_crypto2" >etc/modules.d/rk_crypto
    echo -e "snd_soc_simple_card_utils\nsnd_soc_simple_card\nsnd_soc_rockchip_i2s" >etc/modules.d/snd-rk3568
    echo "pwm_fan" >etc/modules.d/pwm-fan
    echo "option" >etc/modules.d/usb-serial-option
    # For rk3328
    echo -e "snd_soc_simple_card_utils\nsnd_soc_simple_card\nsnd_soc_rockchip_i2s" >etc/modules.d/snd-rk3328

    # Add blacklist
    mkdir -p etc/modprobe.d
    cat >etc/modprobe.d/99-local.conf <<EOF
blacklist snd_soc_meson_aiu_i2s
alias brnf br_netfilter
alias pwm pwm_meson
alias wifi brcmfmac
EOF

    # Adjust startup settings
    [[ -f "etc/init.d/boot" ]] && {
        if ! grep -q 'ulimit -n' etc/init.d/boot; then
            sed -i '/kmodloader/i \\tulimit -n 51200\n' etc/init.d/boot
        fi
        if ! grep -q '/tmp/update' etc/init.d/boot; then
            sed -i '/mkdir -p \/tmp\/.uci/a \\tmkdir -p \/tmp\/update' etc/init.d/boot
        fi
    }
    [[ -f "etc/inittab" ]] && {
        sed -i 's/ttyAMA0/ttyAML0/' etc/inittab
        sed -i 's/ttyS0/tty0/' etc/inittab
    }

    # Automatic expansion of the third and fourth partitions
    echo "yes" >root/.todo_rootfs_resize

    # Relink the kmod program
    [[ -x "sbin/kmod" ]] && (
        kmod_list="depmod insmod lsmod modinfo modprobe rmmod"
        for ki in ${kmod_list}; do
            rm -f sbin/${ki}
            ln -sf kmod sbin/${ki}
        done
    )

    # Add wireless master mode
    wireless_mac80211="lib/netifd/wireless/mac80211.sh"
    [[ -f "${wireless_mac80211}" ]] && {
        cp -f ${wireless_mac80211} ${wireless_mac80211}.bak
        sed -i "s|iw |ipconfig |g" ${wireless_mac80211}
    }

    # Get random macaddr
    mac_hexchars="0123456789ABCDEF"
    mac_end=$(for i in {1..6}; do echo -n ${mac_hexchars:$((${RANDOM} % 16)):1}; done | sed -e 's/\(..\)/:\1/g')
    random_macaddr="9E:62${mac_end}"

    # Optimize wifi/bluetooth module
    [[ -d "lib/firmware/brcm" ]] && (
        cd lib/firmware/brcm/ && rm -f ../*.hcd

        # gtking/gtking pro is bcm4356 wifi/bluetooth, wifi5 module AP6356S
        sed -e "s/macaddr=.*/macaddr=${random_macaddr}:00/" "brcmfmac4356-sdio.txt" >"brcmfmac4356-sdio.azw,gtking.txt"
        # gtking/gtking pro is bcm4356 wifi/bluetooth, wifi6 module AP6275S
        sed -e "s/macaddr=.*/macaddr=${random_macaddr}:01/" "brcmfmac4375-sdio.txt" >"brcmfmac4375-sdio.azw,gtking.txt"
        # MXQ Pro+ is AP6330(bcm4330) wifi/bluetooth
        sed -e "s/macaddr=.*/macaddr=${random_macaddr}:02/" "brcmfmac4330-sdio.txt" >"brcmfmac4330-sdio.crocon,mxq-pro-plus.txt"
        # HK1 Box & H96 Max X3 is bcm54339 wifi/bluetooth
        sed -e "s/macaddr=.*/macaddr=${random_macaddr}:03/" "brcmfmac4339-sdio.ZP.txt" >"brcmfmac4339-sdio.amlogic,sm1.txt"
        # new ugoos x3 is brm43456
        sed -e "s/macaddr=.*/macaddr=${random_macaddr}:04/" "brcmfmac43456-sdio.txt" >"brcmfmac43456-sdio.amlogic,sm1.txt"
        # x96max plus v5.1 (ip1001m phy) adopts am7256 (brcm4354)
        sed -e "s/macaddr=.*/macaddr=${random_macaddr}:05/" "brcmfmac4354-sdio.txt" >"brcmfmac4354-sdio.amlogic,sm1.txt"
        # panther x2 AP6212A
        sed -e "s/macaddr=.*/macaddr=${random_macaddr}:06/" "brcmfmac43430-sdio.txt" >"brcmfmac43430-sdio.panther,x2.txt"
        # ct2000 s922x is brm4359
        sed -i "s/macaddr=.*/macaddr=${random_macaddr}:07/" "brcmfmac4359-sdio.ali,ct2000.txt"
    )

    # Add firmware version information to the terminal page
    [[ -n "${builder_name}" ]] && builder_display="Builder Name: ${builder_name} | " || builder_display=""
    [[ -f "etc/banner" ]] && {
        echo " Install OpenWrt: System → Amlogic Service → Install OpenWrt" >>etc/banner
        echo " Update  OpenWrt: System → Amlogic Service → Online  Update" >>etc/banner
        echo " Board: ${board} | OpenWrt Kernel: ${kernel_name}" >>etc/banner
        echo " ${builder_display}Production Date: $(date +%Y-%m-%d)" >>etc/banner
        echo "───────────────────────────────────────────────────────────────────────" >>etc/banner
    }

    # Add firmware information
    echo "PLATFORM='${PLATFORM}'" >>${op_release}
    echo "MODEL_ID='${MODEL_ID}'" >>${op_release}
    echo "MODEL_NAME='${MODEL_NAME}'" >>${op_release}
    echo "SOC='${SOC}'" >>${op_release}
    echo "FDTFILE='${FDTFILE}'" >>${op_release}
    echo "FAMILY='${FAMILY}'" >>${op_release}
    echo "BOARD='${board}'" >>${op_release}
    echo "KERNEL_TAGS='${conf_kernel_tags}'" >>${op_release}
    echo "KERNEL_VERSION='${kernel}'" >>${op_release}
    echo "BOOT_CONF='${BOOT_CONF}'" >>${op_release}
    echo "MAINLINE_UBOOT='${RECORD_MAINLINE_UBOOT}'" >>${op_release}
    echo "ANDROID_UBOOT='${RECORD_BOOTLOADER_IMG}'" >>${op_release}
    if [[ "${PLATFORM}" == "rockchip" ]]; then
        echo "TRUST_IMG='${RECORD_TRUST_IMG}'" >>${op_release}
    elif [[ "${PLATFORM}" == "amlogic" ]]; then
        echo "UBOOT_OVERLOAD='${UBOOT_OVERLOAD}'" >>${op_release}
    fi
    if [[ "${PLATFORM}" == "rockchip" ]]; then
        echo "SHOW_INSTALL_MENU='no'" >>${op_release}
    else
        echo "SHOW_INSTALL_MENU='yes'" >>${op_release}
    fi
    echo "OPENWRT_SOURCECODE='${OPENWRT_SOURCECODE}'" >>${op_release}
    echo "BUILDER_NAME='${builder_name}'" >>${op_release}
    echo "CONTRIBUTORS='${CONTRIBUTORS}'" >>${op_release}
    echo "PACKAGED_DATE='$(date +%Y-%m-%d)'" >>${op_release}

    cd ${current_path}

    # Create snapshot
    mkdir -p ${tag_rootfs}/.snapshots
    btrfs subvolume snapshot -r ${tag_rootfs}/etc ${tag_rootfs}/.snapshots/etc-000 >/dev/null 2>&1

    sync && sleeps 3
}

clean_tmp() {
    process_msg "(6/6) Cleanup tmp files."
    cd ${current_path}

    # Unmount the OpenWrt image file
    fstrim ${tag_bootfs} 2>/dev/null
    fstrim ${tag_rootfs} 2>/dev/null
    umount -f ${tag_bootfs} 2>/dev/null
    umount -f ${tag_rootfs} 2>/dev/null
    losetup -d ${loop_new} 2>/dev/null

    cd ${out_path}
    # Compress the OpenWrt image file
    pigz -qf ${openwrt_filename} || gzip -qf ${openwrt_filename}

    cd ${current_path}
    # Clear temporary files directory
    rm -rf ${tmp_path} && sync
}

loop_make() {
    cd ${current_path}
    echo -e "${STEPS} Start making OpenWrt firmware..."

    j="1"
    for b in "${make_openwrt[@]}"; do
        {
            # Set specific configuration for making OpenWrt system
            board="${b}"
            confirm_version

            i="1"
            for k in "${build_kernel[@]}"; do
                {
                    # Set the kernel version
                    kernel="${k}"

                    # Check disk space size
                    echo -ne "(${j}.${i}) Start making OpenWrt [\033[92m ${board} - ${conf_kernel_tags}/${kernel} \033[0m]. "
                    now_remaining_space="$(server_remaining_space)"
                    if [[ "${now_remaining_space}" -le "${limit_remaining_space}" ]]; then
                        echo -e "${WARNING} Remaining space is less than ${limit_remaining_space}G, exit this make."
                        break
                    else
                        echo "Remaining space is ${now_remaining_space}G."
                    fi

                    # Execute the following functions in sequence
                    make_image
                    extract_openwrt
                    replace_kernel
                    refactor_bootfs
                    refactor_rootfs
                    clean_tmp

                    echo -e "(${j}.${i}) OpenWrt made successfully. \n"
                    let i++
                }
            done

            let j++
        }
    done
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

# Show welcome message
echo -e "${STEPS} Welcome to make OpenWrt!"
echo -e "${INFO} Server running on Ubuntu: [ Release: ${host_release} / Host: ${arch_info} ] "
# Check script permission
[[ "$(id -u)" == 0 ]] || error_msg "please run this script as root: [ sudo ./${0} ]"

# Initialize variables and download the kernel
init_var "${@}"
init_files
check_data
# Find OpenWrt file
find_openwrt
# Download the dependency files
download_depends
# Query the latest kernel version
[[ "${auto_kernel}" == "true" ]] && query_kernel
# Download the kernel files
download_kernel

# # Show make settings
echo -e "${INFO} [ ${#make_openwrt[@]} ] lists of OpenWrt board: [ $(echo ${make_openwrt[@]} | xargs) ]"
echo -e "${INFO} Kernel Repo: [ ${kernel_repo} ], Kernel Usage: [ ${kernel_usage} ] \n"
# # Show server start information
echo -e "${INFO} Server space usage before starting to compile: \n$(server_space) \n"

# # Loop to make OpenWrt firmware
loop_make

# # Show server end information
echo -e "${STEPS} Server space usage after compilation: \n$(server_space) \n"
echo -e "${SUCCESS} All process completed successfully."
# # All process completed
wait
