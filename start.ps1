$Env:Path = "$(Get-Location)\.ai\node-v18.19.0-win-x64;" + $Env:Path
npm config set prefix "$(Get-Location)\.ai\node-v18.19.0-win-x64\node_global"
npm config set cache "$(Get-Location)\.ai\node-v18.19.0-win-x64\node_cache"
$Env:Path = "$(Get-Location)\.ai\node-v18.19.0-win-x64\node_global;" + $Env:Path




