#ifndef LORA_H_
#define LORA_H_

#include <stdint.h>

uint8_t LoRa_Init(uint32_t frequency);
uint8_t LoRa_ParsePacket(void);
void    LoRa_ReadBytes(uint8_t *buffer, uint8_t size);
uint8_t LoRa_Transmit(uint8_t *buffer, uint8_t size);

#endif /* LORA_H_ */
