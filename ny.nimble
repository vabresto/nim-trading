# Package

version       = "0.1.0"
author        = "Victor Brestoiu"
description   = "A new awesome nimble package"
license       = "Proprietary"
srcDir        = "src"
installExt    = @["nim"]
binDir        = "bin"
namedBin["ny/apps/md_ws/main"] = "ny-md-ws"
namedBin["ny/apps/md_rec/main"] = "ny-md-rec"
namedBin["ny/apps/ou_ws/main"] = "ny-ou-ws"
namedBin["ny/apps/ou_rec/main"] = "ny-ou-rec"
namedBin["ny/apps/trading/main"] = "ny-trading"
namedBin["ny/apps/runner/main"] = "ny-runner"

namedBin["ny/core/heartbeat/client"] = "ny-heartbeat-client"
namedBin["ny/core/heartbeat/server"] = "ny-heartbeat-server"


# For some reason, running on mac requires setting `DYLD_LIBRARY_PATH=/usr/local/lib` before calling the binary ...


# Dependencies

requires "chronicles#ab3ab545be0b550cca1c2529f7e97fbebf5eba81"
requires "db_connector#07a60d54c4b68f1b70266ca08a23fb1a7c78c91b"
requires "fusion#562467452b32cb7a97410ea177f083e6d8405734"
requires "jsony#649705ec70dffeecba4c40df914b62d37a1c695c"
requires "nim >= 2.0.0"
requires "questionable#47692e0d923ada8f7f731275b2a87614c0150987"
requires "results#193d3c6648bd0f7e834d4ebd6a1e1d5f93998197"
requires "threading#79195379ba682fc672690854ad4ec48c9362eb6f"
requires "ws#5ac521b72d7d4860fb394e5e1f9f08cf480e9822"

requires "ssh://git@github-personal/vabresto/nim-redis.git#164c331b71ce6b244cf645267589c457c3808607"

# Indirect dependencies, pin git hashes because they don't properly update versions
requires "stew#1662762c0144854db60632e4115fe596ffa67fca"
