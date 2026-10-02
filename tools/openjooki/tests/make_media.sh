#!/bin/bash
# Generate small test audio files (needs ffmpeg).
cd "$(dirname "$0")"; mkdir -p media
for i in 1 2 3 4 5 6; do
  ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=$((300+i*80)):duration=3" -metadata title="Chanson $i" -metadata artist="Artiste" -metadata album="Album Test" -b:a 64k media/song$i.mp3
done
ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=500:duration=3" -b:a 64k "media/sans tags é.mp3"
# a disc in FLAC (e2e E25): 24 bit / 96 kHz like an audiophile's, tags, a front cover inside track 1,
# file names in the wrong order on purpose (the tracks must follow TRACKNUMBER), a cover.jpg, a .cue
rm -rf "media/Disque FLAC"; mkdir -p "media/Disque FLAC"
ffmpeg -loglevel error -y -f lavfi -i "color=c=orange:s=800x800" -frames:v 1 "media/Disque FLAC/cover.jpg"
ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=440:duration=6" -i "media/Disque FLAC/cover.jpg" -map 0:a -map 1:v -c:v copy -disposition:v attached_pic \
  -ac 2 -ar 96000 -sample_fmt s32 -c:a flac -metadata title="Première piste" -metadata artist="Les Testeurs" -metadata album="Disque d'essai" \
  -metadata album_artist="Les Testeurs" -metadata track="1" -metadata TRACKTOTAL="2" -metadata date="1999" "media/Disque FLAC/b - première.flac"
ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=660:duration=6" -ac 2 -c:a flac -metadata title="Deuxième piste" -metadata artist="Les Testeurs" \
  -metadata album="Disque d'essai" -metadata track="2" "media/Disque FLAC/a - deuxième.flac"
echo "REM a cue sheet, not audio" > "media/Disque FLAC/disque.cue"
echo "pas de l'audio" > media/notaudio.mp3
head -c 20000 /dev/urandom > media/garbage.mp3
ls media
