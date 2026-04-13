/*
 * main.c
 *
 * Created:     2026-04-13
 * Description: ADC (potenciómetro en ADC0/PC0) → PWM → Servo (OC1A/PB1)
 *
 * Cableado:
 *   PC0 (ADC0) ── Terminal central del potenciómetro (10kΩ)
 *   PB1 (OC1A) ── Señal del servo (cable amarillo/naranja)
 *   5V         ── Terminal izquierdo del potenciómetro + VCC servo
 *   GND        ── Terminal derecho del potenciómetro + GND servo
 */

#define F_CPU 16000000UL

#include <avr/io.h>
#include <util/delay.h>
#include "ServoTimer1.h"

/****************************************/
// Prototipos
/****************************************/
void    ADC_Init(void);
uint8_t ADC_Read(uint8_t canal);

/****************************************/
// Main
/****************************************/
int main(void)
{
    ADC_Init();
    Servo_Init();

    while (1)
    {
        uint8_t lectura = ADC_Read(0);  /* Canal ADC0 = PC0 */
        Servo_SetPosition(lectura);
        _delay_ms(20);                  /* Esperar 1 periodo PWM completo */
    }
}

/****************************************/
// ADC
/****************************************/

/*
 * ADC_Init
 * AVCC como referencia, resultado justificado a la izquierda (ADLAR=1)
 * → ADCH contiene los 8 bits más significativos, suficiente resolución.
 * Prescaler 128 → 16MHz/128 = 125kHz (rango recomendado: 50–200kHz).
 */
void ADC_Init(void)
{
    ADMUX  = (1 << REFS0) | (1 << ADLAR);
    ADCSRA = (1 << ADEN) | (1 << ADPS2) | (1 << ADPS1) | (1 << ADPS0);
}

/*
 * ADC_Read
 * Selecciona el canal, inicia la conversión en modo single-shot,
 * espera a que termine y devuelve los 8 bits altos (ADCH).
 */
uint8_t ADC_Read(uint8_t canal)
{
    /* Preservar bits de referencia, cambiar solo el canal */
    ADMUX = (ADMUX & 0xF0) | (canal & 0x0F);

    ADCSRA |= (1 << ADSC);         /* Iniciar conversión  */
    while (ADCSRA & (1 << ADSC));  /* Esperar fin         */

    return ADCH;                    /* 8 bits más significativos */
}
