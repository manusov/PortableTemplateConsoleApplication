// UNDER CONSTRUCTION
// PLATFORM SUPPORT MODULE, CLONE OF LINUX LSCPU UTILITY, WITH X86 DETAILS
// See primary project LSCPU86 for some modules and comments, deleted here.

// Get CPUID dump to destination buffer, countmax bytes is size limit
int getCpuid(char* buffer, int countmax)
    {
    return asmCpuid(buffer, countmax);
    }

// Get CPU TSC clock info to destination buffer
int getRdtsc(char* buffer)
    {
    return asmRdtsc(buffer);
    }

// Get CPU and OS context management info to destination buffer
int getXcr0(char* buffer)
    {
    return asmXcr0(buffer);
    }

// Build CPUID/TSC/Context data dump,
// from binary source buffer (binSrc) to text destination buffer (txtDst)
#define NUMBERS_PER_LINE 7
static char* dumpUp[] = 
    { "Function", "Sub-fnc", "Pass", "EAX", "EBX", "ECX", "EDX" };
#define LINE 70

// Table horizontal line
int tabLine(char** p)
    {
    int i;
    for(i=0; i<LINE; i++)
        {
        snprintf(*p, 2, "-");
        (*p)++;
        }
    snprintf(*p, 2, "\n");
    (*p)++;
    }

// Build dump of received binary data
void buildDump(char *binSrc, char *txtDst, size_t binMax, size_t txtMax)
    {
    // initializing local variables
    int i;
    unsigned int data;
    char* ptrb = binSrc;
    unsigned int* ptrint = NULL;
    char* ptrt = txtDst;
    char* maxb = binSrc + binMax;                  // limit for binary pointer
    char* maxt = txtDst + txtMax - LINE - 2;       // limit for text pointer
                                                   // +2 means "\n\0"
    // print horizontal line, up of table up
    if((ptrb >= maxb)|(ptrt >= maxt))  { *ptrt = 0; return; }
    tabLine(&ptrt);
    // print names of table columns
    if((ptrb >= maxb)|(ptrt >= maxt))  { *ptrt = 0; return; }
    for(i=0; i<NUMBERS_PER_LINE; i++)
        {
        ptrt += snprintf( ptrt, 11, "%-10s", dumpUp[i] );
        }
    ptrt += snprintf(ptrt, 2, "\n");
    // print horizontal line, middle
    if((ptrb >= maxb)|(ptrt >= maxt))  { *ptrt = 0; return; }
    tabLine(&ptrt);
    // print dump
    while( ! ((ptrb >= maxb)|(ptrt >= maxt)))
        {
        ptrint = (unsigned int*)ptrb;
        data = *ptrint++;
        if (data != CPUID_TAG) break;
        for(i=0; i<NUMBERS_PER_LINE; i++)
            {
            data = *ptrint++;
            ptrt += snprintf(ptrt, 11, "%08X  ", data);
            }
        ptrt += snprintf(ptrt, 2, "\n"); 
        ptrb += BINARY_ENTRY;
        }
    // print horizontal line, down of table content
    if(ptrt >= maxt)  { *ptrt = 0; return; }
    tabLine(&ptrt);
    *ptrt = 0;
    }

// Build CPU clock information
void buildClk(char *binSrc, char *txtDst, size_t binMax, size_t txtMax)
    {
    // initializing local variables
    unsigned int data;
    double mhz;
    char* ptrb = binSrc;
    unsigned int* ptrint = NULL;
    unsigned long long* ptrlong = NULL;
    char* ptrt = txtDst;
    char* maxb = binSrc + binMax;                  // limit for binary pointer
    char* maxt = txtDst + txtMax - LINE - 2;       // limit for text pointer
    // search for TSC frequency entry
    while (ptrb < maxb)
        {
        ptrint = (unsigned int*)ptrb;
        ptrlong = (unsigned long long*)(ptrb+24);
        data = *ptrint;
        if (data==RDTSC_TAG)
            {
            mhz = *ptrlong;
            mhz /= 1000000.0;
            ptrt += snprintf(ptrt, LINE, "CPU TSC = %.3f MHz\n", mhz);
            }
        ptrb += BINARY_ENTRY;
        }
    *ptrt = 0;
    }

// Build CPU context management information
void buildXcr(char *binSrc, char *txtDst, size_t binMax, size_t txtMax)
    {
    // initializing local variables
    unsigned int data1, data2;
    char* ptrb = binSrc;
    unsigned int* ptrint = NULL;
    char* ptrt = txtDst;
    char* maxb = binSrc + binMax;                  // limit for binary pointer
    char* maxt = txtDst + txtMax - LINE - 2;       // limit for text pointer
    // search for XCR0 bitmaps entry
    while (ptrb < maxb)
        {
        ptrint = (unsigned int*)ptrb;
        data1 = *ptrint;
        ptrint += 4;
        if (data1 == XCR0_TAG)
            {
            data1 = *ptrint++;
            data2 = *ptrint++;
            ptrt += snprintf
                ( ptrt, LINE, "CPU context mask = %08X%08Xh\n", data2, data1 );
            data1 = *ptrint++;
            data2 = *ptrint++;
            ptrt += snprintf
                ( ptrt, LINE, "OS context mask  = %08X%08Xh\n", data2, data1 );
            }
        ptrb += BINARY_ENTRY;
        }
    *ptrt = 0;
    }
