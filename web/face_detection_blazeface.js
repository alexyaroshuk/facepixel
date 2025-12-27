/**
 * TensorFlow.js BlazeFace Face Detection for Web
 * Alternative to MediaPipe with potentially better performance
 */

// Logger utility required to be loaded before this script

let blazeFaceModel = null;
let isDetectorReady = false;
let videoElement = null;
let detectionLoop = null;
let onFacesDetectedCallback = null;

/**
 * Initialize BlazeFace Face Detection
 */
async function initializeFaceDetection() {
  AppLogger.info('Initializing BlazeFace', 'web');

  try {
    // Load BlazeFace model
    // returnTensors: false for better performance
    // maxFaces: 10 to detect multiple faces
    blazeFaceModel = await blazeface.load({
      maxFaces: 10,
      iouThreshold: 0.3,  // Lower = more overlapping detections allowed
      scoreThreshold: 0.5  // Confidence threshold (0-1)
    });

    isDetectorReady = true;
    AppLogger.info('BlazeFace initialized', 'web');
    return true;
  } catch (error) {
    AppLogger.error('BlazeFace initialization failed', 'web', error);
    return false;
  }
}

/**
 * Start face detection on a video element
 * @param {string} videoElementId - ID of the video element
 * @param {string} callbackName - Name of the global callback function (optional)
 */
function startFaceDetection(videoElementId, callbackName) {
  AppLogger.info(`Starting face detection on video: ${videoElementId}`, 'web');

  videoElement = document.getElementById(videoElementId);
  if (!videoElement) {
    AppLogger.error(`Video element not found: ${videoElementId}`, 'web');
    return false;
  }

  // Set callback - either use named function or dispatch event
  if (callbackName && window[callbackName]) {
    onFacesDetectedCallback = window[callbackName];
  } else {
    // Use custom event for callback
    onFacesDetectedCallback = (faces) => {
      const event = new CustomEvent('facesDetected', {
        detail: { faces: faces }
      });
      window.dispatchEvent(event);
    };
  }

  // Start detection loop (throttled to ~30 FPS)
  const detectFrame = async () => {
    if (blazeFaceModel && videoElement && videoElement.readyState >= 2) {
      try {
        // Run face detection
        const predictions = await blazeFaceModel.estimateFaces(videoElement, false);

        // Convert predictions to our face format
        const faces = [];
        const width = videoElement.videoWidth;
        const height = videoElement.videoHeight;

        for (const prediction of predictions) {
          // BlazeFace returns topLeft and bottomRight coordinates
          const topLeft = prediction.topLeft;
          const bottomRight = prediction.bottomRight;

          const face = {
            x: Math.round(topLeft[0]),
            y: Math.round(topLeft[1]),
            width: Math.round(bottomRight[0] - topLeft[0]),
            height: Math.round(bottomRight[1] - topLeft[1])
          };

          // Clamp to video bounds
          face.x = Math.max(0, Math.min(face.x, width));
          face.y = Math.max(0, Math.min(face.y, height));
          face.width = Math.max(0, Math.min(face.width, width - face.x));
          face.height = Math.max(0, Math.min(face.height, height - face.y));

          faces.push(face);
        }

        // Call callback with detected faces
        if (onFacesDetectedCallback) {
          onFacesDetectedCallback(faces);
        }
      } catch (error) {
        AppLogger.error('Detection error', 'web', error);
      }
    }

    // Continue loop
    if (detectionLoop) {
      setTimeout(() => requestAnimationFrame(detectFrame), 33); // ~30 FPS
    }
  };

  detectionLoop = true;
  detectFrame();

  AppLogger.debug('Detection loop started', 'web');
  return true;
}

/**
 * Stop face detection
 */
function stopFaceDetection() {
  AppLogger.info('Stopping face detection', 'web');
  detectionLoop = false;
  onFacesDetectedCallback = null;
  videoElement = null;
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

// Auto-initialize when the script loads
if (typeof blazeface !== 'undefined') {
  initializeFaceDetection().then(() => {
    AppLogger.info('BlazeFace ready for use', 'web');
  });
} else {
  AppLogger.error('BlazeFace library not loaded', 'web');
}
