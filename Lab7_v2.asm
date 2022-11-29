;***********************************************************
;*
;*	ECE375 Lab7: Rock Paper Scissors
;*
;* 	Requirement:
;* 		1. USART1 communication
;* 		2. Timer/counter1 Normal mode to create a 1.5-sec delay
;*
;***********************************************************
;*
;*	 Author: Kenneth Tang
;*			 Travis Fredrickon
;*	   Date: 2022-11-30
;*
;***********************************************************

.include "m32U4def.inc"         ; Include definition file

;***********************************************************
;*  Internal Register Definitions and Constants
;***********************************************************
.def    mpr		= r16		; Multi-Purpose Register
.def	ilcnt	= r17		; Inner Loop CouNT
.def	olcnt	= r18		; Outer Loop CouNT

.equ    SIGNAL_READY		= 0b1111_1111	; Signal for ready to start game
.equ	SIGNAL_NOT_READY	= 0b0000_0000	; Signal for not ready to start game
.equ	SIGNAL_ROCK			= 0b0000_0001	; Signal for Rock
.equ	SIGNAL_PAPER		= 0b0000_0010	; Signal for Paper
.equ	SIGNAL_SCISSORS		= 0b0000_0011	; Signal for Scissors

;***********************************************************
;*  Start of Code Segment
;***********************************************************
.cseg                           ; Beginning of code segment

;***********************************************************
;*  Interrupt Vectors
;***********************************************************
.org    $0000                   ; Beginning of Interrupt Vectors
		rjmp    INIT            ; Reset interrupt

.org	$0002					; INT0, PD4, cycle hand
		rcall	CYCLE_HAND
		reti

.org	$0004					; INT1, PD7, start game
		rcall	NEXT_GAME_STAGE
		reti

.org	$0028					; Timer/Counter1 Overflow
		rcall	TIMER	
		reti

.org	$0032					; USART1 RX Complete
		;rcall	
		reti

.org	$0036					; USART1 TX Complete
		;rcall	
		reti

.org    $0056                   ; End of Interrupt Vectors

;***********************************************************
;*  Program Initialization
;***********************************************************
INIT:
	; Stack Pointer
	ldi		mpr, high(RAMEND)
	out		SPH, mpr
	ldi		mpr, low(RAMEND)
	out		SPL, mpr

	; I/O Ports
		; PORTB
	ldi		mpr, $FF	; Configure for output
	out		DDRB, mpr	; ^
	ldi		mpr, $00	; Output 0
	out		PORTB, mpr	; ^

		; PORTD
	ldi     mpr, (1<<PD3 | 0b0000_0000) ; Set Port D pin 3 (TXD1) for output
	out     DDRD, mpr                   ; Set Port D pin 2 (RXD1) and others for input
	ldi		mpr, $FF					; Enable pull-up resistors
	out		PORTD, mpr					; ^

	; LCD
	call	LCDInit
	call	LCDBackLightOn

	; Data Memory Variables
		; TIMER_STAGE
	ldi		mpr, 4
	ldi		XH, high(TIMER_STAGE)
	ldi		XL,	low(TIMER_STAGE)
	st		X, mpr

		; GAME_STAGE
	ldi		mpr, 0
	ldi		XH, high(GAME_STAGE)
	ldi		XL,	low(GAME_STAGE)
	st		X, mpr

		; HANDs
	ldi		mpr, SIGNAL_ROCK
	ldi		XH, high(HAND_OPNT)
	ldi		XL,	low(HAND_OPNT)
	st		X, mpr
	ldi		XH, high(HAND_USER)
	ldi		XL,	low(HAND_USER)
	st		X, mpr

		; READY Flags
	ldi		mpr, SIGNAL_NOT_READY
	ldi		XH, high(READY_OPNT)
	ldi		XL,	low(READY_OPNT)
	st		X, mpr
	ldi		XH, high(READY_USER)
	ldi		XL,	low(READY_USER)
	st		X, mpr

	; USART1
		; Frame Format
			; UCSZ1[2:0]	= 011	= 8 Data Bits
			; USB1			= 1		= 2 Stop Bits
			; UMSEL1[1:0]	= 00	= Asynchronous
			; UPM1[1:0]		= 00	= Parity Disabled
		; Transmit (TX) and Recieve (RX)
			; RXCIE1		= 1		= RX Complete Interrupt Enabled
			; TXCIE1		= 1		= TX Complete Interrupt Enabled
			; UDRIE			= 1		= USART Data Register Empty Interrupt Enabled
			; RXEN1			= 1		= RX Enabled
			; TXEN1			= 1		= TX Enabled
			; UCPOL1		= 0		= TX Rising, RX Falling
		; Other
			; U2X1			= 1		= Double USART TX Speed
	ldi		mpr, (0<<RXC1 | 0<<TXC1 | 0<<UDRE1 | 0<<FE1 | 0<<DOR1 | 0<<UPE1 | 1<<U2X1 | 0<<MPCM1)
	sts		UCSR1A, mpr
	ldi		mpr, (1<<RXCIE1 | 1<<TXCIE1 | 1<<UDRIE1 | 1<<RXEN1 | 1<<TXEN1 | 0<<UCSZ12 | 0<<RXB81 | 0<<TXB81)
	sts		UCSR1B, mpr
	ldi		mpr, (0<<UMSEL11 | 0<<UMSEL10 | 0<<UPM11 | 0<<UPM10 | 1<<USBS1 | 1<<UCSZ11 | 1<<UCSZ10 | 0<<UCPOL1)
	sts		UCSR1C, mpr

		; Set baudrate at 2400bps
			; UBBR = clk / ( 8 * Baud ) - 1 = 207.333 = 207 = $00CF
				; clk	= 8MHz
				; Baud	= 2400bps
	ldi		mpr, $00
	sts		UBRR1H, mpr		; Note: Upper nibble not able to be used
	ldi		mpr, $CF
	sts		UBRR1L, mpr

	; TIMER/COUNTER1
		; WGM1[3:0]	= 0000	= Normal Mode
		; CS1[2:0]	= 100	= Prescale 256
	ldi		mpr, (0<<COM1A1 | 0<<COM1A0 | 0<<COM1B1 | 0<<COM1B0 | 0<<COM1C1 | 0<<COM1C0 | 0<<WGM11 | 0<<WGM10)
	sts		TCCR1A, mpr
	ldi		mpr, (0<<ICNC1 | 0<<ICES1 | 0<<WGM13 | 0<<WGM12 | 1<<CS12 | 0<<CS11 | 0<<CS10)
	sts		TCCR1B, mpr
	ldi		mpr, $00		; Not important
	sts		TCCR1C, mpr		; ^

	; Interrupts
		; ISC1[1:0]	= 10	= Trigger INT1 on Falling Edge
		; ISC0[1:0]	= 10	= Trigger INT0 on Falling Edge
	ldi		mpr, (1<<ISC31 | 0<<ISC30 | 1<<ISC21 | 0<<ISC20 | 1<<ISC11 | 0<<ISC10 | 1<<ISC01 | 0<<ISC00)
	sts		EICRA, mpr
	ldi		mpr, (0<<ISC61 | 0<<ISC60)
	sts		EICRB, mpr
		; INT1	= 1	= Enable INT1
		; INT0	= 0	= Disable INT0 (for now)
	ldi		mpr, (0<<INT6 | 0<<INT3 | 0<<INT2 | 1<<INT1 | 0<<INT0)
	out		EIMSK, mpr

	; Call NEXT_GAME_STAGE once to get it started
		; Will do GAME_STAGE_0
	rcall	NEXT_GAME_STAGE

	;Enable global interrupts
	sei

;***********************************************************
;*  Main Program
;***********************************************************
MAIN:
	; Loops indefinetely. Wait for interrupts.
	rjmp	MAIN

;***********************************************************
;*	Functions and Subroutines
;***********************************************************

;-----------------------------------------------------------
; Func:	
; Desc:	This is essentially the core function of the game.
;		Game stages change as follows:
;			0 -> 1		0 = IDLE
;			1 -> 2		1 = READY UP
;			2 -> 3		2 = SELECT HAND
;			3 -> 4		3 = REVEAL HANDS
;			4 -> 0		4 = RESULT
;-----------------------------------------------------------
NEXT_GAME_STAGE:
	; Save variables
	push	mpr
	push	XH
	push	XL

	; Branch based on current Game Stage
	ldi		XH, high(GAME_STAGE)
	ldi		XL, low(GAME_STAGE)
	ld		mpr, X

	cpi		mpr, 0
	breq	NEXT_GAME_STAGE_0
	cpi		mpr, 1
	breq	NEXT_GAME_STAGE_1
	cpi		mpr, 2
	breq	NEXT_GAME_STAGE_2
	cpi		mpr, 3
	breq	NEXT_GAME_STAGE_3
	cpi		mpr, 4
	breq	NEXT_GAME_STAGE_4

	; If no compare match, branch to end
	rjmp	NEXT_GAME_STAGE_END

NEXT_GAME_STAGE_0:						; IDLE
	rcall	GAME_STAGE_0				; Do stuff for this stage
	ldi		mpr, 1						; Update GAME_STAGE
	st		X, mpr						; ^
	rjmp	NEXT_GAME_STAGE_END			; Jump to end

NEXT_GAME_STAGE_1:						; READY UP
	ldi		mpr, (0<<INT1)				; Disable INT1 (PD7) because it's only use was to start the game
	out		EIMSK, mpr					; ^
	rcall	GAME_STAGE_1				; Do stuff for this stage
	ldi		mpr, 2						; Update GAME_STAGE
	st		X, mpr						; ^
	rjmp	NEXT_GAME_STAGE_END			; Jump to end
	
NEXT_GAME_STAGE_2:						; CHOOSE HAND
	rcall	GAME_STAGE_2				; Do stuff for this stage
	ldi		mpr, 3						; Update GAME_STAGE
	st		X, mpr						; ^
	ldi		mpr, (1<<INT0)				; Enable INT0 so hand can be changed
	out		EIMSK, mpr					; ^
	rjmp	NEXT_GAME_STAGE_END			; Jump to end

NEXT_GAME_STAGE_3:						; REVEAL HANDS
	ldi		mpr, (0<<INT0)				; Disable INT0 so hand cannot be changed
	out		EIMSK, mpr					; ^
	rcall	GAME_STAGE_3				; Do stuff for this stage
	ldi		mpr, 4						; Update GAME_STAGE
	st		X, mpr						; ^
	rjmp	NEXT_GAME_STAGE_END			; Jump to end

NEXT_GAME_STAGE_4:						; RESULT
	rcall	GAME_STAGE_4				; Do stuff for this stage
	ldi		mpr, 0						; Update GAME_STAGE, so it wraps around and next time it begins at the start
	st		X, mpr						; ^
	ldi		mpr, (1<<INT1)				; Enable INT1 (PD7) so it can start the game again
	out		EIMSK, mpr					; ^
	rjmp	NEXT_GAME_STAGE_END			; Jump to end

NEXT_GAME_STAGE_END:
	; Clear interrupt queue
	rcall	BUSY_WAIT
	ldi		mpr, 0b1111_1111
	out		EIFR, mpr

	; Restore variables
	pop		XL
	pop		XH
	pop		mpr

	; Return from function
	ret

;-----------------------------------------------------------
; Func:	
; Desc:	GAME_STAGE_0 = IDLE
;-----------------------------------------------------------
GAME_STAGE_0:
	; Save variables
	push	ZH
	push	ZL

	; Print to LCD
	ldi		ZH, high(STRING_IDLE<<1)
	ldi		ZL, low(STRING_IDLE<<1)
	rcall	LCD_ALL

	; Restore variables
	pop		ZL
	pop		ZH

	; Return from function
	ret

;-----------------------------------------------------------
; Func:	
; Desc:	GAME_STAGE_1 = READY UP
;-----------------------------------------------------------
GAME_STAGE_1:
	; Save variables
	push	ZH
	push	ZL

	; Print to LCD
	ldi		ZH, high(STRING_READY_UP<<1)
	ldi		ZL, low(STRING_READY_UP<<1)
	rcall	LCD_ALL

	; Send ready message to other board
		; For now just start timer to progress to next game stage
	rcall	TIMER

	; Restore variables
	pop		ZL
	pop		ZH

	; Return from function
	ret

;-----------------------------------------------------------
; Func:	
; Desc:	GAME_STAGE_2 = CHOOSE HAND
;-----------------------------------------------------------
GAME_STAGE_2:
	; Save variables
	push	ZH
	push	ZL

	; Start 6 second timer
	rcall	TIMER

	; Print to LCD
	ldi		ZH, high(STRING_CHOOSE_HAND<<1)
	ldi		ZL, low(STRING_CHOOSE_HAND<<1)
	rcall	LCD_TOP

	; Print to LCD
		; ROCK is the default choice
		; ___ function handles choosing hand
	ldi		ZH, high(STRING_ROCK<<1)
	ldi		ZL, low(STRING_ROCK<<1)
	rcall	LCD_BOTTOM

	; Restore variables
	pop		ZL
	pop		ZH

	; Return from function
	ret

;-----------------------------------------------------------
; Func:	
; Desc:	GAME_STAGE_3 = REVEAL HANDS
;-----------------------------------------------------------
GAME_STAGE_3:
	; Save variables
	push	mpr
	push	XH
	push	XL
	push	ZH
	push	ZL

	; Start 6 second timer
	rcall	TIMER
	
	; Branch based on Opponent Hand
	ldi		XH, high(HAND_OPNT)
	ldi		XL, low(HAND_OPNT)
	ld		mpr, X
	
	cpi		mpr, 1
	breq	GAME_STAGE_3_ROCK
	cpi		mpr, 2
	breq	GAME_STAGE_3_PAPER
	cpi		mpr, 3
	breq	GAME_STAGE_3_SCISSORS

	; If no compare match, branch to end
	rjmp	GAME_STAGE_3_END

GAME_STAGE_3_ROCK:
	; Print to LCD
	ldi		ZH, high(STRING_ROCK<<1)
	ldi		ZL, low(STRING_ROCK<<1)
	rcall	LCD_TOP

	; Jump to end
	rjmp	GAME_STAGE_3_END

GAME_STAGE_3_PAPER:
	; Print to LCD
	ldi		ZH, high(STRING_PAPER<<1)
	ldi		ZL, low(STRING_PAPER<<1)
	rcall	LCD_TOP

	; Jump to end
	rjmp	GAME_STAGE_3_END

GAME_STAGE_3_SCISSORS:
	; Print to LCD
	ldi		ZH, high(STRING_SCISSORS<<1)
	ldi		ZL, low(STRING_SCISSORS<<1)
	rcall	LCD_TOP

	; Jump to end
	rjmp	GAME_STAGE_3_END

GAME_STAGE_3_END:
	; Restore variables
	pop		ZL
	pop		ZH
	pop		XL
	pop		XH
	pop		mpr

	; Return from function
	ret

;-----------------------------------------------------------
; Func:	
; Desc:	GAME_STAGE_4 = RESULT
;-----------------------------------------------------------
GAME_STAGE_4:
	; Save variables
	push	mpr
	push	ilcnt
	push	XH
	push	XL
	push	ZH
	push	ZL

	; Start 6 second timer
	rcall	TIMER

	; Decide Won/Lost/Draw
		; Calculate result value
			; Won	= -2, 1
			; Lost	= -1, 2
			; Draw	= 0
	ldi		XH, high(HAND_USER)
	ldi		XL,	low(HAND_USER)
	ld		mpr, X
	ldi		XH, high(HAND_OPNT)
	ldi		XL,	low(HAND_OPNT)
	ld		ilcnt, X
	sub		mpr, ilcnt				; Result value stored in mpr

	; Branch based on result
	cpi		mpr, -2
	breq	GAME_STAGE_4_WON
	cpi		mpr, 1
	breq	GAME_STAGE_4_WON
	cpi		mpr, -1
	breq	GAME_STAGE_4_LOST
	cpi		mpr, 2
	breq	GAME_STAGE_4_LOST
	cpi		mpr, 0
	breq	GAME_STAGE_4_DRAW

	; If no compare match, jump to end
	rjmp	GAME_STAGE_4_END

GAME_STAGE_4_WON:
	; Print to LCD
	ldi		ZH, high(STRING_WON<<1)
	ldi		ZL, low(STRING_WON<<1)
	rcall	LCD_TOP

	; Jump to end
	rjmp	GAME_STAGE_4_END

GAME_STAGE_4_LOST:
	; Print to LCD
	ldi		ZH, high(STRING_LOST<<1)
	ldi		ZL, low(STRING_LOST<<1)
	rcall	LCD_TOP

	; Jump to end
	rjmp	GAME_STAGE_4_END

GAME_STAGE_4_DRAW:
	; Print to LCD
	ldi		ZH, high(STRING_DRAW<<1)
	ldi		ZL, low(STRING_DRAW<<1)
	rcall	LCD_TOP

	; Jump to end
	rjmp	GAME_STAGE_4_END

GAME_STAGE_4_END:
	; Restore variables
	pop		ZL
	pop		ZH
	pop		XL
	pop		XH
	pop		ilcnt
	pop		mpr

	; Return from function
	ret

;-----------------------------------------------------------
; Func:	
; Desc:	
;-----------------------------------------------------------
TIMER:
	; Save variables
	push	mpr
	push	XH
	push	XL

	; Set/Reset starting value
		; Value = Max + 1 - ( Delay * clk ) / Prescale = 18661 = $48E5
			; Max	= $FFFF = 65535
			; Delay = 1.5s
			; clk	= 8MHz
			; Prescale	= 256
	ldi		mpr, $48		; Write to high byte first
	sts		TCNT1H, mpr		; ^
	ldi		mpr, $E5		; Write to low byte second
	sts		TCNT1L, mpr		; ^

	; Load in TIMER_STAGE
	ldi		XH, high(TIMER_STAGE)
	ldi		XL,	low(TIMER_STAGE)
	ld		mpr, X

	; Branch based on current TIMER_STAGE
	cpi		mpr, 4
	breq	TIMER_4
	cpi		mpr, 3
	breq	TIMER_3
	cpi		mpr, 2
	breq	TIMER_2
	cpi		mpr, 1
	breq	TIMER_1
	cpi		mpr, 0
	breq	TIMER_0

	; If no compare match, branch to end
	rjmp	TIMER_END

TIMER_4:						; Start timer
	ldi		mpr, (1<<TOIE1)		; TOIE1	= 1	= Overflow Interrupt Enabled
	sts		TIMSK1, mpr			; ^
	ldi		mpr, 3				; Update TIMER_STAGE
	st		X, mpr				; ^
	in		mpr, PINB			; Update LEDs
	andi	mpr, 0b0000_1111	; ^
	ori		mpr, 0b1111_0000	; ^
	out		PORTB, mpr			; ^
	rjmp	TIMER_END			; Jump to end

TIMER_3:
	ldi		mpr, 2				; Update TIMER_STAGE
	st		X, mpr				; ^
	in		mpr, PINB			; Update LEDs
	andi	mpr, 0b0000_1111	; ^
	ori		mpr, 0b0111_0000	; ^
	out		PORTB, mpr			; ^
	rjmp	TIMER_END			; Jump to end

TIMER_2:
	ldi		mpr, 1				; Update TIMER_STAGE
	st		X, mpr				; ^
	in		mpr, PINB			; Update LEDs
	andi	mpr, 0b0000_1111	; ^
	ori		mpr, 0b0011_0000	; ^
	out		PORTB, mpr			; ^
	rjmp	TIMER_END			; Jump to end

TIMER_1:
	ldi		mpr, 0				; Update TIMER_STAGE
	st		X, mpr				; ^
	in		mpr, PINB			; Update LEDs
	andi	mpr, 0b0000_1111	; ^
	ori		mpr, 0b0001_0000	; ^
	out		PORTB, mpr			; ^
	rjmp	TIMER_END			; Jump to end

TIMER_0:						; End timer
	ldi		mpr, (0<<TOIE1)		; TOIE1	= 0	= Overflow Interrupt Disabled
	sts		TIMSK1, mpr			; ^
	ldi		mpr, 4				; Update TIMER_STAGE, so it wraps around and next time it begins at the start
	st		X, mpr				; ^
	in		mpr, PINB			; Update LEDs
	andi	mpr, 0b0000_1111	; ^
	ori		mpr, 0b0000_0000	; ^
	out		PORTB, mpr			; ^
	rcall	NEXT_GAME_STAGE		; Update GAME_STAGE
	rjmp	TIMER_END			; Jump to end

TIMER_END:
	; Restore variables
	pop		XL
	pop		XH
	pop		mpr

	; Return from function
	ret

;-----------------------------------------------------------
; Func:	
; Desc:
;-----------------------------------------------------------
CYCLE_HAND:
; Save variables
	push	mpr
	push	XH
	push	XL
	push	ZH
	push	ZL

	; Load in HAND_USER
	ldi		XH, high(HAND_USER)
	ldi		XL,	low(HAND_USER)
	ld		mpr, X

	; Change hand based on current hand
	cpi		mpr, SIGNAL_ROCK
	breq	CYCLE_HAND_PAPER
	cpi		mpr, SIGNAL_PAPER
	breq	CYCLE_HAND_SCISSORS
	cpi		mpr, SIGNAL_SCISSORS
	breq	CYCLE_HAND_ROCK

	; If no compare match, jump to end
	rjmp	CYCLE_HAND_END

CYCLE_HAND_ROCK:							; Change to ROCK
	; Change Data Memory variable HAND_USER
	ldi		mpr, SIGNAL_ROCK
	st		X, mpr

	; Print to LCD
	ldi		ZH, high(STRING_ROCK<<1)		; Point Z to string
	ldi		ZL, low(STRING_ROCK<<1)			; ^
	rcall	LCD_BOTTOM

	; Jump to end
	rjmp	CYCLE_HAND_END

CYCLE_HAND_PAPER:							; Change to PAPER
	; Change Data Memory variable HAND_USER
	ldi		mpr, SIGNAL_PAPER
	st		X, mpr

	; Print to LCD
	ldi		ZH, high(STRING_PAPER<<1)		; Point Z to string
	ldi		ZL, low(STRING_PAPER<<1)		; ^
	rcall	LCD_BOTTOM

	; Jump to end
	rjmp	CYCLE_HAND_END

CYCLE_HAND_SCISSORS:						; Change to SCISSORS
	; Change Data Memory variable HAND_USER
	ldi		mpr, SIGNAL_SCISSORS
	st		X, mpr

	; Print to LCD
	ldi		ZH, high(STRING_SCISSORS<<1)	; Point Z to string
	ldi		ZL, low(STRING_SCISSORS<<1)		; ^
	rcall	LCD_BOTTOM

	; Jump to end
	rjmp	CYCLE_HAND_END

CYCLE_HAND_END:
	; Clear interrupt queue
	rcall	BUSY_WAIT
	ldi		mpr, 0b1111_1111
	out		EIFR, mpr

	; Restore variables
	pop		ZL
	pop		ZH
	pop		XL
	pop		XH
	pop		mpr

	; Return from function
	ret

;-----------------------------------------------------------
; Func:	
; Desc:	Assumes Z already points to string.
;-----------------------------------------------------------
LCD_ALL:
	; Save variables
	push	mpr
	push	ilcnt
	push	XH
	push	XL

	; Set parameters
	ldi		XH, $01		; Point X to LCD top line
	ldi		XL, $00		; ^
	ldi		ilcnt, 32	; Loop 32 times for 32 characters

LCD_ALL_LOOP:
	; Load in characters
	lpm		mpr, Z+
	st		X+, mpr
	dec		ilcnt
	brne	LCD_ALL_LOOP

	; Write to LCD
	call	LCDWrite

	; Restore variables
	pop		XL
	pop		XH
	pop		ilcnt
	pop		mpr

	; Return from function
	ret

;-----------------------------------------------------------
; Func:	
; Desc:	Assumes Z already points to string.
;-----------------------------------------------------------
LCD_TOP:
	; Save variables
	push	mpr
	push	ilcnt
	push	XH
	push	XL

	; Set parameters
	ldi		XH, $01		; Point X to LCD top line
	ldi		XL, $00		; ^
	ldi		ilcnt, 16	; Loop 16 times for 16 characters

LCD_TOP_LOOP:
	; Load in characters
	lpm		mpr, Z+
	st		X+, mpr
	dec		ilcnt
	brne	LCD_TOP_LOOP

	; Write to LCD
	call	LCDWrite

	; Restore variables
	pop		XL
	pop		XH
	pop		ilcnt
	pop		mpr

	; Return from function
	ret
	
;-----------------------------------------------------------
; Func:	
; Desc:	Assumes Z already points to string.
;-----------------------------------------------------------
LCD_BOTTOM:
	; Save variables
	push	mpr
	push	ilcnt
	push	XH
	push	XL

	; Set parameters
	ldi		XH, $01		; Point X to LCD bottom line
	ldi		XL, $10		; ^
	ldi		ilcnt, 16	; Loop 16 times for 16 characters

LCD_BOTTOM_LOOP:
	; Load in characters
	lpm		mpr, Z+
	st		X+, mpr
	dec		ilcnt
	brne	LCD_BOTTOM_LOOP

	; Write to LCD
	call	LCDWrite

	; Restore variables
	pop		XL
	pop		XH
	pop		ilcnt
	pop		mpr

	; Return from function
	ret

;----------------------------------------------------------------
; Func:	BUSY_WAIT
; Desc:	A wait loop that is 16 + 159975*waitcnt cycles or roughly
;		mpr*10ms.  Just initialize wait for the specific amount
;		of time in 10ms intervals. Here is the general eqaution
;		for the number of clock cycles in the wait loop:
;		((3 * ilcnt + 3) * olcnt + 3) * mpr + 13 + call
;----------------------------------------------------------------
BUSY_WAIT:
	; Save variables
	push    mpr
	push    ilcnt
	push	olcnt
	
	ldi		mpr, 15
BUSY_WAIT_LOOP:
	ldi     olcnt, 224		; Load olcnt register
BUSY_WAIT_OLOOP:
	ldi     ilcnt, 237		; Load ilcnt register
BUSY_WAIT_ILOOP:
	dec		ilcnt			; Decrement ilcnt
	brne	BUSY_WAIT_ILOOP	; Continue Inner Loop
	dec		olcnt			; Decrement olcnt
	brne	BUSY_WAIT_OLOOP	; Continue Outer Loop
	dec		mpr
	brne	BUSY_WAIT_LOOP

	; Restore variables
	pop		olcnt
	pop		ilcnt
	pop		mpr

	; Return from function
	ret

;------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
; Kenny's USART
;------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

SEND_READY: ; Here we need to send a message via USART
	; Save variables
	push mpr
	push XH
	push XL
	push ZH
	push ZL

	; Wait
	rcall	BUSY_WAIT
	
	; Ready up	
	ldi		XH, high(READY_USER)			; Load User's ready flag
	ldi		XL, low(READY_USER)				; ^
	ldi		mpr, 1							; Store a 1 to the ready flag
	st		X, mpr							; ^
	ldi		ZH, high(STRING_READY_UP<<1)	; Print to LCD
	ldi		ZL, low(STRING_READY_UP<<1)		; ^
	call	LCD_ALL							; ^

	;Transmit via USART;
 READY_TRANSMIT:
	lds     mpr, UCSR1A					; Load in USART status register
	sbrs    mpr, UDRE1					; Check the UDRE1 flag
	rjmp    READY_TRANSMIT				; Loop back until data register is empty

	ldi     mpr, SIGNAL_READY				; Send the start message to the other board
	sts     UDR1, mpr

	; Clear interrupt queue
	ldi		mpr, 0b_1111
	out		EIFR, mpr

	; Restore variables
	pop		ZL
	pop		ZH
	pop		XL
	pop		XH
	pop		mpr

	; Return from function
	ret

MESSAGE_RECEIVE:
	;----------------------------------------------------------------
	; Func:	Message Receive
	; Desc:	After receiving data, this function decides what to do with it
	;		It performs checks on it to see what was sent in then branches
	;		to the appropriate function.
	;----------------------------------------------------------------
	
	; Save variables
	push mpr
	push ZH
	push ZL
	
	; Turn interrupts off
	cli

	; Read message in UDR1
	lds		mpr, UDR1				; Read the incoming data
	ldi		olcnt, SIGNAL_READY
	cpse	mpr, olcnt
	rjmp	MR_R2					; Skipped if equal
	call	RECEIVE_START			; Go to receive start

 MR_R2:
	; Other checks here

	; Turn interrupts back on
	sei
	
	; Restore variables
	pop ZL
	pop ZH
	pop mpr
	ret

;----------------------------------------------------------------
; Func:	
; Desc:	
;		
;----------------------------------------------------------------
RECEIVE_START:
	; Save variables
	push	mpr
	push	XH
	push	XL

	; Function
	ldi		mpr, 1					; Change Opponent's ready flag to 1
	ldi		XH, high(READY_OPNT)	; ^
	ldi		XL, low(READY_OPNT)		; ^
	st		X, mpr					;
	call	TRANSMIT_CHECK			; Check to see if we should start

	; Restore variables
	pop XL
	pop XH
	pop mpr

	; Return from function
	ret

;----------------------------------------------------------------
; Func:	
; Desc:	
;		
;----------------------------------------------------------------
LED_TOGGLE:
	; Save variables
	push	mpr
	push	ilcnt

	; Function
	ldi		ilcnt, 0b1000_0000
	in		mpr, PINB
	eor		mpr, ilcnt
	out		PORTB, mpr
	
	; Restore variables
	pop		ilcnt
	pop		mpr

	; Return from function
	ret

;----------------------------------------------------------------
; Func:	Transmit Check
; Desc:	Does a status check after a message has been transmitter on USART1
;----------------------------------------------------------------
TRANSMIT_CHECK:
	; Save variables
	push	mpr
	push	ilcnt
	push	XH
	push	XL

	; Check to see if we should start the game
	ldi		XH, high(READY_USER)	; Load both ready flags
	ldi		XL, low(READY_USER)		; ^
	ld		mpr, X					; ^
	ldi		XH, high(READY_OPNT)	; ^
	ldi		XL, low(READY_OPNT)		; ^
	ld		ilcnt, X				; ^
	cpse	mpr, ilcnt				; Compare the ready flags
	rjmp	TRANSMIT_CHECK_END		; If they aren't equal jump to end
	call	NEXT_GAME_STAGE			; ^ Else increment game stage

 TRANSMIT_CHECK_END:
	; Other checks

	; Restore variables
	pop		XL
	pop		XH
	pop		ilcnt
	pop		mpr

	; Return from function
	ret

;------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
; Kenny's USART end
;------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

;***********************************************************
;*	Stored Program Data
;***********************************************************
STRING_IDLE:
	.DB		"Welcome!        Please press PD7"
STRING_READY_UP:
	.DB		"Ready. Waiting  for opponent    "
STRING_CHOOSE_HAND:
	.DB		"Choose your hand"
STRING_ROCK:
	.DB		"Rock            "
STRING_PAPER:
	.DB		"Paper           "
STRING_SCISSORS:
	.DB		"Scissors        "
STRING_WON:
	.DB		"You won!        "
STRING_LOST:
	.DB		"You lost        "
STRING_DRAW:
	.DB		"Draw            "

;***********************************************************
;*	Data Memory Allocation
;***********************************************************
.dseg
.org	$0200		; Idk why this number, seems big enough

TIMER_STAGE:			; TIMER_STAGE value for timer loop and LED display
	.byte 1
GAME_STAGE:			; Indicates the current stage the game is in
	.byte 1
HAND_OPNT:			; Opponent choice: Rock / Paper / Scissors
	.byte 1
HAND_USER:			; User choice: Rock / Paper / Scissors
	.byte 1
READY_OPNT:			; Opponent ready
	.byte 1
READY_USER:			; User ready
	.byte 1

;***********************************************************
;*	Additional Program Includes
;***********************************************************
.include "LCDDriver.asm"		; Include the LCD Driver