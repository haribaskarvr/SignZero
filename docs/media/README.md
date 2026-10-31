# Landing page recordings

The landing page (`docs/index.html`) shows built-in animated illustrations of each step. Put a real screen recording
here and the page plays it instead, with no code change:

| File | Replaces |
|---|---|
| `sign.mp4` | The hero animation and step 2, *Sign* (the signing page) |
| `send.mp4` | Step 1, *Send* (the Send for Signature action on a record) |
| `seal.mp4` | Step 3, *Sealed* (the completed envelope, certificate and audit trail) |

`.webm` and `.gif` work too; the page looks for `.mp4`, then `.webm`, then `.gif`.

Tips:

- Prefer MP4 over GIF: it is a fraction of the size and sharper. Aim for under 5 MB and 10 to 15 seconds.
- Record at a 16:11 ratio (for example 1280 × 880) so it fills the frame without cropping.
- Use a scratch org with sample data only; recordings are public once pushed.
- To convert a recording: `ffmpeg -i in.mov -vf "scale=1280:-2,fps=30" -c:v libx264 -crf 26 -pix_fmt yuv420p -an -movflags +faststart sign.mp4`
