/*
 * ServoTimer1B.c
 */
#include "ServoTimer1B.h"

void Servo_B_Init(void)
{
    /* PB2 (OC1B) como salida */
    DDRB |= (1 << PB2);

    /*
     * Habilitar OC1B en modo no invertido (COM1B1=1)
     * OR sobre TCCR1A — no toca COM1A ni WGM, ya configurados
     */
    TCCR1A |= (1 << COM1B1);

    OCR1B = SERVO_B_MIN_TICKS;   /* Posición inicial: 0° */
}

void Servo_B_SetPosition(uint8_t adc_val)
{
    uint16_t ticks = SERVO_B_MIN_TICKS
                   + (uint16_t)(((uint32_t)adc_val * SERVO_B_RANGE_TICKS) / 255U);
    Servo_B_SetTicks(ticks);
}

void Servo_B_SetTicks(uint16_t ticks)
{
    if (ticks < SERVO_B_MIN_TICKS) ticks = SERVO_B_MIN_TICKS;
    if (ticks > SERVO_B_MAX_TICKS) ticks = SERVO_B_MAX_TICKS;
    OCR1B = ticks;
}