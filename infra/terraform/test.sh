#!/usr/bin/env bash
# Infrastructure checks only: no jobs, agent execution or model inference.
set -euo pipefail
exec bash "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/verify.sh"
