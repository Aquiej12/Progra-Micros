#ifndef SPI_H_
#define SPI_H_

#include <stdint.h>

void    SPI_Init(void);
uint8_t SPI_Transfer(uint8_t data);

#endif /* SPI_H_ */
