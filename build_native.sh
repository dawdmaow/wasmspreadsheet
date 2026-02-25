#!/usr/bin/env bash

set -euxo pipefail

odin build . -o:speed -define:MICROUI_MAX_WIDTHS=999
