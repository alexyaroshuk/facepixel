# Face Detection + Pixelation App - Development Plan

**Project:** Real-time face detection and pixelation using Flutter + OpenCV
**Timeline:** 3-4 days
**Platforms:** iOS & Android
**Goal:** Portfolio project demonstrating mobile + real-time CV skills

---

## Overview

Build a Flutter app that:
- Captures live camera feed
- Detects faces in real-time using OpenCV
- Pixelates detected faces
- Toggles pixelation on/off
- Adjustable pixelation level (slider)

---

## Technical Architecture

### Flutter Layer
- Camera plugin for video stream
- UI for controls (toggle, pixelation level slider)
- Display live camera preview with overlays

### Native Layer (Platform Channels)
**Android (Kotlin):**
- Receive camera frames from Flutter
- Use OpenCV to detect faces (Haar Cascade classifier)
- Apply pixelation to detected regions
- Return processed frame to Flutter

**iOS (Swift):**
- Same logic as Android
- OpenCV via CocoaPods

### Core Components
- **Face Detection:** OpenCV Haar Cascade (pre-trained)
- **Pixelation:** Resize ROI down then up (blur effect) or mosaic pattern
- **Performance:** Process every Nth frame to maintain FPS

---

## Development Breakdown

### Day 1: Setup & Android Foundation
**Tasks:**
1. Create Flutter project with camera plugin
2. Set up Kotlin + OpenCV integration via platform channels
3. Implement basic camera frame capture → native layer flow
4. Basic Haar Cascade face detection (no pixelation yet)
5. Return detected face coordinates to Flutter
6. Display detected faces as boxes on preview

**Deliverable:** App shows faces detected with green boxes

### Day 2: Pixelation & Optimization
**Tasks:**
1. Implement pixelation algorithm on detected face regions
2. Add toggle (on/off pixelation)
3. Add slider for pixelation level (coarse → fine)
4. Optimize frame processing (skip frames if needed)
5. Test performance (FPS, heat)
6. iOS setup parallel with Android

**Deliverable:** Pixelation working, adjustable, real-time on both platforms

### Day 3: Polish & Testing
**Tasks:**
1. UI refinement (buttons, sliders, labels)
2. Performance profiling and optimization
3. Test on physical devices (Android + iOS)
4. Edge cases (multiple faces, poor lighting, etc.)
5. Add screenshot/record capability
6. Documentation

**Deliverable:** Production-ready app, tested on real devices

### Day 4 (Buffer): Final touches
- Bug fixes if needed
- Performance tweaks
- Build APK and TestFlight releases

---

## Key Technical Details

### Face Detection (Haar Cascade)
```
1. Load pre-trained cascade: haarcascade_frontalface_alt.xml (built into OpenCV)
2. Convert frame to grayscale
3. Detect faces: cascadeClassifier.detectMultiScale(frame)
4. Returns: array of face rectangles (x, y, width, height)
```

### Pixelation Algorithm
**Option A (Simple - Resize):**
```
1. Extract ROI (face region)
2. Resize down to 10x10 pixels
3. Resize back up to original size
→ Creates pixelated/blurry effect
```

**Option B (Mosaic):**
```
1. Divide ROI into 10x10 blocks
2. Average color of each block
3. Fill block with average color
→ Creates mosaic effect
```

Use Option A (simpler, faster).

### Performance Optimization
- Process every 2nd or 3rd frame (skip for speed)
- Process at 480p instead of full resolution
- Run on background thread (not UI thread)
- Recycle frame buffers

---

## Deliverables

### App Features
✓ Live camera feed (front-facing preferred)
✓ Real-time face detection
✓ Pixelation toggle (on/off)
✓ Pixelation level slider (1-100)
✓ FPS counter (optional, for debugging)
✓ Screenshot button

### Files Delivered
- Source code on GitHub (public repo)
- APK file (Android)
- TestFlight build link (iOS)
- README with usage instructions
- Performance notes (FPS, device tested)

### Portfolio
- GitHub repo demonstrating:
  - Platform channels (Kotlin + Swift + Flutter)
  - OpenCV integration
  - Real-time mobile CV
  - Camera integration
  - Performance optimization

---

## Tools & Dependencies

**Flutter:**
- `camera` plugin
- `image` package (for frame processing)

**Android (Kotlin):**
- OpenCV Android SDK (via gradle)
- Platform channels for Flutter communication

**iOS (Swift):**
- OpenCV via CocoaPods
- Platform channels for Flutter communication

---

## Claude Code Integration Points

Claude Code can help with:
1. Boilerplate platform channel setup (MethodChannel)
2. Kotlin/Swift native code generation
3. OpenCV face detection code
4. Pixelation algorithm implementation
5. Flutter UI components

---

## Risk & Contingency

**Potential Issues:**
- Face detection not working in poor lighting → use face alignment pre-processing
- Performance lag → reduce frame resolution or skip more frames
- iOS build taking long → start early
- Camera permissions → handle in Flutter

**Mitigation:**
- Start with Android, parallelize iOS
- Use Claude Code to accelerate boilerplate
- Test on real devices daily
- Buffer day built into timeline

---

## Success Criteria

✓ App runs on both Android and iOS
✓ Detects faces in real-time (visible with ~200ms latency max)
✓ Pixelation toggle works
✓ Pixelation level slider adjusts effect visibly
✓ Maintains 20+ FPS on mid-range devices
✓ No crashes or memory leaks
✓ Clean, readable code
✓ GitHub repo with documentation

---

## Timeline Summary

| Day | Focus | Deliverable |
|-----|-------|------------|
| 1 | Android setup + face detection | Boxes around faces |
| 2 | Pixelation + iOS + optimization | Full feature working |
| 3 | Polish + testing | Production app |
| 4 | Buffer/fixes | Ready to deploy |

---

## Next Steps

1. Create Flutter project
2. Set up camera plugin
3. Start with Android platform channels + OpenCV
4. Begin Day 1 tasks
5. Use Claude Code for native code generation

