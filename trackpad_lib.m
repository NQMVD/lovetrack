#include <CoreFoundation/CoreFoundation.h>
#include <math.h>
#include "trackpad_lib.h"

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

static TrackpadCallback g_callback = NULL;
static MTDeviceRef g_device = NULL;

int trackpad_callback(int device, Finger *data, int nFingers, double timestamp, int frame) {
    if (g_callback == NULL) {
        return 0;
    }

    TrackpadFinger fingers[nFingers];
    for (int i = 0; i < nFingers; i++) {
        Finger *f = &data[i];
        fingers[i] = (TrackpadFinger){
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
    }

    g_callback(nFingers, fingers);
    return 0;
}

void trackpad_start(TrackpadCallback callback) {
    if (g_device != NULL) {
        return;
    }
    g_callback = callback;

    CFMutableArrayRef* deviceList = MTDeviceCreateList();
    if (CFArrayGetCount((CFArrayRef)deviceList) > 0) {
        g_device = (MTDeviceRef)CFArrayGetValueAtIndex((CFArrayRef)deviceList, 0);
        MTRegisterContactFrameCallback(g_device, trackpad_callback);
        MTDeviceStart(g_device, 0);
    }
}

void trackpad_stop() {
    if (g_device != NULL) {
        MTDeviceStop(g_device);
        g_device = NULL;
        g_callback = NULL;
    }
}
