#!/bin/sh

COLOR_RED="\e[31m"
COLOR_BLUE="\e[94m"
COLOR_GREEN="\e[92m"
COLOR_CYAN="\e[96m"
COLOR_YELLOW="\e[93m"
COLOR_DEFAULT="\e[39m"

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

CRYPTSETUP_BIN=$(which cryptsetup)
SHA1SUM_BIN=$(which sha1sum)

PWD=$($PWD_BIN)
SCRIPT_NAME=$($BASENAME_BIN $0)

check_variable()
{
    NAME=$1
    VALUE=$2

    if [ -z $VALUE ]; then
        echo "${COLOR_RED}Variable \"$NAME\" is not set${COLOR_DEFAULT}"
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
    PATH=$1

    if [ ! -f $PATH ]; then
        echo "${COLOR_RED}Storage $PATH not exists${COLOR_DEFAULT}"
        exit 1
    fi
}

get_sha1_sum()
{
    SHA1_SUM=$(echo -n $1 | $SHA1SUM_BIN | $AWK_BIN '{print $1}')

    echo $SHA1_SUM
}

create_storage()
{
    PATH=$1
    SIZE=$2

    check_variable "Path" $PATH
    check_variable "Size" $SIZE

    NAME=$($BASENAME_BIN $PATH)

    echo "${COLOR_CYAN}Create storage (Name: $NAME, Path: $PATH, Size: $SIZE)${COLOR_DEFAULT}"

    if [ -f $PATH ]; then
        echo "${COLOR_RED}Storage $PATH already exists${COLOR_DEFAULT}"
        exit 1
    fi

    $DD_BIN if=/dev/zero of=$1 bs=${SIZE}M count=1000
    check_last_error

    $CRYPTSETUP_BIN create $NAME $PATH
    check_last_error

    $MKFS_BIN /dev/mapper/$NAME
    check_last_error

    $CRYPTSETUP_BIN close $NAME
    check_last_error

    echo "${COLOR_GREEN}Storage (Path: $PATH) successfully created!${COLOR_DEFAULT}"
}

delete_storage()
{
    PATH=$1

    check_variable "Path" $PATH

    NAME=$($BASENAME_BIN $PATH)

    echo "${COLOR_CYAN}Delete storage (Name: $NAME, Path: $PATH)${COLOR_DEFAULT}"

    $CRYPTSETUP_BIN status $NAME
    if [ $? -eq 0 ]; then
        $CRYPTSETUP_BIN close $NAME
        check_last_error
    fi

    check_storage_exists $PATH

    $RM_BIN -i $PATH
    check_last_error

    echo "${COLOR_GREEN}Storage (Path: $PATH) deleted!${COLOR_DEFAULT}"
}

mount_storage()
{
    PATH=$1

    check_variable "Path" $PATH

    NAME=$($BASENAME_BIN $PATH)

    echo "${COLOR_CYAN}Mount storage (Name: $NAME, Path: $PATH)${COLOR_DEFAULT}"

    check_storage_exists $PATH

    $CRYPTSETUP_BIN status $NAME
    if [ $? -ne 0 ]; then
        $CRYPTSETUP_BIN open --type plain $PATH $NAME
        check_last_error
    fi

    REAL_PATH=$($REALPATH_BIN $PATH)

    SHA1SUM=$(get_sha1_sum $REAL_PATH)
    MOUNTPOINT=$PWD/$MOUNTPOINT_PREFIX${SHA1SUM}_${NAME}

    $MKDIR_BIN -p $MOUNTPOINT
    check_last_error

    $MOUNT_BIN /dev/mapper/$NAME $MOUNTPOINT
    if [ ! $? -eq 0 ]; then
        $CRYPTSETUP_BIN close $NAME
        echo "${COLOR_RED}Failed to mount storage${COLOR_DEFAULT}"
        exit 1
    fi

    echo "${COLOR_GREEN}Storage (Path: $PATH) is mounted!${COLOR_DEFAULT}"
}

umount_storage()
{
    PATH=$1

    check_variable "Path" $PATH

    NAME=$($BASENAME_BIN $PATH)

    echo "${COLOR_CYAN}Umount storage (Name: $NAME, Path: $PATH)${COLOR_DEFAULT}"

    check_storage_exists $PATH

    REAL_PATH=$($REALPATH_BIN $PATH)

    SHA1SUM=$(get_sha1_sum $REAL_PATH)
    MOUNTPOINT=$PWD/$MOUNTPOINT_PREFIX${SHA1SUM}_${NAME}

    $UMOUNT_BIN -l -f $MOUNTPOINT
    check_last_error

    $RMDIR_BIN $MOUNTPOINT
    check_last_error

    $CRYPTSETUP_BIN status $NAME > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        $CRYPTSETUP_BIN close $NAME
        check_last_error
    fi

    echo "${COLOR_GREEN}Storage (Path: $PATH) is unmounted!${COLOR_DEFAULT}"
}

status_storage()
{
    PATH=$1

    check_variable "Path" $PATH

    NAME=$($BASENAME_BIN $PATH)

    echo "${COLOR_CYAN}Status storage (Path: $PATH)${COLOR_DEFAULT}"

    check_storage_exists $PATH

    $CRYPTSETUP_BIN status $NAME
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

    echo "Usage encrypt_storage.sh script:"
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
