#ifndef SPI_H_
#define SPI_H_

/*  spi — driver SPI Maestro para ATmega328P
 *
 *  Pinout (fijo en hardware):
 *    MOSI = PB3 (D11)
 *    MISO = PB4 (D12)
 *    SCK  = PB5 (D13)
 *    SS   = PB2 (D10)  — manejado externamente por cada driver
 *
 *  Modo: Master, fosc/4, MSB primero, modo 0 (CPOL=0, CPHA=0)
 */

#include <stdint.h>

void    SPI_Init(void);
uint8_t SPI_Transfer(uint8_t data);

#endif /* SPI_H_ */
