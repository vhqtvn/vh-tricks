#!/bin/bash
remove_from_path() {
  PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "$1" | tr '\n' ':' | sed 's/:$//')
  export PATH
}

wrapper_dir=$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")
remove_from_path "$(basename "$(dirname "$0")")"
