// UNDER CONSTRUCTION
// CLONE OF LINUX LSCPU UTILITY, WITH X86 DETAILS
// THIS IS TEMPORARY PART: LSDUMP86
// See primary project LSCPU86 for some modules and comments, deleted here.

// Standard definitions and headers
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <malloc.h>
#include <string.h>
#include <errno.h>
#include <time.h>
#include <ctype.h>
#include <unistd.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <linux/fs.h>
#include <sys/mman.h>

// Platform support header, cpuid, cpuclk, xcr0 wrappers
#include "platform.h"

// Title and version strings
// static char info1[] = "Processor information utility. LSCPU clone.\n";
// OS-specific string: utility name with build description
#ifdef __i386__
static char info1[] = "CPU information dump utility (ia32 build).\n";
#else
#ifdef __x86_64__
static char info1[] = "CPU information dump utility (x64 build).\n";
#else
static char info1[] = "CPU information dump utility (Incompatible build).\n";
#endif
#endif
// End of OS-specific string
static char info2[] = "(C)2017 IC Book Labs.\n";
static char info3[] = "Version 0.01.\n";
static char* info[] = { info1, info2, info3, NULL };

// Command line help strings
static char help1[] = "Command line options:\n";
static char help2[] = " -h (help)      : print this help\n";
static char help3[] = " -v (version)   : print vendor and version info\n";
static char help4[] = " -i inputfile   : use binary file instead platform\n";
static char help5[] = " -o outputfile  : save platform data to binary file\n";
// - debug version limitations -
static char help6[] = " -t outputfile  : save report to text file\n";
// static char help7[] = " -f hexnumber   : selected function only instead full\n";
static char help8[] = " -c (clock)     : print TSC clock frequency\n";
static char help9[] = " -x (xcr0)      : print CPU/OS context options\n";
static char* help[] = { info1, 
                        help1, help2, help3, help4, help5,
                        // help6, help7, help8, help9, 
                        help6, help8, help9, 
                        NULL };

// Help strings used if command line options error
static char* errorHelp[] = { help1, help2, help3, help4, help5,
                             // help6, help7, help8, help9, 
                             help6, help8, help9, 
                             NULL };

// Options parsing and execution control
// -h  help, without parameter string
// -v  version and about
// -i  input binary file, system state dump, ":" means parameter = file name
// -o  output binary file, system state dump, ":" means parameter = file name
// -t  output text file, report, ":" means parameter = file name
// -f  cpuid function hex number, ":" means parameter = function hex number
// -c  clock measurement
// -x  xcr0 state management bitmap
// default all details f+c+x
#define NUMOPT 6
static int(*routines[NUMOPT])(char*);     // handler definition
static char* parms[NUMOPT];               // array of additional parms. strings
static int fastReturn;                    // this for version and help options
static int errorCommand;                  // command line error flag
static enum { HELP, VERSION, INBIN, OUTBIN, OUTTEXT, FUNCTION } OPTIONS;
static char optstring[] = "vhi:o:t:f:cx";   // command line parsing control

// Binary data addressing and sizing
#define MAX_BINARY 65536  // maximum size of binary data for memory allocation
// #define BINARY_ENTRY 32  // moved to platform.h
#define MAX_ENTRIES 512
static char *baseBinary = NULL, *pointerBinary = NULL;
static size_t sizeBinary = 0;

// Text data addressing and sizing
#define MAX_TEXT 1048576  // maximum size of text data for memory allocation
#define MAX_PART 102400   // maximum size of text data per function
#define MAX_STRING 133    // maximum string output length, with last zero
#define MAX_STRING_CR  MAX_STRING + 1  // plus "\n" char
static char *basePart = NULL, *pointerPart = NULL;
static size_t sizePart = 0;

// Text report mode file save support
static FILE *pReport = NULL;

// Load file by path, data and byte count, use linux-specific API
int fileLoad(char* path, char* buffer, int count)
    {
    // dynamical variables
    int fileDesc;
    int fileStatus;
    ssize_t fileReturn;
    size_t fileTotal = 0;
    // open file with status check and conditional exit 
    fileDesc = open(path, O_RDONLY);
    if (fileDesc < 0)
        {
        printf( "%s: %s ( %s )\n", 
            "Error open file", path, strerror(errno) );
        return fileDesc;
        }
    // read file with status check and conditional exit
    while(fileTotal < count)
        {
        fileReturn = read(fileDesc, buffer, count);
        if (fileReturn<0)
            {
            printf( "%s: %s ( %s )\n", 
                "Error read file", path, strerror(errno) );
            close(fileDesc);
            return fileReturn;
            }
        if (fileReturn==0)
            {
            break;
            }
        fileTotal += fileReturn;
        }
    // close file with status check
    fileStatus = close(fileDesc);
    if (fileStatus < 0)
        {
        printf( "%s: %s ( %s )\n", 
            "Error close file", path, strerror(errno) );
        return fileDesc;
        }
    return fileTotal;
    }

// Save file by path, data and byte count, use linux-specific API
int fileSave(char* path, char* buffer, int count)
    {
    // dynamical variables
    int fileDesc;
    int fileStatus;
    ssize_t fileReturn;
    size_t fileTotal = 0;
    // open(create) file with status check and conditional exit
    fileDesc = open(path, O_CREAT|O_RDWR, S_IRWXU|S_IRWXG|S_IRWXO);
    if (fileDesc < 0)
        {
        printf( "%s: %s ( %s )\n", 
            "Error open file", path, strerror(errno) );
        return fileDesc;
        }
    // write file with status check and conditional exit
    while(fileTotal < count)
        {
        fileReturn = write(fileDesc, buffer, count);
        if (fileReturn<0)
            {
            printf( "%s: %s ( %s )\n", 
                "Error write file", path, strerror(errno) );
            close(fileDesc);
            return fileReturn;
            }
        fileTotal += fileReturn;
        }
    // close file with status check
    fileStatus = close(fileDesc);
    if (fileStatus < 0)
        {
        printf( "%s: %s ( %s )\n", 
            "Error close file", path, strerror(errno) );
        return fileDesc;
        }
    return fileTotal;
    }

// Empty handler for disable optional functionality
int handlerEmpty(char* parm)
    {
    return 0;
    }

// Handler visual about and version
int handlerVersion(char* parm)
    {
    int i;
    for(i=0; info[i] != NULL; i++)
        {
        (*routines[OUTTEXT])(info[i]);
        }
    }

// Handler visual help
int handlerHelp(char* parm)
    {
    int i;
    for(i=0; help[i] != NULL; i++)
        {
        (*routines[OUTTEXT])(help[i]);
        }
    }

// Handler visual help for command line error
int handlerErrorHelp(char* parm)
    {
    int i;
    for(i=0; errorHelp[i] != NULL; i++)
        {
        (*routines[OUTTEXT])(errorHelp[i]);
        }
    }

// Handler get cpuid and other system information from current platform
int handlerInPlatform(char* parm)
    {
    // first message for platform mode
    (*routines[OUTTEXT])("Get platform data...\n");    // Handler console/file
    int retCpuid = 0, retRdtsc = 0, retXcr0 = 0;
    char sup[] = "supported";
    char nsup[] = "not supported";
    char err[] = "error";
    char *s1 = nsup, *s2 = nsup;
    char temp[MAX_STRING];
    // cpuid
    retCpuid = getCpuid(pointerBinary, MAX_BINARY);
    if (retCpuid <= 0)
        {
        snprintf(temp, MAX_BINARY, "CPUID not supported or locked\n");
        }
    else if (retCpuid > MAX_ENTRIES)
        {
        snprintf(temp, MAX_BINARY, "CPUID functions count too big\n");
        }
    else
        {
        pointerBinary += retCpuid * BINARY_ENTRY;
        // rdtsc
        retRdtsc = getRdtsc(pointerBinary);
        // analysing status, default pointers "not supported"
        if      (retRdtsc > 0) { s1 = sup; pointerBinary += BINARY_ENTRY; }
        else if (retRdtsc < 0) s1 = err;
        // xcr0
        retXcr0 = getXcr0(pointerBinary);
        // analysing status, default pointers "not supported"
        if      (retXcr0 > 0)  { s2 = sup; pointerBinary += BINARY_ENTRY; }
        else if (retXcr0 < 0)  s2 = err;
        // print
        snprintf(temp, MAX_BINARY, 
                 "%s%d%s%s%s%s\n",
                 "CPUID functions supported: ", retCpuid,
                 ", TSC ", s1,
                 ", XCR0 control ", s2 );
        }
    // summary string
    (*routines[OUTTEXT])(temp);   // Handler console/file
    }

// Handler get cpuid and other system information from input binary file
int handlerInBin(char* parm)
    {
    // first message for platform mode, prepare and output
    char temp[MAX_STRING];
    int result;
    snprintf( temp, MAX_STRING, "Read %s ...\n", parms[INBIN] );
    (*routines[OUTTEXT])(temp);    // Handler console/file
    result = fileLoad(parms[INBIN], pointerBinary, MAX_BINARY);
    if (result<0) return result;
    snprintf(temp, MAX_STRING, "%d bytes\n", result);
    (*routines[OUTTEXT])(temp);    // Handler console/file
    if (result%32 != 0)
        {
        (*routines[OUTTEXT])("Binary size error, must be 32-byte blocks\n");
        return result;
        }
    pointerBinary += result;
    }

// Handler save cpuid and other system information to output binary file
int handlerOutBin(char* parm)
    {
    // first message for platform mode, prepare and output
    char temp[MAX_STRING];
    int result;
    int size;
    snprintf( temp, MAX_STRING, "Write %s ...\n", parms[OUTBIN] );
    (*routines[OUTTEXT])(temp);    // Handler console/file
    size = pointerBinary - baseBinary;
    snprintf(temp, MAX_STRING, "%d bytes\n", size);
    (*routines[OUTTEXT])(temp);    // Handler console/file
    result = fileSave(parms[OUTBIN], baseBinary, size);
    return result;
    }

// One string write handler for report output mode is console
int handlerOutConsole(char* parm)
    {
    char scratch[MAX_STRING_CR];
    char* temp;
    char c;
    int i;
    // start cycle for separate output strings, divided by "\n"
    // prevent single meta-string with some "\n" divided strings
    while(*parm != 0)             // char 0 interpreted as end of sequence
        {                         // cycle for separate printf for each string
        temp = scratch;
        for(i=0; i<MAX_STRING; i++)
            {                     // cycle for chars at one string
            c = *parm++;
            *temp++ = c;
            if (c=='\n') break;   // char "\n" interpreted as next printf()
            }
        *temp++ = 0;
        printf("%s", scratch);
        }
    }

// One string write handler for report output mode is text file
int handlerOutText(char* parm)
    {
    if ( pReport != NULL )
        {
        char scratch[MAX_STRING_CR];
        char* temp;
        char c;
        int i;
        // start cycle for separate output strings, divided by "\n"
        // prevent single meta-string with some "\n" divided strings
        while(*parm != 0)         // char 0 interpreted as end of sequence
            {                     // cycle for separate printf for each string
            temp = scratch;
            for(i=0; i<MAX_STRING; i++)
                {                     // cycle for chars at one string
                c = *parm++;
                *temp++ = c;
                if (c=='\n') break;   // char "\n" interpreted as next printf()
                }
            *temp++ = 0;
            fprintf( pReport, "%s", scratch );
            }
        }
    }

// Handler for report all mode
// baseBinary  = pointer to platform binary data, result of CPUID/RDTSC/XCR0
// pointerPart = pointer to transit buffer for build text report fragments
// sizeBinary  = size of platform binary data, result of CPUID/RDTSC/XCR0
// sizePart    = size of transit buffer for build text report fragments
int handlerAll(char* parm)
    {
    buildDump(baseBinary, pointerPart, sizeBinary, sizePart);
    (*routines[OUTTEXT])(pointerPart);   // Handler console/file
    // ... UNDER CONSTRUCTION ... DEBUG ... MAKE CYCLE ...
    }

// Handler for selective report, selected cpuid function only
int handlerFunction(char* parm)
    {
    // UNDER CONSTRUCTION.
    }

// Handler for selective report, cpu clock frequency only
int handlerClock(char* parm)
    {
    buildClk(baseBinary, pointerPart, sizeBinary, sizePart);
    (*routines[OUTTEXT])(pointerPart);   // Handler console/file
    }

// Handler for selective report, xcr0 cpu context management info only
int handlerXcr(char* parm)
    {
    buildXcr(baseBinary, pointerPart, sizeBinary, sizePart);
    (*routines[OUTTEXT])(pointerPart);   // Handler console/file
    }

// Application entry point
int main(int argc, char** argv)
{
// Initializing default configuration
    routines[HELP]     = handlerEmpty;
    routines[VERSION]  = handlerEmpty;
    routines[INBIN]    = handlerInPlatform;
    routines[OUTBIN]   = handlerEmpty;
    routines[OUTTEXT]  = handlerOutConsole;
    routines[FUNCTION] = handlerAll;
    int i;
    for (i=0; i<NUMOPT; i++)
        {
        parms[i] = NULL;
        }
// Parse command line, detect options
    int c=0;           // option selector char
    fastReturn = 0;    // this for skip main part if version or help options
    errorCommand = 0;  // command line error flag
// parse cycle
    while ((c = getopt(argc, argv, optstring)) != -1)
    switch (c)
        {
        case 'h':   // help option, set handler for print help
            routines[HELP] = handlerHelp;
            fastReturn = 1;
            break;
        case 'v':   // version option, set handler for print version and about
            routines[VERSION] = handlerVersion;
            fastReturn = 1;
            break;
        case 'i':   // input binary file option, set handler and path
            routines[INBIN] = handlerInBin;
            parms[INBIN] = optarg;
            break;
        case 'o':   // output binary file option, set handler and path
            routines[OUTBIN] = handlerOutBin;
            parms[OUTBIN] = optarg;
            break;
        case 't':   // output report file option, set handler and path 
            routines[OUTTEXT] = handlerOutText;
            parms[OUTTEXT] = optarg;
            pReport = fopen( parms[OUTTEXT], "w" );
            break;
        case 'c':   // function option, clock measurement only mode
            routines[FUNCTION] = handlerClock;
            break;
        case 'x':   // function option, xcr status only mode
            routines[FUNCTION] = handlerXcr;
            break;
        case '?':   // this for unknown option
        case ':':   // this for missing parameter but known option
        default:
            routines[HELP] = handlerErrorHelp;
            errorCommand = 1;
            break;
        }
   
// Check options compatibility
// UNDER CONSTRUCTION.
    
// Support version if option "-v" was detected
    (*routines[VERSION])(parms[VERSION]);
    
// Support help if option "-h" was detected
    (*routines[HELP])(parms[HELP]);

// Check for fast return and command line error(s)
    if(fastReturn==1) return 0;
    if(errorCommand==1) return 1;
    
// Allocate buffer for binary data, get binary data
    baseBinary = malloc(MAX_BINARY);
    if (baseBinary == NULL)
        {
        printf( "\n%s: ( %s )\n", 
            "MEMORY ALLOCATION ERROR", strerror(errno) );
        return 1;
        }
    pointerBinary = baseBinary;
    (*routines[INBIN])(parms[INBIN]);  // can be platform or binary file
    
// Allocate buffer for transit text data per function, part of entire report
    basePart = malloc(MAX_PART);
    if (basePart == NULL)
        {
        printf( "\n%s: ( %s )\n", 
            "MEMORY ALLOCATION ERROR", strerror(errno) );
        free(baseBinary); baseBinary = NULL; pointerBinary = NULL;
        return 1;
        }
    pointerPart = basePart;
    sizeBinary = pointerBinary - baseBinary;
    sizePart = MAX_PART;
    
// Interpreting binary data (platform or file), build text report
    (*routines[FUNCTION])(parms[FUNCTION]);
    
// Save binary data to output binary file
    (*routines[OUTBIN])(parms[OUTBIN]);
    
// Release buffers
    free(basePart);  basePart = NULL;   pointerPart = NULL;    
    free(baseBinary); baseBinary = NULL; pointerBinary = NULL;
    
// Close report file if exist
    if ( pReport != NULL )
        {
        fclose(pReport);
        }

// Exit    
    return 0;
}

