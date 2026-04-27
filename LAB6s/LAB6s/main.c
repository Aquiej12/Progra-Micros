/*
 * LAB6s.c
 *
 * Created: 20/04/2026 13:38:45
 * Author : abner
 */

#define F_CPU 16000000UL
#define BAUD  9600
#define UBRR_VAL (F_CPU/16/BAUD - 1)

#include <avr/io.h>
#include <avr/interrupt.h>

/****************************************/
// Global
volatile uint8_t modoASCII = 0;

/****************************************/
// Function prototypes
void initUART();
void initADC();
uint16_t readADC();
void sendVoltage(uint16_t raw);
void writeChar(char caracter);
void writeString(char* string);
void splitBits(char dato);
void showMenu();
void handleMenu(char opcion);

/****************************************/
// Main
int main(void)
{
    cli();
    initUART();
    initADC();
    DDRB  = 0xFF;
    PORTB = 0x00;
    sei();
    showMenu();
    while (1) {}
}

/****************************************/
// Subroutines

void initUART()
{
    UBRR0H = (uint8_t)(UBRR_VAL >> 8);
    UBRR0L = (uint8_t)(UBRR_VAL);

    DDRD  &= ~(1 << DDD0);
    DDRD  |=  (1 << DDD1);

    UCSR0A = 0;
    UCSR0B = (1 << RXCIE0) | (1 << RXEN0) | (1 << TXEN0);
    UCSR0C = (1 << UCSZ01) | (1 << UCSZ00);
}

void initADC()
{
    ADMUX  = (1 << REFS0);                            // AVCC ref, canal A0
    ADCSRA = (1 << ADEN)
           | (1 << ADPS2)
           | (1 << ADPS1)
           | (1 << ADPS0);                            // prescaler 128
}

uint16_t readADC()
{
    ADCSRA |= (1 << ADSC);
    while (ADCSRA & (1 << ADSC));
    return ADC;
}

void sendVoltage(uint16_t raw)
{
    uint32_t mv  = (uint32_t)raw * 500 / 1023;
    uint8_t  ent = mv / 100;
    uint8_t  dec = mv % 100;

    writeString("\r\nLectura potenciometro: ");
    writeChar('0' + ent);
    writeChar('.');
    writeChar('0' + dec / 10);
    writeChar('0' + dec % 10);
    writeString(" V\r\n");
}

void writeChar(char caracter)
{
    while (!(UCSR0A & (1 << UDRE0)));
    UDR0 = caracter;
}

void writeString(char* string)
{
    for (uint8_t i = 0; string[i] != '\0'; i++)
        writeChar(string[i]);
}

void splitBits(char dato)
{
    DDRD |= (1 << PD2) | (1 << PD3) | (1 << PD4);

    PORTD = (PORTD & ~((1 << PD2) | (1 << PD3) | (1 << PD4)))
          | (((dato >> 0) & 1) << PD2)
          | (((dato >> 1) & 1) << PD3)
          | (((dato >> 2) & 1) << PD4);

    PORTB = (dato >> 3) & 0x1F;
}

void showMenu()
{
    writeString("\r\n=== MENU ===\r\n");
    writeString("1. Leer Potenciometro\r\n");
    writeString("2. Enviar ASCII\r\n");
    writeString("Opcion: ");
}

void handleMenu(char opcion)
{
    switch (opcion)
    {
        case '1':
            sendVoltage(readADC());
            showMenu();
            break;

        case '2':
            writeString("\r\nLetra ASCII: ");
            modoASCII = 1;
            break;

        default:
            showMenu();
            break;
    }
}

/****************************************/
// ISR
ISR(USART_RX_vect)
{
    char bufferRX = UDR0;
    writeChar(bufferRX);

    if (modoASCII)
    {
        splitBits(bufferRX);
        modoASCII = 0;
        showMenu();
    }
    else
    {
        handleMenu(bufferRX);
    }
}