/*
 * prelab4.c
 *
 * Created:     2026-04-05
 * Author:      Abner Quiej
 * Description: Contador binario de 8 bits + ADC + display 7 segmentos multiplexado
 */

/****************************************/
// Encabezado 
/****************************************/

#define F_CPU 16000000UL

#include <avr/io.h>
#include <avr/interrupt.h>
#include <stdint.h>


#define TIMER1_OCR  249

/****************************************/
// Tabla 7 segmentos - anodo comun (activo en bajo)

/****************************************/
const uint8_t seg7[16] = {
    0x40, 0x79, 0x24, 0x30, 0x19,			 // 0 1 2 3 4
    0x12, 0x02, 0x78, 0x00, 0x10,			 // 5 6 7 8 9
    0x08, 0x03, 0x46, 0x21, 0x06, 0x0E		 // A B C D E F
};

/****************************************/
// Function prototypes
/****************************************/

void initPins(void);
void initTimer1(void);
void initADC(void);
void showLEDs(void);
void updateDisplay(uint8_t nibble_alto, uint8_t nibble_bajo);
void checkAlarm(void);

/****************************************/
// Variables globales
/****************************************/

volatile uint8_t counter    = 0;   // Contador binario 0-255
volatile uint8_t flag_inc   = 0;   // Bandera: incrementar
volatile uint8_t flag_dec   = 0;   // Bandera: decrementar
volatile uint8_t adcValor   = 0;   // Ultimo valor leido del ADC
volatile uint8_t displayTurn = 0;  // 0 = unidades (PC4), 1 = decenas (PC5)

/****************************************/
// Main Function
/****************************************/

int main(void)
{
    initPins();
    initADC();
    initTimer1();
    sei();

    showLEDs();

    while (1)
    {
        if (flag_inc)
        {
            flag_inc = 0;
            counter++;
            showLEDs();
        }

        if (flag_dec)
        {
            flag_dec = 0;
            counter--;
            showLEDs();
        }
		checkAlarm();   // ? nueva línea
    }

    return 0;
}

/****************************************/
// NON-Interrupt subroutines
/****************************************/


void initPins(void)
{
    // --- PORTD: segmentos del display (salida) --- 
    DDRD  = 0xFF;
    PORTD = 0xFF;   
    UCSR0B = 0x00;   // deshabilitar UART para liberar PD0 y PD1

    // --- PORTB: PB0-PB5 salidas (LEDs bits 0-5) --- 
    DDRB |= (1<<PB0)|(1<<PB1)|(1<<PB2)|(1<<PB3)|(1<<PB4)|(1<<PB5);
    PORTB &= ~((1<<PB0)|(1<<PB1)|(1<<PB2)|(1<<PB3)|(1<<PB4)|(1<<PB5));

    
    DDRC = (DDRC | (1<<PC2)|(1<<PC3)|(1<<PC4)|(1<<PC5))
                 & ~((1<<PC0)|(1<<PC1));

   
    PORTC = (PORTC & 0xC0)    // conservar PC6 (RESET) y PC7
          | (1<<PC0)           // pull-up boton INC
          | (1<<PC1)           // pull-up boton DEC
          | (1<<PC4)           // display unidades apagado
          | (1<<PC5)           // display decenas apagado
          ;                    // PC2, PC3 quedan en 0
		  
	
		  DDRD  |= (1<<PD7);    // PD7 salida: LED de alarma
		  PORTD &= ~(1<<PD7);   // Apagado inicialmente
}


void initTimer1(void)
{
    TCCR1A = 0;
    TCCR1B = (1<<WGM12) | (1<<CS11)|(1<<CS10);  // CTC, prescaler 64
    OCR1A  = TIMER1_OCR;                          // 1 ms
    TIMSK1 |= (1<<OCIE1A);
    TCNT1  = 0;
}


void initADC(void)
{
	ADMUX  = 0;
	// AVCC como referencia, justificacion izquierda, canal ADC7 
	ADMUX |= (1<<REFS0) | (1<<ADLAR) | (1<<MUX2)|(1<<MUX1)|(1<<MUX0);

	ADCSRA = 0;
	// Habilitar ADC, iniciar,  interrupcion, prescaler 128 
	ADCSRA |= (1<<ADEN)|(1<<ADSC)|(1<<ADATE)|(1<<ADIE)
	| (1<<ADPS2)|(1<<ADPS1);

	ADCSRB = 0x00;  
}


void showLEDs(void)
{
    PORTB = (PORTB & 0xC0) | (counter & 0x3F);

    uint8_t leds_altos = (counter >> 4) & 0x0C;
    PORTC = (PORTC & ~0x0C) | leds_altos;
}


void updateDisplay(uint8_t nibble_alto, uint8_t nibble_bajo)
{
	uint8_t alarm_bit = PORTD & (1<<PD7);   // guardar estado de PD7

	PORTC |= (1<<PC4)|(1<<PC5);
	PORTD  = 0xFF;

	if (displayTurn == 0)
	{
		PORTD  = seg7[nibble_bajo] | alarm_bit;   // restaurar PD7
		PORTC &= ~(1<<PC4);
		displayTurn = 1;
	}
	else
	{
		PORTD  = seg7[nibble_alto] | alarm_bit;   // restaurar PD7
		PORTC &= ~(1<<PC5);
		displayTurn = 0;
	}
}

void checkAlarm(void)
{
	if (adcValor > counter)
	PORTD |=  (1<<PD7);   // Encender LED alarma
	else
	PORTD &= ~(1<<PD7);   // Apagar LED alarma
}

/****************************************/
// Interrupt routines
/****************************************/

ISR(TIMER1_COMPA_vect)
{
    static uint8_t prev_inc = 1;
    static uint8_t prev_dec = 1;

    // --- Botones --- 
    uint8_t curr_inc = (PINC & (1<<PC0)) ? 1 : 0;
    uint8_t curr_dec = (PINC & (1<<PC1)) ? 1 : 0;

    if (prev_inc == 1 && curr_inc == 0) flag_inc = 1;
    if (prev_dec == 1 && curr_dec == 0) flag_dec = 1;

    prev_inc = curr_inc;
    prev_dec = curr_dec;

    // --- Displays --- 
    uint8_t nibble_alto = (adcValor >> 4) & 0x0F;  // decenas hex
    uint8_t nibble_bajo =  adcValor       & 0x0F;  // unidades hex

    updateDisplay(nibble_alto, nibble_bajo);
}


ISR(ADC_vect)
{
    adcValor = ADCH;
}