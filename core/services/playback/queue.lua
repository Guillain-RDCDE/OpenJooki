-- services.playback.queue: the order in which a playlist's tracks are played. The identity, or a
-- shuffle memoised per playlist in playback_int.shuffle (never for an audiobook), drawn from the seed
-- the facade sets at boot from the clock (playback_int.seed), so that two starts, or two playlists of
-- the same length, do not play in the same "random" order. Pure: works on the facade's working table.
local queue = {}

-- ------------------------------------------------------------------ queue
local function shuffled(n, seed)
  local order = {}
  for i = 1, n do order[i] = i end
  local s = seed or 0
  for i = n, 2, -1 do
    s = (s * 1103515245 + 12345) % 2147483648
    local j = (s % i) + 1
    order[i], order[j] = order[j], order[i]
  end
  return order
end

--- The order in which a playlist's tracks are played (identity or a memoised shuffle).
function queue.queue_for(doc, pb, playlist_id, p)
  local n = #p.tracks
  local cfg = doc.audiocfg or {}
  if not cfg.shuffle_mode or p.audiobook then
    local q = {}
    for i = 1, n do q[i] = i end
    return q
  end
  local q = pb.shuffle[playlist_id]
  if q and #q == n then return q end
  q = shuffled(n, math.floor((pb.seed or 0) + n * 7919))
  pb.shuffle[playlist_id] = q
  return q
end

--- Where a track index sits in the queue (nil when it is not there).
function queue.index_of(q, index)
  for pos, i in ipairs(q) do if i == index then return pos end end
  return nil
end

return queue
