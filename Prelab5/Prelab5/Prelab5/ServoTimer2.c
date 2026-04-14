/*
 * ServoTimer2.c
 */
#include "ServoTimer2.h"

/* ---------------------------------------------------------------
 * Servo2_Init
 * --------------------------------------------------------------- */
void Servo2_Init(void)
{
    /* PD3 (OC2B) como salida */
    DDRD |= (1 << PD3);

    /*
     * Modo Phase Correct PWM, TOP = 0xFF
     * COM2B1=1 ? salida no invertida en OC2B
     * WGM20=1  ? Phase Correct PWM
     * CS22|CS21|CS20 = 111 ? prescaler 1024
     */
    TCCR2A = (1 << COM2B1) | (1 << WGM20);
    TCCR2B = (1 << CS22)   | (1 << CS21) | (1 << CS20);

    OCR2B = SERVO2_MIN_TICKS;   /* Posición inicial: 0° */
}

/* ---------------------------------------------------------------
 * Servo2_SetPosition
 * --------------------------------------------------------------- */
void Servo2_SetPosition(uint8_t adc_val)
{
    uint8_t ticks = SERVO2_MIN_TICKS
                  + (uint8_t)(((uint16_t)adc_val * SERVO2_RANGE_TICKS) / 255U);
    Servo2_SetTicks(ticks);
}

/* ---------------------------------------------------------------
 * Servo2_SetTicks
 * --------------------------------------------------------------- */
void Servo2_SetTicks(uint8_t ticks)
{
    if (ticks < SERVO2_MIN_TICKS) ticks = SERVO2_MIN_TICKS;
    if (ticks > SERVO2_MAX_TICKS) ticks = SERVO2_MAX_TICKS;
    OCR2B = ticks;
}