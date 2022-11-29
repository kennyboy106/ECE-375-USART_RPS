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
;               Rock can be     0b0000_0000
;               Scissors can be 0b0000_0001
;               Paper can be    0b0000_0010
;                               0b0000_0011
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

.equ    WTime = 15             ; Time to wait in wait loop

.equ    ROCK            = 0b0000_0001
.equ    PAPER           = 0b0000_0010
.equ    SCISSOR         = 0b0000_0011
.equ    SIG_READY       = 0b1111_1111       ; Signal for ready to start game
.equ    SIG_NOT_READY   = 0b0000_0000   

;***********************************************************
;*  Start of Code Segment
;***********************************************************
.cseg                           ; Beginning of code segment

;***********************************************************
;*  Interrupt Vectors
;***********************************************************
.org    $0000                   ; Beginning of IVs
        rjmp    INIT            ; Reset interrupt


.org    $0002                   ; INT0  Cycle through selection
        rcall CYCLE_HAND
        reti

.org    $0004                   ; INT1 Send Start Msg
        rcall NEXT_GAME_STAGE
        reti

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

    ; Set double data rate
    ldi     mpr, (1<<U2X1)
    sts     UCSR1A, mpr
    ; Set recieve & transmit complete interrupts, transmitter & reciever enable, 8 data bits frame formate
    ldi     mpr, (1<<RXCIE1 | 1<<TXCIE1 | 0<<UDRIE1 | 1<<RXEN1 | 1<<TXEN1 | 0<<UCSZ12)
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
    ldi     ZH, high(WELCOME_STR<<1)        ; Point Z to the welcome string
    ldi     ZL, low(WELCOME_STR<<1)
    call    LCD_ALL                         ; Print welcome message

    ; Set the ready flags
    ldi     mpr, $FF
    ldi     ZH, high(User_Ready_flag)       ; Load both ready flags
    ldi     ZL, low(User_Ready_flag)
    st      Z, mpr                          
    ldi     mpr, $0F                        ; Make sure the flags are different
    ldi     ZH, high(Opnt_Ready_flag)
    ldi     ZL, low(Opnt_Ready_flag)
    st      Z, mpr
    
    ; Set Game stage to be 0
    ldi     mpr, $00
    ldi     ZH, high(GAME_STAGE)
    ldi     ZL, low(GAME_STAGE)
    st      Z, mpr
   

    ; External Interrupts
    ; Initialize external interrupts
    ldi     mpr, 0b0000_1010    ; Set INT1, INT0 to trigger on 
    sts     EICRA, mpr          ; falling edge

    ; Configure the External Interrupt Mask
    ldi     mpr, (1<<INT1 | 0<<INT0)    ; Enable INT1. Disable INT0 for now
    out     EIMSK, mpr



    ; Enable global interrupts
    sei


;***********************************************************
;*  Main Program
;***********************************************************
MAIN:

        rjmp    MAIN


;***********************************************************
;*  Functions and Subroutines
;***********************************************************
; Printing functions ----------------
LCD_ALL:
    ;-----------------------------------------------------------
    ; Func: LCD All
    ; Desc: Prints a string to the entire LCD
    ;       Assumes Z already points to string.
    ;-----------------------------------------------------------
    ; Save variables
    push    mpr
    push    ilcnt
    push    XH
    push    XL

    ; Set parameters
    ldi     XH, $01                     ; Point X to LCD top line
    ldi     XL, $00                     ; ^
    ldi     ilcnt, 32                   ; Loop 32 times for 32 characters

 LCD_ALL_LOOP:
    ; Load in characters
    lpm     mpr, Z+
    st      X+, mpr
    dec     ilcnt
    brne    LCD_ALL_LOOP

    ; Write to LCD
    call    LCDWrite

    ; Restore variables
    pop     XL
    pop     XH
    pop     ilcnt
    pop     mpr

    ; Return from function
    ret

LCD_TOP:
    ;-----------------------------------------------------------
    ; Func: LCD Top
    ; Desc: Prints a string to the top row of the LCD
    ;       Assumes Z already points to string.
    ;-----------------------------------------------------------
    ; Save variables
    push    mpr
    push    ilcnt
    push    XH
    push    XL

    ; Set parameters
    ldi     XH, $01                     ; Point X to LCD top line
    ldi     XL, $00                     ; ^
    ldi     ilcnt, 16                   ; Loop 16 times for 16 characters

 LCD_TOP_LOOP:
    ; Load in characters
    lpm     mpr, Z+
    st      X+, mpr
    dec     ilcnt
    brne    LCD_TOP_LOOP

    ; Write to LCD
    call    LCDWrite

    ; Restore variables
    pop     XL
    pop     XH
    pop     ilcnt
    pop     mpr

    ; Return from function
    ret
    
LCD_BOTTOM:
    ;-----------------------------------------------------------
    ; Func: LCD Bottom
    ; Desc: Prints a string to the bottom row of the LCD
    ;       Assumes Z already points to string.
    ;-----------------------------------------------------------
    ; Save variables
    push    mpr
    push    ilcnt
    push    XH
    push    XL

    ; Set parameters
    ldi     XH, $01                     ; Point X to LCD bottom line
    ldi     XL, $10                     ; ^
    ldi     ilcnt, 16                   ; Loop 16 times for 16 characters

 LCD_BOTTOM_LOOP:
    ; Load in characters
    lpm     mpr, Z+
    st      X+, mpr
    dec     ilcnt
    brne    LCD_BOTTOM_LOOP

    ; Write to LCD
    call    LCDWrite

    ; Restore variables
    pop     XL
    pop     XH
    pop     ilcnt
    pop     mpr

    ; Return from function
    ret


; USART -----------------------------
MESSAGE_RECEIVE:
    ;----------------------------------------------------------------
    ; Sub:  Message Receive
    ; Desc: After receiving data, this function decides what to do with it
    ;       It performs checks on it to see what was sent in then branches
    ;       to the appropriate function.
    ;----------------------------------------------------------------
    push mpr
    push ZH
    push ZL
    push olcnt
    cli                             ; Turn interrupts off
    
    ;--------- Read message in UDR1 -----------;
    lds     mpr, UDR1               ; Read the incoming data
    ldi     olcnt, SIG_READY        ; Check to see if msg is SIG_READY 
    cpse    mpr, olcnt
    rjmp    MR_R2                   ; Skipped if equal
    call    RECEIVE_START           ; Go to receive start

 MR_R2:
    ldi     olcnt, ROCK             ; Check to see if msg is ROCK
    cpse    mpr, olcnt
    rjmp    MR_R3
    call    STORE_HAND
 MR_R3:
    ldi     olcnt, PAPER            ; Check to see if msg is PAPER
    cpse    mpr, olcnt
    rjmp    MR_R4
    call    STORE_HAND
 MR_R4:
    ldi     olcnt, SCISSOR          ; Check to see if msg is SCISSOR
    cpse    mpr, olcnt
    rjmp    MR_R5
    call    STORE_HAND
 MR_R5:


    sei                             ; Turn interrupts back on
    pop olcnt
    pop ZL
    pop ZH
    pop mpr
    ret

TRANSMIT_CHECK:
    ;----------------------------------------------------------------
    ; Sub:  Transmit Check
    ; Desc: Does a status check after a message has been transmitter on USART1
    ;----------------------------------------------------------------
    push mpr
    push ilcnt
    push ZH
    push ZL
    push XH
    push XL

    ;--------- Check to see if we should start the game ----------------;
    ldi     ZH, high(User_Ready_flag)       ; Load both ready flags
    ldi     ZL, low(User_Ready_flag)
    ld      mpr, Z
    ldi     XH, high(Opnt_Ready_flag)
    ldi     XL, low(Opnt_Ready_flag)
    ld      ilcnt, X
    cpse    mpr, ilcnt                      ; Compare the ready flags
    rjmp    TC_END                          ; If they aren't equal jump to end
    call    NEXT_GAME_STAGE                 ; else increment game stage

 TC_END:
    ; Other checks
    pop XL
    pop XH
    pop ZL
    pop ZH
    pop ilcnt
    pop mpr
    ret

SEND_READY:
    ; Here we need to send a message via USART
    push mpr
    push waitcnt

    ldi     waitcnt, WTime                  ; Wait for one second
    rcall   Wait
    
    
    
    ldi     ZH, high(User_Ready_flag)   ; Load the ready flag
    ldi     ZL, low(User_Ready_flag)
    ldi     mpr, 1
    st      Z, mpr                      ; Store a 1 to the ready flag
    ldi     ZH, high(READY_STR<<1)      ; Point Z to the Ready string
    ldi     ZL, low(READY_STR<<1)
    call    LCD_ALL

    ;-------------- Transmit via USART ----------;
 Ready_Transmit:
    lds     mpr, UCSR1A                 ; Load in USART status register
    sbrs    mpr, UDRE1                  ; Check the UDRE1 flag
    rjmp    Ready_Transmit              ; Loop back until data register is empty

    ldi     mpr, SIG_READY              ; Send the start message to the other board
    sts     UDR1, mpr

    ; Clear the queue
    ldi     mpr, 0b0000_0011        ; Clear interrupts
    out     EIFR, mpr

    pop waitcnt
    pop mpr
    ret

RECEIVE_START:
    push mpr
    push ZH
    push ZL

    ldi     mpr, 1                      ; Change opponents ready flag to 1
    ldi     ZH, high(Opnt_Ready_flag)
    ldi     ZL, low(Opnt_Ready_flag)
    st      Z, mpr
    call    TRANSMIT_CHECK              ; Check to see if we should start

    pop ZL
    pop ZH
    pop mpr
    ret

SEND_HAND:
    push mpr
    push ZH
    push ZL

 Hand_Transmit:
    ; See if the USART data register is empty
    lds     mpr, UCSR1A     ; UDRE1 will be 1 when buffer is empty
    sbrs    mpr, UDRE1      ; Test only the 5th bit
    rjmp    Hand_Transmit

    ldi     ZH, high(HAND_USER)     ; Load the user's hand
    ldi     ZL, low(HAND_USER)      
    ld      mpr, Z 
    sts     UDR1, mpr               ; Send user's hand via USART1

    pop ZL
    pop ZH
    pop mpr
    ret

; Core game -------------------------
NEXT_GAME_STAGE:
    ;-----------------------------------------------------------
    ; Func: Next Game Stage
    ; Desc: This is essentially the core function of the game.
    ;       Game stages change as follows:
    ;           0 -> 1      0 = IDLE
    ;           1 -> 2      1 = READY UP
    ;           2 -> 3      2 = SELECT HAND
    ;           3 -> 4      3 = REVEAL HANDS
    ;           4 -> 0      4 = RESULT
    ;-----------------------------------------------------------
    push    mpr
    push    XH
    push    XL

    ldi     XH, high(GAME_STAGE)        ; Load in current game stage value
    ldi     XL, low(GAME_STAGE)
    ld      mpr, X

    ; Branch based on current Game Stage
    cpi     mpr, 0
    breq    NEXT_GAME_STAGE_0
    cpi     mpr, 1
    breq    NEXT_GAME_STAGE_1
    cpi     mpr, 2
    breq    NEXT_GAME_STAGE_2
    cpi     mpr, 3
    breq    NEXT_GAME_STAGE_3
    cpi     mpr, 4
    breq    NEXT_GAME_STAGE_4
    rjmp    NEXT_GAME_STAGE_END         ; In case checks are skipped


 NEXT_GAME_STAGE_0: ; This is called after pressing PD7 (Start game)
    ldi     mpr, 1                      ; Update GAME_STAGE
    st      X, mpr                      ; ^
    ldi     mpr, (0<<INT1 | 1<<INT0)    ; Disable INT1 (PD7) because it's only use was to start the game
    sts     EIMSK, mpr                  ; ^ Enable INT0 (PD4) to change HAND_USER
    call    SEND_READY                  ; Send the ready message via USART1
    rjmp    NEXT_GAME_STAGE_END
    
 NEXT_GAME_STAGE_1: ; This is called after sending SEND_READY
    ldi     mpr, 2                      ; Update GAME_STAGE
    st      X, mpr                      ; ^
    rjmp    NEXT_GAME_STAGE_END         ; Should only be called by Transmit check when both are ready

 NEXT_GAME_STAGE_2: ; This is called after receiving the start msg - Game starts
    ldi     mpr, 3                      ; Update GAME_STAGE
    st      X, mpr                      ; ^
    rcall   TIMER_START                 ; Allow players to choose hand during timer countdown
    ; Show start message
    rjmp    NEXT_GAME_STAGE_END
    
 NEXT_GAME_STAGE_3: ; This is called after the first timer ends
    ldi     mpr, 4                      ; Update GAME_STAGE
    st      X, mpr                      ; ^
    rcall   TIMER_START                 
    ldi     mpr, (0<<INT1 | 0<<INT0)    ; Disable the ability to change hand
    sts     EIMSK, mpr
    call    DISPLAY_OPNT_HAND           ; Display opponents hand

    rjmp    NEXT_GAME_STAGE_END
    
    ; Show who won
 NEXT_GAME_STAGE_4: ; This is called after the hands are displayed - show the winner now
    ldi     mpr, 0                      ; Update GAME_STAGE, so it wraps around and next time it begins at the start
    st      X, mpr                      ; ^
    rcall   TIMER_START

    ; The line below should take place in the timer function not here
    ldi     mpr, (1<<INT1 | 0<<INT0)    ; Enable INT3 (PD7) so it can start the game again

    sts     EIMSK, mpr                  ; ^
    rjmp    NEXT_GAME_STAGE_END

 NEXT_GAME_STAGE_END:

    ldi     waitcnt, WTime              ; Wait for 15 ms to clear interrupt queue
    rcall   Wait
    ldi     mpr, 0b0000_0011            ; Clear interrupt queue
    out     EIFR, mpr

    pop     XL
    pop     XH
    pop     mpr
    ret

START_GAME:
    push mpr
    push ZH
    push ZL

    ; Clear the ready flags
    ldi     mpr, $FF
    ldi     ZH, high(User_Ready_flag)       ; Load both ready flags
    ldi     ZL, low(User_Ready_flag)
    st      Z, mpr                          ; Clear them
    ldi     mpr, $0F                        ; Make sure the flags are different
    ldi     ZH, high(Opnt_Ready_flag)
    ldi     ZL, low(Opnt_Ready_flag)
    st      Z, mpr
    call    TIMER_START

    pop ZL
    pop ZH
    pop mpr
    ret

STORE_HAND:
    ;-----------------------------------------------------------
    ; Func: Store hand
    ; Desc: Stores the incoming opponents hand to HAND_OPNT
    ;-----------------------------------------------------------
    push mpr
    push ZH
    push ZL

    ldi     ZH, high(HAND_OPNT)     ; mpr currently holds OPNT hand
    ldi     ZL, low(HAND_OPNT)
    st      Z, mpr                  ; Store the hand received

    pop ZL
    pop ZH
    pop mpr
    ret 

DISPLAY_OPNT_HAND:
    ;-----------------------------------------------------------
    ; Func: Display hands
    ; Desc: Displays opponents hand to the top LCD
    ;-----------------------------------------------------------
    push mpr
    push ZH
    push ZL

    ldi     ZH, high(HAND_OPNT)     ; Load the OPNT hand into mpr
    ldi     ZL, low(HAND_OPNT)
    ld      mpr, Z 

    cpi     mpr, ROCK 
    breq    DHO_ROCK
    cpi     mpr, SCISSOR
    breq    DHO_SCISSOR
    rjmp    DHO_PAPER               ; Last case & in case all other cases fall through
 DHO_ROCK:
    ldi     ZH, high(ROCK_STR<<1)
    ldi     ZL, low(ROCK_STR<<1)
    rjmp    DHO_DISP_OPNT
 DHO_SCISSOR:
    ldi     ZH, high(SCISSOR_STR<<1)
    ldi     ZL, low(SCISSOR_STR<<1)
    rjmp    DHO_DISP_OPNT
 DHO_PAPER:
    ldi     ZH, high(PAPER_STR<<1)
    ldi     ZL, low(PAPER_STR<<1)
    rjmp    DHO_DISP_OPNT
 DHO_DISP_OPNT:
    call    LCD_TOP                 ; Display whatever Z is pointing at now

    

    pop ZL
    pop ZH
    pop mpr
    ret

CYCLE_HAND:
    ;-----------------------------------------------------------
    ; Func: Cycle hand
    ; Desc: Cycles and displays the player's hand on the LCD
    ;-----------------------------------------------------------
    push mpr
    push ZH
    push ZL


    ldi     ZH, high(HAND_USER)     ; Load the USER hand into mpr
    ldi     ZL, low(HAND_USER)
    ld      mpr, Z      
    inc     mpr                     ; Increment the selection
    sbrs    mpr, 2                  ; If the 3rd bit is set, i.e. value is 0b0000_01xxx
    rjmp    RESET_HAND
    st      Z, mpr                  ; Else store new value
    rjmp    CH_SKIP
 RESET_HAND:
    ldi     mpr, $01                ; Store a 1 to Z
    st      Z, mpr
 CH_SKIP:

    cpi     mpr, ROCK 
    breq    DHP_ROCK
    cpi     mpr, SCISSOR
    breq    DHP_SCISSOR
    rjmp    DHP_PAPER               ; Last case & in case all other cases fall through
 DHP_ROCK:
    ldi     ZH, high(ROCK_STR<<1)
    ldi     ZL, low(ROCK_STR<<1)
    rjmp    DHP_DISP_OPNT
 DHP_SCISSOR:
    ldi     ZH, high(SCISSOR_STR<<1)
    ldi     ZL, low(SCISSOR_STR<<1)
    rjmp    DHP_DISP_OPNT
 DHP_PAPER:
    ldi     ZH, high(PAPER_STR<<1)
    ldi     ZL, low(PAPER_STR<<1)
    rjmp    DHP_DISP_OPNT
 DHP_DISP_OPNT:
    call    LCD_BOTTOM              ; Display whatever Z is pointing at now

    ; Clear the queue
    ldi     mpr, 0b0000_0011        ; Clear interrupts
    out     EIFR, mpr

    pop ZL
    pop ZH
    pop mpr
    ret

LED_TOGGLE:
    push  waitcnt
    push  mpr

    ldi     waitcnt, 0b1000_0000
    in      mpr, PINB 
    eor     mpr, waitcnt    
    out     PORTB, mpr
    
    pop mpr
    pop waitcnt
    ret

TIMER_START:
    ;-----------------------------------------------------------
    ; Func: Timer Start
    ; Desc: Starts the timer for a 4 * 1.5 second delay. Total of 
    ;       6 second delay until OFF is called within update timer. 
    ;-----------------------------------------------------------
    push mpr
    push ZH
    push ZL

    ; Initialize counter var to be 4
    ldi     mpr, 4
    ldi     ZH, high(TCounter)
    ldi     ZL, low(TCounter)
    st      Z, mpr
    ; Set LEDs
    ldi     mpr, 0b1111_0000        ; Set upper 4 LEDs to be on
    out     PORTB, mpr

    ; Start the counter
    ldi     mpr, (1<<TOIE1)         ; Set TOV01 enable
    sts     TIMSK1, mpr
    ldi     mpr, $48                ; Starting counter at 18,661 for 1.5 second delay
    sts     TCNT1H, mpr             ; Write high then low
    ldi     mpr, $E5
    sts     TCNT1L, mpr


    pop ZL
    pop ZH
    pop mpr
    ret

UPDATE_TIMER:
    push mpr
    push ZH
    push ZL
    push olcnt
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
    clc                         ; Clear the carry flag
    in      mpr, PINB           ; Read in current LEDs
    ror     mpr                 ; Shift to the right by 1
    out     PORTB, mpr          ; Put it back on the port
    
    cpi     mpr, 0              ; Turn off TOV01 interrupt flag if @ 0
    breq    OFF
    rjmp    END                 ; Else return normally

 OFF: 
    ldi     mpr, (0<<TOIE1)     ; Clear TOV01 enable
    sts     TIMSK1, mpr
    
    ldi     ZH, high(GAME_STAGE); Check to see if we are calling from GS 4
    ldi     ZL, low(GAME_STAGE)
    ld      mpr, Z
    cpi     mpr, 0
    breq    END                 ; If it is Game_Stage 4 then skip to end

    ldi     olcnt, 3            ; If it is Game_Stage 3 then send hands to other board
    cpse    mpr, olcnt
    rjmp    PASS                ; Skipped if mpr is 3
    call    SEND_HAND           ; Sends user hand via USART
 PASS:   
    call    NEXT_GAME_STAGE
 
 END:
    pop olcnt
    pop ZL                      ; Regular return stuff
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
DRAW_STR:
        .DB "Draw            "
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
User_Ready_flag:        ; Ready flag to be set when receiving start msg
        .byte 1
Opnt_Ready_flag:        ; Ready flag to be set when receiving start msg
        .byte 1
TCounter:               ; Space for a counting variable
        .byte 1
HAND_USER:              ; User choice: Rock / Paper / Scissors
        .byte 1
HAND_OPNT:              ; Opponent choice: Rock / Paper / Scissors
        .byte 1
SOME_DATA:
        .byte 1
GAME_STAGE:             ; Indicates the current stage the game is in
        .byte 1

;***********************************************************
;*  Additional Program Includes
;***********************************************************
.include "LCDDriver.asm"

