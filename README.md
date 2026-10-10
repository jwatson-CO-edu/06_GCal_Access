# GCal Access

Flutter (Linux desktop) tool: pick a Markdown note, click an open `- [ ]` task, and
schedule it as a Google Calendar appointment.

Setup: follow `keys/KEY.md` to put your OAuth client JSON in `keys/`, then `flutter run -d linux`
from the project root (the app looks for `./keys`, or set `GCAL_KEYS_DIR`).

See `BUILD.md` to produce a distributable Linux build (`make dist`).
