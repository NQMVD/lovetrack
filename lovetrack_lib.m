#include <CoreFoundation/CoreFoundation.h>
#include <pthread.h>
#include <string.h>
#include <math.h>
#include "lovetrack_lib.h"

#define MAX_FINGERS 20

// Private MultitouchSupport framework structs and functions
typedef struct { float x,y; } mtPoint;
typedef struct { mtPoint pos,vel; } mtReadout;

typedef struct {
  int frame;
  double timestamp;
  int identifier, state, foo3, foo4;
  mtReadout normalized;
  float size;
  int zero1;
  float angle, majorAxis, minorAxis;
  mtReadout mm;
  int zero2[2];
  float unk2;
} Finger;

typedef void *MTDeviceRef;
typedef int (*MTContactCallbackFunction)(int,Finger*,int,double,int);
CFMutableArrayRef * MTDeviceCreateList();
void MTRegisterContactFrameCallback(MTDeviceRef, MTContactCallbackFunction);
void MTDeviceStart(MTDeviceRef, int);
void MTDeviceStop(MTDeviceRef);

// Globals for thread-safe data exchange
static MTDeviceRef g_device = NULL;
static pthread_mutex_t g_mutex;
static int g_finger_count = 0;
static TrackpadFinger g_finger_buffer[MAX_FINGERS];

// The internal callback that runs on the MT thread
int internal_callback(int device, Finger *data, int nFingers, double timestamp, int frame) {
    pthread_mutex_lock(&g_mutex);
    g_finger_count = nFingers > MAX_FINGERS ? MAX_FINGERS : nFingers;
    for (int i = 0; i < g_finger_count; i++) {
        Finger *f = &data[i];
        g_finger_buffer[i] = (TrackpadFinger){
            .id = f->identifier,
            .x = f->normalized.pos.x,
            .y = f->normalized.pos.y,
            .vx = f->normalized.vel.x,
            .vy = f->normalized.vel.y,
            .angle = f->angle * 90 / atan2(1,0),
            .major_axis = f->majorAxis,
            .minor_axis = f->minorAxis,
            .size = f->size,
            .state = f->state
        };
        g_finger_buffer[i].y = 1.0 - g_finger_buffer[i].y; // Invert Y coordinate
        g_finger_buffer[i].vy = 0.0 - g_finger_buffer[i].vy; // Invert Y coordinate
    }
    pthread_mutex_unlock(&g_mutex);
    return 0;
}

// Public API functions
int trackpad_start() {
    if (g_device != NULL) {
        return 0; // Already started
    }

    if (pthread_mutex_init(&g_mutex, NULL) != 0) {
        return -1; // Mutex init failed
    }

    CFMutableArrayRef* deviceList = MTDeviceCreateList();
    if (deviceList && CFArrayGetCount((CFArrayRef)deviceList) > 0) {
        g_device = (MTDeviceRef)CFArrayGetValueAtIndex((CFArrayRef)deviceList, 0);
        MTRegisterContactFrameCallback(g_device, internal_callback);
        MTDeviceStart(g_device, 0);
        return 0; // Success
    }
    return -1; // No device found
}

int trackpad_poll(TrackpadFinger* fingers, int max_fingers) {
    if (g_device == NULL) {
        return 0;
    }
    pthread_mutex_lock(&g_mutex);
    int count = g_finger_count < max_fingers ? g_finger_count : max_fingers;
    if (count > 0) {
        memcpy(fingers, g_finger_buffer, count * sizeof(TrackpadFinger));
    }
    pthread_mutex_unlock(&g_mutex);
    return count;
}

void trackpad_reset(TrackpadFinger* fingers, int max_fingers) {
    if (g_device == NULL) {
        return;
    }
    pthread_mutex_lock(&g_mutex);
    // reset the finger count and buffer
    g_finger_count = 0;
    memset(g_finger_buffer, 0, sizeof(g_finger_buffer));
    int count = g_finger_count < max_fingers ? g_finger_count : max_fingers;
    if (count > 0) {
        memcpy(fingers, g_finger_buffer, count * sizeof(TrackpadFinger));
    }
    pthread_mutex_unlock(&g_mutex);
    return;
}

void trackpad_stop() {
    if (g_device != NULL) {
        MTDeviceStop(g_device);
        pthread_mutex_destroy(&g_mutex);
        g_device = NULL;
    }
}
