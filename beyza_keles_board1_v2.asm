;#################################################################
; BOARD #1 - AIR CONDITIONER SYSTEM 
; NAME OF THE STUDENT: BEYZA KELES
;#################################################################

LIST p=16f877a
    INCLUDE "p16f877a.inc"
    __CONFIG _XT_OSC & _WDT_OFF & _PWRTE_ON & _BODEN_ON & _LVP_OFF & _CP_OFF

   ;---------------- VARIABLES ----------------
    ; Bu blokta projede kullandigim tum degiskenleri tanimliyorum.
    ; Sicaklik (desired/ambient), fan hizi, keypad durumu ve display icin ayri ayri degiskenler var.
    cblock 0x20
    DESIRED_TEMP_H      
    DESIRED_TEMP_L     
    AMBIENT_TEMP_H      
    AMBIENT_TEMP_L
    FAN_SPEED


    TH_H                ; threshold high/low temp integer
    TH_L                ; threshold high/low temp fractional (0 or 5)
                        ; bit2=SET_H_READY,     bit3=SET_L_READY

    
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
    

    ; --- UART (RX interrupt) ---
    ; UART tarafinda sadece son gelen byte'i ve RX bayragini tutuyorum.
    ; Amac: interrupt icinde isi kisa tutup, main loop'ta komutlari rahat islemek.
    UART_RX_BYTE       
    UART_FLAGS          

    TEMP
    W_TEMP
    STATUS_TEMP
    WORK_TEMP
    PCLATH_TEMP
    
    DISPLAY_COUNTER     
    UPDATE_COUNTER
    endc
    
    org 0x0000
    goto INIT

;***************************************************
    org 0x0004
ISR:
      ; ===== KESME (INTERRUPT) RUTINI =====
    ; Timer1, PORTB degisim (keypad) ve UART RX gibi olaylar olunca buraya geliyoruz.
    ; Ilk is olarak W ve STATUS gibi register'lari sakliyorum, yoksa main program bozulur.

    movwf   W_TEMP            
    swapf   STATUS, W         
    movwf   STATUS_TEMP        
    movf    PCLATH,W
    movwf   PCLATH_TEMP
    ; Force Bank0 for ISR work (NEW)
    bcf STATUS, RP0
    bcf STATUS, RP1

     ; --- UART RX INTERRUPT CHECK ---
    ; UART'tan byte geldiyse (RCIF=1) RCREG okunur ve RX bayragi set edilir.
    ; Not: RCREG okumak RCIF bayraginin temizlenmesine yardimci olur.

    btfsc PIR1, RCIF
    call  UART_RX_ISR

_ISR_CHK_RB:

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
    bsf SCAN_REQ, 1     ; TEMP_REQ: update TEMP_READ/TEMP_CONTROL in main loop (1Hz)
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


;-----------------------------
; UART RX ISR (keep it SHORT)
; Stores last byte in UART_RX_BYTE and sets UART_FLAGS.bit0
;-----------------------------
UART_RX_ISR:
       ; ===== UART RX ISR =====
    ; Burada mumkun oldugunca kisa kaliyorum.
    ; Sadece gelen byte'i alip UART_RX_BYTE degiskenine yaziyorum
    ; ve RX_READY bayragini set ediyorum.

    ; Overrun error olusursa CREN resetlenerek UART tekrar aktif ediliyor.

    btfsc   RCSTA, OERR
    goto    UART_CLR_OERR_ISR

    ; Read received byte (clears RCIF when FIFO empties)
    movf    RCREG, W
    movwf   UART_RX_BYTE
    bsf     UART_FLAGS, 0
    return

UART_CLR_OERR_ISR:
    bcf     RCSTA, CREN
    bsf     RCSTA, CREN
    ; Flush
    ; UART FIFO'da kalan byte varsa RCREG okunarak buffer temizlenir.
    btfsc   PIR1, RCIF
    movf    RCREG, W
    bcf     UART_FLAGS, 0
    return


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
     ; ===== BASLANGIC (INIT) =====
    ; Donanim ayarlarini burada yapiyorum: TRIS, Timer1, ADC, UART, TMR0 (tach).
    ; Sonra varsayilan degerleri atayip kesmeleri aciyorum.

    bcf INTCON,GIE      
    call SET_TRIS
    
    clrf PORTA
    clrf PORTB          
    clrf PORTC
    clrf PORTD
    
    call TIMER1_INIT
    call ADC_INIT

    call TACH_INIT
    
    call UART_INIT
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
    bsf STATUS,RP0
    bsf PIE1,RCIE     ; Enable UART RX interrupt
    bcf STATUS,RP0
    bsf INTCON, GIE

MAIN_LOOP:
    ; ===== ANA DÃ–NGÃœ =====
       ; Display multiplex surekli calisir.
    ; Timer1 ISR ile periyodik sensor ve kontrol yapilir.
    ; PORTB degisim kesmesi ile keypad okunur.
    ; 1. DISPLAY DRIVE
    call DISPLAY_DRIVE
    
    ;2. Sensor and control (rate-limited: 1Hz via Timer1 ISR flag)
    btfss SCAN_REQ, 1        ; TEMP_REQ set by ISR?
    goto SKIP_UPDATE
    bcf   SCAN_REQ, 1

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
    goto MAIN_LOOP
    
;*********************************************************************
SET_TRIS:
    ; ===== TRIS AYARLARI =====
    ; RA0: LM35 ADC giri?i, RA4: Tach (TMR0 harici clock)
    ; RB4-RB7: keypad sat?rlar (input), RB0-RB3: keypad sÃ¼tunlar (output)
    ; RC0-RC3: 7seg digit seçimi, RC4: heater, RC5: fan/cooler, RC6: TX, RC7: RX
     bcf STATUS,RP1
    bsf STATUS,RP0      ;Bank 1 
    movlw b'00010001'   ; RA0 (AN0) and RA4 are input.
    movwf TRISA
    movlw b'11110000'   ;RB0-RB3 are keypad column output, RB4-RB7 are keypad row input.
    movwf TRISB
    movlw b'10000000'    ; RC0-RC3: 7-seg digit enables, RC4: heater, RC5: fan, RC6: TX, RC7: RX (UART)
    movwf TRISC
    clrf TRISD         ;RD0-RD7 are SSD outputs
    bcf OPTION_REG, 7   ;PORTB pull-ups enable
    bcf STATUS,RP0      ;Bank 0
    return
    
TIMER1_INIT:
    ; ===== TIMER1 =====
    ; Timer1 prescaler 1:8. ISR sayimi ile 1 ve 2 saniyelik olaylar olusturuluyor.
    movlw b'00110001'  ; TMR1ON=1 , prescaler=1:8 , internal clock
    movwf T1CON
    movlw 0x0B
    movwf TMR1H
    movlw 0xDC
    movwf TMR1L         ;TMR1=3036
    bcf PIR1,TMR1IF     ;TMR1IF=0
     bcf STATUS,RP1
    bsf STATUS,RP0      
    bsf PIE1,TMR1IE    ;TMR1IE=1
    bcf STATUS,RP0
    return

ADC_INIT:
    ; ===== ADC (LM35) =====
    ; LM35 sensoru AN0 pinine bagli. ADC sonucu 2'ye bolunerek sicaklik degeri elde ediliyor.
     bcf STATUS,RP1
    bsf STATUS,RP0
    movlw b'10001110'  
    movwf ADCON1	;ADFM=1 right justified, AN0 analog, AN1-AN4 digital
    bcf STATUS,RP0
     bcf STATUS,RP1
    movlw b'01000001'    ; ADON=1, GO=0 conversion is not started, CHS0-2=000 channel 0 (RA0/AN0), ADCS0-2=010 clock conversion Fosc/8
    movwf ADCON0
    return
    

TACH_INIT:
     bcf STATUS,RP1
    bsf STATUS,RP0
    movlw b'00101000'  
    movwf OPTION_REG	    ;T0CS=1 external clock(RA4), T0SE=0 rising edge,PSA=1 prescaler is not used by TMR0.
    bcf STATUS,RP0
     bcf STATUS,RP1
    clrf TMR0
    return


;#################################################################
; UART INIT (RX interrupt capable; TX via polling)
; 9600 baud @ 4MHz (XT), 8N1, BRGH=1
;#################################################################
UART_INIT:
    ; ===== UART INIT =====
    ; UART 9600 baud ve 8N1 calisiyor. 4MHz kristal icin SPBRG=25 kullanildi.
    ; CREN=1 yapilarak surekli RX acildi, TXEN=1 ile TX aktif edildi.
    ; TXSTA & SPBRG are in Bank1
    bsf     STATUS, RP0
    movlw   .25                 ; 9600 @ 4MHz with BRGH=1
    movwf   SPBRG
    movlw   b'00100100'         ; TXSTA: BRGH=1, TXEN=1, SYNC=0
    movwf   TXSTA
    bcf     STATUS, RP0         ; Bank0

    movlw   b'10010000'         ; RCSTA: SPEN=1, CREN=1
    movwf   RCSTA

    ; Flush any stale byte(s)
    ; UART buffer'da takili kalan byte varsa RCREG okuyarak temizlemeye calisiyorum.
    btfsc   PIR1, RCIF
    movf    RCREG, W

    bcf     UART_FLAGS, 0
    return

;-----------------------------
; UART TX (polling)
; W = byte to send
;-----------------------------
UART_TX_BYTE:
    ; ===== UART TX =====
    ; TXIF=1 olana kadar bekleyip TXREG'e yaz?yorum. (Polling yÃ¶ntemi)
WAIT_TXIF:
    btfss   PIR1, TXIF
    goto    WAIT_TXIF
    movwf   TXREG
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
    ; ===== 7-SEG MULTIPLEX =====
      ; Onemli: PORTC'yi komple 'clrf' yapmiyorum.
    ; Cunku RC4/RC5 (heater/fan) ve RC6/RC7 (UART) ayni portta,
    ; tum PORTC'yi temizlersem bu pinler de etkileniyor.

    ; --- FIX ---
    ; 7-segment ghosting olmasin diye sadece digit secim pinlerini kapatiyorum.
    ; Sadece RC0..RC3 sifirlaniyor, RC4/RC5 ve RC6/RC7 aynen korunuyor.

    bcf PORTC,0
    bcf PORTC,1
    bcf PORTC,2
    bcf PORTC,3
    nop
    ; 1. All digit are off to prevent ghosting.
    bcf PORTC,0
    bcf PORTC,1
    bcf PORTC,2
    bcf PORTC,3
    
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
; SENSORS
;#################################################################
TEMP_READ:
    ; ===== LM35 OKUMA =====
    ; ADC conversion bitince ADRESL'den degeri aliyorum.
    ; Basitce /2 yaparak sicakligi integer + (0 veya 0.5) seklinde tutuyorum.
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
    ; ===== FAN TACH OKUMA =====
    ; TMR0 her turdan gelen pulse'lari sayiyor. 1 saniyede bir okuyup FAN_SPEED degiskenine yaziyorum.
    movf TMR0,W		    ;TMR0 counts the number of pulses caused by every turn of the fan.
    movwf FAN_SPEED	    ;TMR0 value is written in FAN_SPEED every 1 seconds.
    clrf TMR0
    return

TEMP_CONTROL:
    ; ===== SICAKLIK KONTROL =====
    ; Deadband (+/-0.5°C) kulland?m: çok küçük farklarda sürekli aç/kapa olmas?n diye. - Ambient >= Desired+0.5 => COOL (fan) ON
    ; - Ambient <= Desired-0.5 => HEAT ON
    ; - ArasÄ± => ikisi de OFF
    ;==========================================================
    ; Deadband control (+/- 0.5°C) to prevent chattering
    ; - If AMBIENT >= DESIRED + 0.5  => COOL (fan ON)
    ; - If AMBIENT <= DESIRED - 0.5  => HEAT (heater ON)
    ; - Otherwise                    => BOTH OFF
    ;==========================================================

    ;-------------------------------
    ; TH = DESIRED + 0.5
    ;-------------------------------
    movf    DESIRED_TEMP_L, W
    xorlw   5
    btfsc   STATUS, Z
    goto    TC_PLUS_CARRY

    ; L == 0  -> (H, 0.5)
    movf    DESIRED_TEMP_H, W
    movwf   TH_H
    movlw   5
    movwf   TH_L
    goto    TC_CHECK_COOL

TC_PLUS_CARRY:
    ; L == 0.5 -> (H+1, 0.0)
    movf    DESIRED_TEMP_H, W
    addlw   1
    movwf   TH_H
    clrf    TH_L

TC_CHECK_COOL:
    ; if AMBIENT >= TH  => COOL_ON
    movf    TH_H, W
    subwf   AMBIENT_TEMP_H, W      ; W = AMB_H - TH_H
    btfss   STATUS, Z
    goto    TC_COOL_H_DECIDE       ; H not equal

    ; H equal -> compare L
    movf    TH_L, W
    subwf   AMBIENT_TEMP_L, W      ; W = AMB_L - TH_L
    btfsc   STATUS, C
    goto    COOL_ON
    goto    TC_BUILD_LOW

TC_COOL_H_DECIDE:
    btfsc   STATUS, C              ; AMB_H >= TH_H
    goto    COOL_ON

TC_BUILD_LOW:
    ;-------------------------------
    ; TH = DESIRED - 0.5
    ;-------------------------------
    movf    DESIRED_TEMP_L, W
    xorlw   5
    btfsc   STATUS, Z
    goto    TC_MINUS_SIMPLE

    ; L == 0 -> (H-1, 0.5)
    movf    DESIRED_TEMP_H, W
    addlw   -1
    movwf   TH_H
    movlw   5
    movwf   TH_L
    goto    TC_CHECK_HEAT

TC_MINUS_SIMPLE:
    ; L == 0.5 -> (H, 0.0)
    movf    DESIRED_TEMP_H, W
    movwf   TH_H
    clrf    TH_L

TC_CHECK_HEAT:
    ; if AMBIENT <= TH  => HEAT_ON
    movf    AMBIENT_TEMP_H, W
    subwf   TH_H, W                ; W = TH_H - AMB_H
    btfss   STATUS, Z
    goto    TC_HEAT_H_DECIDE       ; H not equal

    ; H equal -> compare L
    movf    AMBIENT_TEMP_L, W
    subwf   TH_L, W                ; W = TH_L - AMB_L
    btfsc   STATUS, C
    goto    HEAT_ON
    goto    TC_OFF

TC_HEAT_H_DECIDE:
    btfsc   STATUS, C              ; TH_H >= AMB_H  => AMB_H <= TH_H
    goto    HEAT_ON

TC_OFF:
    bcf     PORTC,4                ; Heater OFF
    bcf     PORTC,5                ; Fan OFF
    return

HEAT_ON:
    bsf PORTC,4	    ; Heater ON
    bcf PORTC,5	    ; Fan OFF
    return
    
COOL_ON:
    bcf PORTC,4	    ; Heater OFF
    bsf PORTC,5	    ; Fan ON
    return
;**********************************************************
;---------------------------------------------------------
    END


