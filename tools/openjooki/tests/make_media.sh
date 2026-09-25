#!/bin/bash
# Generate small test audio files (needs ffmpeg).
cd "$(dirname "$0")"; mkdir -p media
for i in 1 2 3 4 5 6; do
  ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=$((300+i*80)):duration=3" -metadata title="Chanson $i" -metadata artist="Artiste" -metadata album="Album Test" -b:a 64k media/song$i.mp3
done
ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=500:duration=3" -b:a 64k "media/sans tags é.mp3"
echo "pas de l'audio" > media/notaudio.mp3
head -c 20000 /dev/urandom > media/garbage.mp3
ls media
