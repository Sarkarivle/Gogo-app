# Fake call greeting clips

Drop 1-3 short audio clips here (a girl's voice saying something like "hello?
hello... aap sun rahe ho?" — 2-4 seconds each) with these exact filenames:

- `call_greeting_1.mp3`
- `call_greeting_2.mp3` (optional)
- `call_greeting_3.mp3` (optional)

`FakeCallScreen` (`lib/features/call/screens/fake_call_screen.dart`) picks one
at random each time so the same clip doesn't always play. At minimum
`call_greeting_1.mp3` must exist, or the fake call will skip straight to
"call ended" with no audio.

This file exists so `assets/audio/` is a real, git-tracked directory (an
empty folder isn't tracked by git) — delete it once real clips are added,
it's not referenced by any code.
