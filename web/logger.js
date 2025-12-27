/**
 * Professional JavaScript logging utility
 * Logs are only shown in debug builds (when debugging is enabled)
 */

// Check if we're in debug mode
const DEBUG_MODE = typeof window !== 'undefined' &&
                   (window.location.hostname === 'localhost' ||
                    window.location.hostname === '127.0.0.1' ||
                    localStorage.getItem('DEBUG_MODE') === 'true');

const AppLogger = {
  /**
   * Log info message
   */
  info: function(message, tag = '') {
    if (DEBUG_MODE) {
      const tagStr = tag ? ` [${tag}]` : '';
      console.log(`[App]${tagStr}: ${message}`);
    }
  },

  /**
   * Log error message
   */
  error: function(message, tag = '', error = null) {
    if (DEBUG_MODE) {
      const tagStr = tag ? ` [${tag}]` : '';
      console.error(`[App]${tagStr} ERROR: ${message}`);
      if (error) {
        console.error('  Exception:', error);
        if (error.stack) {
          console.error('  Stack:', error.stack);
        }
      }
    }
  },

  /**
   * Log warning message
   */
  warning: function(message, tag = '') {
    if (DEBUG_MODE) {
      const tagStr = tag ? ` [${tag}]` : '';
      console.warn(`[App]${tagStr} WARNING: ${message}`);
    }
  },

  /**
   * Log debug message
   */
  debug: function(message, tag = '') {
    if (DEBUG_MODE) {
      const tagStr = tag ? ` [${tag}]` : '';
      console.log(`[App]${tagStr} DEBUG: ${message}`);
    }
  }
};
