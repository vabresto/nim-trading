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
namedBin["ny/apps/trading/main"] = "ny-trading"


# Dependencies

requires "chronicles#ab3ab545be0b550cca1c2529f7e97fbebf5eba81"
requires "db_connector#07a60d54c4b68f1b70266ca08a23fb1a7c78c91b"
requires "jsony#649705ec70dffeecba4c40df914b62d37a1c695c"
requires "nim >= 2.0.0"
requires "questionable#47692e0d923ada8f7f731275b2a87614c0150987"
requires "results#193d3c6648bd0f7e834d4ebd6a1e1d5f93998197"
requires "ws#5ac521b72d7d4860fb394e5e1f9f08cf480e9822"

requires "ssh://git@github-personal/vabresto/nim-redis.git#f6e4962ac3e369a47afc75de8d3f52d148fb6436"

# Indirect dependencies, pin git hashes because they don't properly update versions
requires "stew#1662762c0144854db60632e4115fe596ffa67fca"
