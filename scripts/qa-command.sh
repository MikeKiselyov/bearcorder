#!/bin/bash
# Sends an automation command to a running QA Helper (needs automationEnabled, see Automation.swift).
#   scripts/qa-command.sh save:10
osascript -l JavaScript -e "ObjC.import('Foundation'); \$.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately('QAHelper.automation', '$1', \$(), true)" >/dev/null
