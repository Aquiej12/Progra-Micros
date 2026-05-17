#ifndef LORA_H_
#define LORA_H_

/*  lora — Driver minimo para SX1276 (modo LoRa, 915 MHz)
 *
 *  IMPORTANTE: Los pines RST y DIO0 estan definidos en lora.c.
 *  Cada proyecto (Robot/Control) tiene su lora.c con sus propios pines.
 *
 *  Pinout comun:
 *    MOSI ──> D11 PB3   (SPI hardware)
 *    MISO <── D12 PB4   (SPI hardware)
 *    SCK  ──> D13 PB5   (SPI hardware)
 *    NSS  ──> D10 PB2   (Chip Select)
 *
 *  API:
 *    LoRa_Init(freq)          – reset, version check, freq, PA_BOOST, RX
 *                                returns 0 = OK, 1 = SPI/version fail
 *    LoRa_ParsePacket()       – devuelve tamanio si hay paquete (RX)
 *    LoRa_ReadBytes(buf,n)    – lee N bytes del FIFO (RX)
 *    LoRa_Transmit(buf,n)     – envia N bytes con timeout 100 ms
 *                                returns size = OK, 0 = timeout
 */

#include <stdint.h>

uint8_t LoRa_Init(uint32_t frequency);
uint8_t LoRa_ParsePacket(void);
void    LoRa_ReadBytes(uint8_t *buffer, uint8_t size);
uint8_t LoRa_Transmit(uint8_t *buffer, uint8_t size);

#endif /* LORA_H_ */
