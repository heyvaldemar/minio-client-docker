#!/bin/bash
# Copyright Broadcom, Inc. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0
#
# Bitnami custom library
#
# Changed by Vladimir Mikhalev for heyvaldemar/minio-client (2026): the
# welcome line names this image instead of Bitnami's, which it is not.

# shellcheck disable=SC1091

# Load Generic Libraries
. /opt/bitnami/scripts/liblog.sh

# Constants
BOLD='\033[1m'

# Functions

########################
# Print the welcome page
# Globals:
#   DISABLE_WELCOME_MESSAGE
#   BITNAMI_APP_NAME
# Arguments:
#   None
# Returns:
#   None
#########################
print_welcome_page() {
    if [[ -z "${DISABLE_WELCOME_MESSAGE:-}" ]]; then
        if [[ -n "$BITNAMI_APP_NAME" ]]; then
            print_image_welcome_page
        fi
    fi
}

########################
# Print the welcome page for a Bitnami Docker image
# Globals:
#   BITNAMI_APP_NAME
# Arguments:
#   None
# Returns:
#   None
#########################
print_image_welcome_page() {
    info ""
    info "${BOLD}${BITNAMI_APP_NAME} from heyvaldemar/minio-client, laid out like Bitnami's${RESET}"
    info ""
}

