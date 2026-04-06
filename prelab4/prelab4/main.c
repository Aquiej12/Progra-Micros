/*
 * BinaryCounter8bit.c
 *
 * Created:     2026-04-05
 * Author:      Estudiante AVR
 * Description: Contador binario de 8 bits con antirebote usando Timer1
 */

/****************************************/
// Encabezado (Libraries)
/****************************************/

#define F_CPU 16000000UL

#include <avr/io.h>
#include <avr/interrupt.h>
#include <stdint.h>

/*
 * Timer1 en modo CTC, dispara cada 10 ms
 * Formula: OCR1A = (F_CPU / (Prescaler * Frecuencia)) - 1
 * OCR1A = (16000000 / (64 * 100)) - 1 = 2499
 */
#define TIMER1_OCR  2499

/****************************************/
// Function prototypes
/****************************************/

void initPins(void);
void initTimer1(void);
void showLEDs(void);

/****************************************/
// Variables globales
/****************************************/

volatile uint8_t counter  = 0;   // Contador binario 0-255
volatile uint8_t flag_inc = 0;   // Bandera: incrementar
volatile uint8_t flag_dec = 0;   // Bandera: decrementar

/****************************************/
// Main Function
/****************************************/

int main(void)
{
    initPins();     // Configurar entradas y salidas
    initTimer1();   // Configurar Timer1 para antirebote
    sei();          // Habilitar interrupciones globales

    showLEDs();     // Mostrar estado inicial (0000 0000)

    while (1)
    {
        // Revisar bandera de incremento
        if (flag_inc)
        {
            flag_inc = 0;   // Limpiar bandera
            counter++;      // 255 + 1 = 0  (overflow automatico)
            showLEDs();
        }

        // Revisar bandera de decremento
        if (flag_dec)
        {
            flag_dec = 0;   // Limpiar bandera
            counter--;      // 0 - 1 = 255  (underflow automatico)
            showLEDs();
        }
    }

    return 0;
}

/****************************************/
// NON-Interrupt subroutines
/****************************************/

/*
 * initPins()
 * Configura los pines de entrada (botones) y salida (LEDs).
 *
 * ORDEN IMPORTANTE en PORTC:
 *   1. Primero configurar DDR (direccion)
 *   2. Luego escribir PORTC de una sola vez con:
 *      - PC0=1, PC1=1  -> pull-up activo en botones
 *      - PC2=0, PC3=0  -> LEDs apagados al inicio
 *   Asi evitamos mezclar escrituras que se pisen entre si.
 */
void initPins(void)
{
    /* --- PORTB: PB0-PB5 como salidas (bits 0-5 del contador) --- */
    DDRB |= (1<<PB0)|(1<<PB1)|(1<<PB2)|(1<<PB3)|(1<<PB4)|(1<<PB5);
    PORTB &= ~((1<<PB0)|(1<<PB1)|(1<<PB2)|(1<<PB3)|(1<<PB4)|(1<<PB5)); // apagar

    /* --- PORTC: configurar DDR primero --- */
    /* PC2 y PC3 = salidas (LEDs bits 6 y 7) */
    /* PC0 y PC1 = entradas (botones)         */
    DDRC = (DDRC | (1<<PC2)|(1<<PC3)) & ~((1<<PC0)|(1<<PC1));

    /*
     * Escribir PORTC de una sola vez:
     *   PC0 = 1  -> pull-up boton incremento
     *   PC1 = 1  -> pull-up boton decremento
     *   PC2 = 0  -> LED bit6 apagado
     *   PC3 = 0  -> LED bit7 apagado
     *
     * Usamos mascara para no tocar PC4, PC5, PC6 (RESET):
     *   conservar bits altos tal como estaban
     *   forzar PC0=1, PC1=1, PC2=0, PC3=0
     */
    PORTC = (PORTC & 0xF0)   /* conservar PC4..PC7 sin cambios */
          | (1<<PC0)          /* pull-up botón incremento       */
          | (1<<PC1)          /* pull-up botón decremento       */
          ;                   /* PC2 y PC3 quedan en 0 (apagado)*/
}

/*
 * initTimer1()
 * Configura Timer1 en modo CTC para disparar cada 10 ms.
 * Prescaler 64, OCR1A = 2499.
 */
void initTimer1(void)
{
    TCCR1A = 0;                              // Modo normal de pines (necesario para CTC)
    TCCR1B = (1<<WGM12)                      // Modo CTC (Clear Timer on Compare)
           | (1<<CS11)|(1<<CS10);            // Prescaler = 64
    OCR1A  = TIMER1_OCR;                     // Disparo cada 10 ms
    TIMSK1 |= (1<<OCIE1A);                   // Habilitar interrupcion por comparacion
    TCNT1  = 0;                              // Reiniciar contador del timer
}

/*
 * showLEDs()
 * Escribe el valor del contador en los LEDs.
 *
 *   Bits 0-5 del contador --> PB0-PB5
 *   Bit  6   del contador --> PC2
 *   Bit  7   del contador --> PC3
 *
 * CUIDADO con PORTC:
 *   - Solo modificamos PC2 y PC3
 *   - PC0 y PC1 deben conservar su pull-up (valor 1)
 *   - PC4..PC7 se conservan como estaban
 */
void showLEDs(void)
{
    /* --- PORTB: bits 0-5 directo --- */
    /*
     * 0xC0 = 1100 0000  -> conserva PB6 y PB7
     * 0x3F = 0011 1111  -> toma solo bits 0-5 del contador
     */
    PORTB = (PORTB & 0xC0) | (counter & 0x3F);

    /* --- PORTC: bit 6 -> PC2, bit 7 -> PC3 --- */
    /*
     * Extraemos bit6 y bit7 del contador y los movemos
     * a las posiciones correctas dentro de PORTC:
     *
     *   bit 6 del contador esta en posicion 6
     *   PC2                esta en posicion 2
     *   diferencia: 6 - 2 = 4  -> desplazar 4 posiciones a la derecha
     *
     *   bit 7 del contador esta en posicion 7
     *   PC3                esta en posicion 3
     *   diferencia: 7 - 3 = 4  -> desplazar 4 posiciones a la derecha
     *
     *   Por eso ambos bits se desplazan >> 4 juntos.
     *   Luego enmascaramos con 0x0C (0000 1100) para asegurarnos
     *   de que solo toquemos PC2 y PC3, nada mas.
     */
    uint8_t leds_altos = (counter >> 4) & 0x0C;
    /*
     *  counter >> 4  mueve bit6->pos2 y bit7->pos3 al mismo tiempo
     *  & 0x0C = & 0000 1100  asegura que solo PC2 y PC3 sean afectados
     */

    /*
     * Ahora escribimos en PORTC:
     *   - Limpiamos PC2 y PC3 con ~0x0C = 1111 0011
     *   - Ponemos el nuevo valor de los LEDs altos
     *   - PC0, PC1, PC4..PC7 no se tocan
     */
    PORTC = (PORTC & ~0x0C) | leds_altos;
}

/****************************************/
// Interrupt routines
/****************************************/

/*
 * ISR Timer1 - Comparacion A (cada 10 ms)
 *
 * Lee los botones y detecta flancos de bajada.
 * Flanco de bajada = pin pasa de 1 (libre) a 0 (presionado).
 *
 * Una sola deteccion por pulsacion -> no hay rebote.
 */
ISR(TIMER1_COMPA_vect)
{
    static uint8_t prev_inc = 1;   // Estado anterior PC0 (1=libre)
    static uint8_t prev_dec = 1;   // Estado anterior PC1 (1=libre)

    // Leer estado actual (1=libre, 0=presionado)
    uint8_t curr_inc = (PINC & (1<<PC0)) ? 1 : 0;
    uint8_t curr_dec = (PINC & (1<<PC1)) ? 1 : 0;

    // Flanco de bajada en PC0: antes libre, ahora presionado
    if (prev_inc == 1 && curr_inc == 0)
        flag_inc = 1;

    // Flanco de bajada en PC1: antes libre, ahora presionado
    if (prev_dec == 1 && curr_dec == 0)
        flag_dec = 1;

    // Guardar estado para la proxima comparacion
    prev_inc = curr_inc;
    prev_dec = curr_dec;
}