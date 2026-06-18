#include <stddef.h>

// Intercept MOTAdaptor::Init() - return immediately (success = 0)
int _ZN10MOTAdaptor4InitEv(void) {
    return 0;
}

// Intercept InitMOT()
void _Z7InitMOTv(void) {
    // no-op
}

// Intercept MOT::AllocThreadId() - always return 0 (success, first ID)
// The ARM64 NUMA bug causes the ThreadIdPool bitmap to initialize with ALL bits
// set to "in use", so AllocThreadId() always fails.  We short-circuit it.
unsigned int _ZN3MOT13AllocThreadIdEv(void) {
    return 0;
}

// Intercept MOT::FreeThreadId() - no-op
void _ZN3MOT12FreeThreadIdEv(void) {
    // no-op
}

// Intercept MOT::DumpThreadIds(const char*)
void _ZN3MOT13DumpThreadIdsEPKc(void) {
    // no-op
}
