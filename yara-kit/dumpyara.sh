#!/usr/bin/env bash

[[ $# = 0 ]] && echo "No Input" && exit 1

OS=`uname`
if [ "$OS" = 'Darwin' ]; then
    export LC_CTYPE=C
fi

PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
#PROJECT_DIR="$( 
# Create input & working directory if it does not exist
mkdir -p "$PROJECT_DIR"/input "$PROJECT_DIR"/working

# Determine which command to use for privilege escalation
if command -v sudo > /dev/null 2>&1; then
    sudo_cmd="sudo"
elif command -v doas > /dev/null 2>&1; then
    sudo_cmd="doas"
else
    echo "Neither sudo nor doas found. Please install one of them."
    exit 1
fi

# Activate virtual environment
source .venv/bin/activate

# GitLab token
    if [[ -s "${PROJECT_DIR}"/.gitlab_group ]]; then
		GIT_ORG=$(< "${PROJECT_DIR}"/.gitlab_group)	# Set Your Gitlab Group Name
	else
		GIT_USER="$(git config --get user.name)"
		GIT_ORG="${GIT_USER}"				# Otherwise, Your Username will be used
	fi

	# Gitlab Vars
	GITLAB_TOKEN=$(< "${PROJECT_DIR}"/.gitlab_token)	# Write Your Gitlab Token In a Text File
	if [ -f "${PROJECT_DIR}"/.gitlab_instance ]; then
		GITLAB_INSTANCE=$(< "${PROJECT_DIR}"/.gitlab_instance)
	else
		GITLAB_INSTANCE="gitlab.com"
	fi
	GITLAB_HOST="https://${GITLAB_INSTANCE}"

# download or copy from local?
if echo "$1" | grep -e '^\(https\?\|ftp\)://.*$' > /dev/null; then
    # 1DRV URL DIRECT LINK IMPLEMENTATION
    if echo "$1" | grep -e '1drv.ms' > /dev/null; then
        URL=`curl -I "$1" -s | grep location | sed -e "s/redir/download/g" | sed -e "s/location: //g"`
    else
        URL=$1
    fi
    cd "$PROJECT_DIR"/input || exit
    { type -p aria2c > /dev/null 2>&1 && printf "Downloading File...\n" && aria2c -x16 -j"$(nproc)" "${URL}"; } || { printf "Downloading File...\n" && wget -q --content-disposition --show-progress --progress=bar:force "${URL}" || exit 1; }
    if [[ ! -f "$(echo ${URL##*/} | inline-detox)" ]]; then
        URL=$(wget --server-response --spider "${URL}" 2>&1 | awk -F"filename=" '{print $2}')
    fi
    detox "${URL##*/}"
else
    URL=$(printf "%s\n" "$1")
    [[ -e "$URL" ]] || { echo "Invalid Input" && exit 1; }
fi

ORG=androiddumps #your GitHub org name
FILE=$(echo ${URL##*/} | inline-detox)
EXTENSION=$(echo ${URL##*.} | inline-detox)
UNZIP_DIR=${FILE/.$EXTENSION/}
PARTITIONS="system systemex system_ext system_other vendor cust odm odm_ext oem factory product modem xrom oppo_product opproduct reserve india my_preload my_odm my_stock my_operator my_country my_product my_company my_engineering my_heytap my_custom my_manifest my_carrier my_region my_bigball my_version special_preload vendor_dlkm odm_dlkm system_dlkm mi_ext"

if [[ -d "$1" ]]; then
    echo 'Directory detected. Copying...'
    cp -a "$1" "$PROJECT_DIR"/working/"${UNZIP_DIR}"
elif [[ -f "$1" ]]; then
    echo 'File detected. Copying...'
    cp -a "$1" "$PROJECT_DIR"/input/"${FILE}" > /dev/null 2>&1
fi

# clone other repo's
if [[ -d "$PROJECT_DIR/Firmware_extractor" ]]; then
    git -C "$PROJECT_DIR"/Firmware_extractor pull --recurse-submodules
else
    git clone -q --recurse-submodules https://github.com/AndroidDumps/Firmware_extractor "$PROJECT_DIR"/Firmware_extractor
fi
if [[ -d "$PROJECT_DIR/mkbootimg_tools" ]]; then
    git -C "$PROJECT_DIR"/mkbootimg_tools pull --recurse-submodules
else
    git clone -q https://github.com/carlitros900/mkbootimg_tools "$PROJECT_DIR/mkbootimg_tools"
fi
if [[ -d "$PROJECT_DIR/vmlinux-to-elf" ]]; then
    git -C "$PROJECT_DIR"/vmlinux-to-elf pull --recurse-submodules
else
    git clone -q https://github.com/marin-m/vmlinux-to-elf "$PROJECT_DIR/vmlinux-to-elf"
fi

# extract rom via Firmware_extractor
[[ -f "$1" ]] && bash "$PROJECT_DIR"/Firmware_extractor/extractor.sh "$PROJECT_DIR"/input/"${FILE}" "$PROJECT_DIR"/working/"${UNZIP_DIR}"

# Extract boot.img
if [[ -f "$PROJECT_DIR"/working/"${UNZIP_DIR}"/boot.img ]]; then
    extract-dtb "$PROJECT_DIR"/working/"${UNZIP_DIR}"/boot.img -o "$PROJECT_DIR"/working/"${UNZIP_DIR}"/bootimg > /dev/null # Extract boot
    bash "$PROJECT_DIR"/mkbootimg_tools/mkboot "$PROJECT_DIR"/working/"${UNZIP_DIR}"/boot.img "$PROJECT_DIR"/working/"${UNZIP_DIR}"/boot > /dev/null 2>&1
    echo 'boot extracted'
    # extract-ikconfig
    [[ ! -e "${PROJECT_DIR}"/extract-ikconfig ]] && curl https://raw.githubusercontent.com/torvalds/linux/master/scripts/extract-ikconfig > ${PROJECT_DIR}/extract-ikconfig
    bash "${PROJECT_DIR}"/extract-ikconfig "$PROJECT_DIR"/working/"${UNZIP_DIR}"/boot.img > "$PROJECT_DIR"/working/"${UNZIP_DIR}"/ikconfig
    # vmlinux-to-elf
    mkdir -p "$PROJECT_DIR"/working/"${UNZIP_DIR}"/bootRE
    python3 "${PROJECT_DIR}"/vmlinux-to-elf/vmlinux_to_elf/kallsyms_finder.py "$PROJECT_DIR"/working/"${UNZIP_DIR}"/boot.img > "$PROJECT_DIR"/working/"${UNZIP_DIR}"/bootRE/boot_kallsyms.txt 2>&1
    echo 'boot_kallsyms.txt generated'
    python3 "${PROJECT_DIR}"/vmlinux-to-elf/vmlinux_to_elf/main.py "$PROJECT_DIR"/working/"${UNZIP_DIR}"/boot.img "$PROJECT_DIR"/working/"${UNZIP_DIR}"/bootRE/boot.elf > /dev/null 2>&1
    echo 'boot.elf generated'
fi

if [[ -f "$PROJECT_DIR"/working/"${UNZIP_DIR}"/dtbo.img ]]; then
    extract-dtb "$PROJECT_DIR"/working/"${UNZIP_DIR}"/dtbo.img -o "$PROJECT_DIR"/working/"${UNZIP_DIR}"/dtbo > /dev/null # Extract dtbo
    echo 'dtbo extracted'
fi

# Extract dts
mkdir -p "$PROJECT_DIR"/working/"${UNZIP_DIR}"/bootdts
dtb_list=$(find "$PROJECT_DIR"/working/"${UNZIP_DIR}"/bootimg -name '*.dtb' -type f -printf '%P\n' | sort)
for dtb_file in $dtb_list; do
    dtc -I dtb -O dts -o "$(echo "$PROJECT_DIR"/working/"${UNZIP_DIR}"/bootdts/"$dtb_file" | sed -r 's|.dtb|.dts|g')" "$PROJECT_DIR"/working/"${UNZIP_DIR}"/bootimg/"$dtb_file" > /dev/null 2>&1
done

# extract PARTITIONS
cd "$PROJECT_DIR"/working/"${UNZIP_DIR}" || exit
for p in $PARTITIONS; do
    # Try to extract images via fsck.erofs
    if [ -f $p.img ] && [ $p != "modem" ]; then
        echo "Trying to extract $p partition via fsck.erofs."
        "$PROJECT_DIR"/Firmware_extractor/tools/Linux/bin/fsck.erofs --extract="$p" "$p".img
        # Deletes images if they were correctly extracted via fsck.erofs
        if [ -d "$p" ]; then
            rm "$p".img > /dev/null 2>&1
        else
        # Uses 7z if images could not be extracted via fsck.erofs
            if [[ -e "$p.img" ]]; then
                mkdir "$p" 2> /dev/null || rm -rf "${p:?}"/*
                echo "Extraction via fsck.erofs failed, extracting $p partition via 7z"
                7z x "$p".img -y -o"$p"/ > /dev/null 2>&1
                if [ $? -eq 0 ]; then
                    rm "$p".img > /dev/null 2>&1
                else
                    echo "Couldn't extract $p partition via 7z. Using mount loop"
                    $sudo_cmd mount -o loop -t auto "$p".img "$p"
                    mkdir "${p}_"
                    $sudo_cmd cp -rf "${p}/"* "${p}_"
                    $sudo_cmd umount "${p}"
                    $sudo_cmd cp -rf "${p}_/"* "${p}"
                    $sudo_cmd rm -rf "${p}_"
                    if [ $? -eq 0 ]; then
                        rm -fv "$p".img > /dev/null 2>&1
                    else
                        echo "Couldn't extract $p partition. It might use an unsupported filesystem."
                        echo "For EROFS: make sure you're using Linux 5.4+ kernel."
                        echo "For F2FS: make sure you're using Linux 5.15+ kernel."
                    fi
                fi
            fi
        fi
    fi
done

# Fix permissions
$sudo_cmd chown "$(whoami)" "$PROJECT_DIR"/working/"${UNZIP_DIR}"/./* -fR
$sudo_cmd chmod -fR u+rwX "$PROJECT_DIR"/working/"${UNZIP_DIR}"/./*

printf "\nFinal Repository Should Look Like...\n" && ls -lAog "$PROJECT_DIR"/working/"${UNZIP_DIR}""

# board-info.txt
find "$PROJECT_DIR"/working/"${UNZIP_DIR}"/modem -type f -exec strings {} \; | grep "QC_IMAGE_VERSION_STRING=MPSS." | sed "s|QC_IMAGE_VERSION_STRING=MPSS.||g" | cut -c 4- | sed -e 's/^/require version-baseband=/' >> "$PROJECT_DIR"/working/"${UNZIP_DIR}"/board-info.txt
find "$PROJECT_DIR"/working/"${UNZIP_DIR}"/tz* -type f -exec strings {} \; | grep "QC_IMAGE_VERSION_STRING" | sed "s|QC_IMAGE_VERSION_STRING|require version-trustzone|g" >> "$PROJECT_DIR"/working/"${UNZIP_DIR}"/board-info.txt
if [ -e "$PROJECT_DIR"/working/"${UNZIP_DIR}"/vendor/build.prop ]; then
    strings "$PROJECT_DIR"/working/"${UNZIP_DIR}"/vendor/build.prop | grep "ro.vendor.build.date.utc" | sed "s|ro.vendor.build.date.utc|require version-vendor|g" >> "$PROJECT_DIR"/working/"${UNZIP_DIR}"/board-info.txt
fi
sort -u -o "$PROJECT_DIR"/working/"${UNZIP_DIR}"/board-info.txt "$PROJECT_DIR"/working/"${UNZIP_DIR}"/board-info.txt

# set variables
ls system/build*.prop 2> /dev/null || ls system/system/build*.prop 2> /dev/null || { echo "No system build*.prop found, pushing cancelled!" && exit; }
flavor=$(grep -oP "(?<=^ro.build.flavor=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${flavor}" ]] && flavor=$(grep -oP "(?<=^ro.vendor.build.flavor=).*" -hs vendor/build*.prop)
[[ -z "${flavor}" ]] && flavor=$(grep -oP "(?<=^ro.system.build.flavor=).*" -hs {system,system/system}/build*.prop)
[[ -z "${flavor}" ]] && flavor=$(grep -oP "(?<=^ro.build.type=).*" -hs {system,system/system}/build*.prop)
release=$(grep -oP "(?<=^ro.build.version.release=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${release}" ]] && release=$(grep -oP "(?<=^ro.vendor.build.version.release=).*" -hs vendor/build*.prop)
[[ -z "${release}" ]] && release=$(grep -oP "(?<=^ro.system.build.version.release=).*" -hs {system,system/system}/build*.prop)
release=`echo "$release" | head -1`
id=$(grep -oP "(?<=^ro.build.id=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${id}" ]] && id=$(grep -oP "(?<=^ro.vendor.build.id=).*" -hs vendor/build*.prop)
[[ -z "${id}" ]] && id=$(grep -oP "(?<=^ro.system.build.id=).*" -hs {system,system/system}/build*.prop)
incremental=$(grep -oP "(?<=^ro.build.version.incremental=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${incremental}" ]] && incremental=$(grep -oP "(?<=^ro.vendor.build.version.incremental=).*" -hs vendor/build*.prop)
[[ -z "${incremental}" ]] && incremental=$(grep -oP "(?<=^ro.system.build.version.incremental=).*" -hs {system,system/system}/build*.prop)
tags=$(grep -oP "(?<=^ro.build.tags=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${tags}" ]] && tags=$(grep -oP "(?<=^ro.vendor.build.tags=).*" -hs vendor/build*.prop)
[[ -z "${tags}" ]] && tags=$(grep -oP "(?<=^ro.system.build.tags=).*" -hs {system,system/system}/build*.prop)
platform=$(grep -oP "(?<=^ro.board.platform=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${platform}" ]] && platform=$(grep -oP "(?<=^ro.vendor.board.platform=).*" -hs vendor/build*.prop)
[[ -z "${platform}" ]] && platform=$(grep -oP "(?<=^ro.system.board.platform=).*" -hs {system,system/system}/build*.prop)
manufacturer=$(grep -oP "(?<=^ro.product.odm.manufacturer=).*" -hs odm/etc/build*.prop)
[[ -z "${manufacturer}" ]] && manufacturer=$(grep -oP "(?<=^ro.product.manufacturer=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${manufacturer}" ]] && manufacturer=$(grep -oP "(?<=^ro.vendor.product.manufacturer=).*" -hs vendor/build*.prop)
[[ -z "${manufacturer}" ]] && manufacturer=$(grep -oP "(?<=^ro.system.product.manufacturer=).*" -hs {system,system/system}/build*.prop)
[[ -z "${manufacturer}" ]] && manufacturer=$(grep -oP "(?<=^ro.product.vendor.manufacturer=).*" -hs vendor/build*.prop)
[[ -z "${manufacturer}" ]] && manufacturer=$(grep -oP "(?<=^ro.product.system.manufacturer=).*" -hs {system,system/system}/build*.prop)
fingerprint=$(grep -oP "(?<=^ro.odm.build.fingerprint=).*" -hs odm/etc/*build*.prop)
[[ -z "${fingerprint}" ]] && fingerprint=$(grep -oP "(?<=^ro.build.fingerprint=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${fingerprint}" ]] && fingerprint=$(grep -oP "(?<=^ro.vendor.build.fingerprint=).*" -hs vendor/build*.prop)
[[ -z "${fingerprint}" ]] && fingerprint=$(grep -oP "(?<=^ro.system.build.fingerprint=).*" -hs {system,system/system}/build*.prop)
codename=$(grep -oP "(?<=^ro.product.odm.device=).*" -hs odm/etc/build*.prop | head -1)
[[ -z "${codename}" ]] && codename=$(grep -oP "(?<=^ro.product.device=).*" -hs {vendor,system,system/system}/build*.prop | head -1)
[[ -z "${codename}" ]] && codename=$(grep -oP "(?<=^ro.product.vendor.device=).*" -hs vendor/build*.prop | head -1)
[[ -z "${codename}" ]] && codename=$(grep -oP "(?<=^ro.vendor.product.device=).*" -hs vendor/build*.prop | head -1)
[[ -z "${codename}" ]] && codename=$(grep -oP "(?<=^ro.product.system.device=).*" -hs {system,system/system}/build*.prop | head -1)
[[ -z "${codename}" ]] && codename=$(echo "$fingerprint" | cut -d / -f3 | cut -d : -f1)
[[ -z "${codename}" ]] && codename=$(grep -oP "(?<=^ro.build.fota.version=).*" -hs {system,system/system}/build*.prop | cut -d - -f1 | head -1)
brand=$(grep -oP "(?<=^ro.product.odm.brand=).*" -hs odm/etc/${codename}_build.prop | head -1)
[[ -z "${brand}" ]] && brand=$(grep -oP "(?<=^ro.product.odm.brand=).*" -hs odm/etc/build*.prop | head -1)
[[ -z "${brand}" ]] && brand=$(grep -oP "(?<=^ro.product.brand=).*" -hs {vendor,system,system/system}/build*.prop | head -1)
[[ -z "${brand}" ]] && brand=$(grep -oP "(?<=^ro.product.vendor.brand=).*" -hs vendor/build*.prop | head -1)
[[ -z "${brand}" ]] && brand=$(grep -oP "(?<=^ro.vendor.product.brand=).*" -hs vendor/build*.prop | head -1)
[[ -z "${brand}" ]] && brand=$(grep -oP "(?<=^ro.product.system.brand=).*" -hs {system,system/system}/build*.prop | head -1)
[[ -z "${brand}" ]] && brand=$(echo "$fingerprint" | cut -d / -f1)
description=$(grep -oP "(?<=^ro.build.description=).*" -hs {system,system/system,vendor}/build*.prop)
[[ -z "${description}" ]] && description=$(grep -oP "(?<=^ro.vendor.build.description=).*" -hs vendor/build*.prop)
[[ -z "${description}" ]] && description=$(grep -oP "(?<=^ro.system.build.description=).*" -hs {system,system/system}/build*.prop)
[[ -z "${description}" ]] && description="$flavor $release $id $incremental $tags"
is_ab=$(grep -oP "(?<=^ro.build.ab_update=).*" -hs {system,system/system,vendor}/build*.prop | head -1)
[[ -z "${is_ab}" ]] && is_ab="false"
branch=$(echo "$description" | tr ' ' '-')
repo=$(echo "$brand"_"$codename"_dump | tr '[:upper:]' '[:lower:]')
platform=$(echo "$platform" | tr '[:upper:]' '[:lower:]' | tr -dc '[:print:]' | tr '_' '-' | cut -c 1-35)
top_codename=$(echo "$codename" | tr '[:upper:]' '[:lower:]' | tr -dc '[:print:]' | tr '_' '-' | cut -c 1-35)
manufacturer=$(echo "$manufacturer" | tr '[:upper:]' '[:lower:]' | tr -dc '[:print:]' | tr '_' '-' | cut -c 1-35)
printf "# %s\n- manufacturer: %s\n- platform: %s\n- codename: %s\n- flavor: %s\n- release: %s\n- id: %s\n- incremental: %s\n- tags: %s\n- fingerprint: %s\n- is_ab: %s\n- brand: %s\n- branch: %s\n- repo: %s\n" "$description" "$manufacturer" "$platform" "$codename" "$flavor" "$release" "$id" "$incremental" "$tags" "$fingerprint" "$is_ab" "$brand" "$branch" "$repo" > "$PROJECT_DIR"/working/"${UNZIP_DIR}"/README.md
cat "$PROJECT_DIR"/working/"${UNZIP_DIR}"/README.md

# Generate AOSP device tree
if python3 -c "import aospdtgen"; then
    echo "aospdtgen installed, generating device tree"
    mkdir -p "${PROJECT_DIR}/working/${UNZIP_DIR}/aosp-device-tree"
    if python3 -m aospdtgen . --output "${PROJECT_DIR}/working/${UNZIP_DIR}/aosp-device-tree"; then
        echo "AOSP device tree successfully generated"
    else
        echo "Failed to generate AOSP device tree"
    fi
fi

# copy file names
chown "$(whoami)" ./* -R
chmod -R u+rwX ./* #ensure final permissions
find "$PROJECT_DIR"/working/"${UNZIP_DIR}" -type f -printf '%P\n' | sort | grep -v ".git/" > "$PROJECT_DIR"/working/"${UNZIP_DIR}"/all_files.txt

if [[ -s "${PROJECT_DIR}"/.gitlab_token ]]; then
	if [[ -s "${PROJECT_DIR}"/.gitlab_group ]]; then
		GIT_ORG=$(< "${PROJECT_DIR}"/.gitlab_group)	# Set Your Gitlab Group Name
	else
		GIT_USER="$(git config --get user.name)"
		GIT_ORG="${GIT_USER}"				# Otherwise, Your Username will be used
	fi
    # Check if already dumped or not
	[[ $(curl -sL "${GITLAB_HOST}/${GIT_ORG}/${repo,,}/-/raw/${branch}/all_files.txt" | grep "all_files.txt") ]] && { printf "Firmware already dumped!\nGo to https://"$GITLAB_INSTANCE"/${GIT_ORG}/${repo}/-/tree/${branch}\n" && exit 1; }
    # Remove The Journal File Inside System/Vendor
	find . -mindepth 2 -type d -name "\[SYS\]" -exec rm -rf {} \; 2>/dev/null
	printf "\nFinal Repository Should Look Like...\n" && ls -lAog
	printf "\n\nStarting Git Init...\n"
    git init
    git config --global http.postBuffer 524288000		# A Simple Tuning to Get Rid of curl (18) error while `git push`
	git checkout -b "${branch}" || { git checkout -b "${incremental}" && export branch="${incremental}"; }
	find . \( -name "*sensetime*" -o -name "*.lic" \) | cut -d'/' -f'2-' >| .gitignore
	[[ ! -s .gitignore ]] && rm .gitignore
	[[ -z "$(git config --get user.email)" ]] && git config user.email "guptasushrut@gmail.com"
	[[ -z "$(git config --get user.name)" ]] && git config user.name "Sushrut1101"
	git add --all
    git commit -asm "Add ${description}"
    git update-ref -d HEAD
    git reset system/ vendor/ product/
    git checkout -b "$branch"
    git commit -asm "Add extras for ${description}" && "${GITPUSH[@]}"
    git add vendor/
    git commit -asm "Add vendor for ${description}" && "${GITPUSH[@]}"
    git add system/system/app/ || git add system/app/
    git commit -asm "Add system app for ${description}" && "${GITPUSH[@]}"
    git add system/system/priv-app/ || git add system/priv-app/
    git commit -asm "Add system priv-app for ${description}" && "${GITPUSH[@]}"
    git add system/
    git commit -asm "Add system for ${description}" && "${GITPUSH[@]}"
    git add product/app/
    git commit -asm "Add product app for ${description}" && "${GITPUSH[@]}"
    git add product/priv-app/
    git commit -asm "Add product priv-app for ${description}" && "${GITPUSH[@]}"
    git add product/
    git commit -asm "Add product for ${description}" && "${GITPUSH[@]}"
else
    echo "Dump done locally."
    exit 1
fi

# Telegram channel
TG_TOKEN=$(< "$PROJECT_DIR"/.tg_token)
if [[ -n "$TG_TOKEN" ]]; then
    CHAT_ID=$(< "${PROJECT_DIR}"/.tg_chat)
    commit_head=$(git log --format=format:%H | head -n 1)
    commit_link="https://github.com/$ORG/$repo/commit/$commit_head"
    echo -e "Sending telegram notification"
    printf "<b>Brand: %s</b>" "$brand" >| "$PROJECT_DIR"/working/tg.html
    {
        printf "\n<b>Device: %s</b>" "$codename"
        printf "\n<b>Version:</b> %s" "$release"
        printf "\n<b>Fingerprint:</b> %s" "$fingerprint"
        printf "\n<b>GitHub:</b>"
        printf "\n<a href=\"%s\">Commit</a>" "$commit_link"
        printf "\n<a href=\"https://github.com/%s/%s/tree/%s/\">%s</a>" "$ORG" "$repo" "$branch" "$codename"
    } >> "$PROJECT_DIR"/working/tg.html
    TEXT=$(< "$PROJECT_DIR"/working/tg.html)
    curl -s "https://api.telegram.org/bot${TG_TOKEN}/sendmessage" --data "text=${TEXT}&chat_id=${CHAT_ID}&parse_mode=HTML&disable_web_page_preview=True" > /dev/null
    rm -rf "$PROJECT_DIR"/working/tg.html
fi
