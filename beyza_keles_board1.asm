;#################################################################
; BOARD #1 - AIR CONDITIONER SYSTEM 
; NAME OF THE STUDENT: BEYZA KELES
;#################################################################

LIST p=16f877a
    INCLUDE "p16f877a.inc"
    __CONFIG _XT_OSC & _WDT_OFF & _PWRTE_ON & _BODEN_ON & _LVP_OFF & _CP_OFF

    ;---------------- VARIABLES ----------------
    cblock 0x20
    DESIRED_TEMP_H      
    DESIRED_TEMP_L     
    AMBIENT_TEMP_H      
    AMBIENT_TEMP_L
    FAN_SPEED
    
    KEY_VALUE           
    KEY_STATE           
    KEY_BUFFER          
    
    KP_TEMP_H           
    
    ; Display Registers (Left to the Right: D3, D2, D1, D0)
    DIGIT3             
    DIGIT2             ; tens
    DIGIT1             ; ones + decimal point
    DIGIT0             ; fractional part            
    
    ENTRY_MODE         ; 1=Entry Mode, 0=Normal Mode
    DISPLAY_STATE      ; 0=Desired, 1=Ambient, 2=Fan
    CURRENT_DIGIT       
    
    T1_COUNT            
    KEY_LOCKED          
    
    ; --- DEBOUNCE VARIABLES ---
    LAST_KEY            
    DEBOUNCE_COUNT      
    RELEASE_COUNT       
    KEY_PRESSED         
    
    ; --- INTERRUPT FLAG ---
    SCAN_REQ            
    
    TEMP
    W_TEMP
    STATUS_TEMP
    WORK_TEMP
    UART_TEMP
    PCLATH_TEMP
    
    DISPLAY_COUNTER     
    UPDATE_COUNTER
    endc
    
    org 0x0000
    goto INIT

;***************************************************
    org 0x0004
ISR:
    movwf   W_TEMP            
    swapf   STATUS, W         
    movwf   STATUS_TEMP        
    movf    PCLATH,W
    movwf   PCLATH_TEMP

    ; --- RB PORT CHANGE INTERRUPT CHECK ---
    btfsc INTCON, RBIF    
    goto RB_HANDLER       

    ; --- TIMER1 INTERRUPT CHECK ---
    btfss PIR1,TMR1IF
    goto EXIT_INT

TMR1_HANDLER:
    ; -------- preload 3036 ----------
    movlw 0x0B
    movwf TMR1H
    movlw 0xDC
    movwf TMR1L 
    bcf PIR1,TMR1IF 
    ;since TMR1 has a initial value of 3036, it counts 62500 times.
    ;62500*8us=0.5 seconds.
    
    ;number of 0.5seconds
    INCF T1_COUNT,F
    movf T1_COUNT,W
    xorlw 2
    btfsc STATUS,Z
    goto ONE_SECOND_EVENT ;T1_COUNT=2, one second elapsed.
    
    movf T1_COUNT,W
    xorlw 4
    btfss STATUS,Z
    goto EXIT_INT
    goto TWO_SECOND_EVENT ;T1_COUNT=4, two seconds elapsed.

ONE_SECOND_EVENT:
    call TACH_READ           
    goto EXIT_INT
;Every 1 seconds, tach_read should be implemented.
    
TWO_SECOND_EVENT:
    call TACH_READ           
    call DISPLAY_CHANGE      
    clrf T1_COUNT            
    goto EXIT_INT
;Every 2 seconds, both tach_read and display_change should be implemented.

RB_HANDLER:
   
    movf PORTB, W       ; Mismatch clear
    bcf INTCON, RBIE    ; Turn the interrupt OFF (don't turn it on until the main loop finishes its work)
    bcf INTCON, RBIF    ; clear flag
    bsf SCAN_REQ, 0     ; Give the main loop the "Scan" command.
    goto EXIT_INT

DISPLAY_CHANGE:
    ; Entry Mode Control: If it is 1 don't change display.
    movf ENTRY_MODE,F
    btfss STATUS,Z      
    return              
    
    ; Normal Mode
    INCF DISPLAY_STATE,F
    movf DISPLAY_STATE,W
    xorlw 3
    btfss STATUS,Z
    return
    clrf DISPLAY_STATE
    return

EXIT_INT:
    movf PCLATH_TEMP,W
    movwf PCLATH
    swapf  STATUS_TEMP, W
    movwf  STATUS
    swapf  W_TEMP, F
    swapf  W_TEMP, W
    RETFIE

;#################################################
; TABLE (Common Anode: 0=ON, 1=OFF)
;#################################################
    org 0x050
SEG_TABLE:
    addwf PCL,F
    retlw b'00000011' ; 0 
    retlw b'10011111' ; 1 
    retlw b'00100101' ; 2 
    retlw b'00001101' ; 3 
    retlw b'10011001' ; 4 
    retlw b'01001001' ; 5 
    retlw b'01000001' ; 6 
    retlw b'00011111' ; 7 
    retlw b'00000001' ; 8 
    retlw b'00001001' ; 9 
    retlw b'11111111' ; BLANK
    retlw b'00010001' ; A 
    retlw b'11000001' ; b
    retlw b'01100011' ; C
    retlw b'10000101' ; d
    retlw b'01100001' ; E
    retlw b'01110001' ; F

;#################################################
; INITIALIZATION
;#################################################
INIT:
    bcf INTCON,GIE      
    call SET_TRIS
    
    clrf PORTA
    clrf PORTB          
    clrf PORTC
    clrf PORTD
    
    call TIMER1_INIT
    call ADC_INIT
    call UART_INIT
    call TACH_INIT
    
    ; DEFAULT: 25.0 Degrees
    movlw .25
    movwf DESIRED_TEMP_H
    clrf DESIRED_TEMP_L
    
    clrf KEY_STATE
    clrf KEY_BUFFER
    clrf ENTRY_MODE
    clrf DISPLAY_STATE
    clrf T1_COUNT
    clrf SCAN_REQ       
    
    ;Debounce clear
    clrf LAST_KEY
    clrf DEBOUNCE_COUNT
    clrf RELEASE_COUNT
    clrf KEY_PRESSED
    
    clrf CURRENT_DIGIT
    clrf KEY_LOCKED
    clrf DISPLAY_COUNTER
    clrf UPDATE_COUNTER
    
    call DISPLAY_UPDATE
    
    ; INTERRUPTS ENABLE
    bsf INTCON, RBIE    
    bcf INTCON, RBIF    
    bsf INTCON, PEIE
    bsf INTCON, GIE

MAIN_LOOP:
    ; 1. DISPLAY DRIVE
    call DISPLAY_DRIVE
    
    ;2. Sensor and control
    INCF UPDATE_COUNTER,F
    movf UPDATE_COUNTER,W
    xorlw .30
    btfss STATUS,Z
    goto SKIP_UPDATE
    clrf UPDATE_COUNTER
    
    call TEMP_READ
    call TEMP_CONTROL
    
    movf ENTRY_MODE,F
    btfss STATUS,Z
    goto SKIP_UPDATE    
    call DISPLAY_UPDATE

SKIP_UPDATE:
    ;3. Keypad Read
    btfss SCAN_REQ, 0   
    goto SKIP_KEYPAD    
    
    call KEYPAD_READ    
    
    btfss KEY_PRESSED, 0
    goto NO_KEY_IN_MAIN
    
    btfsc KEY_LOCKED, 0
    goto SKIP_KEYPAD
    
    call KEYPAD_PROCESS
    bsf KEY_LOCKED, 0
    goto SKIP_KEYPAD

NO_KEY_IN_MAIN:
    bcf KEY_LOCKED, 0

SKIP_KEYPAD:
    call UART_SERVICE
    goto MAIN_LOOP
    
;*********************************************************************
SET_TRIS:
    bsf STATUS,RP0      ;Bank 1 
    movlw b'00010001'   ; RA0 (AN0) and RA4 are input.
    movwf TRISA
    movlw b'11110000'   ;RB0-RB3 are keypad column output, RB4-RB7 are keypad row input.
    movwf TRISB
    movlw b'10000000'	;RC0-RC3 are SSD digits, RC4 heater output, RC5 cooler output , RC6 is UART TX (output),and RC7 is UART RX (input)
    movwf TRISC
    clrf TRISD         ;RD0-RD7 are SSD outputs
    bcf OPTION_REG, 7   ;PORTB pull-ups enable
    bcf STATUS,RP0      ;Bank 0
    return
    
TIMER1_INIT:
    movlw b'00110001'  ; TMR1ON=1 , prescaler=1:8 , internal clock
    movwf T1CON
    movlw 0x0B
    movwf TMR1H
    movlw 0xDC
    movwf TMR1L         ;TMR1=3036
    bcf PIR1,TMR1IF     ;TMR1IF=0
    bsf STATUS,RP0      
    bsf PIE1,TMR1IE    ;TMR1IE=1
    bcf STATUS,RP0
    return

ADC_INIT:
    bsf STATUS,RP0
    movlw b'10001110'  
    movwf ADCON1	;ADFM=1 right justified, AN0 analog, AN1-AN4 digital
    bcf STATUS,RP0
    movlw b'01000001'    ; ADON=1, GO=0 conversion is not started, CHS0-2=000 channel 0 (RA0/AN0), ADCS0-2=010 clock conversion Fosc/8
    movwf ADCON0
    return
    
UART_INIT:
    bsf STATUS,RP0
    movlw .25          ;Baud rate=9600 Fosc=4MHz,BRGH=1 ,SPBRG=25
    movwf SPBRG
    movlw b'00100100'  ; asynchronous mode, BRGH=1 high speed,TXEN=1
    movwf TXSTA
    bcf STATUS,RP0
    movlw b'10010000'  
    movwf RCSTA		;SPEN=1, CREN=1. Serial port is active and CREn is open.
    return

TACH_INIT:
    bsf STATUS,RP0
    movlw b'00101000'  
    movwf OPTION_REG	    ;T0CS=1 external clock(RA4), T0SE=0 rising edge,PSA=1 prescaler is not used by TMR0.
    bcf STATUS,RP0
    clrf TMR0
    return

;#################################################################
; KEYPAD SCANNING 
;#################################################################
SCAN_KEYPAD:
    movlw b'11111111'
    movwf PORTB
    
    movlw b'11111110' ; Col 1 Low
    movwf PORTB
    call KP_DELAY
    btfss PORTB,4     
    retlw '1'
    btfss PORTB,5
    retlw '4'
    btfss PORTB,6
    retlw '7'
    btfss PORTB,7
    retlw '*'

    movlw b'11111101' ; Col 2 Low
    movwf PORTB
    call KP_DELAY
    btfss PORTB,4
    retlw '2'
    btfss PORTB,5
    retlw '5'
    btfss PORTB,6
    retlw '8'
    btfss PORTB,7
    retlw '0'

    movlw b'11111011' ; Col 3 Low
    movwf PORTB
    call KP_DELAY
    btfss PORTB,4
    retlw '3'
    btfss PORTB,5
    retlw '6'
    btfss PORTB,6
    retlw '9'
    btfss PORTB,7
    retlw '#'

    movlw b'11110111' ; Col 4 Low
    movwf PORTB
    call KP_DELAY
    btfss PORTB,4
    retlw 'A'
    btfss PORTB,5
    retlw 'B'
    btfss PORTB,6
    retlw 'C'
    btfss PORTB,7
    retlw 'D'
    
    ;Scanning complete, set columns to 0 (Prepare for cutting)
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

;#################################################################
; KEYPAD READ
;#################################################################
KEYPAD_READ:
    call SCAN_KEYPAD
    movwf KEY_VALUE
    
    movf KEY_VALUE,F
    btfsc STATUS,Z
    goto PROCESS_RELEASE   ;If the key is not read, go to Release control.
    
    ;--- Key Pressed ---
    clrf RELEASE_COUNT	    ;Reset release counter.
    
    movf KEY_VALUE,W
    xorwf LAST_KEY,W	    ;Has the key changed?
    btfss STATUS,Z
    goto NEW_KEY            ;New key is pressed.
    
    ;The same key remains pressed.
    INCF DEBOUNCE_COUNT,F
    movlw .20		    ;Debounce counter waits 20 loops.
    subwf DEBOUNCE_COUNT,W
    btfss STATUS,C
    return                 ;Not stable yet. Exit.
    
    bsf KEY_PRESSED,0      ;Stable. Flag is removed.
    return

NEW_KEY:
    clrf DEBOUNCE_COUNT	    ;New key is pressed. Reset the counter.
    movf KEY_VALUE,W
    movwf LAST_KEY	    ;Save the key.
    bcf KEY_PRESSED,0
    return


PROCESS_RELEASE:
    ; 1. Debounce Control
    INCF RELEASE_COUNT,F
    movlw .20		    ;Wait for 20 loops to release.
    subwf RELEASE_COUNT,W
    btfss STATUS,C
    return                 ;No action is taken yet.
    
    ; 2. PHYSICAL RELEASE CONTROL
    
    clrf PORTB          ; Set the columns to 0.
    nop
    nop
    movf PORTB, W       
    andlw b'11110000'   ; Mask only the columns (RB4-7)
    xorlw b'11110000'   ; Are they all 1?
    btfss STATUS, Z
    return              ;If Z=0 , the key is still pressed! Return the value, let the loop continue.
    
    ; 3.Key released
    clrf DEBOUNCE_COUNT
    clrf LAST_KEY
    bcf KEY_PRESSED,0
    
    ; 4. Prepare for interrupt
    bcf STATUS, RP0
    clrf PORTB          ; Set the columns to 0.
    
    bcf SCAN_REQ, 0     ; close request
    
    movf PORTB, W       ; clear Mismatch
    bcf INTCON, RBIF    ; clear flag
    bsf INTCON, RBIE    ;enable RBIE back
    return

;#################################################################
; KEYPAD PROCESS 
;#################################################################
KEYPAD_PROCESS:
    ; A: Start a new enrty
    movf KEY_VALUE,W
    xorlw 'A'
    btfsc STATUS,Z
    goto START_NEW_ENTRY

    ;Ignore other keys if not in entry mode.
    movf ENTRY_MODE,F
    btfsc STATUS,Z
    return

    ; #: Confirm
    movf KEY_VALUE,W
    xorlw '#'
    btfsc STATUS,Z
    goto KP_CONFIRM

    ; *: Decimal Point
    movf KEY_VALUE,W
    xorlw '*'
    btfsc STATUS,Z
    goto KP_FRACTION

    ; Figure Control (0-9)
    movf KEY_VALUE,W
    addlw -'0'
    btfss STATUS,C
    return
    movwf TEMP
    movlw .10
    subwf TEMP,W
    btfsc STATUS,C
    return

    ; State Control
    movf KEY_STATE,W
    xorlw 1
    btfsc STATUS,Z
    goto FIRST_D     ;Save the first digit.
    movf KEY_STATE,W
    xorlw 2
    btfsc STATUS,Z
    goto SECOND_D    ;Save the second digit.
    movf KEY_STATE,W
    xorlw 4
    btfsc STATUS,Z
    goto FRACTION_D  ;Save the fractional digit.
    return

START_NEW_ENTRY:
    movlw 1
    movwf ENTRY_MODE
    movlw 1
    movwf KEY_STATE
    
    clrf DESIRED_TEMP_H
    clrf DESIRED_TEMP_L
    clrf KEY_BUFFER
    call DISPLAY_UPDATE
    return

FIRST_D:
    ; The first digit (tens) is saved to DESIRED_TEMP_H.
    movf KEY_VALUE,W
    addlw -'0'
    movwf DESIRED_TEMP_H
    movlw 2
    movwf KEY_STATE    ;key_state is changed to read the second digit.
    call DISPLAY_UPDATE
    return

SECOND_D:
    ; The second digigt (ones) is saved to KEY_BUFFER.
    movf KEY_VALUE,W
    addlw -'0'
    movwf KEY_BUFFER
    movlw 3       ;key_state is changed to be ready to read '*'.
    movwf KEY_STATE
    call DISPLAY_UPDATE
    return

KP_FRACTION:
    ; * is pushed. Fractional mode is open.
    movf KEY_STATE,W
    xorlw 2
    btfsc STATUS,Z
    goto FRACTION_FROM_SINGLE   ;If it was pushed when there was only one digit
    
    movf KEY_STATE,W
    xorlw 3
    btfss STATUS,Z
    return
    
    clrf DESIRED_TEMP_L
    movlw 4
    movwf KEY_STATE
    call DISPLAY_UPDATE
    return

FRACTION_FROM_SINGLE:
    ; If a single digit was entered, then * was pressed 
    ; Shift the value in H to the ones place (X.)
    movf DESIRED_TEMP_H,W
    movwf KEY_BUFFER
    clrf DESIRED_TEMP_H
    
    clrf DESIRED_TEMP_L
    movlw 4
    movwf KEY_STATE    ;Key state is changed to read the fraction digit.
    call DISPLAY_UPDATE
    return

FRACTION_D:
    ;Fraction digit is saved.
    movf KEY_VALUE,W
    addlw -'0'
    movwf DESIRED_TEMP_L
    movlw 5
    movwf KEY_STATE     ;Key state is changed to read #.
    call DISPLAY_UPDATE
    return

KP_CONFIRM:
    ;Combining and Saving Numbers
    movf KEY_STATE,W
    xorlw 2
    btfsc STATUS,Z
    goto CONFIRM_SINGLE
    
    movf KEY_STATE,W
    xorlw 3
    btfsc STATUS,Z
    goto CONFIRM_DOUBLE
    
    movf KEY_STATE,W
    xorlw 5
    btfsc STATUS,Z
    goto CONFIRM_DOUBLE
    return

CONFIRM_SINGLE:
    clrf KEY_BUFFER    ;If an only value is pressed, the second digit (tens) is 0.
    goto CONFIRM_DOUBLE

CONFIRM_DOUBLE:
    ;DESIRED_TEMP_H= 10*first digit+ second digit
    movf DESIRED_TEMP_H,W
    movwf KP_TEMP_H
    bcf STATUS,C
    rlf KP_TEMP_H,F ;x2
    rlf KP_TEMP_H,F ;x4
    rlf KP_TEMP_H,F ;x8
    movf DESIRED_TEMP_H,W
    addwf KP_TEMP_H,F ;x9
    addwf KP_TEMP_H,F ;x10
    ;the first digit is multplied by 10 and stored in KP_TEMP_H.
    
    movf KEY_BUFFER,W
    addwf KP_TEMP_H,W
    movwf DESIRED_TEMP_H
    
    ; Validitaion (10-50) Degrees
    movf DESIRED_TEMP_H,W
    sublw .9
    btfsc STATUS,C
    goto INVALID_INPUT
    
    movf DESIRED_TEMP_H,W
    sublw .50
    btfss STATUS,C
    goto INVALID_INPUT
    
    clrf ENTRY_MODE    ;Entry mode is closed and return back to normal.
    clrf KEY_STATE
    call DISPLAY_UPDATE
    return

INVALID_INPUT:
    ;The default value 25.0 is displayed in case of invalid input.
    movlw .25
    movwf DESIRED_TEMP_H
    clrf DESIRED_TEMP_L
    clrf ENTRY_MODE
    call DISPLAY_UPDATE
    return

;#################################################################
; DISPLAY UPDATE (FORMAT: _ XX.X )
;#################################################################
DISPLAY_UPDATE:
    movf ENTRY_MODE,F
    btfsc STATUS,Z
    goto NORMAL_DISPLAY
    goto ENTRY_DISPLAY

ENTRY_DISPLAY:
    movf KEY_STATE,W
    xorlw 1
    btfsc STATUS,Z
    goto SHOW_ENTRY_A    ;Waiting for the first digit entry and show A.
    movf KEY_STATE,W
    xorlw 2
    btfsc STATUS,Z
    goto SHOW_1_DIGIT    ;The digit is pressed is showed(X). Waiting for the second digit entry.
    movf KEY_STATE,W
    xorlw 3
    btfsc STATUS,Z
    goto SHOW_2_DIGITS    ;2 keys are presed are showed(XX). Waiting for the * entry.
    movf KEY_STATE,W
    xorlw 4
    btfsc STATUS,Z
    goto SHOW_WAIT_FRAC	    ;(XX.)  Waiting for the fractional digit entry.
    movf KEY_STATE,W
    xorlw 5
    btfsc STATUS,Z
    goto SHOW_FULL	    ;(XX.X)
    goto SHOW_BLANK

SHOW_ENTRY_A:
    movlw b'00010001' ; 'A' pattern
    movwf DIGIT3
    movlw 0xFF        
    movwf DIGIT2
    movwf DIGIT1
    movwf DIGIT0
    return

SHOW_BLANK:
    movlw 0xFF        ; 0xFF = All segments are off (Common Anode 1=OFF)
    movwf DIGIT3
    movwf DIGIT2
    movwf DIGIT1
    movwf DIGIT0
    return

SHOW_1_DIGIT:
    movlw 0xFF
    movwf DIGIT3
    movf DESIRED_TEMP_H,W
    call SEG_TABLE
    movwf DIGIT2       ;The first digit is showed in D2.
    movlw 0xFF
    movwf DIGIT1
    movwf DIGIT0
    return

SHOW_2_DIGITS:
    movlw 0xFF
    movwf DIGIT3
    movf DESIRED_TEMP_H,W
    call SEG_TABLE
    movwf DIGIT2
    movf KEY_BUFFER,W
    call SEG_TABLE
    movwf DIGIT1       ;The second digit is showed in D1.
    movlw 0xFF
    movwf DIGIT0
    return

SHOW_WAIT_FRAC:
    movlw 0xFF
    movwf DIGIT3
    movf DESIRED_TEMP_H,W
    call SEG_TABLE
    movwf DIGIT2
    movf KEY_BUFFER,W
    call SEG_TABLE
    andlw b'11111110'	;dp is active in D1.
    movwf DIGIT1
    movlw 0xFF
    movwf DIGIT0
    return

SHOW_FULL:
    movlw 0xFF
    movwf DIGIT3
    movf DESIRED_TEMP_H,W
    call SEG_TABLE
    movwf DIGIT2
    movf KEY_BUFFER,W
    call SEG_TABLE
    andlw b'11111110'
    movwf DIGIT1
    movf DESIRED_TEMP_L,W
    call SEG_TABLE	;The fractonal digit is showed in D0.
    movwf DIGIT0       
    return

NORMAL_DISPLAY:
    movf DISPLAY_STATE,W
    xorlw 0
    btfsc STATUS,Z
    goto SHOW_DESIRED
    movf DISPLAY_STATE,W
    xorlw 1
    btfsc STATUS,Z
    goto SHOW_AMBIENT
    goto SHOW_FAN

SHOW_DESIRED:
    ;(XX.X)
    movf DESIRED_TEMP_H,W
    call TO_BCD
    movlw 0xFF
    movwf DIGIT3
    movf DIGIT2,W
    call SEG_TABLE
    movwf DIGIT2
    movf DIGIT1,W
    call SEG_TABLE
    andlw b'11111110'
    movwf DIGIT1
    movf DESIRED_TEMP_L,W
    call SEG_TABLE
    movwf DIGIT0
    return

SHOW_AMBIENT:
    ;(XX.X)
    movf AMBIENT_TEMP_H,W
    call TO_BCD
    movlw 0xFF
    movwf DIGIT3
    movf DIGIT2,W
    call SEG_TABLE
    movwf DIGIT2
    movf DIGIT1,W
    call SEG_TABLE
    andlw b'11111110'
    movwf DIGIT1
    movf AMBIENT_TEMP_L,W
    call SEG_TABLE
    movwf DIGIT0
    return

SHOW_FAN:
    ;(XX) (rps)
    movf FAN_SPEED,W
    call TO_BCD
    movlw 0xFF
    movwf DIGIT3
    movf DIGIT2,W
    call SEG_TABLE
    movwf DIGIT2
    movf DIGIT1,W
    call SEG_TABLE
    movwf DIGIT1
    movlw 0xFF
    movwf DIGIT0
    return

TO_BCD:
    movwf WORK_TEMP
    clrf DIGIT2
BCDL1:
    movlw .10
    subwf WORK_TEMP,F
    btfss STATUS,C
    goto FIX
    INCF DIGIT2,F
    goto BCDL1
FIX:
    movlw .10
    addwf WORK_TEMP,W
    movwf DIGIT1
    return

;#################################################################
; DISPLAY DRIVER (NPN Active HIGH - RC0, RC1, RC2, RC3)
;#################################################################
DISPLAY_DRIVE:
    ; 1. All digit are off to prevent ghosting.
    clrf PORTC
    
    ; 2. Select the next digit and load the data.
    movf CURRENT_DIGIT,W
    xorlw 0
    btfsc STATUS,Z
    goto DD0
    movf CURRENT_DIGIT,W
    xorlw 1
    btfsc STATUS,Z
    goto DD1
    movf CURRENT_DIGIT,W
    xorlw 2
    btfsc STATUS,Z
    goto DD2
    movf CURRENT_DIGIT,W
    xorlw 3
    btfsc STATUS,Z
    goto DD3
    
    clrf CURRENT_DIGIT
    return

DD0:
    ; DIGIT0 -> RC3 
    movf DIGIT0,W
    movwf PORTD
    bsf PORTC,3    
    goto DD_NEXT

DD1:
    ; DIGIT1 -> RC2
    movf DIGIT1,W
    movwf PORTD
    bsf PORTC,2
    goto DD_NEXT

DD2:
    ; DIGIT2 -> RC1
    movf DIGIT2,W
    movwf PORTD
    bsf PORTC,1
    goto DD_NEXT

DD3:
    ; DIGIT3 -> RC0 
    movf DIGIT3,W
    movwf PORTD
    bsf PORTC,0
    goto DD_NEXT

DD_NEXT:
    ;Increase CURRENT_DIGIT for the next scan.
    INCF CURRENT_DIGIT,F
    movf CURRENT_DIGIT,W
    xorlw 4
    btfss STATUS,Z
    return
    clrf CURRENT_DIGIT
    return

;#################################################################
; SENSORS & UART
;#################################################################
TEMP_READ:
    bsf ADCON0, GO    ;Start ADC conversion.
WAIT_ADC:
    btfsc ADCON0, GO
    goto WAIT_ADC    ;If GO=1 it is proceeding, if GO=0 it is over.
    
    bsf STATUS,RP0
    movf ADRESL, W
    bcf STATUS,RP0
    movwf AMBIENT_TEMP_H     ;Since temperature range is 10-50, ADDRESH=0.
    
    bcf STATUS, C
    rrf AMBIENT_TEMP_H, F     ;Temperature=(ADC value)/2  is obtained by rotating ADC value to the right.
    btfss STATUS, C
    goto TEMP_INT	     ;If C=0, the temperature is an integer. If C=1,it has the fractional part 0.5.
    movlw 5
    movwf AMBIENT_TEMP_L
    return
TEMP_INT:
    clrf AMBIENT_TEMP_L
    return
    
TACH_READ:
    movf TMR0,W		    ;TMR0 counts the number of pulses caused by every turn of the fan.
    movwf FAN_SPEED	    ;TMR0 value is written in FAN_SPEED every 1 seconds.
    clrf TMR0
    return

TEMP_CONTROL:
; ================= INTEGER COMPARISION =================
    movf AMBIENT_TEMP_H, W
    subwf DESIRED_TEMP_H, W
    btfss STATUS, Z
    goto CHECK_SIGN_H
    
; ======= FRACTION COMPARISION =======
    movf AMBIENT_TEMP_L, W
    subwf DESIRED_TEMP_L, W
    btfss STATUS, Z
    goto CHECK_SIGN_L
    
; ======= EQUAL =======
    bcf PORTC,4	    ; Heater OFF
    bcf PORTC,5	    ; Fan OFF
    return
; ================= INTEGER SIGN CONTROL =================
CHECK_SIGN_H:
    btfss STATUS, C	
    goto COOL_ON	;If desired < ambient  go to cool.
    goto HEAT_ON	;If desired > ambient  go to heat.
    
; ================= FRACTION SIGN CONTROL ================
CHECK_SIGN_L:
    btfss STATUS, C
    goto COOL_ON
    goto HEAT_ON
    
; ========================================================
HEAT_ON:
    bsf PORTC,4	    ; Heater ON
    bcf PORTC,5	    ; Fan OFF
    return
    
COOL_ON:
    bcf PORTC,4	    ; Heater OFF
    bsf PORTC,5	    ; Fan ON
    return
;**********************************************************
    
UART_SERVICE:
    btfss PIR1, RCIF	;Did the data arrive?
    return
    movf RCREG, W	;Receive  the data.
    movwf UART_TEMP
    btfsc UART_TEMP, 7	 ;Bit 7 control (1=Set, 0=Get)
    goto CMD_SET
    goto CMD_GET
CMD_SET:
    btfsc UART_TEMP, 6	  ;Bit 6 control (H veya L byte)
    goto SET_HIGH_BYTE
SET_LOW_BYTE:
    movlw b'00111111'	  ;Masking
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
    ;Send the relevant data according to the incoming command.
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
SEND_BYTE:
WAIT_TX:
    bsf STATUS,RP0
    btfss TXSTA, TRMT	;Is the sending buffer empty?
    goto WAIT_TX_LOOP
    bcf STATUS,RP0
    movwf TXREG		;Send data
    return
    
WAIT_TX_LOOP:
    bcf STATUS,RP0
    goto WAIT_TX
    
    END
    