	PAGE	,132

	TITLE	IOCTL - IOCTL system call
	NAME	IOCTL

;
;	Microsoft Confidential
;	Copyright (C) Microsoft Corporation 1991
;	All Rights Reserved.
;

;**	IOCTL system call.
;
;	$IOCTL
;
;	  Revision history:
;
;		Created: ARR 4 April 1983
;
;		GenericIOCTL added:		KGS	22 April 1985
;
;		A000	version 4.00	Jan. 1988
;
;		Used jump table to dispatch IOCTL functions. HKN 3/12/90
;


	.xlist
	.xcref
	include version.inc
	include dosseg.inc
	INCLUDE DOSSYM.INC
	INCLUDE DEVSYM.INC
	include bpb.inc
	include mult.inc
	include dpb.inc
	include sf.inc
	include vector.inc
	include curdir.inc
	include ioctl.inc
	.cref
	.list

	i_need	THISCDS,DWORD
	i_need	IOCALL,BYTE
	i_need	IOMED,BYTE
	i_need	IOSCNT,WORD
	i_need	IOXAD,DWORD
	I_need	RetryCount,WORD
	I_need	RetryLoop,WORD
	I_need	EXTERR_LOCUS,BYTE
	I_need	OPENBUF,BYTE
	I_need	ExtErr,WORD
	I_need	DrvErr,BYTE
	I_need	USER_IN_AX,WORD 		;AN000;
	I_need	Temp_Var2,WORD			;AN000;

	extrn	GetThisDrv:near

DOSCODE	SEGMENT
	ASSUME	SS:DOSDATA,CS:DOSCODE

BREAK <IOCTL - munge on a handle to do device specific stuff>
;---------------------------------------------------------------------------
;
;   Assembler usage:
;	    MOV     BX, Handle
;	    MOV     DX, Data
;
;	(or LDS     DX,BUF
;	    MOV     CX,COUNT)
;
;	    MOV     AH, Ioctl
;	    MOV     AL, Request
;	    INT     21h
;
;   AH = 0  Return a combination of low byte of sf_flags and device driver
;	    attribute word in DX, handle in BX:
;	    DH = high word of device driver attributes
;	    DL = low byte of sf_flags
;	 1  Set the bits contained in DX to sf_flags.  DH MUST be 0.  Handle
;	    in BX.
;	 2  Read CX bytes from the device control channel for handle in BX
;	    into DS:DX.  Return number read in AX.
;	 3  Write CX bytes to the device control channel for handle in BX from
;	    DS:DX.  Return bytes written in AX.
;	 4  Read CX bytes from the device control channel for drive in BX
;	    into DS:DX.  Return number read in AX.
;	 5  Write CX bytes to the device control channel for drive in BX from
;	    DS:DX.  Return bytes written in AX.
;	 6  Return input status of handle in BX. If a read will go to the
;	    device, AL = 0FFh, otherwise 0.
;	 7  Return output status of handle in BX. If a write will go to the
;	    device, AL = 0FFh, otherwise 0.
;	 8  Given a drive in BX, return 1 if the device contains non-
;	    removable media, 0 otherwise.
;	 9  Return the contents of the device attribute word in DX for the
;	    drive in BX.  0200h is the bit for shared.	1000h is the bit for
;	    network. 8000h is the bit for local use.
;	 A  Return 8000h if the handle in BX is for the network or not.
;	 B  Change the retry delay and the retry count for the system. BX is
;	    the count and CX is the delay.
;
;   Error returns:
;	    AX = error_invalid_handle
;	       = error_invalid_function
;	       = error_invalid_data
;
;-------------------------------------------------------------------------------
;
;   This is the documentation copied from DOS 4.0 it is much better
;   than the above
;
;	There are several basic forms of IOCTL calls:
;
;
;	** Get/Set device information:	**
;
;	ENTRY	(AL) = function code
;		  0 - Get device information
;		  1 - Set device information
;		(BX) = file handle
;		(DX) = info for "Set Device Information"
;	EXIT	'C' set if error
;		  (AX) = error code
;		'C' clear if OK
;		  (DX) = info for "Get Device Information"
;	USES	ALL
;
;
;	**  Read/Write Control Data From/To Handle  **
;
;	ENTRY	(AL) = function code
;		  2 - Read device control info
;		  3 - Write device control info
;		(BX) = file handle
;		(CX) = transfer count
;		(DS:DX) = address for data
;	EXIT	'C' set if error
;		  (AX) = error code
;		'C' clear if OK
;		  (AX) = count of bytes transfered
;	USES	ALL
;
;
;	**  Read/Write Control Data From/To Block Device  **
;
;	ENTRY	(AL) = function code
;		  4 - Read device control info
;		  5 - Write device control info
;		(BL) = Drive number (0=default, 1='A', 2='B', etc)
;		(CX) = transfer count
;		(DS:DX) = address for data
;	EXIT	'C' set if error
;		  (AX) = error code
;		'C' clear if OK
;		  (AX) = count of bytes transfered
;	USES	ALL
;
;
;	**  Get Input/Output Status  **
;
;	ENTRY	(AL) = function code
;		  6 - Get Input status
;		  7 - Get Output Status
;		(BX) = file handle
;	EXIT	'C' set if error
;		  (AX) = error code
;		'C' clear if OK
;		  (AL) = 00 if not ready
;		  (AL) = FF if ready
;	USES	ALL
;
;
;	**  Get Drive Information  **
;
;	ENTRY	(AL) = function code
;		  8 - Check for removable media
;		  9 - Get device attributes
;		(BL) = Drive number (0=default, 1='A', 2='B', etc)
;	EXIT	'C' set if error
;		  (AX) = error code
;		'C' clear if OK
;		  (AX) = 0/1 media is removable/fixed (func. 8)
;		  (DX) = device attribute word (func. 9)
;	USES	ALL
;
;
;	**  Get Redirected bit	**
;
;	ENTRY	(AL) = function code
;		  0Ah - Network stuff
;		(BX) = file handle
;	EXIT	'C' set if error
;		  (AX) = error code
;		'C' clear if OK
;		  (DX) = SFT flags word, 8000h set if network file
;	USES	ALL
;
;
;	**  Change sharer retry parameters  **
;
;	ENTRY	(AL) = function code
;		  0Bh - Set retry parameters
;		(CX) = retry loop count
;		(DX) = number of retries
;	EXIT	'C' set if error
;		  (AX) = error code
;		'C' clear if OK
;	USES	ALL
;
;
;   =================================================================
;
;	**  New Standard Control  **
;
;	ALL NEW IOCTL FACILITIES SHOULD USE THIS FORM.	THE OTHER
;	FORMS ARE OBSOLETE.
;
;   =================================================================
;
;	ENTRY	(AL) = function code
;		  0Ch - Control Function subcode
;		(BX) = File Handle
;		(CH) = Category Indicator
;		(CL) = Function within category
;		(DS:DX) = address for data, if any
;		(SI) = Passed to device as argument, use depends upon function
;		(DI) = Passed to device as argument, use depends upon function
;	EXIT	'C' set if error
;		  (AX) = error code
;		'C' clear if OK
;		  (SI) = Return value, meaning is function dependent
;		  (DI) = Return value, meaning is function dependent
;		  (DS:DX) = Return address, use is function dependent
;	USES	ALL
;
;    ============== Generic IOCTL Definitions for DOS 3.2 ============
;     (See inc\ioctl.inc for more info)
;
;	ENTRY	(AL) = function code
;		  0Dh - Control Function subcode
;		(BL) = Drive Number (0 = Default, 1= 'A')
;		(CH) = Category Indicator
;		(CL) = Function within category
;		(DS:DX) = address for data, if any
;		(SI) = Passed to device as argument, use depends upon function
;		(DI) = Passed to device as argument, use depends upon function
;
;	EXIT	'C' set if error
;		  (AX) = error code
;		'C' clear if OK
;		  (DS:DX) = Return address, use is function dependent
;	USES	ALL
;
;---------------------------------------------------------------------------

TABENT	macro ORDINAL, handler_address

;	.errnz	$-IOCTLJMPTABLE-2*ORDINAL
	DW	handler_address

	endm

IOCTLJMPTABLE	label	word
		TABENT	IOCTL_GET_DEVICE_INFO   , ioctl_getset_data	; 0
		TABENT	IOCTL_SET_DEVICE_INFO	, ioctl_getset_data   	; 1
		TABENT	IOCTL_READ_HANDLE	, ioctl_control_string	; 2
		TABENT	IOCTL_WRITE_HANDLE	, ioctl_control_string	; 3
		TABENT 	IOCTL_READ_DRIVE	, ioctl_get_dev		; 4
		TABENT 	IOCTL_WRITE_DRIVE	, ioctl_get_dev		; 5
		TABENT 	IOCTL_GET_INPUT_STATUS	, ioctl_status		; 6
		TABENT 	IOCTL_GET_OUTPUT_STATUS , ioctl_status		; 7
		TABENT 	IOCTL_CHANGEABLE?	, ioctl_rem_media	; 8
		TABENT 	IOCTL_DeviceLocOrRem?	, Ioctl_Drive_attr	; 9
		TABENT 	IOCTL_HandleLocOrRem?	, IOCTL_Handle_Redir	; a
		TABENT 	IOCTL_SHARING_RETRY	, Set_Retry_Parameters	; b
		TABENT 	GENERIC_IOCTL_HANDLE	, GENERICIOCTLHANDLE	; c
		TABENT 	GENERIC_IOCTL		, GENERICIOCTL		; d
		TABENT  IOCTL_GET_DRIVE_MAP 	, ioctl_drive_owner	; e
		TABENT  IOCTL_SET_DRIVE_MAP	, ioctl_drive_owner	; f
		TABENT 	IOCTL_QUERY_HANDLE	, query_handle_support	; 10
		TABENT 	IOCTL_QUERY_BLOCK	, query_device_support	; 11

	procedure   $IOCTL,NEAR
	ASSUME	DS:NOTHING,ES:NOTHING


	MOV	SI,DS			; Stash DS for calls 2,3,4 and 5
	context DS			;hkn; SS is DOSDATA

	cmp	al, 11h			; al must be between 0 & 11h
	ja	ioctl_bad_funj2		; if not bad function #

	push	AX			; Need to save AL for generic IOCTL
	mov	di, ax			; di NOT a PARM
	and	di, 0ffh		; di = al
	shl	di, 1			; di = index into jmp table
	pop	AX			; Restore AL for generic IOCTL

	jmp	word ptr cs:[IOCTLJMPTABLE+di]


ioctl_bad_funj2:
	JMP	ioctl_bad_fun


;--------------------------------------------------------------------------
;
; IOCTL: AL= 0,1
;
; ENTRY : DS = DOSDATA
;
;---------------------------------------------------------------------

ioctl_getset_data:

	invoke	SFFromHandle		; ES:DI -> SFT
	JNC	ioctl_check_permissions ; have valid handle
ioctl_bad_handle:
	error	error_invalid_handle

ioctl_check_permissions:
	CMP	AL,0
	MOV	AL,BYTE PTR ES:[DI].SF_FLAGS; Get low byte of flags
	JZ	ioctl_read		; read the byte

;**RMFHFE**	test	dh, 0feh		;AN000;MS.allow dh=1

	or	dh, dh
	JZ	ioctl_check_device	; can I set with this data?
	error	error_invalid_data	; no DH <> 0

ioctl_check_device:
	test	AL,devid_device 	; can I set this handle?

;**RMFHFE**	JZ	do_exception		; no, it is a file.

	jz	ioctl_bad_funj2
	OR	DL,devid_device 	; Make sure user doesn't turn off the
					;   device bit!! He can muck with the
					;   others at will.
	MOV	[EXTERR_LOCUS],errLOC_SerDev
	MOV	BYTE PTR ES:[DI].SF_FLAGS,DL  ;AC000;MS.; Set flags


;**RMFHFE**do_exception:
;**RMFHFE**	OR	BYTE PTR ES:[DI.sf_flags+1],DH;AN000;MS.;set 100H bit for disk full

	transfer    SYS_RET_OK



ioctl_read:
	MOV	[EXTERR_LOCUS],errLOC_Disk
	XOR	AH,AH
	test	AL,devid_device 	; Should I set high byte
	JZ	ioctl_no_high		; no
	MOV	[EXTERR_LOCUS],errLOC_SerDev
	LES	DI,ES:[DI.sf_devptr]	; Get device pointer
	MOV	AH,BYTE PTR ES:[DI.SDEVATT+1]	; Get high byte
ioctl_no_high:
	MOV	DX,AX
	invoke	get_user_stack
	MOV	[SI.user_DX],DX
	transfer    SYS_RET_OK


;--------------------------------------------------------------------------
;
; IOCTL: 2,3
;
; ENTRY : DS = DOSDATA
;	  Si = user's DS
;
;--------------------------------------------------------------------------

ioctl_control_string:

	invoke	SFFromHandle		; ES:DI -> SFT
	JC	ioctl_bad_handle	; invalid handle
	TESTB	ES:[DI].SF_FLAGS,devid_device	; can I?
	jz	ioctl_bad_funj2			; No it is a file
	MOV	[EXTERR_LOCUS],errLOC_SerDev
	LES	DI,ES:[DI.sf_devptr]	; Get device pointer
	XOR	BL,BL			; Unit number of char dev = 0
	JMP	ioctl_do_string


;--------------------------------------------------------------------------
;
; IOCTL: AL = 6,7
;
; ENTRY: DS = DOSDATA
;
;--------------------------------------------------------------------------

ioctl_status:

	MOV	AH,1
	SUB	AL,6			; 6=0,7=1
	JZ	ioctl_get_status
	MOV	AH,3
ioctl_get_status:
	PUSH	AX
	invoke	GET_IO_SFT
	POP	AX
	JNC	DO_IOFUNC
	JMP	ioctl_bad_handle	; invalid SFT

DO_IOFUNC:
	invoke	IOFUNC
	MOV	AH,AL
	MOV	AL,0FFH
	JNZ	ioctl_status_ret
	INC	AL
ioctl_status_ret:
	transfer SYS_RET_OK


;------------------------------------------------------------------------
;
; IOCTL: AL = B
;
; ENTRY: DS = DOSDATA
;
;-------------------------------------------------------------------------

Set_Retry_Parameters:
	MOV	RetryLoop,CX		; 0 retry loop count allowed
	OR	DX,DX			; zero retries not allowed
	JZ	IoCtl_Bad_Fun
	MOV	RetryCount,DX		; Set new retry count
doneok:
	transfer	Sys_Ret_Ok	; Done

;--------------------------------------------------------------------------
;
; Generic IOCTL entry point. AL = C, D, 10h, 11h
;
;	here we invoke the Generic IOCTL using the IOCTL_Req structure.
;	SI:DX -> Users Device Parameter Table
;	IOCALL -> IOCTL_Req structure
;
; 	If on entry AL >= IOCTL_QUERY_HANDLE the function is a
;	QueryIOCtlSupport call ELSE it's a standard generic IOCtl
;	call.
;
; BUGBUG: Don't push anything on the stack between GENERIOCTL: and 
;         the call to Check_If_Net because Check_If_Net gets our
;         return address off the stack if the drive is invalid.
;
;----------------------------------------------------------------------------

query_handle_support:	; Entry point for handles
GENERICIOCTLHANDLE:

	invoke	SFFromHandle		; Get SFT for device.
	jc	ioctl_bad_handlej

	TESTB	ES:[DI].SF_FLAGS,sf_isnet	; M031;
	jnz	ioctl_bad_fun		; Cannot do this over net.

	mov	[EXTERR_LOCUS],ErrLOC_Serdev
	les	di,es:[di.sf_devptr]	; Get pointer to device.
	jmp	short Do_GenIOCTL

query_device_support:	; Entry point for devices:
GENERICIOCTL:

	mov	[EXTERR_LOCUS],ErrLOC_Disk
	cmp	ch,IOC_DC		; Only disk devices are allowed to use
	jne	ioctl_bad_fun		; no handles with Generic IOCTL.

	CALL	Check_If_Net		; ES:DI := Get_hdr_block of device in BL
	JNZ	ioctl_bad_fun		; There are no "net devices", and they

Do_GenIOCTL:

	TESTB	ES:[DI.SDEVATT],DEV320	; Can device handle Generic IOCTL funcs
	jz	ioctl_bad_fun

	mov	byte ptr IOCALL.ReqFunc,GENIOCTL ;Assume real Request
	cmp	AL,IOCTL_QUERY_HANDLE	; See if this is just a query
	jl	SetIOCtlBlock

	TESTB	ES:[DI.SDEVATT],IOQUERY ; See if device supports a query
	jz	ioctl_bad_fun		  ; No support for query 

	mov	byte ptr IOCALL.ReqFunc,IOCTL_QUERY ; Just a query (5.00)

SetIOCtlBlock:
	PUSH	ES			; DEVIOCALL2 expects Device header block
	PUSH	DI			; in DS:SI
					; Setup Generic IOCTL Request Block
	mov	byte ptr IOCALL.ReqLen,(size IOCTL_Req)
	MOV	byte ptr IOCALL.ReqUnit,BL
	MOV	byte ptr IOCALL.MajorFunction,CH
	MOV	byte ptr IOCALL.MinorFunction,CL
	MOV	word ptr IOCALL.Reg_SI,SI
	MOV	word ptr IOCALL.Reg_DI,DI
	MOV	word ptr IOCALL.GenericIOCTL_Packet,DX
	MOV	word ptr IOCALL.GenericIOCTL_Packet + 2,SI

;hkn; IOCALL is in DOSDATA
	MOV	BX,offset DOSDATA:IOCALL

	PUSH	SS
	POP	ES

ASSUME DS:NOTHING			; DS:SI -> Device header.
	POP	SI
	POP	DS
	jmp	ioctl_do_IO		; Perform Call to device driver

ioctl_bad_fun:
	error	error_invalid_function

ioctl_bad_handlej:
	jmp	ioctl_bad_handle

;---------------------------------------------------------------------------
;
; IOCTL AL = 8
;
; ENTRY:  DS = DOSDATA
;
; BUGBUG: Don't push anything on the stack between ioctl_rem_media: and 
;         the call to Check_If_Net because Check_If_Net gets our
;         return address off the stack if the drive is invalid.
;
;-------------------------------------------------------------------------

ioctl_rem_media:

	CALL	Check_If_Net
	JNZ	ioctl_bad_fun		; There are no "net devices", and they
					;   certainly don't know how to do this
					;   call.
	TESTB	ES:[DI.SDEVATT],DEVOPCL ; See if device can
	JZ	ioctl_bad_fun		; NO

;hkn; SS override for IOCALL
	MOV	[IOCALL.REQFUNC],DEVRMD
	MOV	AL,REMHL
	MOV	AH,BL			; Unit number
	MOV	WORD PTR [IOCALL.REQLEN],AX
	XOR	AX,AX
	MOV	[IOCALL.REQSTAT],AX
	PUSH	ES
	POP	DS
ASSUME	DS:NOTHING
	MOV	SI,DI			; DS:SI -> driver
	PUSH	SS
	POP	ES

;hkn; IOCALL is in DOSDATA (msconst.asm)
	MOV	BX,OFFSET DOSDATA:IOCALL   ; ES:BX -> Call header
	SAVE	<DS,SI>
	invoke	DEVIOCALL2
	RESTORE <SI,DS>

;hkn; SS override
	MOV	AX,[IOCALL.REQSTAT]	; Get Status word
	AND	AX,STBUI		; Mask to busy bit
	MOV	CL,9
	SHR	AX,CL			; Busy bit to bit 0
	transfer    SYS_RET_OK

;-------------------------------------------------------------------------
;
; IOCTL: AL = 9
;
; ENTRY: DS = DOSDATA
;
;-------------------------------------------------------------------------

Ioctl_Drive_attr:
	mov	al, bl
	call	GetThisDrv
	jc	ioctl_drv_err
	call	Get_Driver_BL
	JC	ioctl_drv_err		; drive not valid

	mov	dx,word ptr es:[di.SDEVATT]	
					; get device attribute word
	MOV	BL,AL			; Phys letter to BL (A=0)

;hkn; SS override
	LES	DI,[THISCDS]
	TESTB	ES:[DI.curdir_flags],curdir_isnet
	JZ	IOCTLShare

;	Net devices don't return a device attribute word.
;	Bit 12 = 1, meaning net device, all others = 0.

	MOV	DX,1000h
IOCTLShare:
	Context DS
ASSUME	DS:NOTHING

;hkn; OPENBUF is in DOSDATA
	MOV	SI,OFFSET DOSDATA:OPENBUF
	ADD	BL,"A"
	MOV	[SI],BL
	MOV	WORD PTR [SI+1],003AH	; ":",0
	MOV	AX,0300H
	CLC
	INT	int_IBM
	JNC	ioctlLocal		; Not shared
	OR	DX,0200H		; Shared, bit 9
IOCTLLocal:
	TESTB	ES:[DI].curdir_flags,curdir_local
	JZ	ioctl_set_dx
	OR	DX,8000h

ioctl_set_DX:
	invoke	get_user_stack
	MOV	[SI.user_DX],DX
	transfer    SYS_RET_OK

ioctl_drv_err:

	error	error_invalid_drive

;--------------------------------------------------------------------------
; IOCTL: AL = A
;
; ENTRY: DS = DOSDATA
;
;--------------------------------------------------------------------------

Ioctl_Handle_redir:
	invoke	SFFromHandle		; ES:DI -> SFT
	JNC	ioctl_got_sft		; have valid handle
	jmp	ioctl_bad_handle

ioctl_got_sft:
	MOV	DX,ES:[DI].SF_FLAGS	; Get flags
	JMP	ioctl_set_DX		; pass dx to user and return

ioctl_bad_funj:
	JMP	ioctl_bad_fun

;--------------------------------------------------------------------------
;
; IOCTL: AL= 4,5
;
; ENTRY: DS = DOSDATA
;	 SI = user's DS
;
;
; BUGBUG: Don't push anything on the stack between ioctl_get_dev: and 
;         the call to Check_If_Net because Check_If_Net gets our
;         return address off the stack if the drive is invalid.
;
;-------------------------------------------------------------------------

ioctl_get_dev:
 	
	DOSAssume   <DS>,"IOCtl_Get_Dev"

	CALL	Check_If_Net
	JNZ	ioctl_bad_funj		; There are no "net devices", and they
					;   certainly don't know how to do this
					;   call.
ioctl_do_string:
	TESTB	ES:[DI.SDEVATT],DEVIOCTL; See if device accepts control
	JZ	ioctl_bad_funj		; NO
					; assume IOCTL read
	MOV	[IOCALL.REQFUNC],DEVRDIOCTL

	TEST	AL, 1			; is it func. 4/5 or 2/3
	JZ	ioctl_control_call	; it is read. goto ioctl_control_call

					; it is an IOCTL write
	MOV	[IOCALL.REQFUNC],DEVWRIOCTL

ioctl_control_call:
	MOV	AL,DRDWRHL
ioctl_setup_pkt:
	MOV	AH,BL			; Unit number
	MOV	WORD PTR [IOCALL.REQLEN],AX
	XOR	AX,AX
	MOV	[IOCALL.REQSTAT],AX
	MOV	[IOMED],AL
	MOV	[IOSCNT],CX
	MOV	WORD PTR [IOXAD],DX
	MOV	WORD PTR [IOXAD+2],SI
	PUSH	ES
	POP	DS
ASSUME	DS:NOTHING
	MOV	SI,DI			; DS:SI -> driver
	PUSH	SS
	POP	ES

;hkn; IOCALL is in DOSDATA
	MOV	BX,OFFSET DOSDATA:IOCALL   ; ES:BX -> Call header
ioctl_do_IO:
	invoke	DEVIOCALL2

;hkn; SS override for IOCALL
	TESTB	[IOCALL.REQSTAT],STERR	    ;Error?
	JNZ	Ioctl_string_err

;hkn; SS override
	MOV	AX,[IOSCNT]		; Get actual bytes transferred
	transfer    SYS_RET_OK

Ioctl_string_err:
	MOV	DI,[IOCALL.REQSTAT]	;Get Error
device_err:
	AND	DI,STECODE		; mask out irrelevant bits
	MOV	AX,DI
	invoke	SET_I24_EXTENDED_ERROR

;hkn; use SS override
;hkn;	mov	ax, cs:extErr
	mov	ax, ss:extErr
	transfer    SYS_RET_ERR

;--------------------------------------------------------------------------
; Proc name : Get_Driver_BL
;
;	DS is DOSDATA
;	BL is drive number (0=default)
;	Returns pointer to device in ES:DI, unit number in BL if carry clear
;	No regs modified
;
;---------------------------------------------------------------------------

Get_Driver_BL:

	DOSAssume   <DS>,"Get_Driver_BL"
    ASSUME ES:NOTHING

	PUSH	AX
	MOV	AL,BL			; Drive
	invoke	GETTHISDRV
	jc	ioctl_bad_drv
	XOR	BL,BL			; Unit zero on Net device
	MOV	[EXTERR_LOCUS],errLOC_Net
	LES	DI,[THISCDS]
	TESTB	ES:[DI.curdir_flags],curdir_isnet
	LES	DI,ES:[DI.curdir_devptr]; ES:DI -> Dpb or net dev
	JNZ	got_dev_ptr		; Is net
	MOV	[EXTERR_LOCUS],errLOC_Disk
	MOV	BL,ES:[DI.dpb_UNIT]	; Unit number
	LES	DI,ES:[DI.dpb_driver_addr]  ; Driver addr
got_dev_ptr:
	CLC
ioctl_bad_drv:
	POP	AX
	return

;-------------------------------------------------------------------------
; Proc Name : Check_If_Net:
;
;
; Checks if the device is over the net or not. Returns result in ZERO flag.
; If no device is found, the return address is popped off the stack, and a
; jump is made to ioctl_drv_err.
;
; On Entry:
; Registers same as those for Get_Driver_BL
;
; On Exit:
; ZERO flag	- set if not a net device
;		- reset if net device
; ES:DI -> the device
;
;
; BUGBUG: This function assumes the following stack setup on entry
;
;	  SP+2 -> Error return address
;	  SP   -> Normal return address
;
;-------------------------------------------------------------------------

Check_If_Net:
	CALL	Get_Driver_BL
	JC	ioctl_drv_err_pop	; invalid drive letter
	PUSH	ES
	PUSH	DI
	LES	DI,[THISCDS]
	TESTB	ES:[DI.curdir_flags],curdir_isnet
	POP	DI
	POP	ES
	ret

ioctl_drv_err_pop:
	pop	ax			; pop off return address
	jmp	ioctl_drv_err

ioctl_bad_funj3:
	jmp	ioctl_bad_fun

ioctl_string_errj:
	jmp	ioctl_string_err

;--------------------------------------------------------------------------
;
; IOCTL: AL = E, F
;
; ENTRY: DS = DOSDATA
;
;
; BUGBUG: Don't push anything on the stack between ioctl_drive_owner: and 
;         the call to Check_If_Net because Check_If_Net gets our
;         return address off the stack if the drive is invalid.
;
;--------------------------------------------------------------------------

ioctl_drive_owner:
	Call	Check_If_Net
	JNZ	ioctl_bad_funj3 	; There are no "net devices", and they
					;   certainly don't know how to do this
					;   call.
	TESTB	ES:[DI.SDEVATT],DEV320	; See if device can handle this
	JZ	ioctl_bad_funj3 	; NO
	mov	[IOCALL.REQFUNC],DEVGETOWN	; default to get owner
	cmp	al, 0eh			; Get Owner ?
	jz	GetOwner
	MOV	[IOCALL.REQFUNC],DEVSETOWN
GetOwner:
	MOV	AL,OWNHL
	MOV	AH,BL			; Unit number
	MOV	WORD PTR [IOCALL.REQLEN],AX
	XOR	AX,AX
	MOV	[IOCALL.REQSTAT],AX
	PUSH	ES
	POP	DS
ASSUME	DS:NOTHING
	MOV	SI,DI			; DS:SI -> driver
	PUSH	SS
	POP	ES

;hkn; IOCALL is in DOSDATA
	MOV	BX,OFFSET DOSDATA:IOCALL   ; ES:BX -> Call header
	SAVE	<DS,SI>
	invoke	DEVIOCALL2
	RESTORE <SI,DS>

;hkn; SS override
	TESTB	[IOCALL.REQSTAT],STERR
	jnz	ioctl_string_errj
	MOV	AL,BYTE PTR [IOCALL.REQUNIT]	; Get owner returned by device
						; owner returned is 1-based.
	transfer    SYS_RET_OK

EndProc $IOCTL


DOSCODE ENDS
	END


