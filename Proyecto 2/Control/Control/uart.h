#ifndef UART_H_
#define UART_H_


#include <stdint.h>

void    UART_Init(uint32_t baud);
void    UART_Send(uint8_t c);
void    UART_PrintString(const char *s);
void    UART_PrintInt(int16_t v);
void    UART_PrintHex(uint8_t v);

uint8_t UART_Available(void);
uint8_t UART_Read(void);

#endif /* UART_H_ */
