# Slitscan Found Image Lab

A desktop app for making experimental slitscan images from two loaded source images.

The main version is a native macOS app built from Objective-C++/C++ with a live Metal shader preview. A Python/Tk version is also included as a lightweight fallback.

## Native GPU App

```bash
./build_native.sh
open "build/Slitscan Found Image Lab.app"
```

## Random Tokyo Street View

The native app can load two random open Tokyo images without a key using Wikimedia Commons. Use `Random Open Tokyo Pair` in the app.

It can also load two random Google Street View images from Tokyo. Paste a Google Street View Static API key into the app, or launch with:

```bash
GOOGLE_STREET_VIEW_API_KEY="your-key" open "build/Slitscan Found Image Lab.app"
```

## Python Fallback

```bash
./run.sh
```

## What It Does

- Load two images at a time.
- Build a new image by taking moving slit samples from both sources.
- Switch between vertical, horizontal, diagonal, radial, wave, and torn-strip modes.
- Tune slit width, drift, blend, wave amount, phase, grain, and color shift.
- Export the current result as PNG or JPEG.
