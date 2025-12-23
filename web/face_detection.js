/**
 * MediaPipe Face Detection for Web (NEW TASKS-VISION API)
 * Official implementation matching https://codepen.io/mediapipe-preview/pen/OJByWQr
 */

let FaceDetector = null;
let FilesetResolver = null;
let faceDetector = null;
let isDetectorReady = false;
let videoElement = null;
let detectionLoop = null;
let onFacesDetectedCallback = null;
let lastVideoTime = -1;
let frameCounter = 0;

// Pixelation state
let pixelationCanvas = null;
let pixelationCtx = null;
let detectedFaces = [];
let pixelationEnabled = false;
let pixelationLevel = 10;

// Blur overlay state
let blurOverlayContainer = null;
let blurOverlays = [];

console.log('[FaceDetection] Script loaded. Loading MediaPipe library as ES module...');

/**
 * Load MediaPipe library dynamically as ES module
 */
async function loadMediaPipeLibrary() {
  console.log('[FaceDetection] Dynamically importing @mediapipe/tasks-vision...');

  try {
    const vision = await import('https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@latest/vision_bundle.js');
    console.log('[FaceDetection] ES module imported:', vision);

    FaceDetector = vision.FaceDetector;
    FilesetResolver = vision.FilesetResolver;

    if (!FaceDetector || !FilesetResolver) {
      throw new Error('FaceDetector or FilesetResolver not exported from module');
    }

    console.log('[FaceDetection] MediaPipe library loaded successfully!');
    return true;
  } catch (error) {
    console.error('[FaceDetection] Failed to load MediaPipe library:', error);
    throw error;
  }
}

/**
 * Initialize MediaPipe Face Detection using the new tasks-vision API
 */
async function initializeFaceDetection() {
  console.log('[FaceDetection] ===== INIT START =====');
  console.log('[FaceDetection] Initializing MediaPipe Face Detection (NEW API)...');

  try {
    // Step 0: Load library
    console.log('[FaceDetection] Step 0: Loading MediaPipe library...');
    await loadMediaPipeLibrary();

    if (!FaceDetector || !FilesetResolver) {
      throw new Error('MediaPipe library not loaded! FaceDetector or FilesetResolver is undefined');
    }

    console.log('[FaceDetection] Loading vision task files...');
    const vision = await FilesetResolver.forVisionTasks(
      "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision/wasm"
    );
    console.log('[FaceDetection] Vision tasks loaded');

    console.log('[FaceDetection] Creating FaceDetector...');
    faceDetector = await FaceDetector.createFromOptions(vision, {
      baseOptions: {
        modelAssetPath: `https://storage.googleapis.com/mediapipe-models/face_detector/blaze_face_short_range/float16/1/blaze_face_short_range.tflite`,
        delegate: "GPU"  // Use GPU acceleration
      },
      runningMode: "VIDEO",  // VIDEO mode for live camera feed
      minDetectionConfidence: 0.5,  // Detection confidence threshold
      minSuppressionThreshold: 0.3   // Non-maximum suppression threshold
    });
    console.log('[FaceDetection] FaceDetector created successfully');

    isDetectorReady = true;
    console.log('[FaceDetection] ===== INIT COMPLETE =====');
    return true;
  } catch (error) {
    console.error('[FaceDetection] ===== INIT FAILED =====');
    console.error('[FaceDetection] Initialization failed:', error);
    console.error('[FaceDetection] Error stack:', error.stack);
    return false;
  }
}

/**
 * Initialize camera and start detection
 */
async function initializeCamera() {
  console.log('[FaceDetection] ===== CAMERA INIT START =====');

  try {
    videoElement = document.getElementById('webcam');
    if (!videoElement) {
      throw new Error('Video element #webcam not found in DOM');
    }
    console.log('[FaceDetection] Video element found:', videoElement);

    console.log('[FaceDetection] Requesting camera access...');
    const stream = await navigator.mediaDevices.getUserMedia({
      video: { width: { ideal: 1280 }, height: { ideal: 720 } }
    });
    console.log('[FaceDetection] Camera access granted. Stream:', stream);

    videoElement.srcObject = stream;
    console.log('[FaceDetection] Stream assigned to video element');

    // Wait for video to be ready
    return new Promise((resolve) => {
      videoElement.onloadedmetadata = () => {
        console.log('[FaceDetection] Video metadata loaded');
        console.log('[FaceDetection] Video dimensions:', videoElement.videoWidth, 'x', videoElement.videoHeight);
        console.log('[FaceDetection] ===== CAMERA READY =====');
        resolve(true);
      };
    });
  } catch (error) {
    console.error('[FaceDetection] ===== CAMERA INIT FAILED =====');
    console.error('[FaceDetection] Camera error:', error);
    throw error;
  }
}

/**
 * Detection loop - runs on every animation frame
 */
async function detectFrame() {
  if (!detectionLoop || !faceDetector || !videoElement) {
    return;
  }

  // Only process if video is ready and has new frame
  if (videoElement.readyState < 2) {
    if (detectionLoop) {
      requestAnimationFrame(detectFrame);
    }
    return;
  }

  const currentTime = videoElement.currentTime;
  let faces = [];
  let shouldDispatchCallback = false;

  // Only detect if we have a new frame (avoid processing same frame twice)
  if (currentTime !== lastVideoTime) {
    lastVideoTime = currentTime;
    frameCounter++;
    shouldDispatchCallback = true;

    try {
      console.log('[FaceDetection] Running detection at time:', currentTime);

      // Run face detection using VIDEO mode
      const detections = faceDetector.detectForVideo(videoElement, performance.now());
      console.log('[FaceDetection] Detections:', detections);

      // Convert detections to our face format
      if (detections && detections.detections) {
        const videoNatWidth = videoElement.videoWidth;
        const videoNatHeight = videoElement.videoHeight;

        // Get the actual rendered dimensions
        let videoDisplayWidth = 0;
        let videoDisplayHeight = 0;

        // FIRST: Check if Flutter has provided override dimensions (most reliable)
        if (overrideDisplayWidth > 0 && overrideDisplayHeight > 0) {
          videoDisplayWidth = overrideDisplayWidth;
          videoDisplayHeight = overrideDisplayHeight;
        } else {
          // Try getBoundingClientRect first
          const rect = videoElement.getBoundingClientRect();
          if (rect.width > 0 && rect.height > 0) {
            videoDisplayWidth = Math.round(rect.width);
            videoDisplayHeight = Math.round(rect.height);
          } else {
            // Fallback: try parent container (for Flutter HtmlElementView compatibility)
            const parent = videoElement.parentElement;
            if (parent) {
              const parentRect = parent.getBoundingClientRect();
              if (parentRect.width > 0 && parentRect.height > 0) {
                videoDisplayWidth = Math.round(parentRect.width);
                videoDisplayHeight = Math.round(parentRect.height);
              }
            }
          }

          // If still 0, use window dimensions and maintain aspect ratio
          if (videoDisplayWidth === 0 || videoDisplayHeight === 0) {
            videoDisplayWidth = window.innerWidth;
            const containerAspectRatio = videoNatWidth / videoNatHeight;
            videoDisplayHeight = Math.round(videoDisplayWidth / containerAspectRatio);
          }
        }

        // Calculate scale ratio (displayed size / natural size)
        const scaleX = videoDisplayWidth / videoNatWidth;
        const scaleY = videoDisplayHeight / videoNatHeight;

        // Log dimensions every 30 frames (not every frame to reduce spam)
        if (frameCounter % 30 === 0) {
          console.log('[FaceDetection] Processing', detections.detections.length, 'faces');
          console.log('[FaceDetection] Natural resolution:', videoNatWidth, 'x', videoNatHeight);
          console.log('[FaceDetection] Display resolution:', videoDisplayWidth, 'x', videoDisplayHeight);
          console.log('[FaceDetection] Display rect:', { top: rect.top, left: rect.left, width: rect.width, height: rect.height });
          console.log('[FaceDetection] Scale:', scaleX, 'x', scaleY);
        }

        for (const detection of detections.detections) {
          const box = detection.boundingBox;

          // Store face in NATURAL coordinate space (not display space)
          // This matches what Flutter expects: face coordinates in natural video dimensions
          // Flutter will then scale them: face.left * scaleX where scaleX = canvasWidth / videoNatWidth
          const face = {
            x: Math.round(box.originX),  // Use natural coordinates, not scaled
            y: Math.round(box.originY),
            width: Math.round(box.width),
            height: Math.round(box.height)
          };

          // Apply horizontal flip for natural coordinates (video is mirrored with CSS rotateY)
          const flippedXNatural = videoNatWidth - (face.x + face.width);
          face.x = flippedXNatural;

          // Clamp to video natural bounds
          face.x = Math.max(0, Math.min(face.x, videoNatWidth));
          face.y = Math.max(0, Math.min(face.y, videoNatHeight));
          face.width = Math.max(0, Math.min(face.width, videoNatWidth - face.x));
          face.height = Math.max(0, Math.min(face.height, videoNatHeight - face.y));

          // Only include faces that are meaningfully visible (not mostly off-screen)
          // Skip if face is too small after clamping (less than 20x20 or off-screen)
          if (face.width > 20 && face.height > 20) {
            faces.push(face);
            console.log('[FaceDetection] Scaled face:', face);
          }
        }
      }
    } catch (error) {
      console.error('[FaceDetection] Detection error:', error);
      console.error('[FaceDetection] Error stack:', error.stack);
    }
  }

  // CRITICAL: Only update UI when we have processed a new frame
  // This prevents clearing boxes when the video frame hasn't changed
  if (shouldDispatchCallback && onFacesDetectedCallback) {
    if (faces.length === 0) {
      console.log('[FaceDetection] Calling callback with EMPTY faces array - should clear boxes');
    } else {
      console.log('[FaceDetection] Calling callback with', faces.length, 'detected faces');
    }
    onFacesDetectedCallback(faces);
  }

  // Continue loop
  if (detectionLoop) {
    requestAnimationFrame(detectFrame);
  }
}

/**
 * Stop face detection
 */
function stopFaceDetection() {
  console.log('[FaceDetection] Stopping face detection');
  detectionLoop = false;
  onFacesDetectedCallback = null;
  videoElement = null;
  lastVideoTime = -1;
}

/**
 * Check if face detection is ready
 * @returns {boolean}
 */
function isFaceDetectionReady() {
  return isDetectorReady;
}

/**
 * Get video dimensions
 * @param {string} videoElementId - ID of the video element
 * @returns {object} Width and height
 */
function getVideoDimensions(videoElementId) {
  const video = document.getElementById(videoElementId);
  if (video) {
    return {
      width: video.videoWidth,
      height: video.videoHeight
    };
  }
  return { width: 0, height: 0 };
}

/**
 * Update canvas display dimensions - called by Flutter to sync JS dimensions with Flutter layout
 * This ensures face detection boxes use the exact same dimensions as Flutter's layout calculation
 * @param {number} width - Canvas display width in pixels
 * @param {number} height - Canvas display height in pixels
 * @param {number} offsetX - Canvas X offset in pixels
 * @param {number} offsetY - Canvas Y offset in pixels
 */
let overrideDisplayWidth = 0;
let overrideDisplayHeight = 0;
let canvasOffsetX = 0;
let canvasOffsetY = 0;

function updateCanvasDimensions(width, height, offsetX, offsetY) {
  console.log('[FaceDetection] updateCanvasDimensions called:', width, 'x', height, 'offset:', offsetX, offsetY);
  overrideDisplayWidth = Math.round(width);
  overrideDisplayHeight = Math.round(height);
  canvasOffsetX = offsetX || 0;
  canvasOffsetY = offsetY || 0;
}

/**
 * Initialize pixelation canvas overlay
 */
function initializePixelationCanvas() {
  console.log('[FaceDetection] Initializing pixelation canvas...');

  pixelationCanvas = document.getElementById('pixelationCanvas');
  if (!pixelationCanvas) {
    console.error('[FaceDetection] Pixelation canvas not found!');
    return;
  }

  pixelationCtx = pixelationCanvas.getContext('2d');

  // Set canvas size to match window
  function resizeCanvas() {
    pixelationCanvas.width = window.innerWidth;
    pixelationCanvas.height = window.innerHeight;
  }

  resizeCanvas();
  window.addEventListener('resize', resizeCanvas);

  console.log('[FaceDetection] Pixelation canvas initialized');
}

/**
 * Initialize blur overlay container
 */
function initializeBlurOverlay() {
  console.log('[FaceDetection] Initializing blur overlay container...');

  // Create container for blur overlays
  blurOverlayContainer = document.createElement('div');
  blurOverlayContainer.id = 'blurOverlayContainer';
  blurOverlayContainer.style.position = 'fixed';
  blurOverlayContainer.style.top = '0';
  blurOverlayContainer.style.left = '0';
  blurOverlayContainer.style.width = '100%';
  blurOverlayContainer.style.height = '100%';
  blurOverlayContainer.style.pointerEvents = 'none';
  blurOverlayContainer.style.zIndex = '999';
  blurOverlayContainer.style.overflow = 'hidden'; // Clip children to prevent overflow
  document.body.appendChild(blurOverlayContainer);

  // Update blur overlay on window resize
  window.addEventListener('resize', () => {
    if (pixelationEnabled && detectedFaces.length > 0) {
      updateBlurOverlay();
    }
  });

  console.log('[FaceDetection] Blur overlay container initialized');
}

/**
 * Apply pixelation to a region of the canvas using video frame data
 * @param {number} screenX - X position in screen coordinates
 * @param {number} screenY - Y position in screen coordinates
 * @param {number} screenWidth - Width in screen coordinates
 * @param {number} screenHeight - Height in screen coordinates
 * @param {number} pixelSize - Pixelation block size
 */
function pixelateRegion(screenX, screenY, screenWidth, screenHeight, pixelSize) {
  if (!pixelationCtx || !videoElement || pixelSize <= 0) {
    return;
  }

  try {
    const videoRect = videoElement.getBoundingClientRect();
    const videoNatWidth = videoElement.videoWidth;
    const videoNatHeight = videoElement.videoHeight;
    const videoDisplayWidth = videoRect.width;
    const videoDisplayHeight = videoRect.height;

    // Calculate scale from natural video size to displayed size
    const scaleX = videoNatWidth / videoDisplayWidth;
    const scaleY = videoNatHeight / videoDisplayHeight;

    // Convert screen coordinates to video natural coordinates
    // First, convert to coordinates relative to video element
    const relativeX = screenX - videoRect.left;
    const relativeY = screenY - videoRect.top;

    // Clamp to video bounds
    const clampedX = Math.max(0, Math.min(relativeX, videoDisplayWidth));
    const clampedY = Math.max(0, Math.min(relativeY, videoDisplayHeight));
    const clampedWidth = Math.max(0, Math.min(screenWidth, videoDisplayWidth - clampedX));
    const clampedHeight = Math.max(0, Math.min(screenHeight, videoDisplayHeight - clampedY));

    if (clampedWidth <= 0 || clampedHeight <= 0) {
      return;
    }

    // Convert to natural video coordinates
    // Note: Since video is flipped horizontally with CSS, we need to flip the X coordinate
    const natX = Math.round((videoDisplayWidth - clampedX - clampedWidth) * scaleX);
    const natY = Math.round(clampedY * scaleY);
    const natWidth = Math.round(clampedWidth * scaleX);
    const natHeight = Math.round(clampedHeight * scaleY);

    // Create temporary canvas to extract and pixelate the face region
    const tempCanvas = document.createElement('canvas');
    tempCanvas.width = natWidth;
    tempCanvas.height = natHeight;
    const tempCtx = tempCanvas.getContext('2d');

    // Draw the face region from video (already flipped by CSS, so draw directly)
    tempCtx.drawImage(
      videoElement,
      natX, natY, natWidth, natHeight,
      0, 0, natWidth, natHeight
    );

    // Apply pixelation: resize down then up
    const blockSize = Math.max(2, Math.ceil(pixelSize));
    const smallWidth = Math.max(1, Math.floor(natWidth / blockSize));
    const smallHeight = Math.max(1, Math.floor(natHeight / blockSize));

    const smallCanvas = document.createElement('canvas');
    smallCanvas.width = smallWidth;
    smallCanvas.height = smallHeight;
    const smallCtx = smallCanvas.getContext('2d');

    // Draw scaled down (creates pixelation effect)
    smallCtx.imageSmoothingEnabled = false;
    smallCtx.drawImage(tempCanvas, 0, 0, smallWidth, smallHeight);

    // Draw pixelated region back to pixelation canvas at screen coordinates
    pixelationCtx.save();
    pixelationCtx.imageSmoothingEnabled = false; // Disable smoothing for crisp pixels
    pixelationCtx.drawImage(
      smallCanvas,
      0, 0, smallWidth, smallHeight,
      screenX, screenY, screenWidth, screenHeight
    );
    pixelationCtx.restore();
  } catch (error) {
    console.error('[FaceDetection] Error in pixelateRegion:', error);
  }
}

/**
 * Update pixelation overlay based on detected faces
 */
function updatePixelationOverlay() {
  if (!pixelationCtx || !pixelationEnabled || !videoElement) {
    // Clear canvas if pixelation is disabled
    if (pixelationCtx) {
      pixelationCtx.clearRect(0, 0, pixelationCanvas.width, pixelationCanvas.height);
    }
    return;
  }

  // Clear the canvas
  pixelationCtx.clearRect(0, 0, pixelationCanvas.width, pixelationCanvas.height);

  // Calculate video display dimensions
  const rect = videoElement.getBoundingClientRect();
  const videoDisplayWidth = Math.round(rect.width);
  const videoDisplayHeight = Math.round(rect.height);

  // Calculate pixel size from level (1-100)
  const pixelSize = Math.max(1, (pixelationLevel / 10) * 2);

  // Apply pixelation to each detected face
  for (const face of detectedFaces) {
    const faceX = rect.left + face.x;
    const faceY = rect.top + face.y;
    const faceWidth = face.width;
    const faceHeight = face.height;

    pixelateRegion(
      Math.round(faceX),
      Math.round(faceY),
      Math.round(faceWidth),
      Math.round(faceHeight),
      pixelSize
    );
  }
}

/**
 * Update blur overlay based on detected faces
 * Uses the same positioning calculation as Flutter to match face detection boxes exactly
 */
function updateBlurOverlay() {
  if (!blurOverlayContainer || !pixelationEnabled || !videoElement) {
    // Remove all blur overlays if disabled
    if (blurOverlayContainer) {
      blurOverlayContainer.innerHTML = '';
      blurOverlays = [];
    }
    return;
  }

  // Clear existing overlays
  blurOverlayContainer.innerHTML = '';
  blurOverlays = [];

  if (detectedFaces.length === 0) {
    return;
  }

  // Use Flutter-provided canvas dimensions and offset (same as face detection boxes)
  const canvasWidth = overrideDisplayWidth > 0 ? overrideDisplayWidth : 640;
  const canvasHeight = overrideDisplayHeight > 0 ? overrideDisplayHeight : 480;

  // Get video natural dimensions (Flutter's _videoSize - these are the natural video dimensions)
  const videoNatWidth = videoElement.videoWidth;
  const videoNatHeight = videoElement.videoHeight;

  if (videoNatWidth === 0 || videoNatHeight === 0) {
    return;
  }

  // Calculate scale factors EXACTLY like Flutter does:
  // scaleX = _canvasWidth / _videoSize.width
  // scaleY = _canvasHeight / _videoSize.height
  // where _videoSize is the natural video dimensions
  const scaleX = canvasWidth / videoNatWidth;
  const scaleY = canvasHeight / videoNatHeight;

  // Video bounds for clipping (canvas area)
  const videoLeft = canvasOffsetX;
  const videoTop = canvasOffsetY;
  const videoRight = canvasOffsetX + canvasWidth;
  const videoBottom = canvasOffsetY + canvasHeight;

  // Calculate blur amount from level (1-100)
  // Level 1 = minimal blur (0.5px), Level 100 = heavy blur (50px)
  const blurAmount = (pixelationLevel / 2).toFixed(1);

  // Create blur overlay for each detected face
  // Use the EXACT same positioning calculation as Flutter:
  // left: canvasOffset.dx + (face.left * scaleX)
  // top: canvasOffset.dy + (face.top * scaleY)
  // width: face.width * scaleX
  // height: face.height * scaleY
  // Note: face coordinates from JavaScript are in display space (640x480),
  // but Flutter treats them as natural dimensions and scales them
  // So we need to treat them the same way Flutter does
  for (const face of detectedFaces) {
    // Scale face coordinates EXACTLY like Flutter does
    // Flutter: face.left * scaleX where scaleX = _canvasWidth / _videoSize.width
    const scaledLeft = face.x * scaleX;
    const scaledTop = face.y * scaleY;
    const scaledWidth = face.width * scaleX;
    const scaledHeight = face.height * scaleY;

    // Add canvas offset (same as Flutter: canvasOffset.dx + scaledLeft)
    let faceX = canvasOffsetX + scaledLeft;
    let faceY = canvasOffsetY + scaledTop;
    let faceWidth = scaledWidth;
    let faceHeight = scaledHeight;

    // Clip to video bounds (same as detection boxes are clipped by Flutter Stack)
    // Clamp position and size to stay within video area
    if (faceX < videoLeft) {
      const diff = videoLeft - faceX;
      faceWidth = Math.max(0, faceWidth - diff);
      faceX = videoLeft;
    }
    if (faceY < videoTop) {
      const diff = videoTop - faceY;
      faceHeight = Math.max(0, faceHeight - diff);
      faceY = videoTop;
    }
    if (faceX + faceWidth > videoRight) {
      faceWidth = Math.max(0, videoRight - faceX);
    }
    if (faceY + faceHeight > videoBottom) {
      faceHeight = Math.max(0, videoBottom - faceY);
    }

    // Skip if clipped to zero size
    if (faceWidth <= 0 || faceHeight <= 0) {
      continue;
    }

    // Calculate border radius (15% of width, matching mobile implementation)
    const borderRadius = Math.min(faceWidth * 0.15, faceHeight * 0.15).toFixed(1);

    // Create blur overlay div
    const blurDiv = document.createElement('div');
    blurDiv.style.position = 'fixed';
    blurDiv.style.left = `${faceX}px`;
    blurDiv.style.top = `${faceY}px`;
    blurDiv.style.width = `${faceWidth}px`;
    blurDiv.style.height = `${faceHeight}px`;
    blurDiv.style.borderRadius = `${borderRadius}px`;
    blurDiv.style.backdropFilter = `blur(${blurAmount}px)`;
    blurDiv.style.webkitBackdropFilter = `blur(${blurAmount}px)`; // Safari support
    blurDiv.style.backgroundColor = 'transparent';
    blurDiv.style.pointerEvents = 'none';
    blurDiv.style.overflow = 'hidden';

    blurOverlayContainer.appendChild(blurDiv);
    blurOverlays.push(blurDiv);
  }

  console.log(`[FaceDetection] Updated blur overlay: ${blurOverlays.length} faces, blur: ${blurAmount}px, canvas: ${canvasWidth}x${canvasHeight} @ (${canvasOffsetX},${canvasOffsetY})`);
}

/**
 * Set pixelation settings from Flutter
 */
window.setPixelationSettings = function (enabled, level) {
  console.log('[FaceDetection] Setting pixelation:', enabled, 'level:', level);
  pixelationEnabled = enabled;
  pixelationLevel = Math.max(1, Math.min(100, level));
  // Immediately update the overlays if faces are already detected
  if (detectedFaces && detectedFaces.length > 0) {
    updatePixelationOverlay();
    updateBlurOverlay();
  }
};

/**
 * Main initialization sequence
 * This is called from Dart when the app is ready
 */
async function startApp() {
  console.log('[FaceDetection] ===== STARTUP SEQUENCE =====');

  try {
    // Step 0: Initialize pixelation canvas and blur overlay
    console.log('[FaceDetection] Step 0: Initializing pixelation canvas and blur overlay...');
    initializePixelationCanvas();
    initializeBlurOverlay();

    // Step 1: Initialize MediaPipe
    console.log('[FaceDetection] Step 1: Initializing MediaPipe...');
    const initSuccess = await initializeFaceDetection();
    if (!initSuccess) {
      throw new Error('MediaPipe initialization failed');
    }

    // Step 2: Initialize camera
    console.log('[FaceDetection] Step 2: Initializing camera...');
    await initializeCamera();

    // Step 3: Set up callback to dispatch events and update pixelation
    console.log('[FaceDetection] Step 3: Setting up callback...');
    onFacesDetectedCallback = (faces) => {
      // Store faces for pixelation overlay
      detectedFaces = faces;

      // Update pixelation overlay
      updatePixelationOverlay();

      // Update blur overlay
      updateBlurOverlay();

      if (faces.length === 0) {
        console.log('[FaceDetection] 🗑️ DISPATCHING EVENT WITH EMPTY ARRAY - boxes should clear');
      } else {
        console.log('[FaceDetection] Dispatching facesDetected event with', faces.length, 'faces');
      }
      const event = new CustomEvent('facesDetected', {
        detail: { faces: faces }
      });
      window.dispatchEvent(event);
    };

    // Step 4: Start detection loop
    console.log('[FaceDetection] Step 4: Starting detection loop...');
    detectionLoop = true;
    detectFrame();

    console.log('[FaceDetection] ===== STARTUP COMPLETE =====');
  } catch (error) {
    console.error('[FaceDetection] ===== STARTUP FAILED =====');
    console.error('[FaceDetection] Error:', error);
    console.error('[FaceDetection] Stack:', error.stack);
  }
}

// Wait for Dart to call startApp() when ready
console.log('[FaceDetection] Waiting for Dart to call startApp()...');
