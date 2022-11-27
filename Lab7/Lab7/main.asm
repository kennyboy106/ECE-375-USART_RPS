;Plan
;
;
;
;   Configure USART1
;       Turn on receiver?   
;           Receiver is on PD2 - RXD1
;       Turn on transmitter?
;           Transmitters on PD3 - TXD1
;       Frame Format
;           Data Frame          8-bit
;           Stop bit            2 stop bits
;           Parity bit          disable
;           Asynchronous Operation
;           Controlled in:
;               UCSR1A
;               UCSR1B
;               UCSR1C
;       Baud                    2400
;           Controlled in:
;               UBRR1H
;               UBRR1L
;           Don't write to UBRR1H bits 15:12 (last 4 bits) they are reserved
;               Thus we can write 14 bits to it in general
;           Since we are doing double data rate we use the following eq to solve
;               for UBRR
;               UBRR = (f_clk / (8 * baud)) - 1 = 8Mhz / 8 * 2400 - 1 = 415.6667
;           415.666 == 416 -> $01A0
;           ldi  mpr, $A0
;           sts  UBRRL, mpr
;           lds  mpr, UBRRH
;           ori  mpr, 0b0000_0001
;           sts  UBRRH, mpr
;
;       Data Register is UDR1
;           To transmit use:
;               sts     UDR1, mpr
;           To recieve use:
;               LDS     mpr, UDR1
;
;       Configure Interrupts
;           UCSR1A
;               dont need to check this 
;               5 Enable UDREI - USART Data register empty
;               
;               1 Enable U2XI  - Double the USART transmission speed
;               0b0000_0010


;           UCSR1B
;               7 Enable RXCIE - Receive Complete Interrupt
;               4 Enable RXEN  - Receiver Enable
;               3 Enable TXEN  - Transmitter Enable
;               2 Set    UCSZ  - Character Size bit 3 of 3
;                   8-bit = 011
;               0b1001_1000

;           UCSR1C
;               7 Set UMSEL1   - USART Mode Select
;               6 Set UMSEL1   - USART Mode Select
;                   Asynch = 00
;               5 Set UPM1     - Parity Mode
;               4 Set UPM1     - Parity Mode
;                   Disabled = 00
;               3 Set USBS1    - Stop Bit Select
;                   2-bits = 1
;               2 Set UCSZ     - Character Size bit 2 of 3
;               1 Set UCSZ     - Character Size bit 1 of 3
;               0 Set UCPOL1   - Clock Polarity
;                   Falling XCKn Edge = 0
;               0b0000_1110

;
;
;
;   LCD Display
;       Need to display current 
;
;
;
;   Buttons
;       PD7 - Start/Ready
;       PD4 - Cycle gestures
;       PB7:4 - countdown timer
;           Need to use like a descending order kinda thing
;       PB3:0 - Used by LCDDriver so no touchy touchy
;
;   Wires
;       Connect as follows:
;       Board 1     Board 2
;       PD2         PD3
;       PD3         PD2
;       GND         GND
;
;
;
;   Game flow
;       Starting the game
;           We need to send a start code to the other board
;               Start can be    0b1000_0000
;           This needs to start the countdown for both boards
;
;
;       Comparing gestures
;           We want to have codes for what each selection is:
;               Rock can be     0b0000_0001
;               Scissors can be 0b0000_0010
;               Paper can be    0b0000_0011
;           On the users board show on the LCD what they have selected
;           by using a word or letter - both are equally easy
;           
;           Once the timer is at 0 we send the gesture code to the other board
;           and compare to the current gesture on te board
;               If a board compares and determines it loses/wins, print status
;               on the LCD
;           *Make sure to enable global interrupts again when needed*
;           
;       Code Flow
;           Main function should do nothing at all
;           To start we press the start button, this goes to interrupt xxxx:
;               >Send the start code via USART to other board
;               >Display the ready msg on the screen until the other board send the ready
;               When receiving the ready msg, start counters
;               Display user choice on the second line
;               Load rock into data variable
;               Enable interrupt so the user can press another button to change option
;               Cycle through options when user presses button
;               When counter ends, send the selection variable to other board
;               receive selection from other board
;               display opponents choice on the first line
;               start the counters again
;               after counter ends display winner or loser
;               start counters again
;               after counter ends display welcome msg again
;
;

;
;
;
;
;
;
;
;
;

;***********************************************************
;*
;*   Author: Kenneth Tang
;*           Travis Fredrickson
;*     Date: 11/19/2022
;*
;***********************************************************

.include "m32U4def.inc"         ; Include definition file

;***********************************************************
;*  Internal Register Definitions and Constants
;***********************************************************
.def    mpr = r16               ; Multi-Purpose Register
.def    waitcnt = r17           ; Wait Loop Counter
.def    ilcnt = r18
.def    olcnt = r19

.equ    WTime = 20             ; Time to wait in wait loop

.equ    WskrR = 0               ; Right Whisker Input Bit
.equ    WskrL = 1               ; Left Whisker Input Bit
.equ    EngEnR = 4              ; Right Engine Enable Bit
.equ    EngEnL = 7              ; Left Engine Enable Bit
.equ    EngDirR = 5             ; Right Engine Direction Bit
.equ    EngDirL = 6             ; Left Engine Direction Bit

;.equ   BotAddress = ;(Enter your robot's address here (8 bits))
.equ    rock        = 0b0000_0001
.equ    paper       = 0b0000_0010
.equ    scissor     = 0b0000_0011
.equ    start_msg   = 0b0000_0100


;***********************************************************
;*  Start of Code Segment
;***********************************************************
.cseg                           ; Beginning of code segment

;***********************************************************
;*  Interrupt Vectors
;***********************************************************
.org    $0000                   ; Beginning of IVs
        rjmp    INIT            ; Reset interrupt

;--------- Not in use ----------;
;                               ;
.org    $0002                   ; INT0  Cycle through selection
        reti

.org    $0004                   ; INT1 No use yet
        reti

.org    $0008                   ; INT3 The start button
        reti
;                               ;
;-------------------------------;


.org    $0028                   ; Timer/Counter 1 Overflow
        rcall UPDATE_TIMER
        reti

.org    $0032                   ; USART1 Rx Complete
        rcall MESSAGE_RECEIVE
        reti

.org    $0034                   ; USART Data Register Empty
        reti

.org    $0036                   ; USART1 Tx Complete
        rcall TRANSMIT_CHECK
        reti



.org    $0056                   ; End of Interrupt Vectors

;***********************************************************
;*  Program Initialization
;***********************************************************
INIT:
    ; Initialize the Stack Pointer
    ldi     mpr, high(RAMEND)
    out     SPH, mpr
    ldi     mpr, low(RAMEND)
    out     SPL, mpr

    ; I/O Ports
    ldi     mpr, (1<<PD3 | 0b0000_0000) ; Set Port D pin 3 (TXD1) for output
    out     DDRD, mpr                   ; Set Port D pin 2 (RXD1) for input
    ldi     mpr, $FF                    ; Enable pull up resistors
    out     PORTD, mpr

    ; Configure PORTB for output
    ldi     mpr, $FF
    out     DDRB, mpr
    ldi     mpr, $00
    out     PORTB, mpr


    ; USART1
    ; Frame Format:
    ;   Data Frame          8-bit
    ;   Stop bit            2 stop bits
    ;   Parity bit          disable
    ;   Asynchronous Operation
    ; Baud 2400
    ; Data register empty interrupt enabled
    ; Recieve complete interrupt enabled
    ; Transmit complete interrupt enabled
    ; Double data rate enabled
    ; Reciever & Transmitter enabled

    ; Set double data rate
    ldi     mpr, (1<<U2X1)
    sts     UCSR1A, mpr
    ; Set recieve & transmit complete interrupts, transmitter & reciever enable, 8 data bits frame formate
    ldi     mpr, (1<<RXCIE1 | 0<<TXCIE1 | 0<<UDRIE1 | 1<<RXEN1 | 1<<TXEN1 | 0<<UCSZ12)
    sts     UCSR1B, mpr
    ; Set frame formate: 8 data bits, 2 stop bits, asnych, no parity
    ldi     mpr, (0<<UMSEL11 | 0<<UMSEL10 | 0<<UPM11 | 0<<UPM10 | 1<<USBS1 | 1<<UCSZ11 | 1<<UCSZ10 | 0<<UCPOL1)
    sts     UCSR1C, mpr
    ; Baud to 2400 @ double data rate
    ldi     mpr, high(416)
    sts     UBRR1H, mpr
    ldi     mpr, low(416)
    sts     UBRR1L, mpr
    
    ; Timer/Counter 1
    ; Setup for normal mode WGM 0000
    ; COM diconnected 00
    ; Use OCR1A for top value
    ; CS TBD, using 100
    ldi     mpr, (0<<COM1A1 | 0<<COM1A0 | 0<<COM1B1 | 0<<COM1B0 | 0<<WGM11 | 0<<WGM10)
    sts     TCCR1A, mpr
    ldi     mpr, (0<<WGM13 | 0<<WGM12 | 1<<CS12 | 0<<CS11 | 0<<CS10)
    sts     TCCR1B, mpr
    

    call    LCDInit                         ; Initialize LCD
    call    LCDBacklightOn
    call    LCDWelcome                      ; Print welcome message

    ; Set the ready flags
    ldi     mpr, $FF
    ldi     ZH, high(User_Ready_flag)       ; Load both ready flags
    ldi     ZL, low(User_Ready_flag)
    st      Z, mpr                          
    ldi     mpr, $0F                        ; Make sure the flags are different
    ldi     ZH, high(Opnt_Ready_flag)
    ldi     ZL, low(Opnt_Ready_flag)
    st      Z, mpr
   
    ; Enable global interrupts
    sei


;***********************************************************
;*  Main Program
;***********************************************************
MAIN:


        sbis    PIND, PIND7     ; Send ready signal
        rcall   SEND_READY

        ; Test to see if transmit or recieve flag is set ;
        ;   write a 1 to TXCI and RXCI to reset them
        ;lds     mpr, UCSR1A     ; Load in the status register for USART1
        ;sbrs    mpr, TXC1
        rjmp    MAIN

        ldi     mpr, (1<<TXC1)  ; Reset the flag ;;;this is wrong
        sts     UCSR1A, mpr
        call    TRANSMIT_CHECK  ; Check transmit complete stuff
        rjmp    MAIN

;***********************************************************
;*  Functions and Subroutines
;***********************************************************
SET_OPP:
    push mpr
    push ZH
    push ZL

    ldi     ZH, high(Opnt_Ready_flag)   ; Load the ready flag
    ldi     ZL, low(Opnt_Ready_flag)
    ldi     mpr, 1
    st      Z, mpr                      ; Store a 1 to the ready flag

    pop ZL
    pop ZH
    pop mpr
    ret

LCDWelcome:
    ;----------------------------------------------------------------
    ; Sub:  LCD Welcome 
    ; Desc: Prints the Welcome message to the LCD
    ;----------------------------------------------------------------
    push mpr
    push ZH
    push ZL
    push XH
    push XL
    push olcnt


    ldi     ZH, high(WELCOME_STR<<1)    ; Point Z to the welcome string
    ldi     ZL, low(WELCOME_STR<<1)
    ldi     XH, $01                     ; Point X to the top of the LCD Screen
    ldi     XL, $00 
    ldi     olcnt, 32                   ; We want to loop for all 32 characters
 Wel_loop:
    lpm     mpr, Z+                     ; Load char into mpr
    st      X+, mpr                     ; Store char in screen
    dec     olcnt
    brne    Wel_loop
    call    LCDWrite                    ; Call write after all chars are set

    ldi     ZH, high(Testbit)
    ldi     ZL, low(Testbit)
    ldi     mpr, $03
    st      Z, mpr

    

    pop olcnt
    pop XL
    pop XH
    pop ZL
    pop ZH
    pop mpr
    ret

LCDReady:
    ;----------------------------------------------------------------
    ; Sub:  LCD Ready 
    ; Desc: Prints the ready message to the LCD
    ;----------------------------------------------------------------
    push mpr
    push ZH
    push ZL
    push XH
    push XL
    push olcnt



    ldi     ZH, high(READY_STR<<1)    ; Point Z to the welcome string
    ldi     ZL, low(READY_STR<<1)
    ldi     XH, $01                     ; Point X to the top of the LCD Screen
    ldi     XL, $00 
    ldi     olcnt, 32                   ; We want to loop for all 32 characters
 Red_loop:
    lpm     mpr, Z+                     ; Load char into mpr
    st      X+, mpr                     ; Store char in screen
    dec     olcnt
    brne    Red_loop
    call    LCDWrite                    ; Call write after all chars are set


    ldi     ZH, high(Testbit)
    ldi     ZL, low(Testbit)
    ldi     mpr, $03
    st      Z, mpr

   

    pop olcnt
    pop XL
    pop XH
    pop ZL
    pop ZH
    pop mpr
    ret

SEND_READY:
    ; Here we need to send a message via USART
    push mpr

    ldi     waitcnt, WTime                  ; Wait for one second
    rcall   Wait

    
    ldi     ZH, high(User_Ready_flag)   ; Load the ready flag
    ldi     ZL, low(User_Ready_flag)
    ldi     mpr, 1
    st      Z, mpr                      ; Store a 1 to the ready flag
    call    LCDReady

    ;-------------- Transmit via USART ----------;
 Ready_Transmit:
    lds     mpr, UCSR1A                 ; Load in USART status register
    sbrs    mpr, UDRE1                  ; Check the UDRE1 flag
    rjmp    Ready_Transmit              ; Loop back until data register is empty

    ldi     mpr, start_msg              ; Send the start message to the other board
    sts     UDR1, mpr

    pop mpr
    ret


; Blink LED if start message is received
MESSAGE_RECEIVE:
    ;----------------------------------------------------------------
    ; Sub:  Message Receive
    ; Desc: After receiving data, this function decides what to do with it
    ;       It performs checks on it to see what was sent in then branches
    ;       to the appropriate function.
    ;----------------------------------------------------------------
    push mpr
    
    cli 
    


    call    LED_TOGGLE
    ;--------- Read message in UDR1 -----------;
    lds     mpr, UDR1               ; Read the incoming data
    ;cpi     mpr, start_msg          ; If start message
    ;breq    LED_TOGGLE
    ;cpi     mpr, rock              ; If rock message
    ;breq    OPPONENT_SELECT        ; Update opponents selection  
    ;cpi     mpr, paper             ; If paper message
    ;breq    OPPONENT_SELECT
    ;cpi     mpr, scissor           ; If scissor message
    ;breq    OPPONENT_SELECT

    sei
   
    pop mpr
    ret

RECEIVE_START:
    push mpr
    push ZH
    push ZL

    call    LED_ON

    ldi     mpr, 1                      ; Change opponents ready flag to 1
    ldi     ZH, high(Opnt_Ready_flag)
    ldi     ZL, low(Opnt_Ready_flag)
    st      Z, mpr

    call    TRANSMIT_CHECK              ; Check to see if we should start

    call    LED_OFF

    pop ZL
    pop ZH
    pop mpr
    ret

LED_TOGGLE:
    push  waitcnt
    push  mpr

    ldi     waitcnt, 0b1000_0000
    in      mpr, PINB 
    
    eor     mpr, waitcnt        ; Bitmask to only keep the MSB
    out     PORTB, mpr
    
    pop mpr
    pop waitcnt
    ret

LED_ON:
    push mpr

    ldi     mpr, 0b1000_0000
    out     PORTB, mpr

    pop mpr
    ret
LED_OFF:
    push mpr

    ldi     mpr, 0b0000_0000
    out     PORTB, mpr

    pop mpr
    ret

TRANSMIT_CHECK:
    push mpr
    push ilcnt
    push ZH
    push ZL
    push XH
    push XL

    ; Check to see if we should start the game
    ldi     ZH, high(User_Ready_flag)       ; Load both ready flags
    ldi     ZL, low(User_Ready_flag)
    ld      mpr, Z
    ldi     XH, high(Opnt_Ready_flag)
    ldi     XL, low(Opnt_Ready_flag)
    ld      ilcnt, X
    cp      mpr, ilcnt                      ; Compare the ready flags
    breq    START_GAME                      ; Start the game if both are set

    ; Other checks

    pop XL
    pop XH
    pop ZL
    pop ZH
    pop ilcnt
    pop mpr
    ret

START_GAME:
    push mpr
    push ZH
    push ZL

    ldi     waitcnt, WTime
    call    Wait

    ; Clear the ready flags
    ldi     mpr, $FF
    ldi     ZH, high(User_Ready_flag)       ; Load both ready flags
    ldi     ZL, low(User_Ready_flag)
    st      Z, mpr                          ; Clear them
    ldi     mpr, $0F                        ; Make sure the flags are different
    ldi     ZH, high(Opnt_Ready_flag)
    ldi     ZL, low(Opnt_Ready_flag)
    st      Z, mpr

    ; Start the counter
    sts     TIMSK1, mpr
    ldi     mpr, $48                ; Starting counter at 18,661 for 1.5 second delay
    sts     TCNT1H, mpr             ; Write high then low
    ldi     mpr, $E5
    sts     TCNT1L, mpr
    ldi     mpr, (1<<TOIE1)         ; Set TOV01 enable

    ; Initialize counter var to be 4
    ldi     mpr, 4
    ldi     ZH, high(TCounter)
    ldi     ZL, low(TCounter)
    st      Z, mpr
    ; Set LEDs
    ldi     mpr, 0b1111_0000        ; Set upper 4 LEDs to be on
    out     PORTB, mpr

    pop ZL
    pop ZH
    pop mpr
    ret

OPPONENT_SELECT:
    ret


UPDATE_TIMER:
    push mpr
    push ZH
    push ZL
    ;------------------------- Reset Counter ----------------------------;
    ldi     mpr, $48            ; Starting counter at 18,661 for 1.5 second delay
    sts     TCNT1H, mpr         ; Write high then low
    ldi     mpr, $E5
    sts     TCNT1L, mpr
    ;------------------------- Decrement the counter --------------------;
    ldi     ZH, high(TCounter)
    ldi     ZL, low(TCounter)
    ld      mpr, Z
    dec     mpr
    st      Z, mpr
    ;------------------------- Adjust the LEDs --------------------------;
    cpi     mpr, 3             ; If TCounter is 3
    breq    THREE_ON
    cpi     mpr, 2             ; If TCounter is 2
    breq    TWO_ON
    cpi     mpr, 1             ; If TCounter is 1
    breq    ONE_ON
    cpi     mpr, 0             ; If TCounter is 0
    breq    OFF
    rjmp    END                ; In case we miss all the compares
    
 THREE_ON:
    ldi     mpr, 0b0111_0000
    out     PORTB, mpr
    rjmp    END
 TWO_ON:
    ldi     mpr, 0b0011_0000
    out     PORTB, mpr
    rjmp    END
 ONE_ON:
    ldi     mpr, 0b0001_0000
    out     PORTB, mpr
    rjmp    END
 OFF: 
    ldi     mpr, 0b0000_0000
    out     PORTB, mpr
    ldi     mpr, (0<<TOIE1)     ; Clear TOV01 enable
    sts     TIMSK1, mpr
    rjmp    END

 END:
    pop ZL
    pop ZH
    pop mpr
    ret




Wait:
    ;----------------------------------------------------------------
    ; Sub:  Wait
    ; Desc: A wait loop that is 16 + 159975*waitcnt cycles or roughly
    ;       waitcnt*10ms.  Just initialize wait for the specific amount
    ;       of time in 10ms intervals. Here is the general eqaution
    ;       for the number of clock cycles in the wait loop:
    ;           ((3 * ilcnt + 3) * olcnt + 3) * waitcnt + 13 + call
    ;----------------------------------------------------------------
        ; Save variables by pushing them to the stack
        push    waitcnt         ; Save wait register
        push    ilcnt           ; Save ilcnt register
        push    olcnt           ; Save olcnt register

    Loop:   ldi     olcnt, 224      ; Load olcnt register
    OLoop:  ldi     ilcnt, 237      ; Load ilcnt register
    ILoop:  dec     ilcnt           ; Decrement ilcnt
            brne    ILoop           ; Continue Inner Loop
            dec     olcnt           ; Decrement olcnt
            brne    OLoop           ; Continue Outer Loop
            dec     waitcnt         ; Decrement wait
            brne    Loop            ; Continue Wait loop

        ; Restore variable by popping them from the stack in reverse order
        pop     olcnt       ; Restore olcnt register
        pop     ilcnt       ; Restore ilcnt register
        pop     waitcnt     ; Restore wait register

        ; Return from subroutine
        ret

;***********************************************************
;*  Stored Program Data
;***********************************************************
WELCOME_STR:
        .DB "Welcome!        Please press PD7"
READY_STR:
        .DB "Ready. Waiting  for the opponent"
WINNER_STR:
        .DB "You Win!        "
LOSER_STR:
        .DB "You Lose!       "
ROCK_STR:
        .DB "Rock            "
PAPER_STR:
        .DB "Paper           "
SCISSOR_STR:
        .DB "Scissor         "

;***********************************************************
;*  Data Memory Allocation
;***********************************************************
.dseg
.org    $0200
User_Ready_flag:         ; Ready flag to be set when receiving start msg
        .byte 1
Opnt_Ready_flag:         ; Ready flag to be set when receiving start msg
        .byte 1
TCounter:           ; Space for a counting variable
        .byte 1
Selection:          ; Space for rock/paper/scissor selection
        .byte 1
Testbit:
        .byte 1

;***********************************************************
;*  Additional Program Includes
;***********************************************************
.include "LCDDriver.asm"

