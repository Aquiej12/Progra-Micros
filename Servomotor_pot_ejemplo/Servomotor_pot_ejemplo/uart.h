#ifndef UART_H_
#define UART_H_

/*  uart — driver UART polling minimo (sin interrupciones)
 *
 *  USART0 del ATmega328P, 8N1, baud configurable.
 *  TX = PD1 (D1), RX = PD0 (D0) — usar conector USB-UART.
 *
 *  Todas las funciones son BLOQUEANTES (busy-wait sobre UDRE0).
 *  A 9600 baud cada byte tarda ~1 ms — usarlas con criterio en main loops rapidos.
 */

#include <stdint.h>

void    UART_Init(uint32_t baud);
void    UART_Send(uint8_t c);
void    UART_PrintString(const char *s);
void    UART_PrintInt(int16_t v);
void    UART_PrintHex(uint8_t v);

/* Recepcion no bloqueante (usadas en modo UART del robot) */
uint8_t UART_Available(void);   /* 1 si hay byte listo en UDR0, 0 si no */
uint8_t UART_Read(void);        /* lee 1 byte (bloqueante si no hay)    */

#endif /* UART_H_ */
