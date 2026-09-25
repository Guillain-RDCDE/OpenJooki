#!/bin/bash
# copy the web UI into the fake Jooki (bench)
set -e
W=/jooki/app/www/public
mkdir -p $W/static/media
rm -f $W/config.js; cp "$(dirname "$0")"/../webui/{index.html,app.js,app.css,mqtt.js,service-worker.js} $W/
# placeholder token pictures (the real ones exist on the Jooki)
for f in dragon.cffed3d7 fox.ac721aec ghost.c2a43882 knight.dc50962b whale.da72da11 dragon-black.27a71b2c fox-black.7d23b82c knight-black.d995170a whale-black.74e936a9 dragon-white.921a8110 fox-white.8f5e5c27 knight-white.b0dd9a37 whale-white.218d88b9 flat.5534d75d; do
  python3 -c "
import base64;open('$W/static/media/$f.png','wb').write(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='))"
done
cp $W/static/media/flat.5534d75d.png $W/icon.png; cp $W/static/media/flat.5534d75d.png $W/favicon.ico
