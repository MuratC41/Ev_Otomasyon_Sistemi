;#################################################################
; BOARD #1 - AIR CONDITIONER SYSTEM 
; NAME OF THE STUDENT: BEYZA KELES , YAGMUR BASAK
; 
;#################################################################

LIST p=16f877a
INCLUDE "p16f877a.inc"

__CONFIG _XT_OSC & _WDT_OFF & _PWRTE_ON & _BODEN_ON & _LVP_OFF & _CP_OFF

;============================================================================
; VARIABLE DEFINITIONS (CORRECTED MEMORY MAP)
;============================================================================

cblock 0x20
    ; --- TEMPERATURE VARIABLES ---
    DESIRED_TEMP_H          ; 0x20: Desired temp integer part
    DESIRED_TEMP_L          ; 0x21: Desired temp fractional part (0 or 5)
    AMBIENT_TEMP_H          ; 0x22: Ambient temp integer part
    AMBIENT_TEMP_L          ; 0x23: Ambient temp fractional part
    FAN_SPEED               ; 0x24: Fan speed in rps
    
    ; --- KEYPAD VARIABLES ---
    KEY_VALUE               ; 0x25: Current key pressed
    KEY_STATE               ; 0x26: Entry mode state (1,2,3,4,5)
    KEY_BUFFER              ; 0x27: Temporary buffer for second digit
    KP_TEMP_H               ; 0x28: Temporary calculation register
    
    ; --- DISPLAY VARIABLES ---
    DIGIT3                  ; 0x29: Display digit 3 (leftmost)
    DIGIT2                  ; 0x2A: Display digit 2
    DIGIT1                  ; 0x2B: Display digit 1
    DIGIT0                  ; 0x2C: Display digit 0 (rightmost)
    ENTRY_MODE              ; 0x2D: 1=Entry Mode, 0=Normal Mode
    DISPLAY_STATE           ; 0x2E: 0=Desired, 1=Ambient, 2=Fan
    CURRENT_DIGIT           ; 0x2F: Current digit being displayed (0-3)
    
    ; --- DEBOUNCE VARIABLES ---
    LAST_KEY                ; 0x30: Previously pressed key
    DEBOUNCE_COUNT          ; 0x31: Debounce counter
    RELEASE_COUNT           ; 0x32: Release counter
    KEY_PRESSED             ; 0x33: Key stable flag
    KEY_LOCKED              ; 0x34: Key lock flag
    
    ; --- TIMING VARIABLES ---
    T1_COUNT                ; 0x35: Timer1 counter (for 0.5s, 1s, 2s events)
    SCAN_REQ                ; 0x36: Keypad scan request flag
    DISPLAY_COUNTER         ; 0x37: Display update counter
    UPDATE_COUNTER          ; 0x38: Sensor update counter
    
    ; --- TEMPORARY VARIABLES ---
    TEMP                    ; 0x39: General temporary register
    W_TEMP                  ; 0x3A: W register save (ISR)
    STATUS_TEMP             ; 0x3B: STATUS register save (ISR)
    PCLATH_TEMP             ; 0x3C: PCLATH save (ISR)
    UART_TEMP               ; 0x3D: UART data temporary
    WORK_TEMP               ; 0x3E: Working register for calculations

    KEY_HOLD_TIMEOUT        ; 0x3F: Timeout counter for held keys
endc

;============================================================================
; INTERRUPT VECTOR
;============================================================================

org 0x0000
goto INIT

org 0x0004
goto ISR

;============================================================================
; INTERRUPT SERVICE ROUTINE (ISR)
;============================================================================
ISR:
    movwf W_TEMP
    swapf STATUS, W
    movwf STATUS_TEMP
    movf PCLATH, W
    movwf PCLATH_TEMP
    
    ;============================================================================
    ; CHECK INTERRUPTS IN PRIORITY ORDER
    ;============================================================================
    
    ; 1. TIMER1 INTERRUPT (HIGHEST PRIORITY - Timing Critical)
    btfss PIR1, TMR1IF
    goto NOT_TIMER1
    
    ; ========== TIMER1 HANDLER ==========
    TMR1_HANDLER:
        movlw 0x0B
        movwf TMR1H
        movlw 0xDC
        movwf TMR1L
        bcf PIR1, TMR1IF
        
        INCF T1_COUNT, F
        
        movf T1_COUNT, W
        xorlw 2
        btfsc STATUS, Z
        goto ONE_SECOND_EVENT
        
        movf T1_COUNT, W
        xorlw 4
        btfss STATUS, Z
        goto EXIT_INT
        goto TWO_SECOND_EVENT
    
    ONE_SECOND_EVENT:
        call TACH_READ
        goto EXIT_INT
    
    TWO_SECOND_EVENT:
        call TACH_READ
        call DISPLAY_CHANGE
        clrf T1_COUNT
        goto EXIT_INT
    
    NOT_TIMER1:
    ; 2. UART RX INTERRUPT (HIGH PRIORITY - Data Loss Risk)
    btfsc PIR1, RCIF
    goto UART_RX_HANDLER
    
    ; 3. KEYPAD INTERRUPT (LOWER PRIORITY)
    btfsc INTCON, RBIF
    goto RB_HANDLER
    
    goto EXIT_INT

;============================================================================
; RB PORT CHANGE HANDLER
;============================================================================
RB_HANDLER:
    movf PORTB, W
    bcf INTCON, RBIE
    bcf INTCON, RBIF
    bsf SCAN_REQ, 0
    goto EXIT_INT

;============================================================================
; DISPLAY CHANGE (Called from TWO_SECOND_EVENT)
;============================================================================
DISPLAY_CHANGE:
    movf ENTRY_MODE, F
    btfss STATUS, Z
    return
    
    INCF DISPLAY_STATE, F
    movf DISPLAY_STATE, W
    xorlw 3
    btfss STATUS, Z
    return
    clrf DISPLAY_STATE
    return

;============================================================================
; EXIT ISR
;============================================================================
EXIT_INT:
    movf PCLATH_TEMP, W
    movwf PCLATH
    swapf STATUS_TEMP, W
    movwf STATUS
    swapf W_TEMP, F
    swapf W_TEMP, W
    RETFIE

;============================================================================
; UART RX INTERRUPT HANDLER (OUTSIDE ISR)
;============================================================================
UART_RX_HANDLER:
    movf RCREG, W
    movwf UART_TEMP
    bcf PIR1, RCIF              ; Clear UART flag
    
    ; Check for errors first
    movf RCSTA, W
    andlw b'00000110'           ; Check FERR and OERR bits
    btfss STATUS, Z
    goto UART_ERROR
    
    ; Normal data processing
    btfsc UART_TEMP, 7          ; Check command type (Bit 7: 1=SET, 0=GET)
    goto CMD_SET
    goto CMD_GET

UART_ERROR:
    ; Clear error by reading RCREG multiple times
    movf RCREG, W
    movf RCREG, W
    movf RCREG, W
    goto EXIT_INT

;============================================================================
; 7-SEGMENT LOOKUP TABLE (Common Anode: 0=ON, 1=OFF)
;============================================================================

org 0x050
SEG_TABLE:
    addwf PCL, F
    retlw b'00000011'       ; 0
    retlw b'10011111'       ; 1
    retlw b'00100101'       ; 2
    retlw b'00001101'       ; 3
    retlw b'10011001'       ; 4
    retlw b'01001001'       ; 5
    retlw b'01000001'       ; 6
    retlw b'00011111'       ; 7
    retlw b'00000001'       ; 8
    retlw b'00001001'       ; 9
    retlw b'11111111'       ; BLANK (all off)
    retlw b'00010001'       ; A
    retlw b'11000001'       ; b
    retlw b'01100011'       ; C
    retlw b'10000101'       ; d
    retlw b'01100001'       ; E
    retlw b'01110001'       ; F

;============================================================================
; INITIALIZATION
;============================================================================

INIT:
    bcf INTCON, GIE         ; Disable interrupts during init
    
    call SET_TRIS           ; Configure port directions
    call TIMER1_INIT        ; Initialize Timer1
    call ADC_INIT           ; Initialize ADC
    call UART_INIT          ; Initialize UART
    call TACH_INIT          ; Initialize Tachometer
    
    ; Clear all ports
    clrf PORTA
    clrf PORTB
    clrf PORTC
    clrf PORTD
    
    ; Set default temperature: 25.0 degrees
    movlw .25
    movwf DESIRED_TEMP_H
    clrf DESIRED_TEMP_L
    
    ; Initialize variables
    clrf KEY_STATE
    clrf KEY_BUFFER
    clrf ENTRY_MODE
    clrf DISPLAY_STATE
    clrf T1_COUNT
    clrf SCAN_REQ
    clrf LAST_KEY
    clrf DEBOUNCE_COUNT
    clrf RELEASE_COUNT
    clrf KEY_PRESSED
    clrf CURRENT_DIGIT
    clrf KEY_LOCKED
    clrf DISPLAY_COUNTER
    clrf UPDATE_COUNTER
    clrf KEY_HOLD_TIMEOUT
    
    call DISPLAY_UPDATE     ; Show initial display
    
    ; Enable interrupts
    bsf INTCON, RBIE        ; RB Port Change Interrupt
    bcf INTCON, RBIF        ; Clear flag
    bsf INTCON, PEIE        ; Peripheral Interrupts
    bsf INTCON, GIE         ; Global Interrupt Enable
    
;============================================================================
; MAIN LOOP
;============================================================================

MAIN_LOOP:
    ; 1. DISPLAY DRIVE (multiplexing)
    call DISPLAY_DRIVE
    
    ; 2. SENSOR AND CONTROL UPDATE (every ~300ms)
    INCF UPDATE_COUNTER, F
    movf UPDATE_COUNTER, W
    xorlw .30
    btfss STATUS, Z
    goto SKIP_UPDATE
    
    clrf UPDATE_COUNTER
    call TEMP_READ          ; Read temperature from LM35
    call TEMP_CONTROL       ; Control heater/cooler
    
    ; Update display if in normal mode
    movf ENTRY_MODE, F
    btfss STATUS, Z
    goto SKIP_UPDATE
    call DISPLAY_UPDATE
    
SKIP_UPDATE:
    ; 3. KEYPAD READ
    btfss SCAN_REQ, 0       ; Scan requested?
    goto SKIP_KEYPAD
    
    call KEYPAD_READ
    btfss KEY_PRESSED, 0    ; Key stable?
    goto NO_KEY_IN_MAIN
    
    btfsc KEY_LOCKED, 0     ; Already processed?
    goto SKIP_KEYPAD
    
    call KEYPAD_PROCESS     ; Process the key
    bsf KEY_LOCKED, 0       ; Lock for debounce
    goto SKIP_KEYPAD
    
NO_KEY_IN_MAIN:
    bcf KEY_LOCKED, 0       ; Unlock
    
SKIP_KEYPAD:
    ; Key timeout check
    btfss KEY_PRESSED, 0
    goto SKIP_KEY_TIMEOUT
    
    INCF KEY_HOLD_TIMEOUT, F
    movf KEY_HOLD_TIMEOUT, W
    xorlw .100
    btfss STATUS, Z
    goto SKIP_KEY_TIMEOUT
    
    ; Key held too long - reset
    bcf KEY_PRESSED, 0
    clrf KEY_HOLD_TIMEOUT
    clrf KEY_STATE
    clrf ENTRY_MODE
    call DISPLAY_UPDATE

SKIP_KEY_TIMEOUT:
    ; UART işlemi ISR'de yapılıyor, burada polling yok!
    
    goto MAIN_LOOP
;============================================================================
; PORT CONFIGURATION (TRIS)
;============================================================================

SET_TRIS:
    bsf STATUS, RP0         ; Bank 1
    
    ; TRISA: RA0 (AN0) and RA4 are inputs
    movlw b'00010001'
    movwf TRISA
    
    ; TRISB: RB0-RB3 keypad columns (output), RB4-RB7 rows (input)
    movlw b'11110000'
    movwf TRISB
    
    ; TRISC: RC0-RC3 display, RC4-RC5 outputs, RC6-RC7 UART
    movlw b'10000000'
    movwf TRISC
    
    ; TRISD: All outputs (7-segment data)
    clrf TRISD
    
    ; Enable PORTB pull-ups
    bcf OPTION_REG, 7
    
    bcf STATUS, RP0         ; Bank 0
    return

;============================================================================
; TIMER1 INITIALIZATION (0.5 second interrupt)
;============================================================================

TIMER1_INIT:
    ; Timer1 Control Register: TMR1ON=1, Prescaler=1:8, Internal Clock
    movlw b'00110001'
    movwf T1CON
    
    ; Preload with 3036
    movlw 0x0B
    movwf TMR1H
    movlw 0xDC
    movwf TMR1L
    
    bcf PIR1, TMR1IF        ; Clear interrupt flag
    
    ; Enable Timer1 interrupt
    bsf STATUS, RP0
    bsf PIE1, TMR1IE
    bcf STATUS, RP0
    return

;============================================================================
; ADC INITIALIZATION (CORRECTED)
;============================================================================

ADC_INIT:
    bsf STATUS, RP0         ; Bank 1
    
    ; ADCON1: AN0 is analog, others digital
    movlw b'10001110'       ; ADFM=1 (right justify), VCFG=00, PCFG=1110
    movwf ADCON1
    
    bcf STATUS, RP0         ; Bank 0
    
    ; ADCON0: ADON=1, CHS0-2=000 (AN0), ADCS=010 (Fosc/8)
    movlw b'01000001'
    movwf ADCON0
    return

;============================================================================
; UART INITIALIZATION
;============================================================================

UART_INIT:
    bsf STATUS, RP0
    movlw .25
    movwf SPBRG
    movlw b'00100100'
    movwf TXSTA
    
    ; ✓ ADD THIS:
    bsf PIE1, RCIE              ; Enable UART RX Interrupt
    
    bcf STATUS, RP0
    movlw b'10010000'
    movwf RCSTA
    return

;============================================================================
; TACHOMETER INITIALIZATION (External Clock on RA4)
;============================================================================

TACH_INIT:
    bsf STATUS, RP0         ; Bank 1
    
    ; OPTION_REG: T0CS=1 (external), T0SE=0 (rising edge), PSA=1 (no prescaler)
    movlw b'00101000'
    movwf OPTION_REG
    
    bcf STATUS, RP0         ; Bank 0
    clrf TMR0               ; Clear timer
    return

;============================================================================
; KEYPAD SCANNING (4x4 Matrix)
;============================================================================

SCAN_KEYPAD:
    movlw b'11111111'
    movwf PORTB
    
    ; Column 1 LOW
    movlw b'11111110'
    movwf PORTB
    call KP_DELAY
    btfss PORTB, 4
    retlw '1'
    btfss PORTB, 5
    retlw '4'
    btfss PORTB, 6
    retlw '7'
    btfss PORTB, 7
    retlw '*'
    
    ; Column 2 LOW
    movlw b'11111101'
    movwf PORTB
    call KP_DELAY
    btfss PORTB, 4
    retlw '2'
    btfss PORTB, 5
    retlw '5'
    btfss PORTB, 6
    retlw '8'
    btfss PORTB, 7
    retlw '0'
    
    ; Column 3 LOW
    movlw b'11111011'
    movwf PORTB
    call KP_DELAY
    btfss PORTB, 4
    retlw '3'
    btfss PORTB, 5
    retlw '6'
    btfss PORTB, 6
    retlw '9'
    btfss PORTB, 7
    retlw '#'
    
    ; Column 4 LOW
    movlw b'11110111'
    movwf PORTB
    call KP_DELAY
    btfss PORTB, 4
    retlw 'A'
    btfss PORTB, 5
    retlw 'B'
    btfss PORTB, 6
    retlw 'C'
    btfss PORTB, 7
    retlw 'D'
    
    ; No key pressed
    movlw b'00000000'
    movwf PORTB
    retlw 0

KP_DELAY:
    movlw .50
    movwf TEMP
DELAY_LOOP:
    decfsz TEMP, F
    goto DELAY_LOOP
    return

;============================================================================
; KEYPAD READ WITH DEBOUNCE (CORRECTED)
;============================================================================

KEYPAD_READ:
    call SCAN_KEYPAD
    movwf KEY_VALUE
    
    movf KEY_VALUE, F
    btfsc STATUS, Z
    goto PROCESS_RELEASE    ; No key pressed
    
    ; === KEY PRESSED ===
    clrf RELEASE_COUNT      ; Reset release counter
    
    movf KEY_VALUE, W
    xorwf LAST_KEY, W       ; Has key changed?
    btfss STATUS, Z
    goto NEW_KEY
    
    ; === SAME KEY HELD ===
    INCF DEBOUNCE_COUNT, F
    movlw .20               ; Need 20 stable samples
    subwf DEBOUNCE_COUNT, W
    btfss STATUS, C
    return                  ; Not stable yet
    
    bsf KEY_PRESSED, 0      ; Key is stable!
    return
    
NEW_KEY:
    clrf DEBOUNCE_COUNT
    movf KEY_VALUE, W
    movwf LAST_KEY
    bcf KEY_PRESSED, 0
    return
    
;============================================================================
PROCESS_RELEASE:
;============================================================================
    ; Debounce release
    INCF RELEASE_COUNT, F
    movlw .20
    subwf RELEASE_COUNT, W
    btfss STATUS, C
    return                  ; Keep waiting
    
    ; === VERIFY PHYSICAL RELEASE ===
    
     clrf PORTB
    nop
    nop
    movf PORTB, W
    andlw b'11110000'           ; Check only rows
    xorlw b'11110000'           ; All rows HIGH?
    btfss STATUS, Z
    return                      ; Still pressed!
    
    ; === KEY RELEASED ===
    clrf DEBOUNCE_COUNT
    clrf LAST_KEY
    bcf KEY_PRESSED, 0
    clrf KEY_HOLD_TIMEOUT       ; ✓ RESET TIMEOUT
    
    ; === RE-ENABLE INTERRUPT ===
    clrf PORTB                  ; Set columns to 0
    nop
    nop
    movf PORTB, W               ; Read to clear mismatch
    bcf INTCON, RBIF            ; Clear pending flag
    bcf SCAN_REQ, 0             ; Clear scan request
    bsf INTCON, RBIE            ; Re-enable interrupt
    return


;============================================================================
; KEYPAD PROCESS
;============================================================================

KEYPAD_PROCESS:
    ; Button 'A' starts new entry
    movf KEY_VALUE, W
    xorlw 'A'
    btfsc STATUS, Z
    goto START_NEW_ENTRY
    
    ; Ignore other keys if not in entry mode
    movf ENTRY_MODE, F
    btfsc STATUS, Z
    return
    
    ; Button '#' confirms entry
    movf KEY_VALUE, W
    xorlw '#'
    btfsc STATUS, Z
    goto KP_CONFIRM
    
    ; Button '*' marks decimal point
    movf KEY_VALUE, W
    xorlw '*'
    btfsc STATUS, Z
    goto KP_FRACTION
    
    ; Digit entry (0-9)
    movf KEY_VALUE, W
    addlw -'0'
    btfss STATUS, C
    return                  ; Not a digit
    movwf TEMP
    movlw .10
    subwf TEMP, W
    btfsc STATUS, C
    return                  ; Greater than 9
    
    ; Process digit based on state
    movf KEY_STATE, W
    xorlw 1
    btfsc STATUS, Z
    goto FIRST_D
    movf KEY_STATE, W
    xorlw 2
    btfsc STATUS, Z
    goto SECOND_D
    movf KEY_STATE, W
    xorlw 4
    btfsc STATUS, Z
    goto FRACTION_D
    return

;============================================================================
START_NEW_ENTRY:
;============================================================================
    movlw 1
    movwf ENTRY_MODE
    movlw 1
    movwf KEY_STATE
    clrf DESIRED_TEMP_H
    clrf DESIRED_TEMP_L
    clrf KEY_BUFFER
    call DISPLAY_UPDATE
    return

;============================================================================
FIRST_D:
;============================================================================
    ; First digit (tens place)
    movf KEY_VALUE, W
    addlw -'0'
    movwf DESIRED_TEMP_H
    movlw 2
    movwf KEY_STATE
    call DISPLAY_UPDATE
    return

;============================================================================
SECOND_D:
;============================================================================
    ; Second digit (ones place)
    movf KEY_VALUE, W
    addlw -'0'
    movwf KEY_BUFFER
    movlw 3
    movwf KEY_STATE
    call DISPLAY_UPDATE
    return

;============================================================================
KP_FRACTION:
;============================================================================
    ; Decimal point pressed
    movf KEY_STATE, W
    xorlw 2
    btfsc STATUS, Z
    goto FRACTION_FROM_SINGLE
    
    movf KEY_STATE, W
    xorlw 3
    btfss STATUS, Z
    return
    
    clrf DESIRED_TEMP_L
    movlw 4
    movwf KEY_STATE
    call DISPLAY_UPDATE
    return

FRACTION_FROM_SINGLE:
    ; Single digit entered, then *
    movf DESIRED_TEMP_H, W
    movwf KEY_BUFFER
    clrf DESIRED_TEMP_H
    clrf DESIRED_TEMP_L
    movlw 4
    movwf KEY_STATE
    call DISPLAY_UPDATE
    return

;============================================================================
FRACTION_D:
;============================================================================
    ; Fractional digit
    movf KEY_VALUE, W
    addlw -'0'
    movwf DESIRED_TEMP_L
    movlw 5
    movwf KEY_STATE
    call DISPLAY_UPDATE
    return

;============================================================================
KP_CONFIRM:
;============================================================================
    ; Combine and validate entry
    movf KEY_STATE, W
    xorlw 2
    btfsc STATUS, Z
    goto CONFIRM_SINGLE
    
    movf KEY_STATE, W
    xorlw 3
    btfsc STATUS, Z
    goto CONFIRM_DOUBLE
    
    movf KEY_STATE, W
    xorlw 5
    btfsc STATUS, Z
    goto CONFIRM_DOUBLE
    return

CONFIRM_SINGLE:
    clrf KEY_BUFFER
    goto CONFIRM_DOUBLE

;============================================================================
CONFIRM_DOUBLE:
;============================================================================
    ; DESIRED_TEMP_H = 10 × first_digit + second_digit
    movf DESIRED_TEMP_H, W
    movwf KP_TEMP_H
    
    bcf STATUS, C
    rlf KP_TEMP_H, F        ; × 2
    rlf KP_TEMP_H, F        ; × 4
    rlf KP_TEMP_H, F        ; × 8
    movf DESIRED_TEMP_H, W
    addwf KP_TEMP_H, F      ; × 9
    addwf KP_TEMP_H, F      ; × 10
    
    movf KEY_BUFFER, W
    addwf KP_TEMP_H, W
    movwf DESIRED_TEMP_H
    
    ; === VALIDATION (10 - 50) DEGREES - CORRECTED ===
    ; Check if DESIRED_TEMP_H >= 10
    movlw .10
    subwf DESIRED_TEMP_H, W     ; DESIRED_TEMP_H - 10
    btfss STATUS, C             ; Carry = 0 means DESIRED < 10
    goto INVALID_INPUT
    
    ; Check if DESIRED_TEMP_H <= 50
    movf DESIRED_TEMP_H, W
    movlw .50
    subwf DESIRED_TEMP_H, W     ; DESIRED_TEMP_H - 50
    btfsc STATUS, C             ; Carry = 1 means DESIRED > 50
    goto INVALID_INPUT
    
    ; === VALID INPUT ===
    clrf ENTRY_MODE
    clrf KEY_STATE
    call DISPLAY_UPDATE
    return

INVALID_INPUT:
    ; Reset to default 25.0°C
    movlw .25
    movwf DESIRED_TEMP_H
    clrf DESIRED_TEMP_L
    clrf ENTRY_MODE
    call DISPLAY_UPDATE
    return

;============================================================================
; DISPLAY UPDATE
;============================================================================

DISPLAY_UPDATE:
    movf ENTRY_MODE, F
    btfsc STATUS, Z
    goto NORMAL_DISPLAY
    goto ENTRY_DISPLAY

;============================================================================
ENTRY_DISPLAY:
;============================================================================
    movf KEY_STATE, W
    xorlw 1
    btfsc STATUS, Z
    goto SHOW_ENTRY_A
    
    movf KEY_STATE, W
    xorlw 2
    btfsc STATUS, Z
    goto SHOW_1_DIGIT
    
    movf KEY_STATE, W
    xorlw 3
    btfsc STATUS, Z
    goto SHOW_2_DIGITS
    
    movf KEY_STATE, W
    xorlw 4
    btfsc STATUS, Z
    goto SHOW_WAIT_FRAC
    
    movf KEY_STATE, W
    xorlw 5
    btfsc STATUS, Z
    goto SHOW_FULL
    
    goto SHOW_BLANK

SHOW_ENTRY_A:
    movlw b'00010001'       ; 'A' pattern
    movwf DIGIT3
    movlw 0xFF
    movwf DIGIT2
    movwf DIGIT1
    movwf DIGIT0
    return

SHOW_BLANK:
    movlw 0xFF
    movwf DIGIT3
    movwf DIGIT2
    movwf DIGIT1
    movwf DIGIT0
    return

SHOW_1_DIGIT:
    movlw 0xFF
    movwf DIGIT3
    movf DESIRED_TEMP_H, W
    call SEG_TABLE
    movwf DIGIT2
    movlw 0xFF
    movwf DIGIT1
    movwf DIGIT0
    return

SHOW_2_DIGITS:
    movlw 0xFF
    movwf DIGIT3
    movf DESIRED_TEMP_H, W
    call SEG_TABLE
    movwf DIGIT2
    movf KEY_BUFFER, W
    call SEG_TABLE
    movwf DIGIT1
    movlw 0xFF
    movwf DIGIT0
    return

SHOW_WAIT_FRAC:
    movlw 0xFF
    movwf DIGIT3
    movf DESIRED_TEMP_H, W
    call SEG_TABLE
    movwf DIGIT2
    movf KEY_BUFFER, W
    call SEG_TABLE
    andlw b'11111110'       ; Decimal point active
    movwf DIGIT1
    movlw 0xFF
    movwf DIGIT0
    return

SHOW_FULL:
    movlw 0xFF
    movwf DIGIT3
    movf DESIRED_TEMP_H, W
    call SEG_TABLE
    movwf DIGIT2
    movf KEY_BUFFER, W
    call SEG_TABLE
    andlw b'11111110'
    movwf DIGIT1
    movf DESIRED_TEMP_L, W
    call SEG_TABLE
    movwf DIGIT0
    return

;============================================================================
NORMAL_DISPLAY:
;============================================================================
    movf DISPLAY_STATE, W
    xorlw 0
    btfsc STATUS, Z
    goto SHOW_DESIRED
    
    movf DISPLAY_STATE, W
    xorlw 1
    btfsc STATUS, Z
    goto SHOW_AMBIENT
    
    goto SHOW_FAN

SHOW_DESIRED:
    movf DESIRED_TEMP_H, W
    call TO_BCD
    movlw 0xFF
    movwf DIGIT3
    movf DIGIT2, W
    call SEG_TABLE
    movwf DIGIT2
    movf DIGIT1, W
    call SEG_TABLE
    andlw b'11111110'
    movwf DIGIT1
    movf DESIRED_TEMP_L, W
    call SEG_TABLE
    movwf DIGIT0
    return

SHOW_AMBIENT:
    movf AMBIENT_TEMP_H, W
    call TO_BCD
    movlw 0xFF
    movwf DIGIT3
    movf DIGIT2, W
    call SEG_TABLE
    movwf DIGIT2
    movf DIGIT1, W
    call SEG_TABLE
    andlw b'11111110'
    movwf DIGIT1
    movf AMBIENT_TEMP_L, W
    call SEG_TABLE
    movwf DIGIT0
    return

SHOW_FAN:
    movf FAN_SPEED, W
    call TO_BCD
    movlw 0xFF
    movwf DIGIT3
    movf DIGIT2, W
    call SEG_TABLE
    movwf DIGIT2
    movf DIGIT1, W
    call SEG_TABLE
    movwf DIGIT1
    movlw 0xFF
    movwf DIGIT0
    return

;============================================================================
TO_BCD:
;============================================================================
    ; Convert decimal number to BCD (tens and ones)
    movwf WORK_TEMP
    clrf DIGIT2             ; Tens place
    
BCDL1:
    movlw .10
    subwf WORK_TEMP, F
    btfss STATUS, C
    goto FIX
    INCF DIGIT2, F
    goto BCDL1
    
FIX:
    movlw .10
    addwf WORK_TEMP, W
    movwf DIGIT1            ; Ones place
    return

;============================================================================
; DISPLAY DRIVER (NPN Active HIGH - RC0, RC1, RC2, RC3)
;============================================================================

DISPLAY_DRIVE:
    ; 1. Turn OFF all displays (prevent ghosting)
    clrf PORTC
    clrf PORTD              ; CORRECTED: Clear segment data too
    
    ; 2. Select next digit and load data
    movf CURRENT_DIGIT, W
    xorlw 0
    btfsc STATUS, Z
    goto DD0
    
    movf CURRENT_DIGIT, W
    xorlw 1
    btfsc STATUS, Z
    goto DD1
    
    movf CURRENT_DIGIT, W
    xorlw 2
    btfsc STATUS, Z
    goto DD2
    
    movf CURRENT_DIGIT, W
    xorlw 3
    btfsc STATUS, Z
    goto DD3
    
    clrf CURRENT_DIGIT
    return

DD0:
    ; DIGIT0 → RC3
    movf DIGIT0, W
    movwf PORTD
    bsf PORTC, 3
    goto DD_NEXT

DD1:
    ; DIGIT1 → RC2
    movf DIGIT1, W
    movwf PORTD
    bsf PORTC, 2
    goto DD_NEXT

DD2:
    ; DIGIT2 → RC1
    movf DIGIT2, W
    movwf PORTD
    bsf PORTC, 1
    goto DD_NEXT

DD3:
    ; DIGIT3 → RC0
    movf DIGIT3, W
    movwf PORTD
    bsf PORTC, 0
    goto DD_NEXT

DD_NEXT:
    INCF CURRENT_DIGIT, F
    movf CURRENT_DIGIT, W
    xorlw 4
    btfss STATUS, Z
    return
    clrf CURRENT_DIGIT
    return

;============================================================================
; TEMPERATURE READING (CORRECTED - Use ADRESH instead of ADRESL)
;============================================================================

TEMP_READ:
    bsf ADCON0, GO              ; Start conversion
    
    ; Add acquisition delay (safe margin)
    movlw .3
    movwf TEMP
ADC_DELAY:
    decfsz TEMP, F
    goto ADC_DELAY
    
WAIT_ADC:
    btfsc ADCON0, GO            ; Wait for completion
    goto WAIT_ADC
    
    bsf STATUS, RP0         ; Bank 1
    movf ADRESH, W          ; CORRECTED: Read ADRESH (upper 8 bits)
    bcf STATUS, RP0         ; Bank 0
    
    movwf AMBIENT_TEMP_H    ; Store as integer part
    
    ; For LM35 sensor: Temperature in °C = ADC_VALUE / 5.12
    ; Approximation: Divide by 5 using shifts
    
    bcf STATUS, C           ; Clear carry
    rrf AMBIENT_TEMP_H, F   ; Divide by 2
    rrf AMBIENT_TEMP_H, F   ; Divide by 4 (approx ÷5)
    
    ; If carry = 1, fractional part = 0.5
    btfss STATUS, C
    goto TEMP_INT
    
    movlw 5
    movwf AMBIENT_TEMP_L    ; Fractional = 0.5
    return

TEMP_INT:
    clrf AMBIENT_TEMP_L     ; Fractional = 0.0
    return

;============================================================================
; TACHOMETER READ (Count pulses every 1 second)
;============================================================================

TACH_READ:
    movf TMR0, W            ; Read pulse count from TMR0
    movwf FAN_SPEED         ; Store as fan speed (rps)
    clrf TMR0               ; Reset counter
    return

;============================================================================
; TEMPERATURE CONTROL (CORRECTED Validation Logic)
;============================================================================

TEMP_CONTROL:
    ; Compare integers first
    movf AMBIENT_TEMP_H, W
    subwf DESIRED_TEMP_H, W     ; DESIRED_TEMP_H - AMBIENT_TEMP_H
    btfss STATUS, Z
    goto CHECK_SIGN_H           ; Not equal, check sign
    
    ; === EQUAL INTEGERS, CHECK FRACTIONAL ===
    movf AMBIENT_TEMP_L, W
    subwf DESIRED_TEMP_L, W     ; DESIRED_TEMP_L - AMBIENT_TEMP_L
    btfss STATUS, Z
    goto CHECK_SIGN_L
    
    ; === COMPLETELY EQUAL ===
    bcf PORTC, 4                ; Heater OFF
    bcf PORTC, 5                ; Fan OFF
    return

CHECK_SIGN_H:
    ; Check carry: 0 = Desired < Ambient (cool), 1 = Desired > Ambient (heat)
    btfss STATUS, C
    goto COOL_ON
    goto HEAT_ON

CHECK_SIGN_L:
    btfss STATUS, C
    goto COOL_ON
    goto HEAT_ON

HEAT_ON:
    bsf PORTC, 4            ; Heater ON
    bcf PORTC, 5            ; Fan OFF
    return

COOL_ON:
    bcf PORTC, 4            ; Heater OFF
    bsf PORTC, 5            ; Fan ON
    return

CMD_SET:
    btfsc UART_TEMP, 6      ; Bit 6: High or Low byte?
    goto SET_HIGH_BYTE
    
SET_LOW_BYTE:
    movlw b'00111111'
    andwf UART_TEMP, W
    movwf DESIRED_TEMP_L
    call DISPLAY_UPDATE
    return

SET_HIGH_BYTE:
    movlw b'00111111'
    andwf UART_TEMP, W
    movwf DESIRED_TEMP_H
    call DISPLAY_UPDATE
    return

CMD_GET:
    ; Send relevant data based on command code
    movf UART_TEMP, W
    xorlw 0x01
    btfsc STATUS, Z
    goto SEND_DESIRED_L
    
    movf UART_TEMP, W
    xorlw 0x02
    btfsc STATUS, Z
    goto SEND_DESIRED_H
    
    movf UART_TEMP, W
    xorlw 0x03
    btfsc STATUS, Z
    goto SEND_AMBIENT_L
    
    movf UART_TEMP, W
    xorlw 0x04
    btfsc STATUS, Z
    goto SEND_AMBIENT_H
    
    movf UART_TEMP, W
    xorlw 0x05
    btfsc STATUS, Z
    goto SEND_FAN_SPEED
    
    return

SEND_DESIRED_L:
    movf DESIRED_TEMP_L, W
    call SEND_BYTE
    return

SEND_DESIRED_H:
    movf DESIRED_TEMP_H, W
    call SEND_BYTE
    return

SEND_AMBIENT_L:
    movf AMBIENT_TEMP_L, W
    call SEND_BYTE
    return

SEND_AMBIENT_H:
    movf AMBIENT_TEMP_H, W
    call SEND_BYTE
    return

SEND_FAN_SPEED:
    movf FAN_SPEED, W
    call SEND_BYTE
    return

;============================================================================
; SEND ONE BYTE VIA UART (CORRECTED - No undefined label)
;============================================================================

SEND_BYTE:
    movwf UART_TEMP
    
WAIT_TX:
    bsf STATUS, RP0         ; Bank 1
    btfss TXSTA, TRMT       ; Is transmission buffer empty?
    goto WAIT_TX            ; CORRECTED: Loop back to WAIT_TX (not WAIT_TX_LOOP)
    
    bcf STATUS, RP0         ; Bank 0
    movf UART_TEMP, W
    movwf TXREG             ; Send data
    return

;============================================================================
END
