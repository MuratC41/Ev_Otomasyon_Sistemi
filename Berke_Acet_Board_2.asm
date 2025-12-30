
; PROJE: BOARD #2 - PERDE KONTROL


    LIST P=16F877A
    INCLUDE "P16F877A.INC"

    __CONFIG _HS_OSC & _WDT_OFF & _PWRTE_ON & _BODEN_OFF & _LVP_OFF & _CP_OFF
    
    ERRORLEVEL -302


W       EQU 0
F       EQU 1
RS_PIN  EQU 2
EN_PIN  EQU 3
LDR_LIMIT EQU D'100'


    CBLOCK 0x20
    Desired_Curtain
    Current_Curtain
    Pot_Raw
    LDR_Raw
    
    ;bmp180
    Temp_Value
    Press_Value_L
    
    ; UART 
    Rx_Byte     
    Tx_Byte    
    
    LATD_Shadow
    Motor_Phase
    Step_Counter
    
    ; Simulasyon
    Sim_Timer_1
    Sim_Timer_2
    Weather_Counter
    
    Math_Res_L
    BCD_100, BCD_10, BCD_1
    vTemp
    cnt1, cnt2
    
    Rx_Data
    W_Temp
    STATUS_Temp
    ENDC


    ORG 0x000
    GOTO Init
    ORG 0x004
    GOTO ISR_Handler


Init:
    BANKSEL TRISA
    MOVLW   0xFF
    MOVWF   TRISA
    CLRF    TRISB
    
  
    BANKSEL TRISC
    BSF     TRISC, 7
    BCF     TRISC, 6
    CLRF    TRISD
    
    
    MOVLW   D'25'
    MOVWF   SPBRG
    MOVLW   B'00100100' 
    MOVWF   TXSTA
    BANKSEL RCSTA
    MOVLW   B'10010000' 
    MOVWF   RCSTA
    
  
    BANKSEL ADCON1
    MOVLW   B'00000100' 
    MOVWF   ADCON1
    BANKSEL ADCON0
    MOVLW   B'01000001'
    MOVWF   ADCON0
    
    BANKSEL PORTA
    CLRF    PORTB
    CLRF    PORTD
    CLRF    LATD_Shadow
    CLRF    Motor_Phase
    CLRF    Current_Curtain
    
    CLRF    Sim_Timer_1
    CLRF    Sim_Timer_2
    CLRF    Weather_Counter
    
    CALL    LCD_Init
    CALL    LCD_Draw_Static_Layout
    
    
    CALL    Read_Sensors_Fast
    MOVF    Pot_Raw, W
    CALL    Scale_Pot_0_100
    MOVWF   Desired_Curtain
    MOVWF   Current_Curtain
    
    CALL    Simulate_Weather
    CALL    LCD_Refresh_Values

MainLoop:
   
    CALL    UART_Check_Incoming
   
    CALL    Simulate_Weather
    
    
    CALL    Read_Sensors_Fast
    

    MOVF    LDR_Raw, W
    SUBLW   LDR_LIMIT
    BTFSS   STATUS, C
    GOTO    Mode_Man
    
    MOVLW   D'100'
    MOVWF   Desired_Curtain
    GOTO    Check_M

Mode_Man:
   
    MOVF    Pot_Raw, W
    CALL    Scale_Pot_0_100
    MOVWF   Desired_Curtain

Check_M:
    
    MOVF    Desired_Curtain, W
    SUBWF   Current_Curtain, W
    BTFSC   STATUS, Z
    GOTO    Refresh_LCD
    
    BTFSC   STATUS, C
    GOTO    M_Open
    GOTO    M_Close

M_Close:
    MOVLW   D'10'
    MOVWF   Step_Counter
L_CW:
    CALL    Step_CW
    CALL    Delay_Turbo
    DECFSZ  Step_Counter, F
    GOTO    L_CW
    INCF    Current_Curtain, F
    CALL    LCD_Refresh_Values
    GOTO    Loop_Cont

M_Open:
    MOVLW   D'10'
    MOVWF   Step_Counter
L_CCW:
    CALL    Step_CCW
    CALL    Delay_Turbo
    DECFSZ  Step_Counter, F
    GOTO    L_CCW
    DECF    Current_Curtain, F
    CALL    LCD_Refresh_Values
    GOTO    Loop_Cont

Loop_Cont:
  
    CALL    UART_Check_Incoming 
    GOTO    MainLoop

Refresh_LCD:
    CALL    LCD_Refresh_Values
    GOTO    MainLoop

;UARTtable
UART_Check_Incoming:
    BANKSEL PIR1
    BTFSS   PIR1, RCIF  
    RETURN              
    
 
    BANKSEL RCREG
    MOVF    RCREG, W
    MOVWF   Rx_Byte     
    
    MOVF    Rx_Byte, W
    XORLW   0x01
    BTFSC   STATUS, Z
    GOTO    Resp_Zero   
    
    MOVF    Rx_Byte, W
    XORLW   0x02
    BTFSC   STATUS, Z
    GOTO    Resp_Curtain
    

    MOVF    Rx_Byte, W
    XORLW   0x03
    BTFSC   STATUS, Z
    GOTO    Resp_Zero  
    
    
    MOVF    Rx_Byte, W
    XORLW   0x04
    BTFSC   STATUS, Z
    GOTO    Resp_Temp
    
    
    MOVF    Rx_Byte, W
    XORLW   0x05
    BTFSC   STATUS, Z
    GOTO    Resp_Press_L
    
   
    MOVF    Rx_Byte, W
    XORLW   0x06
    BTFSC   STATUS, Z
    GOTO    Resp_Press_H
    
  
    MOVF    Rx_Byte, W
    XORLW   0x07
    BTFSC   STATUS, Z
    GOTO    Resp_Zero
    
  
    MOVF    Rx_Byte, W
    XORLW   0x08
    BTFSC   STATUS, Z
    GOTO    Resp_Light
    
   
    MOVF    Rx_Byte, W
    ANDLW   B'11000000' 
    XORLW   B'11000000' 
    BTFSC   STATUS, Z
    GOTO    Cmd_Set_Curtain
    
    RETURN 


Resp_Zero:
    MOVLW   0x00
    GOTO    Send_It

Resp_Curtain:
    MOVF    Current_Curtain, W
    GOTO    Send_It

Resp_Temp:
    MOVF    Temp_Value, W
    GOTO    Send_It

Resp_Press_L:
    MOVF    Press_Value_L, W
    GOTO    Send_It

Resp_Press_H:
    MOVLW   D'10'       
    GOTO    Send_It

Resp_Light:
    MOVF    LDR_Raw, W
    GOTO    Send_It

Cmd_Set_Curtain:
   
    MOVF    Rx_Byte, W
    ANDLW   B'00111111' 
    MOVWF   Desired_Curtain
   
    RETURN  

Send_It:
    BANKSEL PIR1
Wait_TX:
    BTFSS   PIR1, TXIF
    GOTO    Wait_TX
    BANKSEL TXREG
    MOVWF   TXREG
    BANKSEL PORTA
    RETURN

;------
Simulate_Weather:
    INCF    Sim_Timer_1, F
    BTFSS   STATUS, Z
    RETURN
    INCF    Sim_Timer_2, F
    MOVF    Sim_Timer_2, W
    ANDLW   0x1F    
    BTFSS   STATUS, Z
    RETURN
    INCF    Weather_Counter, F
    ; T 
    MOVF    Weather_Counter, W
    ANDLW   0x0F
    ADDLW   D'20'
    MOVWF   Temp_Value
    ; P 
    MOVF    Weather_Counter, W
    ANDLW   0x1F
    MOVWF   Press_Value_L
    RETURN

Read_Sensors_Fast:
    BANKSEL ADCON0
    BCF     ADCON0, CHS0
    BCF     ADCON0, CHS1
    BCF     ADCON0, CHS2
    CALL    Delay_Short
    BSF     ADCON0, GO
W_Pot:
    BTFSC   ADCON0, GO
    GOTO    W_Pot
    MOVF    ADRESH, W
    MOVWF   Pot_Raw
    BSF     ADCON0, CHS0
    CALL    Delay_Short
    BSF     ADCON0, GO
W_LDR:
    BTFSC   ADCON0, GO
    GOTO    W_LDR
    MOVF    ADRESH, W
    MOVWF   LDR_Raw
    RETURN

Scale_Pot_0_100:
    MOVWF   Math_Res_L
    BCF     STATUS, C
    RRF     Math_Res_L, W
    MOVWF   vTemp
    MOVLW   D'100'
    SUBWF   vTemp, W
    BTFSC   STATUS, C
    RETLW   D'100'
    MOVF    vTemp, W
    RETURN

Step_CW:
    INCF    Motor_Phase, F
    GOTO    Drive
Step_CCW:
    DECF    Motor_Phase, F
Drive:
    MOVF    Motor_Phase, W
    ANDLW   0x03
    CALL    Get_Steps
    MOVWF   vTemp
    MOVWF   PORTB
    RETURN

Get_Steps:
    ADDWF   PCL, F
    RETLW   B'00000001'
    RETLW   B'00000010'
    RETLW   B'00000100'
    RETLW   B'00001000'


LCD_Draw_Static_Layout:
    CALL    LCD_Clear
    MOVLW   0x86
    CALL    LCD_Cmd
    MOVLW   0xDF
    CALL    LCD_PutChar
    MOVLW   'C'
    CALL    LCD_PutChar
    MOVLW   0x8D
    CALL    LCD_Cmd
    MOVLW   'h'
    CALL    LCD_PutChar
    MOVLW   'P'
    CALL    LCD_PutChar
    MOVLW   'a'
    CALL    LCD_PutChar
    MOVLW   0xC6
    CALL    LCD_Cmd
    MOVLW   'L'
    CALL    LCD_PutChar
    MOVLW   'u'
    CALL    LCD_PutChar
    MOVLW   'x'
    CALL    LCD_PutChar
    MOVLW   0xCF
    CALL    LCD_Cmd
    MOVLW   '%'
    CALL    LCD_PutChar
    RETURN

LCD_Refresh_Values:
    MOVLW   0x80
    CALL    LCD_Cmd
    MOVLW   '+'
    CALL    LCD_PutChar
    MOVF    Temp_Value, W
    MOVWF   Math_Res_L
    CALL    BCD_Dec
    MOVLW   0x89
    CALL    LCD_Cmd
    MOVLW   '1'
    CALL    LCD_PutChar
    MOVLW   '0'
    CALL    LCD_PutChar
    MOVF    Press_Value_L, W
    MOVWF   Math_Res_L
    CALL    BCD_2D_Only
    MOVLW   0xC0
    CALL    LCD_Cmd
    MOVLW   '0'
    CALL    LCD_PutChar
    MOVLW   '0'
    CALL    LCD_PutChar
    MOVF    LDR_Raw, W
    MOVWF   Math_Res_L
    CALL    BCD_3D
    MOVLW   0xCA
    CALL    LCD_Cmd
    MOVF    Current_Curtain, W
    MOVWF   Math_Res_L
    MOVLW   D'100'
    SUBWF   Math_Res_L, W
    BTFSC   STATUS, Z
    GOTO    Pr_100
    CALL    BCD_3D
    MOVLW   '.'
    CALL    LCD_PutChar
    MOVLW   '0'
    CALL    LCD_PutChar
    RETURN
Pr_100:
    MOVLW   '1'
    CALL    LCD_PutChar
    MOVLW   '0'
    CALL    LCD_PutChar
    MOVLW   '0'
    CALL    LCD_PutChar
    MOVLW   ' '
    CALL    LCD_PutChar
    RETURN

BCD_Dec:
    CLRF    BCD_100
    CLRF    BCD_10
L_D100: MOVLW D'100'
    SUBWF   Math_Res_L, W
    BTFSS   STATUS, C
    GOTO    L_D10
    MOVWF   Math_Res_L
    INCF    BCD_100, F
    GOTO    L_D100
L_D10:  MOVLW D'10'
    SUBWF   Math_Res_L, W
    BTFSS   STATUS, C
    GOTO    P_D
    MOVWF   Math_Res_L
    INCF    BCD_10, F
    GOTO    L_D10
P_D:    MOVF    BCD_10, W
    ADDLW   '0'
    CALL    LCD_PutChar
    MOVF    Math_Res_L, W
    ADDLW   '0'
    CALL    LCD_PutChar
    MOVLW   '.'
    CALL    LCD_PutChar
    MOVLW   '5'
    CALL    LCD_PutChar
    RETURN

BCD_2D_Only:
    CLRF    BCD_10
L_2D:   MOVLW D'10'
    SUBWF   Math_Res_L, W
    BTFSS   STATUS, C
    GOTO    P_2D
    MOVWF   Math_Res_L
    INCF    BCD_10, F
    GOTO    L_2D
P_2D:   MOVF    BCD_10, W
    ADDLW   '0'
    CALL    LCD_PutChar
    MOVF    Math_Res_L, W
    ADDLW   '0'
    CALL    LCD_PutChar
    RETURN

BCD_3D:
    CLRF    BCD_100
    CLRF    BCD_10
L_3100: MOVLW D'100'
    SUBWF   Math_Res_L, W
    BTFSS   STATUS, C
    GOTO    L_310
    MOVWF   Math_Res_L
    INCF    BCD_100, F
    GOTO    L_3100
L_310:  MOVLW D'10'
    SUBWF   Math_Res_L, W
    BTFSS   STATUS, C
    GOTO    P_3
    MOVWF   Math_Res_L
    INCF    BCD_10, F
    GOTO    L_310
P_3:    MOVF    BCD_100, W
    ADDLW   '0'
    CALL    LCD_PutChar
    MOVF    BCD_10, W
    ADDLW   '0'
    CALL    LCD_PutChar
    MOVF    Math_Res_L, W
    ADDLW   '0'
    CALL    LCD_PutChar
    RETURN


LCD_Init:
    CALL    Delay_L
    BCF     LATD_Shadow, RS_PIN
    BCF     LATD_Shadow, EN_PIN
    CALL    LCD_Push
    MOVLW   0x30
    CALL    LCD_Nib
    CALL    Delay_S
    MOVLW   0x30
    CALL    LCD_Nib
    MOVLW   0x30
    CALL    LCD_Nib
    MOVLW   0x20
    CALL    LCD_Nib
    MOVLW   0x28
    CALL    LCD_Cmd
    MOVLW   0x0C
    CALL    LCD_Cmd
    MOVLW   0x06
    CALL    LCD_Cmd
    MOVLW   0x01
    CALL    LCD_Cmd
    RETURN

LCD_Clear:
    MOVLW   0x01
    CALL    LCD_Cmd
    CALL    Delay_S
    RETURN

LCD_Cmd:
    MOVWF   vTemp
    BCF     LATD_Shadow, RS_PIN
    GOTO    LCD_Send
LCD_PutChar:
    MOVWF   vTemp
    BSF     LATD_Shadow, RS_PIN
LCD_Send:
    MOVF    vTemp, W
    ANDLW   0xF0
    CALL    LCD_Nib_D
    SWAPF   vTemp, W
    ANDLW   0xF0
    CALL    LCD_Nib_D
    CALL    Delay_S
    RETURN

LCD_Nib:
    MOVWF   vTemp
    MOVF    LATD_Shadow, W
    ANDLW   0x0F
    MOVWF   LATD_Shadow
    MOVF    vTemp, W
    ANDLW   0xF0
    IORWF   LATD_Shadow, F
    CALL    Pulse_E
    RETURN

LCD_Nib_D:
    MOVWF   cnt2
    MOVF    LATD_Shadow, W
    ANDLW   0x0F
    MOVWF   LATD_Shadow
    MOVF    cnt2, W
    IORWF   LATD_Shadow, F
    CALL    Pulse_E
    RETURN

Pulse_E:
    BSF     LATD_Shadow, EN_PIN
    CALL    LCD_Push
    NOP
    NOP
    BCF     LATD_Shadow, EN_PIN
    CALL    LCD_Push
    RETURN

LCD_Push:
    MOVF    LATD_Shadow, W
    MOVWF   PORTD
    RETURN

Delay_Short:
    MOVLW   D'5'
    MOVWF   cnt1
L_DS:DECFSZ cnt1, F
    GOTO    L_DS
    RETURN

Delay_S:
    MOVLW   D'20'
    MOVWF   cnt1
L_DSSS:DECFSZ cnt1, F
    GOTO    L_DSSS
    RETURN

Delay_L:
    MOVLW   D'200'
    MOVWF   cnt2
L_DL:CALL   Delay_S
    DECFSZ  cnt2, F
    GOTO    L_DL
    RETURN

Delay_Turbo:
    MOVLW   D'3'
    MOVWF   cnt2
L_DT:CALL   Delay_S
    DECFSZ  cnt2, F
    GOTO    L_DT
    RETURN

ISR_Handler:
    RETFIE

    END