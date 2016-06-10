#!/usr/bin/env bash
set -o nounset # Treat unset variables as an error and immediately exit
set -o errexit # If a command fails exit the whole script

if [ "${DEBUG:-false}" = "true" ]; then
  set -x # Run the entire script in debug mode
fi

usage() {
    echo "usage: $(basename $0) <box_name> <box_suffix> <version>"
    echo
    echo "Requires the following environment variables to be set:"
    echo "  ATLAS_USERNAME"
    echo "  ATLAS_TOKEN"
}

args() {
    if [ $# -lt 3 ]; then
        usage
        exit 1
    fi

    if [ -z ${ATLAS_USERNAME+x} ]; then
        echo "ATLAS_USERNAME environment variable not set!"
        usage
        exit 1
    elif [ -z ${ATLAS_TOKEN+x} ]; then
        echo "ATLAS_TOKEN environment variable not set!"
        usage
        exit 1
    fi

    BOX_NAME=$1
    BOX_SUFFIX=$2
    VERSION=$3
}

get_short_description() {
    if [[ "${BOX_NAME}" =~ i386 ]]; then
        BIT_STRING="32-bit"
    else
        BIT_STRING="64-bit"
    fi
    RAW_VERSION=${BOX_NAME#centos}
    PRETTY_VERSION=${RAW_VERSION:0:1}.${RAW_VERSION:1}

    VIRTUALBOX_VERSION=$(virtualbox --help | head -n 1 | awk '{print $NF}')
    VMWARE_VERSION=10.0.6
    SHORT_DESCRIPTION="CentOS ${PRETTY_VERSION} (${BIT_STRING})"
}

create_description() {
    if [[ "${BOX_NAME}" =~ i386 ]]; then
        BIT_STRING="32-bit"
    else
        BIT_STRING="64-bit"
    fi
    RAW_VERSION=${BOX_NAME#centos}
    PRETTY_VERSION=${RAW_VERSION:0:1}.${RAW_VERSION:1}

    VIRTUALBOX_VERSION=$(virtualbox --help | head -n 1 | awk '{print $NF}')
    VMWARE_VERSION=10.0.6

    VMWARE_BOX_FILE=box/vmware/${BOX_NAME}${BOX_SUFFIX}
    VIRTUALBOX_BOX_FILE=box/virtualbox/${BOX_NAME}${BOX_SUFFIX}
    DESCRIPTION="CentOS ${PRETTY_VERSION} (${BIT_STRING})

"
    if [[ -e ${VMWARE_BOX_FILE} ]]; then
        FILESIZE=$(du -k -h "${VMWARE_BOX_FILE}" | cut -f1)
        DESCRIPTION=${DESCRIPTION}"VMWare ${FILESIZE}B/"
    fi
    if [[ -e ${VIRTUALBOX_BOX_FILE} ]]; then
        FILESIZE=$(du -k -h "${VIRTUALBOX_BOX_FILE}" | cut -f1)
        DESCRIPTION=${DESCRIPTION}"VirtualBox ${FILESIZE}B/"
    fi
    DESCRIPTION=${DESCRIPTION%?}

    if [[ -e ${VMWARE_BOX_FILE} ]]; then
        DESCRIPTION="${DESCRIPTION}

VMware Tools ${VMWARE_VERSION}"
    fi
    if [[ -e ${VIRTUALBOX_BOX_FILE} ]]; then
        DESCRIPTION="${DESCRIPTION}

VirtualBox Guest Additions ${VIRTUALBOX_VERSION}"
    fi

    VERSION_JSON=$(
      jq -n "{
        version: {
          version: \"${VERSION}\",
          description: \"${DESCRIPTION}\"
        }
      }"
    )
}

publish_provider() {
    atlas_username=$1
    atlas_access_token=$2

    echo "==> Checking to see if ${PROVIDER} provider exists"
    HTTP_STATUS=$(curl -s -f -o /dev/null -w "%{http_code}" -i "${ATLAS_API_URL}/box/${atlas_username}/${BOX_NAME}/version/${VERSION}/provider/${PROVIDER}"?access_token="${atlas_access_token}" || true)
    if [ 200 -eq ${HTTP_STATUS} ]; then
        echo "==> Updating ${PROVIDER} provider"
        curl -X PUT -o /dev/null "${ATLAS_API_URL}/box/${atlas_username}/${BOX_NAME}/version/${VERSION}/provider/${PROVIDER}" -d "access_token=${atlas_access_token}" -d provider[name]="${PROVIDER}"
    else
        echo "==> Creating ${PROVIDER} provider"
        curl -X POST -o /dev/null "${ATLAS_API_URL}/box/${atlas_username}/${BOX_NAME}/version/${VERSION}/providers" -d "access_token=${atlas_access_token}" -d provider[name]="${PROVIDER}"
    fi
    upload_provider ${atlas_username} ${atlas_access_token}
}

upload_provider() {
    atlas_username=$1
    atlas_access_token=$2

    echo "==> Retrieving upload path for provider"
    JSON_RESULT=$(curl "${ATLAS_API_URL}/box/${atlas_username}/${BOX_NAME}/version/${VERSION}/provider/${PROVIDER}/upload"?access_token="${atlas_access_token}")

    upload_path=$(echo ${JSON_RESULT} | jq '.upload_path')

    echo "==> Uploading the built image for ${PROVIDER}"
    echo "==> Upload Path: ${upload_path}"

    if [ -z ${upload_path+x} ]; then
        echo "upload_path environment variable not set!"
        usage
        exit 1
    fi

    if [[ "${PROVIDER}" =~ vmware ]]; then
      box_file=$(echo $VMWARE_BOX_FILE)
    fi
    if [[ "${PROVIDER}" =~ virtualbox ]]; then
      box_file=$(echo $VIRTUALBOX_BOX_FILE)
    fi

    HTTP_STATUS=$(eval curl -X PUT -s -f -o /dev/null -w "%{http_code}" -i --upload-file ${box_file} "${upload_path}")

    if [ 200 -eq ${HTTP_STATUS} ]; then
      echo "==> Successfully uploaded ${PROVIDER}"
    else
      echo "Failed to upload ${PROVIDER}: ${HTTP_STATUS}"
      exit 1
    fi
}

atlas_publish() {
    atlas_username=$1
    atlas_access_token=$2

    ATLAS_API_URL=https://atlas.hashicorp.com/api/v1

    echo "==> Checking for existing box ${BOX_NAME} on ${atlas_username}"
    # Retrieve box
    HTTP_STATUS=$(curl -s -f -o /dev/null -w "%{http_code}" -i "${ATLAS_API_URL}/box/${atlas_username}/${BOX_NAME}"?access_token="${atlas_access_token}" || true)
    if [ 404 -eq ${HTTP_STATUS} ]; then
        echo "${BOX_NAME} does not exist, creating"
        get_short_description

        curl -X POST "${ATLAS_API_URL}/boxes" -d box[name]="${BOX_NAME}" -d box[short_description]="${SHORT_DESCRIPTION}" -d box[is_private]=false -d "access_token=${atlas_access_token}"
    elif [ 200 -ne ${HTTP_STATUS} ]; then
        echo "Unknown status ${HTTP_STATUS} from box/get" && exit 1
    fi

    echo "==> Checking for existing version ${VERSION} on ${atlas_username}"
    # Retrieve version
    HTTP_STATUS=$(curl -s -f -o /dev/null -w "%{http_code}" -i "${ATLAS_API_URL}/box/${atlas_username}/${BOX_NAME}/version/${VERSION}" || true)
    if [ 404 -ne ${HTTP_STATUS} ] && [ 200 -ne ${HTTP_STATUS} ]; then
        echo "Unknown HTTP status ${HTTP_STATUS} from version/get" && exit 1
    fi

    create_description
    if [ 404 -eq ${HTTP_STATUS} ]; then
       echo "==> none found; creating"
       JSON_RESULT=$(curl -s -f -X POST -H "Content-Type: application/json" "${ATLAS_API_URL}/box/${atlas_username}/${BOX_NAME}/versions?access_token=${atlas_access_token}" -d "${VERSION_JSON}" || true)
    else
       echo "==> version found; updating"
       JSON_RESULT=$(curl -s -f -X PUT "${ATLAS_API_URL}/box/${atlas_username}/${BOX_NAME}/version/${VERSION}" -d "access_token=${atlas_access_token}" -d "version[description]=${DESCRIPTION}" || true)
    fi
    STATUS=$(echo ${JSON_RESULT} | jq -r .status)

    if [[ -e ${VMWARE_BOX_FILE} ]]; then
        PROVIDER=vmware_desktop
        publish_provider ${atlas_username} ${atlas_access_token}
    fi
    if [[ -e ${VIRTUALBOX_BOX_FILE} ]]; then
        PROVIDER=virtualbox
        publish_provider ${atlas_username} ${atlas_access_token}
    fi

    case $STATUS in
    unreleased)
      curl -X PUT -o /dev/null "${ATLAS_API_URL}/box/${atlas_username}/${BOX_NAME}/version/${VERSION}/release" -d "access_token=${atlas_access_token}"
      echo "==> Successfully released ${BOX_NAME}:${PRETTY_VERSION}"
      ;;
    active)
      echo "==> ${BOX_NAME}:${PRETTY_VERSION} already released"
      ;;
    *)
      echo "Failed to release ${BOX_NAME}:${PRETTY_VERSION}"
      echo "Cannot publish version with status '$STATUS'"
    esac
}

main() {
    args "$@"

    ATLAS_API_URL=https://atlas.hashicorp.com/api/v1
    atlas_publish ${ATLAS_USERNAME} ${ATLAS_TOKEN}
}

main "$@"
