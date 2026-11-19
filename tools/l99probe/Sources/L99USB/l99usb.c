#include "l99usb.h"
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <unistd.h>
#include <pthread.h>
#include <string.h>
#include <time.h>
#include <errno.h>

typedef IOUSBDeviceInterface320 **Dev;
typedef IOUSBInterfaceInterface300 **Intf;

static Dev dev = NULL;
static Intf data = NULL;
static UInt8 pipeOut = 0, pipeIn = 0;
static int captured = 0;
static IOReturn last = kIOReturnSuccess;
static int commNum = -1, dataNum = -1; static UInt8 cfgVal = 0; static IOReturn lcResult = 0, lsResult = 0;
static UInt8 epOut = 0, epIn = 0;

// Like Windows' usbser and macOS's CDC driver, keep a bulk IN read posted at all times
// (the capture shows Windows' IN request pending before the first OUT).
static pthread_t reader;
static int readerRunning = 0, readerStop = 0, readerError = 0;
static pthread_mutex_t mu = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t cv = PTHREAD_COND_INITIALIZER;
static uint8_t ring[65536];
static uint32_t ringHead = 0, ringLen = 0;

static uint8_t inBuf[64];
static CFRunLoopRef readerLoop = NULL;

static void postRead(void);

static void readDone(void *refcon, IOReturn result, void *arg0) {
    (void)refcon;
    UInt32 size = (UInt32)(uintptr_t)arg0;
    pthread_mutex_lock(&mu);
    if (result != kIOReturnSuccess) {
        if (!readerStop) { readerError = result; last = result; }
        pthread_cond_broadcast(&cv);
        pthread_mutex_unlock(&mu);
        CFRunLoopStop(CFRunLoopGetCurrent());
        return;
    }
    for (UInt32 k = 0; k < size && ringLen < sizeof ring; k++) ring[(ringHead + ringLen++) % sizeof ring] = inBuf[k];
    pthread_cond_broadcast(&cv);
    int stop = readerStop;
    pthread_mutex_unlock(&mu);
    if (!stop) postRead();
}

static void postRead(void) {
    IOReturn r = (*data)->ReadPipeAsync(data, pipeIn, inBuf, sizeof inBuf, readDone, NULL);
    if (r != kIOReturnSuccess) {
        pthread_mutex_lock(&mu); readerError = r; last = r; pthread_cond_broadcast(&cv); pthread_mutex_unlock(&mu);
        CFRunLoopStop(CFRunLoopGetCurrent());
    }
}

static void *readLoop(void *arg) {
    (void)arg;
    CFRunLoopSourceRef src = NULL;
    if ((*data)->CreateInterfaceAsyncEventSource(data, &src) != kIOReturnSuccess || !src) {
        pthread_mutex_lock(&mu); readerError = kIOReturnError; pthread_cond_broadcast(&cv); pthread_mutex_unlock(&mu);
        return NULL;
    }
    readerLoop = CFRunLoopGetCurrent();
    CFRunLoopAddSource(readerLoop, src, kCFRunLoopDefaultMode);
    postRead();
    CFRunLoopRun();
    CFRunLoopRemoveSource(readerLoop, src, kCFRunLoopDefaultMode);
    readerLoop = NULL;
    return NULL;
}

int32_t l99usb_last_error(void) { return last; }

static io_service_t find(uint16_t vid, uint16_t pid) {
    CFMutableDictionaryRef m = IOServiceMatching("IOUSBHostDevice");
    int v = vid, p = pid;
    CFNumberRef nv = CFNumberCreate(NULL, kCFNumberIntType, &v), np = CFNumberCreate(NULL, kCFNumberIntType, &p);
    CFDictionarySetValue(m, CFSTR("idVendor"), nv);
    CFDictionarySetValue(m, CFSTR("idProduct"), np);
    CFRelease(nv); CFRelease(np);
    return IOServiceGetMatchingService(kIOMainPortDefault, m);   // consumes m
}

static Dev makeDev(io_service_t s) {
    IOCFPlugInInterface **plug = NULL; SInt32 score = 0; Dev d = NULL;
    last = IOCreatePlugInInterfaceForService(s, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plug, &score);
    if (last != kIOReturnSuccess || !plug) return NULL;
    (*plug)->QueryInterface(plug, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID320), (LPVOID *)&d);
    IODestroyPlugInInterface(plug);
    return d;
}

static int fail(char *err, int n, const char *what) {
    snprintf(err, n, "%s (IOReturn 0x%08x)", what, last);
    l99usb_close();
    return -1;
}

static IOReturn control(UInt8 req, UInt16 value, UInt16 index, void *buf, UInt16 len) {
    IOUSBDevRequestTO r = {0};
    r.bmRequestType = 0x21; r.bRequest = req; r.wValue = value; r.wIndex = index; r.wLength = len;
    r.pData = buf; r.noDataTimeout = 1000; r.completionTimeout = 1000;
    return (*dev)->DeviceRequestTO(dev, &r);
}

int l99usb_open(uint16_t vid, uint16_t pid, int capture, char *err, int errlen) {
    io_service_t s = find(vid, pid);
    if (!s) { last = kIOReturnNoDevice; return fail(err, errlen, "Screen USB device not found"); }
    if (capture) {
        Dev d = makeDev(s);
        IOObjectRelease(s);
        if (!d) return fail(err, errlen, "Could not create the USB device interface");
        last = (*d)->USBDeviceReEnumerate(d, kUSBReEnumerateCaptureDeviceMask);
        (*d)->Release(d);
        if (last != kIOReturnSuccess) return fail(err, errlen, "Could not take the screen from macOS's serial driver (run with sudo)");
        captured = 1;
        s = 0;
        for (int i = 0; i < 50 && !s; i++) { usleep(100000); s = find(vid, pid); }
        if (!s) { last = kIOReturnNoDevice; return fail(err, errlen, "The screen did not come back after capture"); }
        usleep(300000);
    }
    dev = makeDev(s);
    IOObjectRelease(s);
    if (!dev) return fail(err, errlen, "Could not create the USB device interface");
    last = (*dev)->USBDeviceOpenSeize(dev);
    if (last != kIOReturnSuccess) return fail(err, errlen, "Could not open the screen's USB device (busy? run with sudo)");

    UInt8 config = 0;
    (*dev)->GetConfiguration(dev, &config);
    cfgVal = config;
    if (config == 0) {
        IOUSBConfigurationDescriptorPtr cd = NULL;
        last = (*dev)->GetConfigurationDescriptorPtr(dev, 0, &cd);
        if (last != kIOReturnSuccess) return fail(err, errlen, "No configuration descriptor");
        last = (*dev)->SetConfiguration(dev, cd->bConfigurationValue);
        if (last != kIOReturnSuccess) return fail(err, errlen, "SetConfiguration failed");
    }

    IOUSBFindInterfaceRequest q = { kIOUSBFindInterfaceDontCare, kIOUSBFindInterfaceDontCare,
                                    kIOUSBFindInterfaceDontCare, kIOUSBFindInterfaceDontCare };
    io_iterator_t it = 0;
    last = (*dev)->CreateInterfaceIterator(dev, &q, &it);
    if (last != kIOReturnSuccess) return fail(err, errlen, "Could not list the USB interfaces");
    int commIndex = -1;
    io_service_t is;
    while ((is = IOIteratorNext(it))) {
        IOCFPlugInInterface **plug = NULL; SInt32 score = 0; Intf i = NULL;
        if (IOCreatePlugInInterfaceForService(is, kIOUSBInterfaceUserClientTypeID, kIOCFPlugInInterfaceID, &plug, &score) == kIOReturnSuccess && plug) {
            (*plug)->QueryInterface(plug, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID300), (LPVOID *)&i);
            IODestroyPlugInInterface(plug);
        }
        IOObjectRelease(is);
        if (!i) continue;
        UInt8 cls = 0, num = 0;
        (*i)->GetInterfaceClass(i, &cls);
        (*i)->GetInterfaceNumber(i, &num);
        if (cls == 0x02) commIndex = num;
        if (cls == 0x0A && !data) { data = i; dataNum = num; continue; }
        (*i)->Release(i);
    }
    IOObjectRelease(it);
    if (!data) { last = kIOReturnNotFound; return fail(err, errlen, "No CDC data interface found"); }
    last = (*data)->USBInterfaceOpen(data);
    if (last != kIOReturnSuccess) return fail(err, errlen, "Could not open the CDC data interface (still held by macOS? run with sudo)");

    UInt8 n = 0;
    (*data)->GetNumEndpoints(data, &n);
    for (UInt8 p = 1; p <= n; p++) {
        UInt8 dir, number, type, interval; UInt16 maxPacket;
        if ((*data)->GetPipeProperties(data, p, &dir, &number, &type, &maxPacket, &interval) != kIOReturnSuccess) continue;
        if (type != kUSBBulk) continue;
        if (dir == kUSBOut && !pipeOut) { pipeOut = p; epOut = number; }
        if (dir == kUSBIn && !pipeIn) { pipeIn = p; epIn = 0x80 | number; }
    }
    if (!pipeOut || !pipeIn) { last = kIOReturnNotFound; return fail(err, errlen, "Bulk endpoints not found"); }

    // Same control requests Windows sent in the capture: 115200 8N1, DTR/RTS low.
    if (commIndex >= 0) {
        UInt8 lc[7] = { 0x00, 0xC2, 0x01, 0x00, 0, 0, 8 };
        lcResult = control(0x20, 0, (UInt16)commIndex, lc, 7);
        lsResult = control(0x22, 0, (UInt16)commIndex, NULL, 0);
    }
    commNum = commIndex;
    readerStop = 0; readerError = 0; ringHead = ringLen = 0;
    if (pthread_create(&reader, NULL, readLoop, NULL) == 0) readerRunning = 1;
    usleep(50000);
    return 0;
}

void l99usb_describe(char *buf, int len) {
    snprintf(buf, len, "config %u, comm if %d, data if %d, OUT ep 0x%02x (pipe %u), IN ep 0x%02x (pipe %u), line coding 0x%08x, line state 0x%08x, captured %d",
             cfgVal, commNum, dataNum, epOut, pipeOut, epIn, pipeIn, lcResult, lsResult, captured);
}

int l99usb_write(const uint8_t *buf, uint32_t len, uint32_t timeout_ms) {
    if (!data) return -1;
    last = (*data)->WritePipeTO(data, pipeOut, (void *)buf, len, timeout_ms, timeout_ms);
    return last == kIOReturnSuccess ? 0 : -1;
}

int l99usb_read(uint8_t *buf, uint32_t cap, uint32_t timeout_ms) {
    if (!data || !readerRunning) return -1;
    struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts);
    ts.tv_sec += timeout_ms / 1000; ts.tv_nsec += (long)(timeout_ms % 1000) * 1000000L;
    if (ts.tv_nsec >= 1000000000L) { ts.tv_sec++; ts.tv_nsec -= 1000000000L; }
    pthread_mutex_lock(&mu);
    while (ringLen == 0 && !readerError) {
        if (pthread_cond_timedwait(&cv, &mu, &ts) == ETIMEDOUT) break;
    }
    int n = 0;
    while (ringLen > 0 && (uint32_t)n < cap) { buf[n++] = ring[ringHead]; ringHead = (ringHead + 1) % sizeof ring; ringLen--; }
    int err = readerError;
    pthread_mutex_unlock(&mu);
    if (n == 0 && err) return -1;
    return n;
}

void l99usb_close(void) {
    if (readerRunning) {
        pthread_mutex_lock(&mu); readerStop = 1; pthread_mutex_unlock(&mu);
        if (data) (*data)->AbortPipe(data, pipeIn);   // completes the pending read; its callback stops the loop
        usleep(100000);
        if (readerLoop) CFRunLoopStop(readerLoop);
        pthread_join(reader, NULL);
        readerRunning = 0;
    }
    if (data) { (*data)->USBInterfaceClose(data); (*data)->Release(data); data = NULL; }
    if (dev) {
        if (captured) (*dev)->USBDeviceReEnumerate(dev, kUSBReEnumerateReleaseDeviceMask);
        (*dev)->USBDeviceClose(dev); (*dev)->Release(dev); dev = NULL;
    }
    pipeOut = pipeIn = 0; captured = 0;
}
