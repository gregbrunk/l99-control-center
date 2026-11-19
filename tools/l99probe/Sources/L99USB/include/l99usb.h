// Direct USB access to the L99 screen's CDC bulk endpoints, bypassing macOS's serial
// driver (research/ISP_PROTOCOL.md, "Mac tests"). Capturing the device from the
// kernel driver needs root. One device at a time; not thread-safe.
#ifndef L99USB_H
#define L99USB_H
#include <stdint.h>

/// Opens VID:PID. With capture=1, detaches the kernel CDC driver first (root only).
/// Sends SET_LINE_CODING 115200 8N1 and SET_CONTROL_LINE_STATE 0 like Windows did.
/// Returns 0 on success; on failure writes a message into err.
int l99usb_open(uint16_t vid, uint16_t pid, int capture, char *err, int errlen);
/// Writes exactly len bytes as one bulk OUT transfer. 0 on success.
int l99usb_write(const uint8_t *buf, uint32_t len, uint32_t timeout_ms);
/// One bulk IN transfer of up to cap bytes. Returns bytes read, 0 on timeout, -1 on error.
int l99usb_read(uint8_t *buf, uint32_t cap, uint32_t timeout_ms);
/// Closes, and if the device was captured, hands it back to macOS.
void l99usb_close(void);
/// One-line description of what was opened (interfaces, pipes, control request results).
void l99usb_describe(char *buf, int len);
/// Last IOReturn, for messages.
int32_t l99usb_last_error(void);
#endif
