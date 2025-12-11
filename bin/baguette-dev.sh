#!/usr/bin/env bash
#
# Usage: bin/baguette-dev.sh [path/to/a/baguette/app/script/or/folder]
#
# Build and run a generic baguette docker contaienr, mount the specified ($1)
# baguette app script or folder into the container and run it.
#
# Currently, this script is meant for demo-ing examples, and for doing local
# development; however, we might generalize it later to serve as a baguette
# app launcher.
#
set -e

script_dir=$(cd "$(dirname "$0")" && pwd)

noargs=
baguette_app=${1:-.}
[[ ${1:-} ]] && shift || noargs=x

image=localhost/baguette
container_home=/home/baguette

app_mount_root=$container_home/baguette/mnt
#
# NOTE: This is chosen so the relative symbolic links in the example
#       apps will work inside the container.

app_is_a_folder=
if [[ -d $baguette_app ]]; then
    app_is_a_folder=x
    app_script=main.sh
    app_folder=$(cd "$baguette_app" && pwd)
else
    app_script=${baguette_app##*/}
    app_folder=$(cd "$(dirname "$baguette_app")" && pwd)
fi
app_script=$app_folder/$app_script

get-app-bind-mount () {
    if [[ $app_is_a_folder ]]; then
        echo "$app_folder:$app_mount_root/${app_folder##*/}"
    else
        echo "$app_script:$app_mount_root/${app_script##*/}"
    fi
}

get-app-folder-name () {
    if [[ $app_is_a_folder ]]; then
        echo "${app_folder##*/}"
    else
        echo .
    fi
}

cd "$script_dir/.."

docker build -t $image .

docker_opts=(
    --rm
    -e WSD_PORT=5000 -p 5000:5000
    -v "$PWD:$container_home/baguette"
    -v "$(get-app-bind-mount)"
    -w "$app_mount_root/$(get-app-folder-name)"
)

cmd=./${app_script##*/}
if [[ $noargs ]]; then
    docker_opts+=("-it")
    cmd=/bin/bash
fi

mkdir -p mnt
exec docker run "${docker_opts[@]}" $image "$cmd" "$@"
