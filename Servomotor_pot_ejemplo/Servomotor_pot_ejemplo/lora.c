/*
 * lora.c
 *
 * Created: 
 * Author: 
 * Description: Driver SX1276 minimo (LoRa, RX continuo + TX bloqueante)
 */

 
/****************************************/
// Encabezado (Libraries)
/****************************************/
#define F_CPU 16000000UL
#include "lora.h"
#include "spi.h"
#include <avr/io.h>
#include <util/delay.h>

//Pin map  — ROBOT (RX)

#define NSS_PORT   PORTB
#define NSS_DDR    DDRB
#define NSS_BIT    PB2          
#define RST_PORT   PORTC
#define RST_DDR    DDRC
#define RST_BIT    PC0          
#define DIO0_DDR   DDRC
#define DIO0_PIN   PINC
#define DIO0_BIT   PC1          

// Registros SX1276 (modo LoRa)

#define REG_FIFO                  0x00
#define REG_OP_MODE               0x01
#define REG_FRF_MSB               0x06
#define REG_FRF_MID               0x07
#define REG_FRF_LSB               0x08
#define REG_PA_CONFIG             0x09
#define REG_LNA                   0x0C
#define REG_FIFO_ADDR_PTR         0x0D
#define REG_FIFO_TX_BASE_ADDR     0x0E
#define REG_FIFO_RX_BASE_ADDR     0x0F
#define REG_FIFO_RX_CURRENT_ADDR  0x10
#define REG_IRQ_FLAGS             0x12
#define REG_RX_NB_BYTES           0x13
#define REG_PAYLOAD_LENGTH        0x22
#define REG_MODEM_CONFIG_3        0x26
#define REG_DIO_MAPPING_1         0x40
#define REG_VERSION               0x42

// Modos (REG_OP_MODE)
#define MODE_LONG_RANGE_MODE  0x80      
#define MODE_SLEEP            0x00
#define MODE_STDBY            0x01
#define MODE_TX               0x03
#define MODE_RX_CONTINUOUS    0x05

// DIO0 mappings (bits 7:6 de REG_DIO_MAPPING_1) 
#define DIO0_RXDONE           0x00      
#define DIO0_TXDONE           0x40      

// PA Config 
#define PA_BOOST              0x80

// IRQ flags 
#define IRQ_TX_DONE_MASK         0x08
#define IRQ_PAYLOAD_CRC_ERROR    0x20
#define IRQ_RX_DONE_MASK         0x40

// Estado
static uint8_t packet_size = 0;

// NSS helpers 
static void lora_select(void)   { NSS_PORT &= ~(1 << NSS_BIT); }
static void lora_deselect(void) { NSS_PORT |=  (1 << NSS_BIT); }

// Lectura/escritura de registros 
static uint8_t lora_read(uint8_t addr) {
    uint8_t val;
    lora_select();
    SPI_Transfer(addr & 0x7F);          /* MSB = 0 → lectura  */
    val = SPI_Transfer(0x00);
    lora_deselect();
    return val;
}


/****************************************/
// Function prototypes
/****************************************/

static void lora_write(uint8_t addr, uint8_t value) {
    lora_select();
    SPI_Transfer(addr | 0x80);          /* MSB = 1 → escritura */
    SPI_Transfer(value);
    lora_deselect();
}

// Init — devuelve 0 = OK, 1 = fallo de SPI/version

uint8_t LoRa_Init(uint32_t frequency) {
    uint64_t frf;
    uint8_t  version;

    // Configurar pines de control
    NSS_DDR  |=  (1 << NSS_BIT);        // NSS  = salida
    RST_DDR  |=  (1 << RST_BIT);        // RST  = salida
    DIO0_DDR &= ~(1 << DIO0_BIT);       // DIO0 = entrada

    lora_deselect();                    // NSS = HIGH 

    // Pulso de reset: LOW 10ms a HIGH 10ms 
    RST_PORT &= ~(1 << RST_BIT);
    _delay_ms(10);
    RST_PORT |=  (1 << RST_BIT);
    _delay_ms(10);

    // Inicializar SPI 
    SPI_Init();

    //  Prueba SPI: REG_VERSION debe leer 0x12
    version = lora_read(REG_VERSION);
    if (version != 0x12) {
        return 1;                       
    }

    // SLEEP + LongRange 
    lora_write(REG_OP_MODE, MODE_LONG_RANGE_MODE | MODE_SLEEP);
    _delay_ms(10);

    // Frecuencia: FRF = (freq << 19) / 32 MHz 
    frf = ((uint64_t)frequency << 19) / 32000000UL;
    lora_write(REG_FRF_MSB, (uint8_t)(frf >> 16));
    lora_write(REG_FRF_MID, (uint8_t)(frf >> 8));
    lora_write(REG_FRF_LSB, (uint8_t)(frf));

    // Base addresses del FIFO 
    lora_write(REG_FIFO_TX_BASE_ADDR, 0x00);
    lora_write(REG_FIFO_RX_BASE_ADDR, 0x00);

    // LNA boost ON 
    lora_write(REG_LNA, lora_read(REG_LNA) | 0x03);

    // AGC automatico 
    lora_write(REG_MODEM_CONFIG_3, 0x04);

    // Potencia TX = 17 dBm via PA_BOOST 
    lora_write(REG_PA_CONFIG, PA_BOOST | (17 - 2));

    // Standby antes de pasar a RX 
    lora_write(REG_OP_MODE, MODE_LONG_RANGE_MODE | MODE_STDBY);

    // DIO0 = RxDone 
    lora_write(REG_DIO_MAPPING_1, DIO0_RXDONE);

    // Limpiar todas las flags IRQ antes de entrar a RX 
    lora_write(REG_IRQ_FLAGS, 0xFF);

    // Recepcion continua 
    lora_write(REG_OP_MODE, MODE_LONG_RANGE_MODE | MODE_RX_CONTINUOUS);

    return 0;                          
}

// ParsePacket — chequea IRQ y devuelve tamanio (0 si no hay)

uint8_t LoRa_ParsePacket(void) {
    uint8_t irq = lora_read(REG_IRQ_FLAGS);

    // Limpiar TODAS las flags (incluido RxDone a DIO0 baja)
    lora_write(REG_IRQ_FLAGS, irq);

    if ((irq & IRQ_RX_DONE_MASK) && !(irq & IRQ_PAYLOAD_CRC_ERROR)) {
        packet_size = lora_read(REG_RX_NB_BYTES);
        // Apuntar FIFO al inicio del paquete recibido
        lora_write(REG_FIFO_ADDR_PTR, lora_read(REG_FIFO_RX_CURRENT_ADDR));
        return packet_size;
    }
    return 0;
}

// ReadBytes — drena el FIFO en una sola transaccion SPI

void LoRa_ReadBytes(uint8_t *buffer, uint8_t size) {
    uint8_t i;
    lora_select();
    SPI_Transfer(REG_FIFO & 0x7F);         
    for (i = 0; i < size; i++) {
        buffer[i] = SPI_Transfer(0x00);
    }
    lora_deselect();
}

// Transmit — envio bloqueante de N bytes con timeout 100 ms

uint8_t LoRa_Transmit(uint8_t *buffer, uint8_t size) {
    uint8_t  i;
    uint16_t timeout_ms = 100;

    // 1. STDBY
    lora_write(REG_OP_MODE, MODE_LONG_RANGE_MODE | MODE_STDBY);

    // 2. Apuntar FIFO al inicio del area TX
    lora_write(REG_FIFO_ADDR_PTR, 0x00);

    // 3. Cargar payload en el FIFO (una sola transaccion SPI) 
    lora_select();
    SPI_Transfer(REG_FIFO | 0x80);
    for (i = 0; i < size; i++) {
        SPI_Transfer(buffer[i]);
    }
    lora_deselect();

    // 4. Tamanio del payload
    lora_write(REG_PAYLOAD_LENGTH, size);

    // 4b. Mapear DIO0 a TxDone 
    lora_write(REG_DIO_MAPPING_1, DIO0_TXDONE);

    // 5. Disparar transmision
    lora_write(REG_OP_MODE, MODE_LONG_RANGE_MODE | MODE_TX);

    // 6. Esperar TxDone con TIMEOUT 
    while (!(DIO0_PIN & (1 << DIO0_BIT))) {
        if (timeout_ms == 0) {
            lora_write(REG_IRQ_FLAGS, 0xFF);
            lora_write(REG_OP_MODE,
                       MODE_LONG_RANGE_MODE | MODE_STDBY);
            lora_write(REG_DIO_MAPPING_1, DIO0_RXDONE);  /* restaurar */
            return 0;
        }
        _delay_ms(1);
        timeout_ms--;
    }

    // 7. Limpiar bandera IRQ_TX_DONE 
    lora_write(REG_IRQ_FLAGS, IRQ_TX_DONE_MASK);

    // 7b. Restaurar DIO0 = RxDone (para que el RX siga funcionando) 
    lora_write(REG_DIO_MAPPING_1, DIO0_RXDONE);

    // 8. Volver a STDBY
    lora_write(REG_OP_MODE, MODE_LONG_RANGE_MODE | MODE_STDBY);

    return size;
}


