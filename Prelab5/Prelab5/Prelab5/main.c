/*
 * main.c
 *
 * ADC0 (PC0) → Servo 1  — Timer1 OC1A / PB1
 * ADC1 (PC1) → Servo 2  — Timer1 OC1B / PB2
 * ADC2 (PC2) → LED PWM  — Software PWM / PD5
 */
#define F_CPU 16000000UL
#include <avr/io.h>
#include <avr/interrupt.h>
#include <util/delay.h>
#include "ServoTimer1.h"
#include "ServoTimer1B.h"
#include "SoftPWM.h"

void    ADC_Init(void);
uint8_t ADC_Read(uint8_t canal);

int main(void)
{
    ADC_Init();
    Servo_Init();      /* Timer1 → OC1A / PB1 */
    Servo_B_Init();    /* Timer1 → OC1B / PB2 */
    SoftPWM_Init();    /* Timer2 ISR → LED PD5 */

    sei();             /* Habilitar interrupciones globales */

    while (1)
    {
        Servo_SetPosition(ADC_Read(0));      /* PC0 → Servo 1 */
        Servo_B_SetPosition(ADC_Read(1));    /* PC1 → Servo 2 */
        SoftPWM_SetDuty(ADC_Read(2));        /* PC2 → Brillo LED */

        _delay_ms(5);
    }
}

void ADC_Init(void)
{
    ADMUX  = (1 << REFS0) | (1 << ADLAR);
    ADCSRA = (1 << ADEN) | (1 << ADPS2) | (1 << ADPS1) | (1 << ADPS0);
}

uint8_t ADC_Read(uint8_t canal)
{
    ADMUX = (ADMUX & 0xF0) | (canal & 0x0F);
    ADCSRA |= (1 << ADSC);
    while (ADCSRA & (1 << ADSC));
    return ADCH;
}