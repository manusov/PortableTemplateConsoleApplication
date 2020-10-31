// UNDER CONSTRUCTION
// PLATFORM SUPPORT HEADER, CLONE OF LINUX LSCPU UTILITY, WITH X86 DETAILS
// See primary project LSCPU86 for some modules and comments, deleted here.

#define CPUID_TAG 0        // ID code for CPUID entry in the dump table
#define RDTSC_TAG 1        // ID code for RDTSC entry in the dump table
#define XCR0_TAG 2         // ID code for XCR0 entry in the dump table
#define BINARY_ENTRY 32    // Entry size in the dump table is 32 bytes

int asmCpuid(char* buffer, int countmax);    // Get CPUID data
int asmRdtsc(char* buffer);                  // Measure TSC clock frequency
int asmXcr0(char* buffer);                   // Get CPU context control bitmaps

#include "platform.c"
