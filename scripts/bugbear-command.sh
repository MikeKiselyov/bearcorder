#!/bin/bash
# Sends an automation command to a running Bugbear (needs automationEnabled, see Automation.swift).
#   scripts/bugbear-command.sh save:10
# The command goes in as an argument, not inside the script text, so quotes and backslashes in it
# arrive as they are.
osascript -l JavaScript -e 'function run(argv) { ObjC.import("Foundation"); $.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately("Bugbear.automation", argv[0], $(), true); }' "$1" >/dev/null
