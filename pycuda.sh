#!/bin/bash

#####################################################################################################
##                                Global Variables                                                 ##
#####################################################################################################

LOG_INFO_COLOR="\033[0;36m"
LOG_ERROR_COLOR="\033[1;91m"
LOG_CMD_COLOR="\033[0m"

SUFFIX=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)
WORKING_DIR=tmp-${SUFFIX}

CUDA_REPO="nvidia/cuda"
CUDA_TAG_SUFFIX="devel-ubuntu22.04"
PYTHON_REPO="python"
PYTHON_TAG_SUFFIX="bullseye"
DOCKER_NOT_FOUND_STR="no such manifest"

OUTPUT_IMAGE_NAME="pycuda"

#####################################################################################################
##                                Util Functions                                                   ##
#####################################################################################################

usage() {
    echo "Usage: $0 --python PYTHON_VERSION --cuda CUDA_VERSION [--requirements REQUIREMENTS_PATH]"
    echo ""
    echo "Options:"
    echo "  -h, --help                Show this help message and exit."
    echo "  -p, --python VERSION      Specify the Python version to use."
    echo "  -c, --cuda VERSION        Specify the CUDA version to use."
    echo "  -r, --requirements PATH   Specify the path to a requirements.txt file for Python packages."
}

generate_image_tag() {
    local version="$1"
    local suffix="$2"
    local dot_count=$(grep -o "\." <<< "$version" | wc -l)

    if [[ dot_count -eq 0 ]]; then
        version="${version}.0.0"
    elif [[ dot_count -eq 1 ]]; then
        version="${version}.0"
    fi

    image_tag="${version}-${suffix}"
    printf "%s" "$image_tag"
}

check_docker_tag() {
    local repo="$1"
    local tag="$2"

    echo -e "${LOG_INFO_COLOR}:date -u:Info: Checking if ${repo}:${tag} exist. ${LOG_CMD_COLOR}"

    if ! docker manifest inspect "$repo":"$tag" > /dev/null 2>&1; then
       echo -e "${LOG_ERROR_COLOR}:date -u:Error: Image $repo:$tag doesn't exist. ${LOG_CMD_COLOR}"
       exit 1
    fi
}

generate_dockerfile() {
    local docker_context=""
    local cuda_tag="$1"
    local python_tag="$2"
    local new_dockerfile_path="${WORKING_DIR}/Dockerfile"

    echo -e "${LOG_INFO_COLOR}:date -u:Info: Generating Dockerfile and temporary working directory. ${LOG_CMD_COLOR}"

    mkdir -p "${WORKING_DIR}"

    local from_lines="FROM ${CUDA_REPO}:${cuda_tag} AS builder
FROM ${PYTHON_REPO}:${python_tag} AS final"

    docker_context="$from_lines"

    local cuda_semver=$(echo "$cuda_tag" | awk -F'-' '{print $1}')
    IFS="." read -r -a cuda_version_parts <<< "$cuda_semver"
    cuda_major="${cuda_version_parts[0]}"
    cuda_minor="${cuda_version_parts[1]}"

    local copy_cuda_lines="COPY --from=builder /usr/local/cuda /usr/local/cuda
COPY --from=builder /usr/local/cuda-${cuda_major} /usr/local/cuda-${cuda_major}
COPY --from=builder /usr/local/cuda-${cuda_major}.${cuda_minor} /usr/local/cuda-${cuda_major}.${cuda_minor}"

    docker_context="$docker_context
$copy_cuda_lines"

    docker_context="$docker_context
WORKDIR /workspace"

    if [ ! -z "$requirements_path" ]; then
        cp "${requirements_path}" "${WORKING_DIR}/requirements.txt"
        docker_context="$docker_context
COPY ./requirements.txt ."
    fi

    local constant_run_line="RUN apt-get update -y && \
apt-get install -y --no-install-recommends xfce4-terminal gcc glibc* nano vim openjdk-17-jdk openjdk-17-jre byobu && \
rm -rf /var/lib/apt/lists/* && \
pip install --upgrade pip"

    docker_context="$docker_context
$constant_run_line"

    if [ ! -z "$requirements_path" ]; then
        docker_context="$docker_context
RUN pip install -r ./requirements.txt"
    fi

    docker_context="$docker_context
ENTRYPOINT bash"

    echo "${docker_context}" | sed 's/^[ \t]*//' | sed 's/\"//g' > "${new_dockerfile_path}"

    printf "%s" "${new_dockerfile_path}"
}

build_docker() {
    local build_path="$1"
    local is_buildx="true"
    local full_image_name="${OUTPUT_IMAGE_NAME}:py${python_version}-cuda${cuda_version}"

    echo -e "${LOG_INFO_COLOR}:date -u:Info: Building Docker image. ${LOG_CMD_COLOR}"

    if ! docker buildx version > /dev/null 2>&1; then
        echo -e "${LOG_INFO_COLOR}:date -u:Info: Docker Buildx is not installed on this host, using regular Docker. ${LOG_CMD_COLOR}"
        is_buildx="false"
    fi

    cd ${WORKING_DIR}

    if [[ is_buildx == "true" ]]; then
        echo -e "${LOG_INFO_COLOR}:date -u:Info: Docker Buildx is used to build the image. ${LOG_CMD_COLOR}"
        docker buildx build -t ${full_image_name} .
    else
        docker build -t ${full_image_name} .
    fi

    if [[ $? != 0 ]]; then
         echo -e "${LOG_INFO_COLOR}:date -u:Fail: Failed to build Docker image. ${LOG_CMD_COLOR}"
    else
         echo -e "${LOG_INFO_COLOR}:date -u:Info: New Docker image is available: ${full_image_name}. ${LOG_CMD_COLOR}"
    fi

    cd ..
    rm -rf ${WORKING_DIR}
}

#####################################################################################################
##                                Options Parsing                                                  ##
#####################################################################################################

TEMP=$(getopt -o hp:c:r: --long help,python:,cuda:,requirements: -n "$0" -- "$@")
if [ $? != 0 ]; then
    echo -e "${LOG_ERROR_COLOR}:date -u:Error: Failed to parse options ${LOG_CMD_COLOR}" >&2
    exit 1
fi

eval set -- "$TEMP"

while true; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -p|--python)
            python_version="$2"
            shift 2
            ;;
        -c|--cuda)
            cuda_version="$2"
            shift 2
            ;;
        -r|--requirements)
            requirements_path="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            usage
            ;;
    esac
done

if [[ -z "$python_version" || -z "$cuda_version" ]]; then
    echo -e "${LOG_ERROR_COLOR}:date -u:Error: -p|--python and -c|--cuda are mandatory options. ${LOG_CMD_COLOR}"
    exit 1
fi

#####################################################################################################
##                                Program Execution                                                ##
#####################################################################################################

main() {
    local python_tag=$(generate_image_tag "$python_version" "$PYTHON_TAG_SUFFIX")
    local cuda_tag=$(generate_image_tag "$cuda_version" "$CUDA_TAG_SUFFIX")

    check_docker_tag "$PYTHON_REPO" "$python_tag"
    check_docker_tag "$CUDA_REPO" "$cuda_tag"

    mkdir ${WORKING_DIR}

    local build_path=$(generate_dockerfile "$cuda_tag" "$python_tag")

    build_docker "$build_path"
}

main