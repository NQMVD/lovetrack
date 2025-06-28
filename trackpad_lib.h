#ifndef trackpad_lib_h
#define trackpad_lib_h

// A struct to hold the data for a single touch point.
typedef struct {
    int id;
    float x, y;      // Normalized position
    float vx, vy;    // Normalized velocity
    float angle;
    float major_axis, minor_axis;
    float size;
    int state;
} TrackpadFinger;

// The callback function that will be invoked with trackpad data.
// It receives an array of TrackpadFinger structs and the number of fingers.
typedef void (*TrackpadCallback)(int nFingers, const TrackpadFinger* fingers);

// Starts the trackpad listening service.
// You must provide a callback function to receive the data.
void trackpad_start(TrackpadCallback callback);

// Stops the trackpad listening service.
void trackpad_stop();

#endif /* trackpad_lib_h */
