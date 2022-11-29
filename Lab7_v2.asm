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
.def    mpr		= r16			; Multi-Purpose Register
.def	ilcnt	= r17			; Inner Loop CouNT
.def	olcnt	= r18			; Outer Loop CouNT

.equ    SIG_READY		= 0b1111_1111	; Signal for ready to start game
.equ	SIG_NOT_READY	= 0b0000_0000	; Signal for not ready to start game
.equ	SIG_ROCK		= 0b0000_0001	; Signal for Rock
.equ	SIG_PAPER		= 0b0000_0010	; Signal for Paper
.equ	SIG_SCISSORS	= 0b0000_0011	; Signal for Scissors

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
		;rcall
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
		; PORTB for output
	ldi		mpr, $FF
	out		DDRB, mpr
	ldi		mpr, $00
	out		PORTB, mpr

		; PORTD for input
	ldi		mpr, $00
	out		DDRD, mpr
	ldi		mpr, $FF
	out		PORTD, mpr

	; LCD
	call	LCDInit
	call	LCDBackLightOn

	; Data Memory Variables
		; COUNTDOWN
	ldi		mpr, 0
	ldi		XH, high(COUNTDOWN)
	ldi		XL,	low(COUNTDOWN)
	st		X, mpr

		; GAME_STAGE
	ldi		mpr, 0
	ldi		XH, high(GAME_STAGE)
	ldi		XL,	low(GAME_STAGE)
	st		X, mpr

		; HANDs
	ldi		mpr, SIG_ROCK
	ldi		XH, high(HAND_OPNT)
	ldi		XL,	low(HAND_OPNT)
	st		X, mpr
	ldi		XH, high(HAND_USER)
	ldi		XL,	low(HAND_USER)
	st		X, mpr

		; READY Flags
	ldi		mpr, SIG_NOT_READY
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
		; INT0	= 1	= Enable INT0
	ldi		mpr, (0<<INT6 | 0<<INT3 | 0<<INT2 | 1<<INT1 | 1<<INT0)
	sts		EIMSK, mpr

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
	rjmp	NEXT_GAME_STAGE_END

NEXT_GAME_STAGE_1:						; READY UP
	ldi		mpr, (0<<INT1 | 1<<INT0)	; Disable INT1 (PD7) because it's only use was to start the game
	sts		EIMSK, mpr					; ^ INT0 (PD4) is still needed to change HAND_USER
	rcall	GAME_STAGE_1				; Do stuff for this stage
	ldi		mpr, 2						; Update GAME_STAGE
	st		X, mpr						; ^
	rjmp	NEXT_GAME_STAGE_END
	
NEXT_GAME_STAGE_2:						; CHOOSE HAND
	rcall	GAME_STAGE_2				; Do stuff for this stage
	ldi		mpr, 3						; Update GAME_STAGE
	st		X, mpr						; ^
	rjmp	NEXT_GAME_STAGE_END

NEXT_GAME_STAGE_3:						; REVEAL HANDS
	rcall	GAME_STAGE_3				; Do stuff for this stage
	ldi		mpr, 4						; Update GAME_STAGE
	st		X, mpr						; ^
	rjmp	NEXT_GAME_STAGE_END

NEXT_GAME_STAGE_4:						; RESULT
	rcall	GAME_STAGE_4				; Do stuff for this stage
	ldi		mpr, 0						; Update GAME_STAGE, so it wraps around and next time it begins at the start
	st		X, mpr						; ^
	ldi		mpr, (1<<INT1 | 1<<INT0)	; Enable INT1 (PD7) so it can start the game again
	sts		EIMSK, mpr					; ^
	rjmp	NEXT_GAME_STAGE_END

NEXT_GAME_STAGE_END:
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

	; Enable Global Interrupts so timer can work and hand can be changed
	sei

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

	; Enable Global Interrupts so timer can work
	sei
	
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
	rjmp	GAME_STAGE_3_END

GAME_STAGE_3_PAPER:
	; Print to LCD
	ldi		ZH, high(STRING_PAPER<<1)
	ldi		ZL, low(STRING_PAPER<<1)
	rcall	LCD_TOP
	rjmp	GAME_STAGE_3_END

GAME_STAGE_3_SCISSORS:
	; Print to LCD
	ldi		ZH, high(STRING_SCISSORS<<1)
	ldi		ZL, low(STRING_SCISSORS<<1)
	rcall	LCD_TOP
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
	push	ZH
	push	ZL

	; Start 6 second timer
	rcall	TIMER

	; Enable Global Interrupts so timer can work
	sei

	; Print to LCD
		; Should do some logic to deicde actaul result
	ldi		ZH, high(STRING_DRAW<<1)
	ldi		ZL, low(STRING_DRAW<<1)
	rcall	LCD_TOP

	; Restore variables
	pop		ZL
	pop		ZH

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

	; Load in COUNTDOWN
	ldi		XH, high(COUNTDOWN)
	ldi		XL,	low(COUNTDOWN)
	ld		mpr, X

	; Branch based on current COUNTDOWN
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
	ldi		mpr, 4				; Update COUNTDOWN
	st		X, mpr				; ^
	in		mpr, PINB			; Update LEDs
	andi	mpr, 0b1111_1111	; ^
	out		PORTB, mpr			; ^
	rjmp	TIMER_END

TIMER_3:
	ldi		mpr, 3				; Update COUNTDOWN
	st		X, mpr				; ^
	in		mpr, PINB			; Update LEDs
	andi	mpr, 0b0111_1111	; ^
	out		PORTB, mpr			; ^
	rjmp	TIMER_END

TIMER_2:
	ldi		mpr, 2				; Update COUNTDOWN
	st		X, mpr				; ^
	in		mpr, PINB			; Update LEDs
	andi	mpr, 0b0011_1111	; ^
	out		PORTB, mpr			; ^
	rjmp	TIMER_END

TIMER_1:
	ldi		mpr, 1				; Update COUNTDOWN
	st		X, mpr				; ^
	in		mpr, PINB			; Update LEDs
	andi	mpr, 0b0001_1111	; ^
	out		PORTB, mpr			; ^
	rjmp	TIMER_END

TIMER_0:						; End timer
	ldi		mpr, (0<<TOIE1)		; TOIE1	= 0	= Overflow Interrupt Disabled
	sts		TIMSK1, mpr			; ^
	ldi		mpr, 0				; Update COUNTDOWN, so it wraps around and next time it begins at the start
	st		X, mpr				; ^
	in		mpr, PORTB			; Update LEDs
	andi	mpr, 0b0000_1111	; ^
	out		PORTB, mpr			; ^
	rcall	NEXT_GAME_STAGE		; Update GAME_STAGE
	rjmp	TIMER_END

TIMER_END:
	; Restore variables
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
	ldi		XH, $01						; Point X to LCD top line
	ldi		XL, $00						; ^
	ldi		ilcnt, 32					; Loop 32 times for 32 characters

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
	ldi		XH, $01						; Point X to LCD top line
	ldi		XL, $00						; ^
	ldi		ilcnt, 16					; Loop 16 times for 16 characters

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
	ldi		XH, $01						; Point X to LCD bottom line
	ldi		XL, $10						; ^
	ldi		ilcnt, 16					; Loop 16 times for 16 characters

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
	
	ldi		mpr, 20
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

        ; Return from subroutine
        ret

;-----------------------------------------------------------
; Func:	
; Desc:	Assumes Z already points to string.
;-----------------------------------------------------------
LCD_TEST:
	; Save variables
	push	mpr
	push	ZH
	push	ZL

	; Test STRING_IDLE
	ldi		ZH, high(STRING_IDLE<<1)	; Point Z to string
	ldi		ZL, low(STRING_IDLE<<1)		; ^
	call	LCD_ALL

	; Wait
	call	BUSY_WAIT

	; Test STRING_READY_UP
	ldi		ZH, high(STRING_READY_UP<<1)	; Point Z to string
	ldi		ZL, low(STRING_READY_UP<<1)	; ^
	call	LCD_ALL

	; Wait
	call	BUSY_WAIT

	; Test STRING_CHOOSE_HAND
	ldi		ZH, high(STRING_CHOOSE_HAND<<1)	; Point Z to string
	ldi		ZL, low(STRING_CHOOSE_HAND<<1)	; ^
	call	LCD_TOP

	; Test STRING_ROCK
	ldi		ZH, high(STRING_ROCK<<1)	; Point Z to string
	ldi		ZL, low(STRING_ROCK<<1)		; ^
	call	LCD_BOTTOM

	; Wait
	call	BUSY_WAIT

	; Test STRING_PAPER
	ldi		ZH, high(STRING_PAPER<<1)	; Point Z to string
	ldi		ZL, low(STRING_PAPER<<1)	; ^
	call	LCD_BOTTOM

	; Wait
	call	BUSY_WAIT

	; Test STRING_SCISSORS
	ldi		ZH, high(STRING_SCISSORS<<1); Point Z to string
	ldi		ZL, low(STRING_SCISSORS<<1)	; ^
	call	LCD_BOTTOM

	; Wait
	call	BUSY_WAIT

	; Test STRING_WON
	ldi		ZH, high(STRING_WON<<1); Point Z to string
	ldi		ZL, low(STRING_WON<<1)	; ^
	call	LCD_TOP

	; Wait
	call	BUSY_WAIT

	; Test STRING_LOST
	ldi		ZH, high(STRING_LOST<<1); Point Z to string
	ldi		ZL, low(STRING_LOST<<1)	; ^
	call	LCD_TOP

	; Wait
	call	BUSY_WAIT

	; Test STRING_DRAW
	ldi		ZH, high(STRING_DRAW<<1); Point Z to string
	ldi		ZL, low(STRING_DRAW<<1)	; ^
	call	LCD_TOP

	; Wait
	call	BUSY_WAIT

	; Restore variables
	pop		ZL
	pop		ZH
	pop		mpr

	; Return from function
	ret

;***********************************************************
;*	Stored Program Data
;***********************************************************
STRING_IDLE:
	.DB		"Welcome!        Please press PD7"
STRING_READY_UP:
	.DB		"Ready. Waiting  for the opponent"
STRING_CHOOSE_HAND:
	.DB		"Game start      "
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

COUNTDOWN:			; Countdown value for timer loop and LED display
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
