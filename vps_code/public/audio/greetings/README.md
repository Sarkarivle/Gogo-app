# Call greeting clips

Drop `.mp3` / `.m4a` / `.wav` / `.aac` / `.ogg` files in this folder to make
them available in the app's simulated call preview (the "ring → connect →
hear a voice → cut → paywall" flow for free-mode users, and the fake call
shown to creator profiles).

- Files are served statically at `/audio/greetings/<filename>`.
- The app fetches the current list from `GET /api/chat/call/greeting-audio`
  (see `ChatController.getCallGreetingAudio`) and picks one at random.
- No app release is needed to add, replace, or remove clips — just add/remove
  files here on the server.
- If this folder is empty, the app falls back to no greeting audio (silent
  "Connected" beat before the call ends).
- Keep clips short (a few seconds) — the call auto-ends shortly after the
  clip finishes (8s safety cap either way).
