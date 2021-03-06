;/*
; *                      Microsoft Confidential
; *			 Copyright (C) Microsoft Corporation 1988-1992
; *                      All Rights Reserved.
; */
	page	95,160
	title   'HIMEM.SYS - Microsoft XMS Device Driver'
;*****************************************************************************
;*									     *
;*  HIMEM.ASM -								     *
;*									     *
;*	Extended Memory Specification Driver -				     *
;*									     *
;*****************************************************************************
;
;	himem.inc	- global equates, macros, structures, opening segment
;	himem.asm	- main driver entry, interrupt hooks, a20/HMA functions
;	himem1.asm	- a20 switching code
;	himem2.asm	- driver initialization
;	himem3.asm	- messages for driver initialization
;	himem4.asm	- extended memory allocation functions
;	himem5.asm	- memory move function
;
;	for revision history prior to 1990, see version 2.37 or earlier
;
;	2.35	- Removed a few push/pops from IsA20On, misc	01/14/90
;		  source code reformatting
;	2.36	- Include Int 6Dh vector in shadow RAM disable	01/18/90
;		  check, also allow disable if video Ints already
;		  point at C000h segment.  Also added some CLD's near
;		  string instructions.
;	2.37	- Removed 2.33 'fix' for All Chargecard.  They	01/23/89
;		  now do Global and Local enables to turn on A20, and
;		  the previous 'fix' caused us to never didle A20 again
;		  after running Windows real mode twice (Windows does
;		  Global enables/disables too).  Also, GetParms needed to
;		  check for LF in addition to CR for end of line.
;;
;;; Following changes synced from \402\dev\himem tree
;;
;	2.50	- Revised version # for Windows 3.0 release.	02/05/90
;	 ""	- Ignore 'super'-extended memory on EISA memory 02/08/90
;		  memory boards (mem > 16 meg).  Software that
;		  uses 24 bit (80286) descriptors doesn't do
;		  well with memory @ 16 meg.
;	 ""	- Himem will now try to control A20 by default, 02/12/90
;		  even if A20 is already enabled when himem is
;		  loaded.  Added /A20CONTROL: ON | OFF switch to
;		  override this if necessary (ON is default and
;		  means we take control, OFF means we take control
;		  unless A20 was already on, in which case we
;		  don't mess with it).
;
;	2.60	- Added special A20 routine for Toshiba 1600	02/22/90
;		  laptop, and revised driver version number to
;		  be later than Compaq's (2.50) so Windows
;		  setup will install ours.
;	 ""	- Clear bit 15 in device attributes word of	02/28/90
;		  device header if driver is being flushed. The
;		  MS-DOS Encylopedia says to do this, and a
;		  system with DOS 3.21 was hanging when loading
;		  the driver after himem if himem flushed itself.
;	 ""	- Added special A20 handler for Wyse 12.5 MHz	03/27/90
;		  286 machine. Almost the same as AT, but
;		  a little different.
;	 ""	- Now displays a msg indicating which A20	04/05/90
;		  handler is installed, and allows numbers for the
;		  /MACHINE: parameter.
;;
;;; End of \402\dev\himem changes
;;
;
;	 ""	- Added /INT15=xxxx option to reserve xxxxK of	04/13/90
;		  extended memory for INT 15. Himem will reserve xxxx K
;		  (64 K of HMA inclusive) for apps which use Ext Mem thru
;		  int 15 interface. The HMA portion of the INT 15 ext memory
;		  should be protected by a VDISK header. Apps which
;		  do not recognize VDISK headers may destroy the HMA.
;
;	 ""	- When there is a /INT15=xxxx option on the	04/20/90
;		  command line, the HMA is made unavailable to the
;		  apps. But DOS 5.0 goes ahead and checks for INT 15
;		  memory if the alloc HMA call fails. And if INT 15 memory
;		  is present it uses the first 64 K for loading itself
;		  high (simulated HMA)
;
;	 ""	- ORGed the movable segment to high value for flexibility
;		  in loading into HMA. Added code to be flexible enough to
;		  run from HMA as well as low memory.

	public	Interrupt
	public	dd_int_loc
	public	fHMAExists
	public	PrevInt15
	public	fA20Check
	public	OldStackSeg
	public	pPPFIRET
	public	EnableCount
	public	pReqHdr
	public	MinHMASize
	public	MoveIt
	public	Int2fHandler
	public	ISA15Handler
	public	fHMAMayExist
	public	MemCorr
	public	PrevInt2f
	public	fCanChangeA20
	public	IsVDISKIn
	public	fVDISK

	public	LocalEnableA20
	public	LocalDisableA20
	public	FLclEnblA20
	public	FLclDsblA20
	public	IsA20On
	public	winbug_fix
	public	ATA20Delay

	public	pVersion
	public	pQuery
	public	pAlloc
	public	pFree
	public	pLock
	public	pUnlock
	public	pGetInfo
	public	pRealloc
	public	pAddMem

	public	TopOfTextSeg

	public	XMMControl
	public	pfnEnabA20
	public	pfnDisabA20


; Define a direct call to the Phoenix Cascade BIOS for A20 handling
;	Note:  if these segments are not defined here, the Int13Handler
;	definition in segment Zero in the 386 memory move will generate
;	bad code.

PTL_Seg	segment at 0f000h
PTL_Seg	ends
BiosSeg SEGMENT  AT 40h		  ; Used to locate 6300 PLUS reset address
BiosSeg ends

	include	himem.inc		; define structures, macros, open seg.
	extrn	EndText:byte
_text	ends

funky	segment	para public 'funky'
	assume	cs:funky

;	externals from himem4

	extrn	Version:near
	extrn	aQueryExtMemory:near
	extrn	aAllocExtMemory:near
	extrn	aFreeExtMemory:near
	extrn	LockExtMemory:near
	extrn	UnlockExtMemory:near
	extrn	aGetExtMemoryInfo:near
	extrn	aReallocExtMemory:near
	extrn	aAddMem:near

	extrn	HandleInfo:byte
	extrn	cHandles:word
	extrn	KiddValley:word

;	externals from himem5

	extrn	MoveBlock286:near

funky	ends

;
;------ the following segment should be the last in the sys file
;	This segment is read by the stripdd utility to remove
;	the zeroes introduced by the hi ORG in the movable segment

ZZZ	segment para 'ZZZ'
	dw	16			; len of this segment
	dw	offset _text:EndText	; len of text seg in double word
	dw	0
	dw	HISEG_ORG		; number of zeroes to be stripped
	dw	-1
	dw	-1			; terminator
	db	(4) dup (55h)		; filler
ZZZ	ends


_text	segment word public 'code'
	assume	cs:_text

;	externals from himem1

	extrn	A20Handler:near

;	externals from himem2

	extrn	InitInterrupt:near

	public	DevAttr
	public	Int15MemSize
	public	fInHMA
	public	pInt15Vector
	public	PrevISAInt15

; The Driver Header definition.
Header	dd	-1			; Link to next driver, -1 = end of list
DevAttr	dw	1010000000000000b	; Char device & Output until busy(?)
	dw	Strategy    		; "Stategy" entry point
dd_int_loc	dw	InitInterrupt	; "Interrupt" entry point
		db	'XMSXXXX0'	; Device name


;************************************************************************
;*									*
;*  Global Variables							*
;*									*
;************************************************************************


	if	keep_cs
callers_cs	dw	0
	endif

TopOfTextSeg	dw	0	; size of retained driver
pPPFIRet	dw	PPFIRet ; The offset of an IRET for the POPFF macro
pReqHdr		dd	?	; Pointer to MSDOS Request Header structure
pInt15Vector	dw	15h*4,0 ; Pointer to the INT 15 Vector
PrevInt15	dd	0	; Original INT 15 Vector
PrevInt2f	dd	0	; Original INT 2f Vector
PrevISAInt15	dd	0	; Orig Int 15 Vector for ext mem > 16 meg calls
fHMAInUse	db	0	; High Memory Control Flag, != 0 -> In Use
fCanChangeA20	db	1	; A20 Enabled at start? (assume changable)
fHMAMayExist	db	0	; True if the HMA could exist at init time
fHMAExists	db	0	; True if the HMA exists
fInstalled	db	0	; True if ext mem has been allocated
fInHMA		db	0	; true if hiseg is in HMA

fVDISK		db	0	; True if a VDISK device was found

fA20Check	db	0	; True if A20 handler supports On/Off check
ATA20Delay	db	0	; Type of AT A20 delay in use (0 - NUM_ALT_A20)

		even

EnableCount	dw	0	; A20 Enable/Disable counter
fGlobalEnable	dw	0	; Global A20 Enable/Disable flag
MinHMASize	dw	0	; /HMAMIN= parameter value
Int15MemSize	dw	0	; Memory size reserved for INT 15

MemCorr		dw	0	; KB of memory at FA0000 on AT&T 6300 Plus.
				;      This is used to correct INT 15h,
				;      Function 88h return value.
OldStackSeg	dw	0	; Stack segment save area for 6300 Plus.
				;      Needed during processor reset.

; Pointers to functions that enable and disable A20.

		even
pfnEnabA20	dw	offset _text:ExtEnabA20
pfnDisabA20	dw	offset _text:ExtDisabA20

	if	NUM_A20_RETRIES
A20Retries	db	0	; Count of retires remaining on A20 diddling
	endif

	public	lpExtA20Handler

lpExtA20Handler dd	0	; Far entry point to an external A20 handler

	public	InstldA20HndlrN	;				M008

InstldA20HndlrN	db	0	; Installed A20 handler number	M008

pAddMem		dw	aAddMem
;*----------------------------------------------------------------------*
;*									*
;*  Strategy -								*
;*									*
;*	Called by MS-DOS when ever the driver is accessed.		*
;*									*
;*  ARGS:   ES:BX = Address of Request Header				*
;*  RETS:   Nothing							*
;*  REGS:   Preserved							*
;*									*
;*----------------------------------------------------------------------*

Strategy    proc    far
	assume	ds:nothing

	; Save the address of the request header.
	mov	word ptr [pReqHdr],bx
	mov	word ptr [pReqHdr][2],es
	ret

Strategy    endp


;*----------------------------------------------------------------------*
;*									*
;*  Interrupt -								*
;*									*
;*	Called by MS-DOS immediately after Strategy routine		*
;*									*
;*  ARGS:   None							*
;*  RETS:   Return code in Request Header's Status field		*
;*  REGS:   Preserved							*
;*									*
;*	This is our permanent entry point.  By this time, the only	*
;*	useful function done by the device driver (initializing us)	*
;*	has been done by a previous call.  There are no more valid	*
;*	uses for this entry point.  All we have to do is decide		*
;*	whether to ignore the call or generate an error.		*
;*									*
;*----------------------------------------------------------------------*

Interrupt   proc    far
	assume	ds:nothing


	push    bx		; save minimal register set
	push    ds

	lds	bx,[pReqHdr]		; ds:bx = Request Header

	cmp	ds:[bx].Command,16	; legal DOS function?  (approx???)
	mov	ds:[bx].Status,100h	; "Done" for healthy calls
	jbe	FuncOk
	or	ds:[bx].Status,8003h	; Return "Unknown Command" error
FuncOk:
	pop	ds
	pop	bx
	ret

Interrupt   endp


;*----------------------------------------------------------------------*
;*									*
;*  Int2fHandler -							*
;*									*
;*	Hooks Function 43h, Subfunction 10h to return the		*
;*	address of the High Memory Manager Control function.		*
;*	Also returns 80h if Function 43h, Subfunction 0h is requested.	*
;*									*
;*  ARGS:   AH = Function, AL = Subfunction				*
;*  RETS:   ES:BX = Address of XMMControl function (if AX=4310h)	*
;*	    AL = 80h (if AX=4300)					*
;*  REGS:   Preserved except for ES:BX (if AX=4310h)			*
;*	    Preserved except for AL    (if AX=4300h)			*
;*									*
;*----------------------------------------------------------------------*

Int2fHandler proc   far
	assume	ds:nothing, es:nothing

	sti			; Flush any queued interrupts

	cmp	ah,43h		; Function 43h?
	jne     I2fNextInt
	or	al,al		; Subfunction 0?
	jne     I2fNextSub	; No, continue

	mov	al,80h		; Return 80h in AL (XMS Installed)
PPFIRet:
	iret			; Label sets up the POPFF macro

I2fNextSub:
	cmp	al,10h		; Subfunction 10?
	jne	trya20id	; No, check whther it is A20 handler request M008

	push    cs		; return XMS entry in es:bx
	pop	es
	mov	bx,offset XMMControl
	iret
;
; Check if it is A20 handler request and process it if so M008
;
trya20id:
	cmp	al, 08h
	jne	tryHandleInfo

	mov	al, ah		; mark that we did the job AL = 43H
	mov	bh, ATA20Delay	; return the delay type used
	mov	bl, InstldA20HndlrN	; return the a20 handler number in al
	iret

; Check if it is Handle table info request

tryHandleInfo:
	cmp	al, 09h
	jne     I2fNextInt	; No, goto next handler

	mov	al, ah		; mark that we did the job AL = 43H
	mov	es, cs:[hiseg]	; return ptr to HandleInfo in es:bx
	mov	bx, offset funky:HandleInfo

	iret

;	Continue down the Int 2f chain.


I2fNextInt:
	cli			; Disable interrupts again
	jmp	[PrevInt2f]

Int2fHandler endp


;*----------------------------------------------------------------------*
;*									*
;*  ControlJumpTable -							*
;*									*
;*	Contains the address for each of the XMS Functions.		*
;*									*
;*	**************** WARNING **********************			*
;*									*
;*	Assumes that offsets of functions in lo mem seg are < 8000h	*
;*	& that offsets of segment in Hiseg are >= 8000h			*
;*									*
;*----------------------------------------------------------------------*

public ControlJumpTable

ifdef debug_tsr
        JumpPtr equ <dd>        ; dword addresses for TSR
ControlJumpTable label dword
else
        JumpPtr equ <dw>        ; word offsets for DOS device driver
ControlJumpTable label word
endif

pVersion:	JumpPtr	Version		  	; Function 00h - funky
		JumpPtr	RequestHMA	  	; Function 01h - _text
		JumpPtr	ReleaseHMA	  	; Function 02h - _text
		JumpPtr	GlobalEnableA20	  	; Function 03h - _text
		JumpPtr	GlobalDisableA20  	; Function 04h - _text
                JumpPtr LocalEnableA20	  	; Function 05h - _text
                JumpPtr LocalDisableA20         ; Function 06h - _text
		JumpPtr	IsA20On		  	; Function 07h - _text
pQuery:		JumpPtr	aQueryExtMemory	  	; Function 08h - funky
pAlloc:		JumpPtr	aAllocExtMemory	  	; Function 09h - funky
pFree:		JumpPtr	aFreeExtMemory	  	; Function 0Ah - funky
MoveIt:		JumpPtr	MoveBlock286	  	; Function 0Bh - funky
pLock:		JumpPtr	LockExtMemory	  	; Function 0Ch - funky
pUnlock:	JumpPtr	UnlockExtMemory	  	; Function 0Dh - funky
pGetInfo:	JumpPtr	aGetExtMemoryInfo 	; Function 0Eh - funky
pRealloc:	JumpPtr	aReallocExtMemory	; Function 0Fh - funky

ifdef debug_tsr
NumFns	=	((offset $) - (offset ControlJumpTable))/4
else
NumFns	=	((offset $) - (offset ControlJumpTable))/2
endif

;*----------------------------------------------------------------------*
;*									*
;*  XMMControl -							*
;*									*
;*	Main Entry point for the Extended Memory Manager		*
;*									*
;*  ARGS:   AH = Function, AL = Optional parm				*
;*  RETS:   AX = Function Success Code, BL = Optional Error Code	*
;*  REGS:   AX, BX, DX and ES may not be preserved depending on func.   *
;*									*
;*  INTERNALLY REENTRANT						*
;*									*
;*----------------------------------------------------------------------*


XMMControl  proc   far

	jmp	short XCControlEntry	; For "hookability"
	nop				; NOTE: The jump must be a
	nop				;  short jump to indicate
	nop				;  the end of any hook chain.
					;  The nop's allow a far jump
					;  to be patched in.
XCControlEntry:

if keep_cs	;--------------------------------------------------------
	push	bp
	mov	bp,sp
	mov	bp,4[bp]		; get caller's cs
	mov	callers_cs,bp	        ;  (debug only)
	pop	bp
endif		;--------------------------------------------------------

	push    si
	push    di
	push	cx

	push    ds
	push    es
	pushf
	cld

	push    ds			; save ds in es
	pop	es			; NOTE: ES cannot be used for parms!

	push    cs			; ds=cs
	pop	ds
	assume	ds:_text

	push    ax			; save the function number

if debug_vers
	call	debug_dump
endif

	or	ah,ah			; GetXMSVersion?
	jz	XCCallFunc		; Yes, don't hook INT 15h yet

	and	ah, 7fh			; mask off Super bit
	cmp	ah,NumFns		; valid function number??
	jb	XCCheckHook
	pop	ax			; No, Un-preserve AX and return an error
	xor	ax,ax
	mov	bl,ERR_NOTIMPLEMENTED
	jmp	short XCExit

XCCheckHook:
	pushf				; Is INT 15h already hooked?
	cli				; This is a critical section

	cmp	word ptr [PrevInt15][2],0 ; Is the segment non-zero?
	jne     XCCheckVD

	push	dx			; save callers DX
	call	HookInt15		; claim all remaining ext mem
	pop	dx

XCCheckVD:
	popff				; End of critical section

	cmp	[fVDISK],0		; was VDISK found?
	je	XCCallFunc
	pop	ax			; Yes, Un-preserve AX and return error
	xor	ax,ax
	mov	bl,ERR_VDISKFOUND
	xor	dx,dx
	jmp	short XCExit

;	Call the appropriate API function.

XCCallFunc:
	pop	ax			; Restore AX
	push    ax			; save ax so functions get both ah & al
	mov	al,ah
	and	ax, 7fh
	shl	ax,1
ifdef debug_tsr
	shl	ax,1
endif
	mov	di,ax			; NOTE: DI cannot be used for parms!
	pop	ax			; restore callers ax for function

        ; In the TSR version, the function addresses are always in low
        ; memory, and the jump table entries are dwords.  In the DOS device
        ; driver version, the function addresses may be in low or high
        ; memory, and the jump table addresses are word offsets.

ifdef debug_tsr

        push    ax
        mov     ax, cs
        cmp     ControlJumpTable[di].sel, ax
        pop     ax
        je      NearXMSCall
        call    ControlJumpTable[di]
        jmp     short @f

NearXMSCall:
        call    ControlJumpTable[di].off

@@:

else
	mov	di,ControlJumpTable[di]	; get function address
	or	di,di
	jns	CallLowSegFn		; brif it's in the low segment

	cmp	fInHMA, 0		; is the hiseg in HMA ?
	jz	InLoMem
;
;------ Turn on the A20 line if it is off
;
	push	si
	push	di
	push	ax
	push	bx
	push	cx
	call	[pfnEnabA20]		; Note:  This is always necessary
	cmp	ax, 1
	pop	cx			; for the Memory Move function.  In
	pop	bx			; the case where this driver loads
	pop	ax			; high, it is necessary for all calls
	pop	di			; to the high segment.
	pop	si
	jne	a20_error

InLoMem:
	push	cs			; set up far return
	call	call_hi_in_di		; and call the function

	cmp	fInHMA, 0		; is the hiseg in HMA ?
	jz	XCExit

	push	ax			; save the registers which may be
	push	bx			; returning values
	call	[pfnDisabA20]		; and restore a20
	cmp	ax, 1
	pop	bx
	pop	ax

	je	short XCExit

a20_error:
	xor	ax, ax
	xor	dx, dx
	mov	bl, ERR_A20
	jmp	short XCExit

CallLowSegFn:
	call	di			; call routine in this segment

endif

XCExit:
;	if	debug_vers or tdump	;------------------------------------
;	pusha
;	call	dump_tables
;	popa
;	endif		;------------------------------------------------------

	popff				; NOTE: Flags must be restored
	pop	es			; immedately after call API functions.
	pop	ds

	pop	cx
	pop	di
	pop	si

;	if	debug_vers ;---------------------------------------------------
;	pushf
;	pusha
;	mov	al,'.'
;	call	cofa
;	mov	al,cs:byte ptr fun_number
;	sub	al,0bh			; don't get key on 0bh, 0ch or 0dh
;	cmp	al,2
;	jbe	no_keywait
;	mov	ah,1		; wait for console key now!!!!!!
;;	int	21h
;no_keywait:
;	popa
;	popf
;	endif		;------------------------------------------------------

	ret

XMMControl  endp

	if	tdump or debug_vers	;------------------------------------

fun_number	db	0		; function number for debug info

dump_tables:
	if	not tdump
	cmp	fun_number,9		; only display on allocate calls
	jnz	dd_done			;  unless full tdump is enabled
	endif
	mov	dx,offset heading
	mov	ah,9
	int	21h

	push	es
	mov	es,hiseg
	assume	es:funky
	mov	si,[KiddValley]
	mov	cx,[cHandles]
	mov	bx,SIZE Handle

xlup:
	mov	al,[si].Flags		; get flags
	cmp	al,4			; don't show UNUSED entries
	jz	x_entry_done

	mov	dx,offset msg_FREE
	cmp	al,1			; free?
	jz	x_showflags
	mov	dx,offset msg_USED
	cmp	al,2			; used?
	jz	x_showflags
	mov	dx,offset msg_BAD
x_showflags:
	mov	ah,9
	int	21h

	mov	al,[si].cLock		; get lock count
	call	hex_byte
	call	space

	mov	ax,[si].Base		; get base
	call	hex_word
	call	space

	mov	ax,[si].Len		; get length
	call	hex_word

	if	keep_cs
	call	space
	mov	ax,[si].Acs		; get the allocator's cs:
	call	hex_word
	endif

x_newline:
	mov	al,13
	call	cofa
	mov	al,10
	call	cofa

x_entry_done:
	add	si,bx
	loop	xlup

	pop	es
	assume	es:nothing
	mov	dx,offset donemsg
	mov	ah,9
	int	21h
dd_done:
	ret


heading		db	'Flags Lock Base Len CS:',13,10,'$'
msg_FREE	db	'FREE   $'
msg_USED	db	'USED   $'
msg_BAD		db	'BAD    $'
donemsg		db	'End of XMS table$'

	endif

	if	debug_vers


debug_dump	proc	near
	pusha
	mov	fun_number,ah	; save (non-reentrantly!) function number
;				;  so that we can display different debug
;				;  information on exit depending on which
;				;  function we've been doing
	mov	al,ah		; just display function number
	call	hex_nib
	popa
	ret

	if	0		; enable this if you want to see the
;				;  command block for memory moves
	cmp	ah,0bh		; memory move?
	jnz	debug_dump_done	; done if not
	pusha
	call	crlf
	mov	ax,es:2[si]	; get count-hi
	call	hex_word
	mov	ax,es:[si]	; get count-low
	call	hex_word
	add	si,4		; point to source address field

	mov	cx,2		; now display two handle/addresses
dd1:
	call	space
	lods	es:word ptr [si] ; get a handle
	call	hex_word
	mov	al,'-'
	call	cofa
	mov	ax,es:2[si]	; get high address
	call	hex_word
	mov	al,':'
	call	cofa
	lods	es:word ptr [si] ; get low address
	call	hex_word
	add	si,2		; skip to next entry for loop
	loop	dd1
	popa
debug_dump_done:
	endif
	ret
debug_dump	endp

	endif

	if	debug_vers or tdump

hex_word:
	push	ax
	mov	al,ah
	call	hex_byte
	pop	ax
hex_byte:
	push	ax
	shr	ax,4		; XMS present implies '286 or better
	call	hex_nib
	pop	ax
hex_nib:
	and	al,0fh
	add	al,90h
	daa
	adc	al,3ah
	daa
cofa:
;	mov	dl,al
;	mov	ah,2
;	int	21h
	mov	ah,0eh
	mov	bx,7
	int	10h
	ret

space:
	mov	al,' '
	jmp	cofa

crlf:
	mov	al,13
	call	cofa
	mov	al,10
	jmp	cofa

	endif		;------------------------------------------------------

;	little utility stub for calling routine in the other segment.
;	  called with the branch offset address in di
;	  a far return address is already on the stack.  Now branch to
;	  hiseg:(di)

	public	hiseg	; allow initialization code to relocate hiseg
hiseg	dw	funky

	public	call_hi_in_di
call_hi_in_di proc near
	push	hiseg
	push	di
call_hi_in_di endp
call_hi_far proc far
	ret
call_hi_far endp


;	Routines to enable and disable A20 by making (recursive) calls to
;	Himem's external XMMControl entry point.  Calling the external
;	entry point instead of internal routines allows XMS hook code to
;	see the A20 enable and disable calls.  This is important for
;	memory managers (like EMM386) that virtualize A20 when Himem is
;	using an A20 handler that the memory manager doesn't trap (for
;	example Zenith FASTGATE A20 hardware accessed via the ZBIOS A20
;	handler).

ExtEnabA20	proc	near

	mov	ah, 05				;local enable A20 service
	push	cs
	call	near ptr XMMControl
	ret

ExtEnabA20	endp

ExtDisabA20	proc	near

	mov	ah, 06				;local disable A20 service
	push	cs
	call	near ptr XMMControl
	ret

ExtDisabA20	endp


;*----------------------------------------------------------------------*
;*									*
;*  HookInt15 -								*
;*									*
;*	Insert the INT 15 hook						*
;*									*
;*  ARGS:   None							*
;*  RETS:   None							*
;*  REGS:   AX, BX, CX, DX, DI, SI, and Flags are clobbered		*
;*									*
;*  EXTERNALLY NON-REENTRANT						*
;*	Interrupts must be disabled before calling this function.	*
;*									*
;*----------------------------------------------------------------------*


HookInt15   proc    near

	push    es

	call    IsVDISKIn		; has a VDISK been installed?
	cmp	[fVDISK],0
	je	HINoVD			; No, continue
	pop	es			; Yes, return without hooking
	ret

HINoVD:
	mov	ah,88h			; Is 64K of Extended memory around?
	int	15h

ifdef WIN30COMPATIBLE
	cmp	ax,15*1024		; Limit himem.sys to using 15 meg
	jb	@f			;   of extended memory for apps
	mov	ax,15*1024		;   that don't deal with > 24 bit
@@:					;   addresses
endif

	sub	ax,[MemCorr]    	; 6300 Plus may have memory at FA0000h
	cmp	ax,64
	jb	HIInitMemory		; Less than 64K free?  Then no HMA.
	cmp	Int15MemSize, 0		; are we supporting int 15 memory
	jnz	HIInitMemory		; then we dont support HMA
	mov	[fHMAExists],1

HIInitMemory:

;	Init the first handle to be one huge free block.

	or	ax, ax			; don't do it if no Int 15 memory avail
	jz	HISkipInit

	mov	cx,1024			; base is just above 1 meg

	xor	bx, bx			; assume no HMA

	cmp	[fHMAExists],0		; Reserve room for HMA if it exists
	je	@f
	mov	bx, 64
@@:	cmp	bx, Int15MemSize
	jae	@f
	mov	bx, Int15MemSize
@@:	add	cx,bx
	sub     ax,bx
	xor	dx, dx
	mov	bx, dx

	mov	di, pAddMem
	push	cs
	call	call_hi_in_di

HISkipInit:

;	Save the current INT 15 vector.

	les     si,dword ptr pInt15Vector

;	Exchange the old vector with the new one.

	mov	ax,offset Int15Handler
	xchg    ax,es:[si][0]
	mov	word ptr [PrevInt15][0],ax
	mov	ax,cs
	xchg    ax,es:[si][2]
	mov	word ptr [PrevInt15][2],ax

	pop	es
	ret

HookInt15   endp

;*----------------------------------------------------------------------*
;*									*
;*  IsVDISKIn -								*
;*									*
;*	Looks for drivers which use the IBM VDISK method of allocating	*
;*  Extended Memory.  XMS is incompatible with the VDISK method.  It is *
;*  necessary to check two different locations since some programs only *
;*  one or the other, although they should do both.			*
;*									*
;*  ARGS:   None							*
;*  RETS:   None.  Sets "fVDISK" accordingly				*
;*  REGS:   AX, BX, CX, SI, DI and Flags are clobbered			*
;*									*
;*  INTERNALLY REENTRANT						*
;*									*
;*----------------------------------------------------------------------*

pVDISK	label   dword
	dw	00013h
	dw	0FFFFh

szVDISK	db	'VDISK'

IsVDISKIn   proc    near

;	Look for "VDISK" signature at offset 12h in Int 19h segment

	push	es

	xor	ax,ax
	mov	es,ax
	mov	es,es:[(19h * 4)+2]
	mov	di,12h
	mov	si,offset szVDISK
	mov	cx,5
	cld
	repz	cmpsb

	pop	es

	jz	IVIFoundIt

;	Look for "VDISK" starting at the 4th byte of extended memory.

	call    LocalEnableA20		; Turn on A20

	push	es

	les	di,cs:pVDISK		; set up the comparison
	mov	si,offset szVDISK
	mov	cx,5
	cld
	repz	cmpsb			; Do the comparison

	pop	es

	pushf
	call	LocalDisableA20
	popff

	jz	IVIFoundIt

	mov	[fVDISK],0		; No VDISK device found
	ret

IVIFoundIt:
	mov	[fVDISK],1		; "VDISK" was found
	ret

IsVDISKIn   endp


;*----------------------------------------------------------------------*
;*									*
;*  Int15Handler -							*
;*									*
;*	Hooks Function 88h to return zero as the amount of extended	*
;*	memory available in the system.					*
;*									*
;*	Hooks Function 87h and preserves the state of A20 across the	*
;*	block move.							*
;*									*
;*  ARGS:   AH = Function, AL = Subfunction				*
;*  RETS:   AX = 0 (if AH == 88h)					*
;*  REGS:   AX is clobbered						*
;*									*
;*----------------------------------------------------------------------*


Int15Handler proc   far

	cmp	ah,88h			; request == report free ext mem?
	je	I15ExtMem

	cmp	ah,87h			; Block move?
	je	I15BlkMov

	jmp     cs:[PrevInt15]		; continue down the int 15h chain

I15ExtMem:
	mov	ax, cs:Int15MemSize	; return 'free' Int 15h extended memory
	iret


I15BlkMov:
	cli				; Make sure interrupts are off

	sub	sp,4			; Make space for A20 flag & flags word
	pusha				; Preserve the caller's registers

	call	IsA20On 		; Get current A20 state

	mov	bp,sp			; Stk= [pusha] [fl] [a20] [ip] [cs] [fl]
	mov	[bp+18],ax		; Save A20 state
	mov	ax,[bp+24]		; Get caller's entry flags and save on
	mov	[bp+16],ax		;   stack, forms part of iret frame

	popa				; Restore the caller's registers

;	Simulate an interrupt to lower level Int 15h handler.  Note that
;	the flags image is already on the stack from code above.  The Int
;	15h handler may or may return with interrupts enabled.

	call	cs:[PrevInt15]

	push	ax			; Save returned AX
	pushf				; Save flags returned from lower level

	push	bp			; Stack =
	mov	bp,sp			;    [bp] [fl] [ax] [a20] [ip] [cs] [fl]
	mov	ax,[bp+2]		; Setup to pass lower level flags
	mov	[bp+12],ax		;   back to caller on iret
	cmp	word ptr [bp+6],0	; While we're here test old A20 state
	pop	bp
	pop	ax			; Discard flags
	pop	ax			; Restore AX

	jz	I15HExit		; A20 was off, don't mess with it

	cli				; A20 handlers called with ints off
	pusha				; Preserve previous handler's return
	mov     ax,1
	call	A20Handler		; turn A20 back on
	popa				; Restore the previous handler's return

I15HExit:
	add	sp,2			; 'pop' A20 state flag
	iret				; Uses flags from lower level handler

Int15Handler endp

;*----------------------------------------------------------------------------*
;*                                                                            *
;*  ISA15handler -                                                            *
;*                                                                            *
;*      Hooks Function AX=E801h                                               *
;*                                                                            *
;*  ARGS:   AH = Function, AL = Subfunction                                   *
;*  If AX=E801 then:                                                          *
;*      RETS:   AX = available extended memory <16M (int 15 function 88h)     *
;*              BX = available extended memory >16M if ISA machine            *
;*		other regs = E801h int 15 return values.		      *
;*                                                                            *
;*----------------------------------------------------------------------------*

ISA15handler proc   far

        cmp     ax,0E801h
	je	ISAOurs

        jmp     cs:[PrevISAInt15]      ; Continue down the Int 15h chain.

ISAOurs:
        pushf                               ; Simualate an interrupt
        call    cs:[PrevISAInt15]

        mov     bx,0                        ; if hooked 0 memory available >16M

	cmp	word ptr cs:[PrevInt15][2],0  ; if Int 15h/88h hooked, return
	je	ISAend			      ;   whatever it would return

	mov	ax, cs:[Int15MemSize]	    ;  return free INT 15 memory
					    ;	  just like Int 15h/88h
ISAend:
        iret

ISA15handler endp


;*----------------------------------------------------------------------*
;*									*
;*  RequestHMA -					FUNCTION 01h    *
;*									*
;*	Give caller control of the High Memory Area if it is available.	*
;*									*
;*  ARGS:   DX = HMA space requested in bytes				*
;*  RETS:   AX = 1 if the HMA was reserved, 0 otherwise.  BL = Error	*
;*  REGS:   AX, BX and Flags clobbered					*
;*									*
;*  INTERNALLY NON-REENTRANT						*
;*									*
;*----------------------------------------------------------------------*

winbug_fix	dw	0	; storage for windows bug workaround

RequestHMA  proc   near

	cli			; This is a non-reentrant function.
				; Flags are restored after the return.

	mov	bl,ERR_HMAINUSE

;	***************************
;	**  There's a problem with WIN386 2.11.  It calls XMS driver
;	**   incorrectly and then goes ahead and uses the memory
;	**   it didn't properly allocate.  In order to convince it
;	**   not to go ahead and use the extended memory, we must
;	**   fail this function when it calls us.  We know that
;	**   al=40h and dx=free memory returned from QueryExtMemory
;	**   when we're called from windows.  Hopefully no legitimate
;	**   caller will happen to have that exact same 24 bit code
;	**   in al/dx when they call this function because they will fail.
;	***************************

	cmp	al,40h		; called from win386 2.11?
	jnz	not_winbug
	cmp	dx,winbug_fix   ; dx=last result from QueryExtMem?
	jz	RHRetErr	; fail if so
not_winbug:

	cmp	[fHMAInUse],1   ; Is the HMA already allocated?
	je	RHRetErr

	mov	bl,ERR_HMANOTEXIST
	cmp	[fHMAExists],0  ; Is the HMA available?
	je	RHRetErr

	mov	bl,ERR_HMAMINSIZE
	cmp	dx,[MinHMASize] ; Is this guy allowed in?
	jb	RHRetErr

	mov	ax,1
	mov	[fHMAInUse],al  ; Reserve the High Memory Area
	xor     bl,bl		; Clear the error code
	ret

RHRetErr:
	xor     ax,ax		; Return failure with error code in BL
	ret

RequestHMA  endp


;*----------------------------------------------------------------------*
;*									*
;*  ReleaseHMA -					FUNCTION 02h    *
;*									*
;*	Caller is releasing control of the High Memory area		*
;*									*
;*  ARGS:   None							*
;*  RETS:   AX = 1 if control is released, 0 otherwise.	 BL = Error	*
;*  REGS:   AX, BX and Flags clobbered					*
;*									*
;*  INTERNALLY NON-REENTRANT						*
;*									*
;*----------------------------------------------------------------------*

ReleaseHMA  proc   near

	cli				; This is a non-reentrant function

	mov	al,[fHMAInUse]		; HMA currently in use?
	or	al,al
	jz	RLHRetErr	 	; No, return error

	mov	[fHMAInUse],0		; Release the HMA and return success
	mov	ax,1
	xor	bl,bl
	ret

RLHRetErr:
	xor	ax,ax
	mov	bl,ERR_HMANOTALLOCED
	ret

ReleaseHMA  endp


;*----------------------------------------------------------------------*
;*									*
;*  GlobalEnableA20 -					FUNCTION 03h    *
;*									*
;*	Globally enable the A20 line					*
;*									*
;*  ARGS:   None							*
;*  RETS:   AX = 1 if the A20 line is enabled, 0 otherwise.  BL = Error	*
;*  REGS:   AX, BX CX, SI, DI and Flags clobbered			*
;*									*
;*  INTERNALLY NON-REENTRANT						*
;*									*
;*----------------------------------------------------------------------*

GlobalEnableA20 proc near

	cli				; This is a non-reentrant function
	cmp	[fGlobalEnable],1	; Is A20 already globally enabled?
	je	GEARet

GEAEnable:
	call    LocalEnableA20		; Attempt to enable A20
	or	ax,ax
	jz	GEAA20Err

	mov	[fGlobalEnable],1	; Mark A20 global enabled

GEARet:
	mov	ax,1			; return success
	xor	bl,bl
	ret

GEAA20Err:
	mov	bl,ERR_A20		; some A20 error occurred
	xor	ax,ax
	ret
GlobalEnableA20 endp


;*----------------------------------------------------------------------*
;*									*
;*  GlobalDisableA20 -					FUNCTION 04h    *
;*									*
;*	Globally disable the A20 line					*
;*									*
;*  ARGS:   None							*
;*  RETS:   AX=1 if the A20 line is disabled, 0 otherwise.  BL = Error	*
;*  REGS:   AX, BX, CX, SI, DI and Flags are clobbered			*
;*									*
;*  INTERNALLY NON-REENTRANT						*
;*									*
;*----------------------------------------------------------------------*

GlobalDisableA20 proc near

	cli				; This is a non-reentrant function
	cmp	[fGlobalEnable],0	; Is A20 already global-disabled?
	je	GDARet

	call    LocalDisableA20		; Attempt to disable it
	or	ax,ax			;   (also zaps CX, SI, DI)
	jz	GDAA20Err

	mov	[fGlobalEnable],0	; mark as global-disabled

GDARet:
	mov	ax,1			; return success
	xor	bl,bl
	ret

GDAA20Err:
	mov	bl,ERR_A20		; some A20 error occurred
	xor	ax,ax
	ret
GlobalDisableA20 endp


;*----------------------------------------------------------------------*
;*									*
;*  LocalEnableA20 -					FUNCTION 05h    *
;*									*
;*	Locally enable the A20 line					*
;*									*
;*  ARGS:   None							*
;*  RETS:   AX = 1 if the A20 line is enabled, 0 otherwise.  BL = Error	*
;*  REGS:   AX, BX, CX, SI, DI and Flags clobbered			*
;*									*
;*  INTERNALLY NON-REENTRANT						*
;*									*
;*----------------------------------------------------------------------*


LocalEnableA20 proc near

	cli				; This is a non-reentrant function

	push	cx

	cmp	[fCanChangeA20],1	; Can we change A20?
	jne	LEARet			; No, don't touch A20

if	NUM_A20_RETRIES
	mov	A20Retries,NUM_A20_RETRIES
endif

	cmp	[EnableCount],0 	; If enable count == 0, go set it
	jz	LEASetIt		;   without bothering to check 1st

if	NUM_A20_RETRIES

LEATestIt:

endif
	call	IsA20On 		; If A20 is already on, don't do
	or	ax,ax			;   it again, but if it isn't on,
	jnz	LEAIncIt		;   then make it so

LEASetIt:
	mov	ax,1			; attempt to turn A20 on
	call    A20Handler		; Call machine-specific A20 handler

ife	NUM_A20_RETRIES
	or	ax,ax			; If we're not doing retries, then
	jz	LEAA20Err		;   use A20 handler's error return
else
	dec	A20Retries		; Any retries remaining?  If so, go
	jnz	LEATestIt		;   test current state, else return
	jmp	short LEAA20Err 	;   an error condition
endif

LEAIncIt:
	inc	[EnableCount]
LEARet:
	mov	ax,1			; return success
	xor	bl,bl
LEA9:
	pop	cx
	ret

LEAA20Err:
	mov	bl,ERR_A20		; some A20 error occurred

	xor	ax,ax
	if	debug_vers
disp_a20_err:
	pusha
	mov	al,'#'
	call	cofa
	popa
	endif
	jmp	short LEA9

LocalEnableA20 endp


;*----------------------------------------------------------------------*
;*									*
;*  LocalDisableA20 -					FUNCTION 06h    *
;*									*
;*	Locally disable the A20 line					*
;*									*
;*  ARGS:   None							*
;*  RETS:   AX=1 if the A20 line is disabled, 0 otherwise.  BL = Error	*
;*  REGS:   AX, BX, CX, SI, DI and Flags are clobbered			*
;*									*
;*  INTERNALLY NON-REENTRANT						*
;*									*
;*----------------------------------------------------------------------*


LocalDisableA20 proc near

	cli				; This is a non-reentrant function

	push	cx

	cmp	[fCanChangeA20],0	; Can we change A20?
	je	LDARet			; No, don't touch A20

	cmp	[EnableCount],0		; make sure the count's not zero
	je	LDAA20Err

if	NUM_A20_RETRIES

	mov	A20Retries,NUM_A20_RETRIES

LDATestIt:

endif
	call	IsA20On 		; Currently on or off?

	cmp     [EnableCount],1		; Only if the count = 1 should A20 be
	jnz     LDAStayOn		;   turned off, otherwise it stays on

	or	ax,ax			; If A20 is already off, don't
	jz	LDADecIt		;   bother to turn off again

	xor     ax,ax			; It's on, but should be turned off
	jmp     short LDASetIt

LDAStayOn:
	or	ax,ax			; A20 must stay on, if it is on, just
	jnz	LDADecIt		;   dec count, else force A20 on

	mov     ax,1
LDASetIt:
	call	A20Handler		; Call machine-specific A20 handler

ife	NUM_A20_RETRIES
	or	ax,ax			; If we're not doing retries, then
	jz	LDAA20Err		;   use A20 handler's error return
else
	dec	A20Retries		; Any retries remaining?  If so, go
	jnz	LDATestIt		;   test current state, else return
	jmp	short LDAA20Err 	;   an error condition
endif

LDADecIt:
	dec	[EnableCount]

LDARet:
	mov	ax,1			; return success
	xor	bl,bl
LDA9:
	pop	cx
	ret

LDAA20Err:
	mov     bl,ERR_A20		; some A20 error occurred
	xor     ax,ax
	if	debug_vers
	jmp	disp_a20_err
	endif
	jmp	short LDA9

LocalDisableA20 endp

;
;---------------------------------------------------------------------------
; procedure : FLclEnblA20
; procedure : FLclDsblA20
;
;		Called from the Block move functions. Serves 2 purposes
;		1. Interfaces a far call for a near routine
;		2. If funky is in HMA does a dummy success return
;---------------------------------------------------------------------------
;

FLclEnblA20	proc	far
		cmp	cs:fInHMA, 0
		jz	@f
		mov	ax, 1
		ret
@@:
		call	LocalEnableA20
		ret
FLclEnblA20	endp

FLclDsblA20	proc	far
		cmp	cs:fInHMA, 0
		jz	@f
		mov	ax, 1
		ret
@@:
		call	LocalDisableA20
		ret
FLclDsblA20	endp
;
;*----------------------------------------------------------------------*
;*									*
;*  IsA20On -						FUNCTION 07h    *
;*									*
;*	Returns the state of the A20 line				*
;*									*
;*  ARGS:   None							*
;*  RETS:   AX = 1 if the A20 line is enabled, 0 otherwise		*
;*	    BL = 0							*
;*  REGS:   AX, BL, CX, SI, DI and Flags clobbered			*
;*									*
;*  INTERNALLY REENTRANT						*
;*									*
;*----------------------------------------------------------------------*

if 0	;********************************************************************

LowMemory   label   dword	; Set equal to 0000:0080
	dw	00080h
	dw	00000h

HighMemory  label   dword
	dw	00090h		; Set equal to FFFF:0090
	dw	0FFFFh

else	;********************************************************************

CmpLoc	db	80h

endif	;********************************************************************


; NOTE: When this routine is called from the Int15 handler, ds is undefined.
;  Hence the CS: overrides on data references.


IsA20On     proc    near

	push	cx

	cmp	cs:[fA20Check],0    ; Does the installed A20 handler support
	jz	@f		    ;	an A20 on/off check routine?

	mov	ax,2		    ; yes, ask it to check the state
	call	A20Handler
	jmp	short IA20Exit
@@:
	push    ds
	push	es

if 0	;*******************************************************************

	xor	ax,ax		    ; assume A20 is off

	lds	si,cs:LowMemory     ; Compare the 4 words at 0000:0080
	les	di,cs:HighMemory    ;	with the 4 at FFFF:0090

	mov	cx,4
	cld
	repe    cmpsw

	jz	@f
	inc	ax		    ; must be on afterall
@@:
else	;*******************************************************************

	add	byte ptr cs:CmpLoc,08h	; change offset for this compare
	mov	al,byte ptr cs:CmpLoc
	and	ax,78h			; use 0, 8, 10, 18, ... 78, 0, ...
	mov	si,ax
	lea	di,[si+10h]		; offset 1 paragraph

	xor	ax,ax			; ax = ds = 0, es = FFFFh
	mov	ds,ax
	dec	ax
	mov	es,ax
	inc	ax

	mov	cx,4			; match up to 4 words
	cld
	repe    cmpsw

	jz	@f
	inc	ax			; must be on afterall, set ax = 1
@@:
endif	;*******************************************************************

	pop	es
	pop	ds

IA20Exit:
	xor	bl,bl		; return success

	pop	cx
	ret			; Yes, return A20 Disabled

IsA20On	endp


_text	ends
	end



