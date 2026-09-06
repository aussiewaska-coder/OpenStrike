# Jet engine audio

`jet_engine_loop.ogg` is derived from the user-supplied Downloads file
`jet-engine-ambience-gfx-sounds-1-01-10.mp3` (70.50 seconds, stereo 44.1 kHz).
The original file remains in Downloads. No independent licence or recording
provenance was supplied with the file.

Preparation: take seconds 12–37; join the final and first second with an
equal-power crossfade, then rotate the join to the end of the remaining body.
The result is a 24-second loop with no added start/end fades or silence.
Apply +6 dB gain and encode stereo Vorbis at quality 5 / 44.1 kHz.

The game modulates volume and pitch from actual spooled engine power, adds
gain for afterburner and filters cockpit playback. Jet audio fades away in
missile view, after a crash, or when switching to the helicopter. Settings →
Flight has a persisted engine-volume control. Playback pauses with flight.
