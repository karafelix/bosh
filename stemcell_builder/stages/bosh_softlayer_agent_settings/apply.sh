#!/usr/bin/env bash

base_dir=$(readlink -nf $(dirname $0)/../..)
source $base_dir/lib/prelude_apply.bash


cat > $chroot/var/vcap/bosh/agent.json <<JSON
{
  "Platform": {
    "Linux": {
      "CreatePartitionIfNoEphemeralDisk": false
    }
  },
  "Infrastructure": {
    "Settings": {
      "DevicePathResolutionType": "virtio",
      "NetworkingType": "manual",
      "Sources": [
        {
          "Type": "File",
          "SettingsPath": "/var/vcap/bosh/user_data.json"
        }
      ],
      "UseRegistry": true
    }
  }
}
JSON
