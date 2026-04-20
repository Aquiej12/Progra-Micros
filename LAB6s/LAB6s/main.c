/*
 * LAB6s.c
 *
 * Created: 20/04/2026 13:38:45
 * Author : abner
 * Description:
 */
/****************************************/
// Encabezado (Libraries)

#include <avr/io.h>
#include <avr/interrupt.h>
#define BAUD  9600
#define F_CPU 16000000UL
#define UBRR_VAL (F_CPU/16/BAUD - 1)   // = 103

/****************************************/
// Function prototypes
void initUART();
void writeChar(char caracter);
void writeString(char* string);


/****************************************/
// Main Function
int main(void)
{
	DDRB = 0xFF;
	PORTB = 0x00;  // inicializa apagado

	cli();
	initUART();
	sei();
	writeChar('Q');
	writeString("ue?");
	while (1)
	{
	}
}
/****************************************/
// NON-Interrupt subroutines
void initUART()
{
	UBRR0H = (uint8_t)(UBRR_VAL >> 8);
	UBRR0L = (uint8_t)(UBRR_VAL);
	
	//Configurar RX Y TX
	DDRD	&= ~(1<<DDD0);
	DDRD	|= (1<<DDD1);
	
	UCSR0A	= 0;
	UCSR0B	=(1<<RXCIE0) |(1<<RXEN0) |(1<<TXEN0);
	UCSR0C	=(1<<UCSZ01) |(1<<UCSZ00);
	
}
void writeChar(char caracter)
{
	while(!(UCSR0A & (1<<UDRE0)));
		
	UDR0 = caracter;
}
void writeString(char* string)
{
	for (uint8_t i=0; string[i] !='\0'; i++)
	{
		writeChar(string[i]);	
	}	
}

/****************************************/
// Interrupt routines
ISR(USART_RX_vect)
{
	static char buf[5] = {0};
	static uint8_t idx = 0;

	char bufferRX = UDR0;
	PORTB = bufferRX;
	writeChar(bufferRX);

	buf[idx++] = bufferRX;

	if (idx >= 4)   // recibió 4 caracteres
	{
		if (buf[0]=='Q' && buf[1]=='u' && buf[2]=='e' && buf[3]=='?')
		{
			writeString("\r\nSO :v\r\n");
		}
		idx = 0;   // reinicia buffer
	}
}