;========== Platform support library: CPUID/RDTSC/XCR0 for Linux 64. ==========;

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

format ELF64

public asmCpuid as 'asmCpuid'
public asmRdtsc as 'asmRdtsc'
public asmXcr0  as 'asmXcr0'

ENTRIES_LIMIT = 512    ; Maximum number of output buffer 16384 bytes = 512*32

;---------- Public entry point ------------------------------------------------;
;---------- Get CPUID binary data ---------------------------------------------;
; Parm#1 = RDI = Pointer to buffer for dump data                               ;
; Output = RAX = Number of output entries or special value                     ;
;               0 means CPUID not supported                                    ;
;              -1 means CPUID get information error                            ;
;          Buffer with output entries, maximum 16384 bytes                     ;
;          maximum 16384/32 = 512 entries returned                             ;
;------------------------------------------------------------------------------;
asmCpuid:
;- This transit point reserved for Linux32/64, Windows32/64 compatibility
;- call Internal_GetCpuid
;- ret

;---------- CPUID support subroutine ------------------------------------------;
; INPUT:  Parameter#1 = RDI = Pointer to output buffer
; OUTPUT: RAX = Number of output entries or special value
;               0 means CPUID not supported
;              -1 means CPUID get information error
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
Internal_GetCpuid:
;---------- Initializing ------------------------------------------------------;
cld
push rbx rbp rsi rdi
xor ebp,ebp               ; EBP = Global output entries counter
;---------- Check ID bit writeable for "1" and "0", CPUID support indicator ---;
call CheckCpuid           ; Return CF=Error flag, EAX=Maximum standard function
jc NoCpuId
;---------- Get standard CPUID results ----------------------------------------;
xor r9d,r9d               ; R9D  = standard functions start
cmp eax,ENTRIES_LIMIT/2   ; EAX = maximum supported standard function number
ja ErrorCpuId             ; Go if invalid limit
call SequenceCpuId
jc ErrorCpuId             ; Exit if output buffer overflow at subfunction
;---------- Get virtual CPUID results -----------------------------------------;
mov r9d,40000000h         ; R9D = virtual functions start
mov eax,r9d               ; EAX = Function
xor ecx,ecx               ; ECX = Subfunction
cpuid
and eax,0FFFFFF00h
cmp eax,040000000h
jne NoVirtual             ; Skip virtual CPUID if not supported
mov eax,r9d               ; EAX = Limit, yet 1 function 40000000h
call SequenceCpuId
jc ErrorCpuId             ; Exit if output buffer overflow at subfunction
NoVirtual:
;---------- Get extended CPUID results ----------------------------------------;
mov r9d,80000000h         ; R9D  = extended functions start
mov eax,r9d
cpuid
cmp eax,80000000h + ENTRIES_LIMIT/2  ; EAX = maximum extended function number
ja ErrorCpuId                        ; Go if invalid limit
call SequenceCpuId
jc ErrorCpuId                        ; Exit if output buffer overflow
;---------- Return points -----------------------------------------------------;
xchg eax,ebp              ; Normal exit point, return RAX = number of entries
ExitCpuId:
pop rdi rsi rbp rbx
ret
NoCpuId:                  ; Exit for CPUID not supported, RAX=0  
xor eax,eax
jmp ExitCpuId
ErrorCpuId:               ; Exit for CPUID error, RAX=-1=FFFFFFFFFFFFFFFFh
mov rax,-1
jmp ExitCpuId 
;---------- Subroutine, sequence of CPUID functions ---------------------------;
; INPUT:  R9D = Start CPUID function number
;         EAX = Limit CPUID function number (inclusive)
;         RDI = Pointer to memory buffer
; OUTPUT: RDI = Modified by store CPUID input parms + output parms entry
;         Flags condition code: Carry (C) = means entries count limit
;---
SequenceCpuId:
mov r10d,eax              ; R10D = standard or extended functions limit 
CycleCpuId:
;--- Specific handling for functions with subfunctions ---
mov eax,r9d           ; EAX = function number, input at R9D
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
inc r9d
cmp r9d,r10d
jbe CycleCpuId            ; Cycle for CPUID standard functions
ret
OverSubFunction:
stc
ret 
;---------- Subroutine, one CPUID function execution --------------------------;
; INPUT:  EAX = CPUID function number
;         R9D = EAX
;         ECX = CPUID subfunction number
;         ESI = ECX
;         RDI = Pointer to memory buffer
; OUTPUT: RDI = Modified by store CPUID input parms + output parms entry
;         Flags condition code: Above (A) = means entries count limit
;---
StoreCpuId:
cpuid
StoreCpuId_Entry:     ; Entry point for CPUID results (EAX,EBX,ECX,EDX) ready 
push rax
xor eax,eax
stosd                 ; Store tag dword[0] = Information type
mov eax,r9d
stosd                 ; Store argument dword [1] = CPUID function number 
mov eax,esi
stosd                 ; Store argument dword [2] = CPUID sub-function number
xor eax,eax
stosd                 ; Store argument dword [3] = CPUID pass number (see fn.2)
pop rax
stosd                 ; Store result dword [4] = output EAX 
xchg eax,ebx
stosd                 ; Store result dword [5] = output EBX
xchg eax,ecx
stosd                 ; Store result dword [6] = output ECX
xchg eax,edx
stosd                 ; Store result dword [7] = output EDX
inc ebp               ; Global counter +1
cmp ebp,ENTRIES_LIMIT ; Limit for number of output entries
ret
;---------- CPUID function 04h = Deterministic cache parameters ---------------;
Function04:
xor esi,esi           ; ESI = Storage for sub-function number
.L0:
mov eax,r9d           ; EAX = function number
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
mov eax,r9d           ; EAX = function number (BUGGY DUPLICATED)
cpuid
mov r8d,eax           ; R8D = Maximal sub-function number
.L0:
mov eax,r9d
mov ecx,esi           ; ECX = Current sub-function number
call StoreCpuId
ja OverSubFunction    ; Go if output buffer overflow
inc esi               ; Sunfunctions number +1
cmp esi,r8d           ; 
jbe .L0               ; Go cycle if next sub-function exist
jmp AfterSubFunction
;---------- CPUID function 0Bh = Extended topology enumeration ----------------;
Function0B:
xor esi,esi           ; ESI = Storage for sub-function number
.L0:
mov eax,r9d           ; EAX = function number
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
mov eax,r9d           ; EAX = function number
xor ecx,ecx           ; ECX = sub-function number
cpuid
shl rdx,32
lea r8,[rdx+rax]
xor esi,esi           ; ESI = Storage for sub-function number
.L2:
shr r8,1
jnc .L3
mov eax,r9d
mov ecx,esi           ; ECX = Sub-function number
call StoreCpuId
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
push rax r9       
call StoreCpuId       ; Subfunction 0 of fixed list [0,1]
pop r9 rax
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
mov eax,r9d           ; EAX = function number (BUGGY DUPLICATED)
cpuid
mov r8d,eax           ; R8D = Maximal sub-function number
.L0:
mov eax,r9d
mov ecx,esi           ; ECX = Current sub-function number
call StoreCpuId
ja OverSubFunction    ; Go if output buffer overflow
inc esi               ; Sunfunctions number +1
cmp esi,r8d           ; 
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
CheckCpuid:
mov ebx,21
pushf                     ; In the 64-bit mode, push RFLAGS
pop rax
bts eax,ebx               ; Set EAX.21=1
push rax
popf                      ; Load RFLAGS with RFLAGS.21=1
pushf                     ; Store RFLAGS
pop rax                   ; Load RFLAGS to RAX
btr eax,ebx               ; Check EAX.21=1, Set EAX.21=0
jnc .L0                   ; Go error branch if cannot set EFLAGS.21=1
push rax
popf                      ; Load RFLAGS with RFLAGS.21=0
pushf                     ; Store RFLAGS
pop rax                   ; Load RFLAGS to RAX
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
; Parm#1 = RDI = Pointer to buffer for dump data                               ;
; Output = RAX = Number of output entries or special value                     ;
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
; INPUT:   RDI = Pointer to OPB (Output Parameters Block)                ;
;                                                                        ;
; OUTPUT:  RAX = Status:                                                 ;
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
Internal_GetCpuClk:
push rbx rcx rdx
mov qword [rdi+00],1    ; Tag and reserved dword
xor eax,eax
mov [rdi+08],rax        ; Blank reserved
mov [rdi+16],rax
mov [rdi+24],rax
call CheckCpuid
jc MeasureTscAbsent     ; Go skip if CPUID not supported
cmp eax,1
jb MeasureTscAbsent     ; Go skip if CPUID function 1 not supported
mov eax,1
cpuid
test dl,10h
jz MeasureTscAbsent     ; Go if TSC not supported
call MeasureCpuClk
jc MeasureTscFailed     ; Go if TSC clock measurement error
mov qword [rdi+24],rax
mov eax,1               ; 1 means sucessful, 1 valid entry stored
@@:
pop rdx rcx rbx
ret
MeasureTscAbsent:
xor eax,eax             ; 0 means TSC not supported
jmp @b
MeasureTscFailed:
mov eax,-1              ; -1 means TSC measurement failed
jmp @b

;--- Measure CPU TSC (Time Stamp Counter) clock frequency ---------------;
;                                                                        ;
; INPUT:   None                                                          ;
;                                                                        ;
; OUTPUT:  CF flag = Status: 0(NC)=Measured OK, 1(C)=Measurement error	 ;
;          Output RAX,RDX valid only if CF=0(NC)                         ;
;          RAX = TSC Frequency, Hz, F = Delta TSC per 1 second           ;
;------------------------------------------------------------------------;
MeasureCpuClk:
push rcx rsi rdi r8 r9 r10 r11
;--- Prepare parameters, early to minimize dTSC ---
;lea rdi,[TimespecWait]    ; RDI = Pointer to loaded wait time: DQ sec, ns
;lea rsi,[rdi+16]          ; RSI = Pointer to stored remain time: DQ sec, ns
sub rsp,32
mov rdi,rsp
lea rsi,[rdi+16]
xor eax,eax
mov qword [rdi+00],1
mov qword [rdi+08],rax
mov qword [rsi+00],rax
mov qword [rsi+08],rax
;--- Get TSC value before 1 second pause ---
rdtsc                     ; EDX:EAX = TSC, EDX = High , EAX = Low
push rax rdx
;--- Wait 1 second ---
mov eax,SYS_NANOSLEEP     ; EAX = Linux API function (syscall number)
push rsi
syscall
pop rsi
xchg r8,rax
;--- Get TSC value after 1 second pause ---
rdtsc                     ; EDX:EAX = TSC, EDX = High , EAX = Low , BEFORE 1 second pause
pop rcx rdi               ; ECX:EDI = TSC, ECX = High , EBX = Low , AFTER 1 second pause
;--- Check results ---
test r8,r8
jnz TimerFailed           ; Go if error returned or wait interrupted
mov r8,[rsi+00]           ; RAX = Time remain, seconds
or  r8,[rsi+08]           ; RAX = Disjunction with Time remain, nanoseconds
jnz TimerFailed           ; Go if remain time stored by function
;--- Calculate delta-TSC per 1 second = TSC frequency ---
sub eax,edi               ; Subtract: DeltaTSC.Low  = EndTSC.Low - StartTSC.Low
sbb edx,ecx               ; Subtract: DeltaTSC.High = EndTSC.High - StartTSC.High - Borrow
;--- Extract TSC frequency as 64-bit value ---
shl rdx,32
add rax,rdx
;--- Exit points ---
add rsp,32
clc
TimerDone:
pop r11 r10 r9 r8 rdi rsi rcx
ret
TimerFailed:
add rsp,32
stc
jmp TimerDone


;---------- Public entry point ------------------------------------------------;
;---------- Get CPU context management bitmaps, XCR0-based --------------------;
; Parm#1 = RDI = Pointer to buffer for dump data                               ;
; Output = RAX = Number of output entries or special value                     ;
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
; INPUT:   RDI = Pointer to OPB (Output Parameters Block)                ;
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
Internal_GetCpuContext:
push rbx rcx rdx
mov qword [rdi+00],2       ; Set tag, pre-clear output data
mov qword [rdi+08],0
call CheckCpuid
jc ContextControlAbsent    ; Skip if CPUID not supported
xor eax,eax
cpuid
cmp eax,0Dh
jb ContextControlAbsent    ; Skip if CPUID context declaration not supported
mov eax,1
cpuid
bt ecx,27
jnc ContextControlAbsent   ; Skip if CPU context management not supported
mov eax,0Dh
xor ecx,ecx
cpuid
mov [rdi+16],eax           ; QWORD OPB[16] = CPU validation mask
mov [rdi+20],edx
xor ecx,ecx
xgetbv
mov [rdi+24],eax           ; QWORD OPB[24] = OS validation mask 
mov [rdi+28],edx
mov eax,1                  ; 1 means sucessful, 1 valid entry stored
@@:
pop rdx rcx rbx
ret
ContextControlAbsent:
xor eax,eax             ; 0 means TSC not supported
jmp @b






; ********** DEBUG AND EXPERIMENTS **********

; This test with data access for Read and Write
; INPUT:   <var>
; OUTPUT:  <var> and RAX = Return code
; 6 parameters without stack
; Parm#1  = double  = XMM0
; Parm#2  = double  = XMM1
; Parm#3  = double  = XMM2
; Parm#4  = double  = XMM3
; Parm#5  = double  = XMM4
; Parm#6  = double  = XMM5
; Parm#7  = double* = RDI
; Parm#8  = double* = RSI
; Parm#9  = double* = RDX
; Parm#10 = double* = RCX
; Parm#11 = double* = R8
; Parm#12 = double* = R9

; format ELF64

; public TestRoutine as 'TestRoutine'


; TestRoutine:
; movsd xmm6,[Data1]
; addsd xmm0,xmm6
; addsd xmm1,xmm6
; addsd xmm2,xmm6
; addsd xmm3,xmm6
; addsd xmm4,xmm6
; addsd xmm5,xmm6
; movsd [rdi],xmm0
; movsd [rsi],xmm1
; movsd [rdx],xmm2
; movsd [rcx],xmm3
; movsd [r8],xmm4
; movsd [r9],xmm5
; mov eax,25
; ret
; Data1 DQ 10.0


