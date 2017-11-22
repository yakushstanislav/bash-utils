#!/bin/sh

COLOR_RED="\033[0;31m"
COLOR_BLUE="\033[0;94m"
COLOR_GREEN="\033[0;92m"
COLOR_CYAN="\033[0;96m"
COLOR_YELLOW="\033[0;93m"
COLOR_DEFAULT="\033[0m"

FS_TYPE=ext4
MOUNTPOINT_PREFIX=mount_

PWD_BIN=$(which pwd)
BASENAME_BIN=$(which basename)
REALPATH_BIN=$(which realpath)

AWK_BIN=$(which awk)

DD_BIN=$(which dd)
RM_BIN=$(which rm)

MKDIR_BIN=$(which mkdir)
RMDIR_BIN=$(which rmdir)

MOUNT_BIN=$(which mount)
UMOUNT_BIN=$(which umount)

MKFS_BIN=$(which mkfs.$FS_TYPE)
FSCK_BIN=$(which fsck.$FS_TYPE)

CRYPTSETUP_BIN=$(which cryptsetup)
SHA1SUM_BIN=$(which sha1sum)

PWD=$($PWD_BIN)
SCRIPT_NAME=$($BASENAME_BIN $0)

check_variable()
{
    local name=$1
    local value=$2

    if [ -z $value ]; then
        echo "${COLOR_RED}Variable \"$name\" is not set${COLOR_DEFAULT}"
        exit 1
    fi
}

check_last_error()
{
    if [ ! $? -eq 0 ]; then
        echo "${COLOR_RED}Last command return error${COLOR_DEFAULT}"
        exit 1
    fi
}

check_storage_exists()
{
    local path=$1

    if [ ! -f $path ]; then
        echo "${COLOR_RED}Storage $path not exists${COLOR_DEFAULT}"
        exit 1
    fi
}

get_sha1_sum()
{
    local sha1_sum=$(echo -n $1 | $SHA1SUM_BIN | $AWK_BIN '{print $1}')

    echo $sha1_sum
}

create_storage()
{
    local path=$1
    local size=$2

    check_variable "Path" $path
    check_variable "Size" $size

    local name=$($BASENAME_BIN $path)

    echo "${COLOR_CYAN}Create storage (Name: $name, Path: $path, Size: $size)${COLOR_DEFAULT}"

    if [ -f $path ]; then
        echo "${COLOR_RED}Storage $path already exists${COLOR_DEFAULT}"
        exit 1
    fi

    $DD_BIN if=/dev/zero of=$1 bs=${size}M count=1000
    check_last_error

    $CRYPTSETUP_BIN -q -y luksFormat $path
    check_last_error

    echo "${COLOR_BLUE}Please, enter passphrase again...${COLOR_DEFAULT}"

    $CRYPTSETUP_BIN luksOpen $path $name
    check_last_error

    echo "${COLOR_YELLOW}Format storage...${COLOR_DEFAULT}"

    $MKFS_BIN /dev/mapper/$name
    check_last_error

    $CRYPTSETUP_BIN luksClose $path $name
    check_last_error

    echo "${COLOR_GREEN}Storage (Path: $path) successfully created!${COLOR_DEFAULT}"
}

delete_storage()
{
    local path=$1

    check_variable "Path" $path

    local name=$($BASENAME_BIN $path)

    echo "${COLOR_CYAN}Delete storage (Name: $name, Path: $path)${COLOR_DEFAULT}"

    $CRYPTSETUP_BIN status $name
    if [ $? -eq 0 ]; then
        $CRYPTSETUP_BIN luksClose $name
        check_last_error
    fi

    check_storage_exists $path

    $RM_BIN -i $path
    check_last_error

    echo "${COLOR_GREEN}Storage (Path: $path) deleted!${COLOR_DEFAULT}"
}

mount_storage()
{
    local path=$1

    check_variable "Path" $path

    local name=$($BASENAME_BIN $path)

    echo "${COLOR_CYAN}Mount storage (Name: $name, Path: $path)${COLOR_DEFAULT}"

    check_storage_exists $path

    $CRYPTSETUP_BIN status $name
    if [ $? -ne 0 ]; then
        $CRYPTSETUP_BIN luksOpen $path $name
        check_last_error
    fi

    local real_path=$($REALPATH_BIN $path)

    local sha1_sum=$(get_sha1_sum $real_path)
    local mountpoint=$PWD/$MOUNTPOINT_PREFIX${sha1_sum}_${name}

    $MKDIR_BIN -p $mountpoint
    check_last_error

    $FSCK_BIN /dev/mapper/$name
    if [ $? -ne 0 ]; then
        $CRYPTSETUP_BIN luksClose $name
        echo "${COLOR_RED}Storage filesystem ${FS_TYPE} is corrupted${COLOR_DEFAULT}"
        exit 1
    fi

    $MOUNT_BIN /dev/mapper/$name $mountpoint
    if [ $? -ne 0 ]; then
        $CRYPTSETUP_BIN luksClose $name
        echo "${COLOR_RED}Failed to mount storage${COLOR_DEFAULT}"
        exit 1
    fi

    echo "${COLOR_GREEN}Storage (Path: $path) is mounted!${COLOR_DEFAULT}"
}

umount_storage()
{
    local path=$1

    check_variable "Path" $path

    local name=$($BASENAME_BIN $path)

    echo "${COLOR_CYAN}Umount storage (Name: $name, Path: $path)${COLOR_DEFAULT}"

    check_storage_exists $path

    local real_path=$($REALPATH_BIN $path)

    local sha1_sum=$(get_sha1_sum $real_path)
    local mountpoint=$PWD/$MOUNTPOINT_PREFIX${sha1_sum}_${name}

    $UMOUNT_BIN -l -f $mountpoint
    check_last_error

    $RMDIR_BIN $mountpoint
    check_last_error

    $CRYPTSETUP_BIN status $name > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        $CRYPTSETUP_BIN luksClose $name
        check_last_error
    fi

    echo "${COLOR_GREEN}Storage (Path: $path) is unmounted!${COLOR_DEFAULT}"
}

status_storage()
{
    local path=$1

    check_variable "Path" $path

    local name=$($BASENAME_BIN $path)

    echo "${COLOR_CYAN}Status storage (Path: $path)${COLOR_DEFAULT}"

    check_storage_exists $path

    $CRYPTSETUP_BIN status $name
}

print_logo()
{
    echo -n "${COLOR_BLUE}"
    cat <<EOF
_________   ______________________ _____  _____________ _____________
|______| \  ||      |______   |   |     ||_____/|_____||  ____|______
|______|  \_||_____ ______|   |   |_____||    \_|     ||_____||______
----------------------------------------------------------------------
EOF
    echo -n "${COLOR_DEFAULT}"
}

show_help()
{
    print_logo

    echo "Usage $SCRIPT_NAME script:"
    echo "    $SCRIPT_NAME create <path> <size in GB>"
    echo "    $SCRIPT_NAME delete <path>"
    echo "    $SCRIPT_NAME mount <path>"
    echo "    $SCRIPT_NAME umount <path>"
    echo "    $SCRIPT_NAME status <path>"
}

case "$1" in
    create)
        create_storage $2 $3
        ;;
    delete)
        delete_storage $2
        ;;
    mount)
        mount_storage $2
        ;;
    umount)
        umount_storage $2
        ;;
    status)
        status_storage $2
        ;;
    help)
        show_help
        ;;
    *)

    echo "${COLOR_RED}Invalid command: $1${COLOR_DEFAULT}"
    show_help
    exit 1
esac

exit 0
