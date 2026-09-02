#!/usr/bin/env bash

set -Eeuo pipefail
# shellcheck source=common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_command node
require_command npm
(cd "${PROJECT_ROOT}" && npm test)
