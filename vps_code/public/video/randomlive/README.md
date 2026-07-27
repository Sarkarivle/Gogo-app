# Random Live fake-partner videos

Drop `.mp4` / `.mov` / `.webm` files here (short clips, ideally with voice/talking,
filmed to look like a normal front-camera video chat) to make them available in
the app's Random Live matching flow.

- Files are served statically at `/video/randomlive/<filename>`.
- The app fetches the current list from `GET /api/chat/random-live/videos` (see
  `ChatController.getRandomLiveVideos`) and picks one at random.
- Used to simulate an occasional "partner" for free-mode users during random
  matching — periodically (every 1–4 real connections), instead of matching
  with a real stranger, the app plays one of these clips full-screen as if it
  were a live video call, then cuts and shows the paywall.
- No app release is needed to add, replace, or remove clips — just add/remove
  files here on the server.
- Keep clips short (10-20s) — playback is capped at 25s regardless.
