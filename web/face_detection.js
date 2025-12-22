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
  console.log('[FaceDetection] detectFrame called');

  if (!detectionLoop || !faceDetector || !videoElement) {
    console.log('[FaceDetection] detectFrame early return:', { detectionLoop, hasFaceDetector: !!faceDetector, hasVideoElement: !!videoElement });
    return;
  }

  // Only process if video is ready and has new frame
  if (videoElement.readyState < 2) {
    console.log('[FaceDetection] Video not ready, readyState:', videoElement.readyState);
    if (detectionLoop) {
      requestAnimationFrame(detectFrame);
    }
    return;
  }

  const currentTime = videoElement.currentTime;

  // Only detect if we have a new frame (avoid processing same frame twice)
  if (currentTime !== lastVideoTime) {
    lastVideoTime = currentTime;

    try {
      console.log('[FaceDetection] Running detection at time:', currentTime);

      // Run face detection using VIDEO mode
      const detections = faceDetector.detectForVideo(videoElement, performance.now());
      console.log('[FaceDetection] Detections:', detections);

      // Convert detections to our face format
      const faces = [];
      if (detections && detections.detections) {
        const videoNatWidth = videoElement.videoWidth;
        const videoNatHeight = videoElement.videoHeight;

        // Get the actual rendered dimensions
        let videoDisplayWidth = 0;
        let videoDisplayHeight = 0;

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

        // Calculate scale ratio (displayed size / natural size)
        const scaleX = videoDisplayWidth / videoNatWidth;
        const scaleY = videoDisplayHeight / videoNatHeight;

        console.log('[FaceDetection] Processing', detections.detections.length, 'faces');
        console.log('[FaceDetection] Natural resolution:', videoNatWidth, 'x', videoNatHeight);
        console.log('[FaceDetection] Display resolution:', videoDisplayWidth, 'x', videoDisplayHeight);
        console.log('[FaceDetection] Scale:', scaleX, 'x', scaleY);

        for (const detection of detections.detections) {
          const box = detection.boundingBox;

          // First, scale the bounding box to match the displayed video size
          const scaledOriginX = box.originX * scaleX;
          const scaledOriginY = box.originY * scaleY;
          const scaledWidth = box.width * scaleX;
          const scaledHeight = box.height * scaleY;

          // Then apply horizontal flip (the video is mirrored with CSS rotateY)
          const flippedX = videoDisplayWidth - (scaledOriginX + scaledWidth);

          const face = {
            x: Math.round(flippedX),
            y: Math.round(scaledOriginY),
            width: Math.round(scaledWidth),
            height: Math.round(scaledHeight)
          };

          // Clamp to video bounds
          face.x = Math.max(0, Math.min(face.x, videoDisplayWidth));
          face.y = Math.max(0, Math.min(face.y, videoDisplayHeight));
          face.width = Math.max(0, Math.min(face.width, videoDisplayWidth - face.x));
          face.height = Math.max(0, Math.min(face.height, videoDisplayHeight - face.y));

          faces.push(face);
          console.log('[FaceDetection] Scaled face:', face);
        }
      }

      // Call callback with detected faces
      if (onFacesDetectedCallback) {
        onFacesDetectedCallback(faces);
      }
    } catch (error) {
      console.error('[FaceDetection] Detection error:', error);
      console.error('[FaceDetection] Error stack:', error.stack);
    }
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
 * Main initialization sequence
 * This is called from Dart when the app is ready
 */
async function startApp() {
  console.log('[FaceDetection] ===== STARTUP SEQUENCE =====');

  try {
    // Step 1: Initialize MediaPipe
    console.log('[FaceDetection] Step 1: Initializing MediaPipe...');
    const initSuccess = await initializeFaceDetection();
    if (!initSuccess) {
      throw new Error('MediaPipe initialization failed');
    }

    // Step 2: Initialize camera
    console.log('[FaceDetection] Step 2: Initializing camera...');
    await initializeCamera();

    // Step 3: Set up callback to dispatch events
    console.log('[FaceDetection] Step 3: Setting up callback...');
    onFacesDetectedCallback = (faces) => {
      console.log('[FaceDetection] Dispatching facesDetected event with', faces.length, 'faces');
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
