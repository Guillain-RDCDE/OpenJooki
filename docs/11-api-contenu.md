# Jooki content API (reverse-engineered, static)

The web interface drives the library through an **MQTT bus** (mosquitto broker,
port 1883) and an HTTP upload endpoint. Reconstructed from the original JS bundle.

## MQTT mechanism
Every command = publish a **JSON payload** on the topic **`/j/web/input/<TYPE>`**
(the action minus its internal fields). The app publishes its full state on
**`/j/web/output/state`** (playlists, tracks, playback).

## Uploading a file
`POST http://<jooki>/upload` as **multipart/form-data**:
- **field name = `upload_id`** (a random integer, `floor(random*1e7)`),
- **value = the file** (filename = the file's name).
- The file must be **> 5000 bytes**. HTTP 200 response on success.
- The server processes the file, computes a track id (hex) and extracts the
  metadata (duration, ID3 title, cover art).

## Library commands (topic → payload)
| Action | Topic (`/j/web/input/…`) | Payload |
|---|---|---|
| New playlist | `PLAYLIST_NEW` | `{title, audiobook}` |
| Add an upload | `PLAYLIST_ADD_UPLOAD` | `{playlistId, uploadId, filename}` |
| Add an existing track | `PLAYLIST_ADD_TRACK` | `{playlistId, trackId}` |
| Add a stream | `PLAYLIST_ADD_STREAM` | `{playlistId, title, url}` |
| Remove a track | (remove) | `{playlistId, trackIndex}` |
| Update playlist (title, order, token) | `PLAYLIST_UPDATE` | `{playlist:{…}}` |
| Delete playlist | `PLAYLIST_DELETE` | `{playlistId}` |
| Play playlist | `PLAYLIST_PLAY` | `{playlistId}` |
| Name a token | `TOKEN_EDIT` | `{tagId, name}` |
| Delete a token | `TOKEN_DELETE` | `{tagId}` |
| Volume / shuffle / repeat | `SET_VOL` / `SET_CFG` | `{vol}` / `{shuffle_mode}` `{repeat_mode}` |
| Playback | `DO_PLAY`/`DO_PAUSE`/`DO_NEXT`/`DO_PREV` | (empty) |

## "Add music to a playlist" flow
1. `upload_id = floor(random*1e7)`
2. `POST /upload` (field=upload_id, value=file)
3. publish `PLAYLIST_ADD_UPLOAD` `{playlistId, uploadId:upload_id, filename:name}`
4. the app records the track and republishes the state.

## Data model (files on the device)
`/jooki/external/jooki/`: `playlists.json` (playlist→{tagId, title, audiobook,
tracks:[trackId…]}), `tracks.json` (trackId→{title, artist, album, duration,
filename, size, userFilename, hasImage}), `uploads/<trackId>` (the MP3).
