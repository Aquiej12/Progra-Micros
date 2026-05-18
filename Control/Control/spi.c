/*
 * spi.c
 *
 * Created: Guatemala 17/05/2026
 * Author: Abner Quiej (un humano mas)
 * Description: Driver SPI Maestro a fosc/16 (1 MHz @ 16 MHz)
 */
/****************************************/
// Encabezado (Libraries)
#include "spi.h"
#include <avr/io.h>

/****************************************/
// Function prototypes

void SPI_Init(void) {
    /* Direcciones de pines:
     *   MOSI (PB3), SCK (PB5), SS (PB2) → salida
     *   MISO (PB4) → entrada (default)
     *
     *  SS DEBE estar como salida en modo master, si no el chip se
     *  cae a modo slave cuando la linea va a LOW.                    */
    DDRB |=  (1 << PB3) | (1 << PB5) | (1 << PB2);
    DDRB &= ~(1 << PB4);

    /* SS = HIGH (deseleccionado, lo manejan los drivers) */
    PORTB |= (1 << PB2);

    /* SPCR:
     *   SPE  = 1  → habilitar
     *   MSTR = 1  → master
     *   DORD = 0  → MSB primero
     *   CPOL = 0, CPHA = 0  → modo 0
     *   SPR1=0, SPR0=1  → fosc/16 = 1 MHz                              */
    SPCR = (1 << SPE) | (1 << MSTR) | (1 << SPR0);
    SPSR = 0;                                /* SPI2X = 0 */
}

uint8_t SPI_Transfer(uint8_t data) {
    SPDR = data;
    while (!(SPSR & (1 << SPIF))) { }
    return SPDR;
}