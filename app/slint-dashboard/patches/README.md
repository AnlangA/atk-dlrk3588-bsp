# Slint LinuxKMS GPU scanout patch

The production application uses Mali GPU rendering only: LinuxKMS, FemtoVG,
OpenGL ES and GBM. It does not select a software renderer or LinuxFB fallback.

`vendor/i-slint-backend-linuxkms` is the published Slint 1.17.1 backend crate
with `0001-gbm-negotiate-scanout-modifiers.patch` applied. Original source and
licenses are retained. Upstream crate archive SHA-256:
`68e76f2b13846ca54bba6b8eb3b5454b26879ad987396d0a2d8abedc31a6c469`.

The original GBM backend allocates without consulting the selected primary
plane's IN_FORMATS property. On this board that plane advertises AFBC modifiers.
The patch parses that property, selects the compatible primary plane using its
possible CRTC mask, and passes the advertised modifiers to GBM. It logs the
selected output, primary plane, resulting framebuffer modifier and pitch.
There are no hard-coded DRM card, CRTC or plane IDs.

The parser uses bounds-checked native-endian reads of the DRM UAPI structure.
Tests cover format-specific modifier masks and malformed/truncated blobs.

The earlier software-renderer pitch experiment is no longer part of this
application patch. Headless unit tests use Slint's software window only to test
UI input logic; the production binary and hardware validation use the GPU.

The patch is prepared locally and has not been submitted upstream.
