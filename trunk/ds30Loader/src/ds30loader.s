;------------------------------------------------------------------------------
; Title:			ds30 loader for PIC24FJ
;					Modified for Bus Pirate v2go, v3
;
; File description:	Main firmwarefile
;
; Copyright: 		Copyright � 2009, Mikael Gustafsson
;
; Version			1.0.2 november 2009
;
; Webpage: 			http://mrmackey.no-ip.org/elektronik/ds30loader/
;
; History:			1.0.2 Erase is now made just before write to increase reliability					
;					1.0.1 Fixed baudrate error check
;					1.0.0 Added flash verification
;						  Removed PIC24FxxKAyyy stuff, se separate fw
;						  Corrected buffer variable location to .bss
;						  Buffer is now properly sized
;					0.9.1 Removed initialization of stack limit register
;						  BRG is rounded instead of truncated
;						  Removed frc+pll option
;						  Added pps code
;						  Added baudrate error check
;					0.9.0 First version released, based on the dsPIC33F version
                                                              
;------------------------------------------------------------------------------

;-----------------------------------------------------------------------------
;    This file is part of ds30 Loader.
;
;    ds30 Loader is free software: you can redistribute it and/or modify
;    it under the terms of the GNU General Public License as published by
;    the Free Software Foundation.
;
;    ds30 Loader is distributed in the hope that it will be useful,
;    but WITHOUT ANY WARRANTY; without even the implied warranty of
;    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;    GNU General Public License for more details.
;
;    You should have received a copy of the GNU General Public License
;    along with ds30 Loader. If not, see <http://www.gnu.org/licenses/>.
;------------------------------------------------------------------------------ 

;------------------------------------------------------------------------------
;
; USAGE  USAGE  USAGE  USAGE  USAGE  USAGE  USAGE  USAGE  USAGE  USAGE  USAGE
;
;------------------------------------------------------------------------------
;
;
; To use other chip and/or configuration you need to do:
; * Select correct device in MPLAB IDE, menu Configure->Select Device
; * Include correct linker script
; * Search for xxx in settings.inc and check/alter those lines
; * If your device has the PPS(peripheral pin select) feature you need to configure that, template below, search for xxx
; * Put your own code in this file at designated areas, like i/o initialization etc. (optional)
; * No device specific errata workarounds are implemented in the code below
;
; Tabsize used is 4
;
;------------------------------------------------------------------------------


;------------------------------------------------------------------------------
; Register usage
;------------------------------------------------------------------------------
		;.equ	MIXED,		W0		;immediate
		.equ	DOERASE,	W1		;flag indicated erase should be done before next write
		.equ	WBUFPTR,	W2		;buffer pointer
		.equ	WCNT,		W3		;loop counter
		.equ	WADDR2,		W4		;memory pointer
		.equ	WADDR,		W5		;memory pointer		
		.equ	PPSTEMP1,	W6		;used to restore pps register
		.equ	PPSTEMP2,	W7		;used to restore pps register
		;.equ	UNUSED,		W8		;
		;.equ	UNUSED,		W9		;
		.equ	WDEL1,		W10		;delay outer
		.equ	WDEL2,		W11		;delay inner
		;.equ	UNUSED,		W12		;
		.equ	WCMD,		W13		;command
		.equ 	WCRC, 		W14		;checksum
		.equ	WSTPTR,		W15		;stack pointer


;------------------------------------------------------------------------------
; Includes
;------------------------------------------------------------------------------
		.include "settings.inc"	


;-----------------------------------------------------------------------------
; UARTs
;------------------------------------------------------------------------------ 
		.ifndef USE_UART1
			.ifndef USE_UART2
				.ifndef USE_UART3
					.ifndef USE_UART4
						.error "No uart is specified"
					.endif
				.endif
			.endif
		.endif
		
		.ifdef USE_UART1
			.ifdef USE_UART2
				.error "Multiple uarts specified"
			.endif
			.ifdef USE_UART3
				.error "Multiple uarts specified"
			.endif
			.ifdef USE_UART4
				.error "Multiple uarts specified"
			.endif

		   	.equ    UMODE,	    U1MODE					;uart mode
		   	.equ    USTA,  		U1STA					;uart status
		   	.equ    UBRG,		U1BRG					;uart baudrate
		   	.equ    UTXREG,		U1TXREG					;uart transmit
		   	.equ	URXREG,		U1RXREG					;uart receive
			.equ	UIFS,		IFS0					;uart interupt flag sfr
			.equ	URXIF,		U1RXIF					;uart received interupt flag
			.equ	UTXIF,		U1TXIF					;uart transmit interupt flag		   	
		.endif			

;------------------------------------------------------------------------------
; Constants, don�t change
;------------------------------------------------------------------------------
		.equ	VERMAJ,		1										/*firmware version major*/
		.equ	VERMIN,		0										/*fimrware version minor*/
		.equ	VERREV,		2										/*firmware version revision*/

		.equ 	HELLO, 		0xC1		
		.equ 	OK, 		'K'										/*erase/write ok*/
		.equ 	CHECKSUMERR,'N'										/*checksum error*/
		.equ	VERFAIL,	'V'										/*verification failed*/
		

		.equ	BLDELAY,	( BLTIME * (FCY / 1000) / (65536 * 7) )	/*delay berfore user application is loaded*/
		;.equ	UARTBR,		( (((FCY / BAUDRATE) / 8) - 1) / 2 )	/*baudrate*/
		.equ 	UARTBR, ((FCY/(4*BAUDRATE))-1)
		.equ	PAGESIZE,	512										/*words*/
		.equ	ROWSIZE,	64										/*words*/		
;		.equ	STARTADDR,	( FLASHSIZE - 2*(PAGESIZE * 2) ) 		/*place bootloader in 2nd last program page*/
		.equ	STARTADDR,	( FLASHSIZE - (2* (PAGESIZE)) ) 		/*place bootloader in last program page*/

;------------------------------------------------------------------------------
; Validate user settings
;------------------------------------------------------------------------------
		; Internal cycle clock
		.if FCY > 16000000
			.error "Fcy specified is out of range"
		.endif

		; Baudrate error
		.equ REALBR,	( FCY / (4 * (UARTBR+1)) )
		.equ BAUDERR,	( (1000 * ( BAUDRATE - REALBR)) / BAUDRATE )
		.if ( BAUDERR > 25) || (BAUDERR < -25 )
			.error "Baudrate error is more than 2.5%. Remove this check or try another baudrate and/or clockspeed."
		.endif 
		

;------------------------------------------------------------------------------
; Global declarations
;------------------------------------------------------------------------------
        .global __reset          	;the label for the first line of code, needed by the linker script


;------------------------------------------------------------------------------
; Uninitialized variables in data memory
;------------------------------------------------------------------------------
		.bss
buffer:	.space ( ROWSIZE * 3 + 1/*checksum*/ ) 


;------------------------------------------------------------------------------
; Send macro
;------------------------------------------------------------------------------
		.macro SendL char
			mov #\char, W0
			mov W0, UTXREG
		.endm
		

;------------------------------------------------------------------------------
; Start of code section in program memory
;------------------------------------------------------------------------------
		.section *, code, address(STARTADDR-4)
usrapp:	nopr						;these two instructions will be replaced
		nopr						;with a goto to the user app. by the pc program
		

;------------------------------------------------------------------------------
; Reset vector
;------------------------------------------------------------------------------
		.section *, code, address(STARTADDR)
__reset:mov 	#__SP_init, WSTPTR	;initalize the Stack Pointer


;------------------------------------------------------------------------------
; User specific entry code go here, see also user exit code section at end of file
;------------------------------------------------------------------------------
		bclr OSCCON, #SOSCEN
		bclr CLKDIV, #RCDIV0 ;set clock divider to 0
waitPLL:btss OSCCON, #LOCK		
		bra waitPLL ;wait for the PLL to lock

		mov #0xFFFF, W0 ;all pins to digital
		mov W0, AD1PCFG	

;jumper check test
		;setup the jumper check
		;enable input on PGx
		bclr LATB, #LATB1 ;rb1 low
		bset TRISB, #TRISB1 ;rb1 input
		bset CNPU1, #CN5PUE ;enable pullups on PGC/CN5/RB1
		;ground/output on PGx
		bclr LATB, #RB0 ;rb0 low
		bclr TRISB, #TRISB0 ;rb0 output
		;wait
		nop
		nop
		;check for jumper
		btsc PORTB,#RB1	;skip next instruction if RB1=0 (jumper)
		bra quit ;branch to the user application if RB1=0
		;remove timeout???

		;----------------------------------------------------------------------
		; UART pps config
		;----------------------------------------------------------------------
		.ifdef HAS_PPS
			;.error "UART pps is not configured. Read datasheet and configure pps."			;xxx remove this line			
			
			; ** IMPORTANT **
			;
			; THIS CODE IS JUST A TEMPLATE AND WILL MOST LIKELY NOT WORK FOR YOU, 
			; READ THE DATASHEET AND ALTER LINES MARKED WITH XXX
			;
			; ** IMPORTANT **
			
			; Backup, these are restored in exit code at end of file
			; Changes needs to be done in exit, search for xxx
setup:		mov		RPINR18, PPSTEMP1		;xxx
			mov		RPOR2, PPSTEMP2			;xxx

			; Receive, map pin to uart (RP5)
			bset	RPINR18, #U1RXR0		;xxx
			bclr	RPINR18, #U1RXR1		;xxx
			bset	RPINR18, #U1RXR2		;xxx
			bclr	RPINR18, #U1RXR3		;xxx
			bclr	RPINR18, #U1RXR4		;xxx
			
			; Transmit, map uart to pin (RPOR2bits.RP4R = 3)
			bset	RPOR2, #RP4R0			;xxx
			bset	RPOR2, #RP4R1			;xxx
			bclr	RPOR2, #RP4R2			;xxx
			bclr	RPOR2, #RP4R3			;xxx
			bclr	RPOR2, #RP4R4			;xxx		
		.endif	
		
		;MODE LED on during bootload 
		bset LATA, #LATA1 ;on
		bclr TRISA, #TRISA1 ;output

        			
;------------------------------------------------------------------------------
; Init
;------------------------------------------------------------------------------
		clr		DOERASE
		
		;UART
		mov		#UARTBR, W0 		;set	
		mov 	W0, UBRG			; baudrate
		bset	UMODE, #BRGH		;enable BRGH
		bset 	UMODE, #UARTEN		;enable UART
		bset 	USTA, #UTXEN		;enable TX


;------------------------------------------------------------------------------
; Receive hello
;------------------------------------------------------------------------------
		rcall 	Receive
		sub 	#HELLO, W0			;check
		bra 	nz, exit			; prompt


;------------------------------------------------------------------------------
; Send device id and firmware version
;------------------------------------------------------------------------------
		SendL 	DEVICEID
		SendL	VERMAJ
		SendL	(VERMIN*16 + VERREV)
		

;------------------------------------------------------------------------------
; Main
;------------------------------------------------------------------------------
		; Send ok
Main:	SendL 	OK

		; Init checksum
main1:	clr 	WCRC

	
		;----------------------------------------------------------------------
		; Receive address
		;----------------------------------------------------------------------
		; Upper byte
		rcall 	Receive
		mov 	W0, TBLPAG
		; High byte, use PR1 as temporary sfr
		rcall 	Receive		
		mov.b	WREG, PR1+1
		; Low byte, use PR1 as temporary sfr
		rcall 	Receive
		mov.b	WREG, PR1
		;
		mov		PR1, WREG
		mov		W0,	WADDR
		mov		W0, WADDR2
		
		
		;----------------------------------------------------------------------
		; Receive command
		;----------------------------------------------------------------------
		rcall 	Receive
		mov		W0, WCMD
		

		;----------------------------------------------------------------------
		; Receive nr of data bytes that will follow
		;----------------------------------------------------------------------
		rcall 	Receive				
		mov 	W0, WCNT
	

		;----------------------------------------------------------------------
		; Receive data		
		;----------------------------------------------------------------------
		mov 	#buffer, WBUFPTR
rcvdata:
		rcall 	Receive				
		mov.b 	W0, [WBUFPTR++]
		dec		WCNT, WCNT
		bra 	nz, rcvdata			;last byte received is checksum		
		
				
		;----------------------------------------------------------------------
		; Check checksum
		;----------------------------------------------------------------------
		cp0.b 	WCRC
		bra 	z, ptrinit
		SendL 	CHECKSUMERR
		bra 	main1			
		
	
		;----------------------------------------------------------------------
		; Init pointer
		;----------------------------------------------------------------------			
ptrinit:mov 	#buffer, WBUFPTR
		
		;----------------------------------------------------------------------
		; Check address
		;----------------------------------------------------------------------	
		;check that address does not overlap the bootloader
		;if(TBLPAG=0){ ;always 0 on this PIC (?)
		;write row size is fixed, no need to convert, just add rowsize to starting postion
		mov 	#ROWSIZE, WCNT		;load row size 
		;don't DEC the number so we can use bra NC
		;dec 	WCNT, WCNT			;subtract 1 from end position (write 10 bytes to 10 = end at 19)
		add 	WADDR, WCNT, W0		;find the end write address W0=(WADDR+ #ROWSIZE)
		mov #0xa900, W0
		mov 	#BLSTARTWD, WCNT	;load start word into WCNT
		;asr 	W0, #8, W0				;shift 8 bits off end
		;asr 	WCNT, #8, WCNT
		;if bootloader start word (WCNT) is > write end address (W0) then skip fail
		cp		WCNT, W0
		;sub 	WCNT, W0, W0		;w0=wcnt-w0 (w0=blstart-end write address)
		bra 	LEU, vfail				;send verification fail notice if write > bl start (= is ok because we don't DEC above)
										;could also bra Main to fail silently

				
		;----------------------------------------------------------------------
		; Check command
		;----------------------------------------------------------------------			
		; Write row			0x00 02 00 - 0x02 AB FA 
		btsc	WCMD,	#1		
		bra		erase
		; Else erase page
		mov		#0xffff, DOERASE
		bra		Main
		
			
		;----------------------------------------------------------------------		
		; Erase page
		;----------------------------------------------------------------------		
erase:	btss	DOERASE, #0
		bra		program		
		tblwtl	WADDR, [WADDR]		;"Set base address of erase block", equivalent to setting nvmadr/u in dsPIC30F?
		; Erase
		mov 	#0x4042, W0
		rcall 	Write	
		; Erase finished
		clr		DOERASE
		
		
		;----------------------------------------------------------------------		
		; Write row
		;----------------------------------------------------------------------		
program:mov 	#ROWSIZE, WCNT
		; Load latches
latlo:	tblwth.b 	[WBUFPTR++], [WADDR] 	;upper byte
		tblwtl.b	[WBUFPTR++], [WADDR++] 	;low byte
		tblwtl.b	[WBUFPTR++], [WADDR++] 	;high byte	
		dec 	WCNT, WCNT
		bra 	nz, latlo
		; Write flash row
		mov 	#0x4001, W0		
		rcall 	Write

		
		;----------------------------------------------------------------------		
		; Verify row
		;----------------------------------------------------------------------
		mov 	#ROWSIZE, WCNT
		mov 	#buffer, WBUFPTR	
		; Verify upper byte
verrow:	tblrdh.b [WADDR2], W0
		cp.b	W0, [WBUFPTR++]
		bra		NZ, vfail	
		; Verify low byte
		tblrdl.b [WADDR2++], W0
		cp.b	W0, [WBUFPTR++]
		bra		NZ, vfail
		; Verify high byte
		tblrdl.b [WADDR2++], W0
		cp.b	W0, [WBUFPTR++]
		bra		NZ, vfail
		; Loop
		dec		WCNT, WCNT
		bra 	nz, verrow
		; Verify completed without errors
		bra		Main	
		
			
		;----------------------------------------------------------------------
		; Verify fail
		;----------------------------------------------------------------------
vfail:	SendL	VERFAIL
		bra		main1		
		
				
;------------------------------------------------------------------------------
; Write
;------------------------------------------------------------------------------
Write:	mov 	W0, NVMCON
		mov 	#0x55, W0
		mov 	W0, NVMKEY
		mov 	#0xAA, W0
		mov 	W0, NVMKEY
		bset 	NVMCON, #WR
		nop
		nop	
		; Wait for erase/write to finish	
compl:	btsc	NVMCON, #WR		
		bra 	compl				
		return


;------------------------------------------------------------------------------
; Receive
;------------------------------------------------------------------------------
		; Init delay
Receive:mov 	#BLDELAY, WDEL1
		; Check for received byte
rpt1:	clr		WDEL2
rptc:	clrwdt						;clear watchdog
		btss 	USTA, #URXDA		
		bra 	notrcv
		mov 	URXREG, W0			
		add 	WCRC, W0, WCRC		;add to checksum
		return
 		; Delay
notrcv:	dec 	WDEL2, WDEL2
		bra 	nz, rptc
		dec 	WDEL1, WDEL1
		bra 	nz, rpt1
		; If we get here, uart receive timed out
        mov 	#__SP_init, WSTPTR	;reinitialize the Stack Pointer
        
		
;------------------------------------------------------------------------------
; Exit point, clean up and load user application
;------------------------------------------------------------------------------		
exit:	bclr	UIFS, #URXIF		;clear uart received interupt flag
		bclr	UIFS, #UTXIF		;clear uart transmit interupt flag
		bclr	USTA, #UTXEN		;disable uart transmit
		bclr 	UMODE, #UARTEN		;disable uart
		clr		PR1					;clear PR1 was used as temporary sfr
		;MODE LED off
		bclr LATA, #LATA1 ;off
		bset TRISA, #TRISA1 ;input
	
	
;------------------------------------------------------------------------------
; User specific exit code go here
;------------------------------------------------------------------------------
		.ifdef HAS_PPS
			;.error "PPS restoration is not configured."			;xxx remove this line
			mov		PPSTEMP1, RPINR18	;xxx restore 
			mov		PPSTEMP2, RPOR2		;xxx  pps settings
		.endif

quit:	;clean up from jumper test
		bclr CNPU1, #CN5PUE ;disable pullups on PGC/CN5/RB1
		bset TRISB, #TRISB0 ;rb0 back to input
		mov #0x0000, W0 ;clear pins to analog default
		mov W0, AD1PCFG	

;------------------------------------------------------------------------------
; Load user application
;------------------------------------------------------------------------------
        bra 	usrapp

	
;------------------------------------------------------------------------------
; End of code
;------------------------------------------------------------------------------
		.end

 
