# Package

version       = "0.1.0"
author        = "Victor Brestoiu"
description   = "A new awesome nimble package"
license       = "Proprietary"
srcDir        = "src"
installExt    = @["nim"]
binDir        = "bin"
namedBin["apps/mdconn/main"] = "mdconn"
namedBin["apps/mdrec/main"] = "mdrec"
namedBin["apps/study/ny"] = "study:ny"


# Dependencies

requires "nim >= 2.0.0"

requires "ssh://git@github-personal/vabresto/nim-redis.git#f6e4962ac3e369a47afc75de8d3f52d148fb6436"
