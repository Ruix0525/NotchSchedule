#!/bin/bash
# 朋友用: 抓最新版並重新安裝
set -e
cd "$(dirname "$0")"
git pull
./build.sh install
