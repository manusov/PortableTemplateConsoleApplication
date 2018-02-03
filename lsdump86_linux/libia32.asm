;========== Platform support library: CPUID/RDTSC/XCR0 for Linux 32. ==========;

SYS_READ         = 0      ; Linux API functions (syscall numbers)
SYS_WRITE        = 1
SYS_OPEN         = 2
SYS_CLOSE        = 3
SYS_LSEEK        = 8
SYS_MMAP         = 9
SYS_MUNMAP       = 11
SYS_NANOSLEEP    = 35
SYS_EXIT         = 60
SYS_UNLINK       = 87
SYS_GETTIME      = 228
SYS_GETRES       = 229
SYS_SETAFFINITY  = 203
SYS_GETAFFINITY  = 204
SYS_SETMEMPOLICY = 238    ; Note alternative codes
SYS_GETMEMPOLICY = 239    ; Note alternative codes

format ELF

public asmCpuid as 'asmCpuid'
public asmRdtsc as 'asmRdtsc'
public asmXcr0  as 'asmXcr0'

ENTRIES_LIMIT = 512    ; Maximum number of output buffer 16384 bytes = 512*32

;---------- Public entry point ------------------------------------------------;
;---------- Get CPUID binary data ---------------------------------------------;
; Parm#1 = DWORD [esp+04] = Pointer to buffer for dump data                    ;
; Parm#2 = DWORD [esp+08] = Size limit, not used yet                           ;
; Output = EAX = Number of output entries or special value                     ;
;               0 means CPUID not supported                                    ;
;              -1 means CPUID get information error                            ;
;          Buffer with output entries, maximum 16384 bytes                     ;
;          maximum 16384/32 = 512 entries returned                             ;
;------------------------------------------------------------------------------;
asmCpuid:
;- This transit point reserved for Linux32/64, Windows32/64 compatibility
;- call Internal_GetCpuid
;- ret

;---------- Target subroutine -------------------------------------------------;
; INPUT:  Parameter#1 = [esp+4] = Pointer to output buffer
; OUTPUT: EAX = Number of output entries
;         Output buffer updated
;---
; Output buffer maximum size is 16384 bytes, 512 entries * 32 bytes
; Each entry is 32 bytes, 8 dwords:
; dword   offset in entry(hex)   comments
;--------------------------------------------------------------------------
;   0     00-03                  Information type tag, 0 for CPUID info                  
;   1     04-07                  CPUID function number
;   2     08-0B                  CPUID subfunction number
;   3     0C-0F                  CPUID pass number (as for function #2)
;   4     10-13                  Result EAX after CPUID
;   5     14-17                  Result EBX after CPUID
;   6     18-1B                  Result ECX after CPUID
;   7     1C-1F                  Result EDX after CPUID
;---
Internal_GetCPUID:
;---------- Initializing ------------------------------------------------------;

temp_r8   EQU  dword [ebp+00]  ; this for porting from x64 code
temp_r9   EQU  dword [ebp+04]
temp_r10  EQU  dword [ebp+08]
temp_ebp  EQU  dword [ebp+12]

cld
;--- Store registers ---
push ebx ebp esi edi
;--- Variables pool ---
xor eax,eax
push eax eax eax eax
mov ebp,esp
;--- Start ---
mov edi,[esp+32+4]
mov temp_ebp,0            ; xor ebp,ebp ; EBP = Global output entries counter
;---------- Check for ID bit writeable for "1" and "0" ------------------------;
call CheckCPUID           ; Return CF=Error flag, EAX=Maximum standard function
jc NoCpuId
;---------- Get standard CPUID results ----------------------------------------;
mov temp_r9,0             ; xor r9d,r9d  ; R9D  = standard functions start
cmp eax,ENTRIES_LIMIT/2   ; EAX = maximum supported standard function number
ja ErrorCpuId             ; Go if invalid limit
call SequenceCpuId
jc ErrorCpuId             ; Exit if output buffer overflow at subfunction
;---------- Get virtual CPUID results -----------------------------------------;
mov temp_r9,40000000h     ; R9D = virtual functions start
mov eax,temp_r9           ; EAX = Function
xor ecx,ecx               ; ECX = Subfunction
cpuid
and eax,0FFFFFF00h
cmp eax,040000000h
jne NoVirtual             ; Skip virtual CPUID if not supported
mov eax,temp_r9           ; EAX = Limit, yet 1 function 40000000h
call SequenceCpuId
jc ErrorCpuId             ; Exit if output buffer overflow at subfunction
NoVirtual:
;---------- Get extended CPUID results ----------------------------------------;
mov temp_r9,80000000h     ; mov r9d,80000000h ; R9D  = extended functions start
mov eax,temp_r9           ; r9d
cpuid
cmp eax,80000000h + ENTRIES_LIMIT/2  ; EAX = maximum extended function number
ja ErrorCpuId                        ; Go if invalid limit
call SequenceCpuId
jc ErrorCpuId                        ; Exit if output buffer overflow
;---------- Return points -----------------------------------------------------;
mov eax,temp_ebp          ; Normal exit point, return EAX = number of entries
ExitCpuId:
add esp,16
pop edi esi ebp ebx
ret      ;  8  ; 4
NoCpuId:                  ; Exit for CPUID not supported, EAX=0
xor eax,eax
jmp ExitCpuId
ErrorCpuId:               ; Exit for CPUID error, EAX=-1=FFFFFFFFh
mov eax,-1
jmp ExitCpuId 
;---------- Subroutine, sequence of CPUID functions ---------------------------;
; INPUT:  R9D = Start CPUID function number
;         EAX = Limit CPUID function number (inclusive)
;         EDI = Pointer to memory buffer
; OUTPUT: EDI = Modified by store CPUID input parms + output parms entry
;         Flags condition code: Carry (C) = means entries count limit
;---
SequenceCpuId:
mov temp_r10,eax      ; mov r10d,eax ; R10D = standard or extended functions limit 
CycleCpuId:
;--- Specific handling for functions with subfunctions ---
mov eax,temp_r9       ; r9d ; EAX = function number, input at R9D
cmp eax,04h
je Function04
cmp eax,07h
je Function07
cmp eax,0Bh
je Function0B
cmp eax,0Dh
je Function0D
cmp eax,0Fh
je Function0F
cmp eax,10h
je Function10
cmp eax,14h
je Function14
cmp eax,8000001Dh
je Function04
;--- Default handling for functions without subfunctions ---
xor esi,esi               ; ESI = sub-function number for CPUID
xor ecx,ecx               ; ECX = sub-function number for save entry 
call StoreCpuId
ja OverSubFunction
AfterSubFunction:         ; Return point after sub-function specific handler
mov eax,temp_r9
inc eax
mov temp_r9,eax
cmp eax,temp_r10
jbe CycleCpuId            ; Cycle for CPUID standard functions
ret
OverSubFunction:
stc
ret 
;---------- Subroutine, one CPUID function execution --------------------------;
; INPUT:  EAX = CPUID function number
;         R9D = EAX (R8-R15 emulated in memory, because port from x64)
;         ECX = CPUID subfunction number
;         ESI = ECX
;         RDI = Pointer to memory buffer
; OUTPUT: RDI = Modified by store CPUID input parms + output parms entry
;         Flags condition code: Above (A) = means entries count limit
;---
StoreCpuId:
cpuid
StoreCpuId_Entry:     ; Entry point for CPUID results (EAX,EBX,ECX,EDX) ready 
push eax
xor eax,eax
stosd                 ; Store tag dword[0] = Information type
mov eax,temp_r9       ; r9d
stosd                 ; Store argument dword [1] = CPUID function number 
mov eax,esi
stosd                 ; Store argument dword [2] = CPUID sub-function number
xor eax,eax
stosd                 ; Store argument dword [3] = CPUID pass number (see fn.2)
pop eax
stosd                 ; Store result dword [4] = output EAX 
xchg eax,ebx
stosd                 ; Store result dword [5] = output EBX
xchg eax,ecx
stosd                 ; Store result dword [6] = output ECX
xchg eax,edx
stosd                 ; Store result dword [7] = output EDX
inc temp_ebp          ; ebp ; Global counter +1
cmp temp_ebp,ENTRIES_LIMIT  ; ebp ; Limit for number of output entries
ret
;---------- CPUID function 04h = Deterministic cache parameters ---------------;
Function04:
xor esi,esi           ; ESI = Storage for sub-function number
.L0:
mov eax,temp_r9       ; r9d ; EAX = function number
mov ecx,esi           ; ECX = subfunction number
cpuid
test al,00011111b     ; Check for subfunction list end
jz AfterSubFunction   ; Go if reach first not valid subfunction
call StoreCpuId_Entry
ja OverSubFunction    ; Go if output buffer overflow
inc esi               ; Sunfunctions number +1
jmp .L0               ; Go repeat for next subfunction
;---------- CPUID function 07h = Structured extended feature flags ------------;   
Function07:
xor esi,esi           ; ESI = Storage for sub-function number
mov ecx,esi
mov eax,temp_r9       ; r9d ; EAX = function number (BUGGY DUPLICATED)
cpuid
mov temp_r8,eax       ; r8d,eax ; R8D = Maximal sub-function number
.L0:
mov eax,temp_r9       ; r9d
mov ecx,esi           ; ECX = Current sub-function number
call StoreCpuId
ja OverSubFunction    ; Go if output buffer overflow
inc esi               ; Sunfunctions number +1
cmp esi,temp_r8       ; r8d 
jbe .L0               ; Go cycle if next sub-function exist
jmp AfterSubFunction
;---------- CPUID function 0Bh = Extended topology enumeration ----------------;
Function0B:
xor esi,esi           ; ESI = Storage for sub-function number
.L0:
mov eax,temp_r9       ; r9d ; EAX = function number
mov ecx,esi           ; ECX = subfunction number
cpuid
test eax,eax          ; Check for subfunction list end
jz AfterSubFunction   ; Go if reach first not valid subfunction
call StoreCpuId_Entry
ja OverSubFunction    ; Go if output buffer overflow
inc esi               ; Sunfunctions number +1
jmp .L0               ; Go repeat for next subfunction
;---------- CPUID function 0Dh = Processor extended state enumeration ---------;
Function0D:
mov eax,temp_r9       ; r9d ; EAX = function number
xor ecx,ecx           ; ECX = sub-function number
cpuid
xor esi,esi           ; ESI = Storage for sub-function number
.L2:
rcr edx,1
rcr eax,1
jnc .L3
push eax edx
mov eax,temp_r9       ; r9d
mov ecx,esi           ; ECX = Sub-function number
call StoreCpuId
pop edx eax
ja OverSubFunction    ; Go if output buffer overflow
.L3:
inc esi               ; Sunfunctions number +1
cmp esi,63            ;  
jbe .L2               ; Go cycle if next sub-function exist
;---
jmp AfterSubFunction 
;---------- CPUID function 0Fh = Platform QoS monitoring enumeration ----------;
Function0F:
;---------- CPUID function 10h = L3 cache QoS enforcement enumeration (same) --;
Function10:
xor esi,esi           ; ESI = sub-function number for CPUID
xor ecx,ecx           ; ECX = sub-function number for save entry 
push eax temp_r9      ; r9       
call StoreCpuId       ; Subfunction 0 of fixed list [0,1]
pop temp_r9 eax       ; r9
ja OverSubFunction    ; Go if output buffer overflow
mov esi,1
mov ecx,esi
call StoreCpuId       ; Subfunction 1 of fixed list [0,1]
ja OverSubFunction    ; Go if output buffer overflow
jmp AfterSubFunction
;---------- CPUID function 14h = Intel Processor Trace Enumeration ------------;
Function14:
xor esi,esi           ; ESI = Storage for sub-function number
mov ecx,esi
mov eax,temp_r9       ; r9d ; EAX = function number (BUGGY DUPLICATED)
cpuid
mov temp_r8,eax       ; r8d,eax ; R8D = Maximal sub-function number
.L0:
mov eax,temp_r9       ; r9d
mov ecx,esi           ; ECX = Current sub-function number
call StoreCpuId
ja OverSubFunction    ; Go if output buffer overflow
inc esi               ; Sunfunctions number +1
cmp esi,temp_r8       ; r8d 
jbe .L0               ; Go cycle if next sub-function exist
jmp AfterSubFunction

;------------------------------------------------------------------------;
; Check CPUID instruction support.                                       ;
;                                                                        ;
; INPUT:   None                                                          ;
;                                                                        ;
; OUTPUT:  CF = Error flag,                                              ; 
;          0(NC) = Result in EAX valid, 1(C) = Result not valid          ;
;          EAX = Maximum supported standard function, if no errors       ;
;------------------------------------------------------------------------;
CheckCPUID:
mov ebx,21
pushf                     ; In the 32-bit mode, push EFLAGS
pop eax
bts eax,ebx               ; Set EAX.21=1
push eax
popf                      ; Load EFLAGS with EFLAGS.21=1
pushf                     ; Store EFLAGS
pop eax                   ; Load EFLAGS to EAX
btr eax,ebx               ; Check EAX.21=1, Set EAX.21=0
jnc .L0                   ; Go error branch if cannot set EFLAGS.21=1
push eax
popf                      ; Load EFLAGS with EFLAGS.21=0
pushf                     ; Store EFLAGS
pop eax                   ; Load EFLAGS to EAX
btr eax,ebx               ; Check EAX.21=0
jc .L0                    ; Go if cannot set EFLAGS.21=0
xor eax,eax
cpuid
ret
.L0:
stc
ret


;---------- Public entry point ------------------------------------------------;
;---------- Measure TSC (Time Stamp Counter) clock frequency ------------------;
; Parm#1 = DWORD [esp+04] = Pointer to buffer for dump data                    ;
; Output = EAX = Number of output entries or special value                     ;
;               1 means successful, for this function result always 1 entry    ;
;               0 means CPUID or RDTSC not supported                           ;
;              -1 means CPUID or RDTSC get information error                   ;
;          Buffer with output entries, 1 entry = 32 bytes for this function    ;
;------------------------------------------------------------------------------;
asmRdtsc:
;- This transit point reserved for Linux32/64, Windows32/64 compatibility
;- call Internal_GetCpuClk
;- ret

;------------------------------------------------------------------------;
; Measure CPU Clock frequency by Time Stamp Counter (TSC)                ;
;                                                                        ;
; INPUT:   EDI = Pointer to OPB (Output Parameters Block)                ;
;                                                                        ;
; OUTPUT:  EAX = Status:                                                 ;
;                -1 = Error, 0 = Not supported, 1 = Successfull measure  ;
;                 at OPB, measured TSC frequency valid only if RAX=1     ;
;                                                                        ;
; dword   offset in entry(hex)   comments                                ;
;------------------------------------------------------------------------;
;   0     00-03                  Information type tag, 1 for RDTSC info  ;
;   1     04-07                  0 reserved                              ;
;   2     08-0B                  0 reserved                              ;
;   3     0C-0F                  0 reserved                              ;
;   4     10-13                  0 reserved                              ;
;   5     14-17                  0 reserved                              ;
;   6     18-1B                  TSC Frequency Hz, low 32-bit dword      ;
;   7     1C-1F                  TSC Frequency Hz, high 32-bit dword     ;
;------------------------------------------------------------------------;
Get_CpuClk:
push eax ebx ecx edx
;-
mov edi,[esp+04+16]
push edi
cld
mov ecx,8
xor eax,eax
rep stosd
pop edi
mov dword[edi],1  ; Tag
;- mov dword [edi+0],0
;- mov dword [edi+4],0
call CheckCPUID
jc MeasureTscAbsent        ; Go skip if CPUID not supported
cmp eax,1
jb MeasureTscAbsent        ; Go skip if CPUID function 1 not supported
mov eax,1
cpuid
test dl,10h
jz MeasureTscAbsent        ; Go skip if TSC not supported
call MeasureCpuClk
jc MeasureTscFailed        ; Go if measurement error 
mov dword [edi+24],eax     ; mov dword [edi+0],eax
mov dword [edi+28],edx     ; mov dword [edi+4],edx
mov eax,1
@@:
pop edx ecx ebx eax
ret   ;  4
MeasureTscAbsent:
xor eax,eax                 ; 0 means TSC not supported
jmp @b
MeasureTscFailed:
mov eax,-1                  ; -1 means TSC measurement failed
jmp @b


;--- Measure CPU TSC (Time Stamp Counter) clock frequency ---------------;
;                                                                        ;
; INPUT:   None                                                          ;
;                                                                        ;
; OUTPUT:  CF flag = Status: 0(NC)=Measured OK, 1(C)=Measurement error	 ;
;          Output RAX,RDX valid only if CF=0(NC)                         ;
;          EDX:EAX = TSC Frequency, Hz, F = Delta TSC per 1 second       ;
;------------------------------------------------------------------------;
MeasureCpuClk:
push edi esi ebp
;--- Prepare parameters, early to minimize dTSC ---
sub esp,32
mov ebx,esp               ; EBX = Pointer to loaded wait time: DQ sec, ns
lea ecx,[ebx+16]          ; ECX = Pointer to stored remain time: DQ sec, ns
xor eax,eax
mov dword [ebx+00],1
mov dword [ebx+04],eax 
mov dword [ebx+08],eax
mov dword [ebx+12],eax 
mov dword [ecx+00],eax
mov dword [ecx+04],eax 
mov dword [ecx+08],eax
mov dword [ecx+12],eax 
;--- Get TSC value before 1 second pause ---
rdtsc                     ; EDX:EAX = TSC, EDX = High , EAX = Low
push eax edx
;--- Wait 1 second ---
mov eax,162               ; EAX = Linux API function (syscall number) = SYS_NANOSLEEP
push ecx
int 80h
pop ecx
xchg ebx,eax
;--- Get TSC value after 1 second pause ---
rdtsc                     ; EDX:EAX = TSC, EDX = High , EAX = Low , BEFORE 1 second pause
pop edi esi               ; EDI:ESI = TSC, ECX = High , EBX = Low , AFTER 1 second pause
;--- Check results ---
test ebx,ebx
jnz TimerFailed           ; Go if error returned or wait interrupted
mov ebx,[ecx+00]          ; Time remain, seconds
or ebx,[ecx+04]
or ebx,[ecx+08]           ; Disjunction with Time remain, nanoseconds
or ebx,[ecx+12]
jnz TimerFailed           ; Go if remain time stored by function
;--- Calculate delta-TSC per 1 second = TSC frequency ---
sub eax,esi               ; Subtract: DeltaTSC.Low  = EndTSC.Low - StartTSC.Low
sbb edx,edi               ; Subtract: DeltaTSC.High = EndTSC.High - StartTSC.High - Borrow
test edx,edx
jnz TimerFailed           ; This debug 32-bit code not supports > 4GHz
;--- Exit points ---
add esp,32
clc
TimerDone:
pop ebp esi edi
ret
TimerFailed:
add esp,32
stc
jmp TimerDone


;---------- Public entry point ------------------------------------------------;
;---------- Get CPU context management bitmaps, XCR0-based --------------------;
; Parm#1 = DWORD [esp+04] = Pointer to buffer for dump data                    ;
; Output = EAX = Number of output entries or special value                     ;
;               1 means successful, for this function result always 1 entry    ;
;               0 means CPUID or XCR0 not supported                            ;
;              -1 means CPUID or XCR0 get information error                    ;
;          Buffer with output entries, 1 entry = 32 bytes for this function    ;
;------------------------------------------------------------------------------;
asmXcr0:
;- This transit point reserved for Linux32/64, Windows32/64 compatibility
;- call Internal_GetCpuContext
;- ret

;------------------------------------------------------------------------;
; Get CPU context management bitmaps, XCR0-based                         ;
;                                                                        ;
; INPUT:   DWORD [esp+04] = Pointer to OPB (Output Parameters Block)     ;
;                                                                        ;
; OUTPUT:  RAX = Status:                                                 ;
;                -1 = Error, 0 = Not supported, 1 = Successfull measure  ;
;                 at OPB, bitmaps valid only if RAX=1                    ;
;                                                                        ;
; dword   offset in entry(hex)   comments                                ;
;------------------------------------------------------------------------;
;   0     00-03                  Information type tag, 2 for XCR0 info   ;
;   1     04-07                  0 reserved                              ;
;   2     08-0B                  0 reserved                              ;
;   3     0C-0F                  0 reserved                              ;
;   4     10-13                  CPU validation mask, low 32-bit dword   ;
;   5     14-17                  CPU validation mask, high 32-bit dword  ;
;   6     18-1B                  OS validation mask, low 32-bit dword    ;
;   7     1C-1F                  OS validation mask, high 32-bit dword   ;
;------------------------------------------------------------------------;
GetCpuContext:
push ebx ecx edx
;-
mov edi,[esp+04+12]
push edi
cld
mov ecx,8
xor eax,eax
rep stosd
pop edi
mov dword[edi],2  ; Tag
; xor eax,eax
; mov [edi+00],eax     ; Pre-clear output data
; mov [edi+04],eax
; mov [edi+08],eax
; mov [edi+12],eax
call CheckCPUID
jc ContextControlAbsent     ; Skip if CPUID not supported
xor eax,eax
cpuid
cmp eax,0Dh
jb ContextControlAbsent     ; Skip if CPUID context declaration not supported
mov eax,1
cpuid
bt ecx,27
jnc ContextControlAbsent    ; Skip if CPU context management not supported
mov eax,0Dh
xor ecx,ecx
cpuid
mov [edi+16],eax      ; QWORD OPB[16] = CPU validation mask
mov [edi+20],edx
xor ecx,ecx
xgetbv
mov [edi+24],eax      ; QWORD OPB[24] = OS validation mask 
mov [edi+28],edx
mov eax,1
@@:
pop edx ecx ebx
ret
ContextControlAbsent:
xor eax,eax             ; 0 means TSC not supported
jmp @b
