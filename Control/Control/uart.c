/*  uart.c — USART0 polling, 8N1, sin interrupciones                    */

#define F_CPU 16000000UL
#include "uart.h"
#include <avr/io.h>

void UART_Init(uint32_t baud) {
    uint16_t ubrr = (uint16_t)((F_CPU / (16UL * baud)) - 1);
    UBRR0H = (uint8_t)(ubrr >> 8);
    UBRR0L = (uint8_t)(ubrr & 0xFF);

    UCSR0B = (1 << TXEN0) | (1 << RXEN0);
    UCSR0C = (1 << UCSZ01) | (1 << UCSZ00);
}

void UART_Send(uint8_t c) {
    while (!(UCSR0A & (1 << UDRE0))) { }
    UDR0 = c;
}

void UART_PrintString(const char *s) {
    while (*s) {
        UART_Send((uint8_t)(*s));
        s++;
    }
}

void UART_PrintInt(int16_t v) {
    char     buf[6];
    int8_t   i = 0;
    uint16_t u;

    if (v < 0) {
        UART_Send('-');
        u = (uint16_t)(-v);
    } else {
        u = (uint16_t)v;
    }

    if (u == 0) {
        UART_Send('0');
        return;
    }

    while (u > 0 && i < 6) {
        buf[i++] = (char)('0' + (u % 10));
        u /= 10;
    }
    while (i > 0) {
        UART_Send((uint8_t)buf[--i]);
    }
}

void UART_PrintHex(uint8_t v) {
    static const char hex[] = "0123456789ABCDEF";
    UART_Send((uint8_t)hex[(v >> 4) & 0x0F]);
    UART_Send((uint8_t)hex[ v       & 0x0F]);
}
