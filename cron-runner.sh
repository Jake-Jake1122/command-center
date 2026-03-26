#!/bin/bash
cd /root/clawd/command-center
source .env
./refresh-dashboard.sh "$1" >> /root/clawd/command-center/cron.log 2>&1
