#ifndef lovetrack_lib_h
#define lovetrack_lib_h

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

// Starts the trackpad listening service.
// Returns 0 on success, -1 on failure.
int trackpad_start();

// Polls for the latest trackpad data.
// `fingers` should be a pointer to an array of TrackpadFinger structs.
// `max_fingers` is the maximum number of fingers the array can hold.
// Returns the number of fingers currently on the trackpad.
int trackpad_poll(TrackpadFinger* fingers, int max_fingers);

// Reset the trackpad state.
void trackpad_reset(TrackpadFinger* fingers, int max_fingers);

// Stops the trackpad listening service.
void trackpad_stop();

#endif /* trackpad_lib_h */
