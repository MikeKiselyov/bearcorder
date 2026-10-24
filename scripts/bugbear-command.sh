#!/bin/bash
# Sends an automation command to a running Bugbear (needs automationEnabled, see Automation.swift).
#   scripts/bugbear-command.sh save:10
osascript -l JavaScript -e "ObjC.import('Foundation'); \$.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately('Bugbear.automation', '$1', \$(), true)" >/dev/null
