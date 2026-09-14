# Contributing

Bug reports and pull requests are welcome.

For sensor or capture issues, include the macOS version, Mac model identifier,
app version, and steps to reproduce. Use the generated sample preview when a
screenshot is enough; do not include private desktop content, signing keys,
or account credentials.

## Local development

Open `Package.swift` in Xcode, or use Swift Package Manager:

```sh
swift build
swift test
swift run -c release MacDuo --render-check
```

The renderer checks use a generated desktop and do not request screen-recording
access. They need a Metal-capable Mac. Full-screen capture and physical lid
behavior require testing on a compatible MacBook.

Use `scripts/build-app.sh` and your own Apple Development identity when testing
the packaged app. Keep the identity and app path stable across updates. Do not
check generated builds or signing material into Git.

Preserve these rendering invariants:

- Screenshot pixels stay in their original coordinates; only the mask changes shape.
- The mask's bottom endpoints remain at the hinge corners.
- The final overlay is opaque, with a black background and soft edges.
- The initial frame matches the captured desktop, and cleanup releases the capture.

Keep changes focused and describe how you verified them. Contributions are
provided under the project's [MIT license](LICENSE).
