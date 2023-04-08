# Moonraker/Klipper update configuration
#
# Copyright (C) 2022  Eric Callahan <arksine.code@gmail.com>
#
# This file may be distributed under the terms of the GNU GPLv3 license.

from __future__ import annotations
import os
import sys
import copy
from ...utils import source_info
from typing import (
    TYPE_CHECKING,
    Dict
)

if TYPE_CHECKING:
    from ...confighelper import ConfigHelper
    from ..database import MoonrakerDatabase

KLIPPER_DEFAULT_PATH = os.path.expanduser("~/klipper-group/klipper")
KLIPPER_DEFAULT_EXEC = os.path.expanduser("~/klipper-group/klippy-env/bin/python")

BASE_CONFIG: Dict[str, Dict[str, str]] = {
    "moonraker": {
        "origin": "https://gitlab.com/pipettin-bot/forks/moonraker.git",
        "primary_branch": "pipetting",
        "requirements": "scripts/moonraker-requirements.txt",
        "venv_args": "-p python3",
        "install_script": "scripts/install-moonraker-arch.sh",
        "host_repo": "https://gitlab.com/pipettin-bot/forks/moonraker",
        "env": sys.executable,
        # NOTE: This will return the path to "moonraker/"
        "path": str(source_info.source_path()),
        "managed_services": "moonraker"
    },
    "klipper": {
        "moved_origin": "https://gitlab.com/pipettin-bot/forks/klipper.git",
        "origin": "https://gitlab.com/pipettin-bot/forks/klipper.git",
        "primary_branch": "pipetting",
        "requirements": "scripts/klippy-requirements.txt",
        "venv_args": "-p python3",
        "install_script": "scripts/install-octopi.sh",  # NOTE: not yet supported.
        "host_repo": "https://gitlab.com/pipettin-bot/forks/klipper",
        "managed_services": "klipper",
        # NOTE: This will return the path to "moonraker/../"
        "path": str(source_info.source_path().parent)
    }
}

def get_base_configuration(config: ConfigHelper, channel: str) -> ConfigHelper:
    server = config.get_server()
    base_cfg = copy.deepcopy(BASE_CONFIG)
    app_type = "zip" if channel == "stable" else "git_repo"
    # Moonraker
    base_cfg["moonraker"]["channel"] = channel
    base_cfg["moonraker"]["type"] = app_type
    # Klipper
    base_cfg["klipper"]["channel"] = channel
    base_cfg["klipper"]["type"] = app_type
    db: MoonrakerDatabase = server.lookup_component('database')
    base_cfg["klipper"]["path"] = db.get_item("moonraker", "update_manager.klipper_path", KLIPPER_DEFAULT_PATH).result()
    base_cfg["klipper"]["env"] = db.get_item("moonraker", "update_manager.klipper_exec", KLIPPER_DEFAULT_EXEC).result()
    
    return config.read_supplemental_dict(base_cfg)
