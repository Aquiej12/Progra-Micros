/*  lora.c — Driver SX1276 minimo (LoRa, RX continuo + TX bloqueante)
 *
 *  ╔══════════════════════════════════════════════════════════════════╗
 *  ║ ESTA ES LA VERSION DEL CONTROL (TX).                            ║
 *  ║ Pines RST y DIO0 difieren respecto al ROBOT (RX).               ║
 *  ║ Si copias este archivo al proyecto Robot, cambia el bloque      ║
 *  ║ "Pin map" para que use:                                          ║
 *  ║    RST  = PC0 (A0)                                               ║
 *  ║    DIO0 = PC1 (A1)                                               ║
 *  ╚══════════════════════════════════════════════════════════════════╝
 */
#define F_CPU 16000000UL
#include "lora.h"
#include "spi.h"
#include <avr/io.h>
#include <util/delay.h>

/* ════════════════════════════════════════════════════════════════════
 *  Pin map  — CONTROL (TX)
 * ═══════════════════════════════════════════════════════════════════ */
#define NSS_PORT   PORTB
#define NSS_DDR    DDRB
#define NSS_BIT    PB2          /* D10 — comun a ambos proyectos */

#define RST_PORT   PORTB
#define RST_DDR    DDRB
#define RST_BIT    PB1          /* D9 — Control */

#define DIO0_DDR   DDRB
#define DIO0_PIN   PINB
#define DIO0_BIT   PB0          /* D8 — Control */

/* ════════════════════════════════════════════════════════════════════
 *  Registros SX1276 (modo LoRa)
 * ═══════════════════════════════════════════════════════════════════ */
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
#define REG_VERSION               0x42

/* ── Modos (REG_OP_MODE) ──────────────────────────────────────────── */
#define MODE_LONG_RANGE_MODE  0x80      /* bit LoRa */
#define MODE_SLEEP            0x00
#define MODE_STDBY            0x01
#define MODE_TX               0x03
#define MODE_RX_CONTINUOUS    0x05

/* ── PA Config ────────────────────────────────────────────────────── */
#define PA_BOOST              0x80

/* ── IRQ flags ────────────────────────────────────────────────────── */
#define IRQ_TX_DONE_MASK         0x08
#define IRQ_PAYLOAD_CRC_ERROR    0x20
#define IRQ_RX_DONE_MASK         0x40

/* ── Estado ───────────────────────────────────────────────────────── */
static uint8_t packet_size = 0;

/* ── NSS helpers ─────────────────────────────────────────────────── */
static void lora_select(void)   { NSS_PORT &= ~(1 << NSS_BIT); }
static void lora_deselect(void) { NSS_PORT |=  (1 << NSS_BIT); }

/* ── Lectura/escritura de registros ───────────────────────────────── */
static uint8_t lora_read(uint8_t addr) {
    uint8_t val;
    lora_select();
    SPI_Transfer(addr & 0x7F);
    val = SPI_Transfer(0x00);
    lora_deselect();
    return val;
}

static void lora_write(uint8_t addr, uint8_t value) {
    lora_select();
    SPI_Transfer(addr | 0x80);
    SPI_Transfer(value);
    lora_deselect();
}

/* ════════════════════════════════════════════════════════════════════
 *  Init
 * ═══════════════════════════════════════════════════════════════════ */
uint8_t LoRa_Init(uint32_t frequency) {
    uint64_t frf;
    uint8_t  version;

    /* Pines de control */
    NSS_DDR  |=  (1 << NSS_BIT);
    RST_DDR  |=  (1 << RST_BIT);
    DIO0_DDR &= ~(1 << DIO0_BIT);

    lora_deselect();

    /* Reset: LOW 10ms → HIGH 10ms */
    RST_PORT &= ~(1 << RST_BIT);
    _delay_ms(10);
    RST_PORT |=  (1 << RST_BIT);
    _delay_ms(10);

    SPI_Init();

    /* ── Prueba SPI: REG_VERSION debe leer 0x12 ─────────────────── */
    version = lora_read(REG_VERSION);
    if (version != 0x12) {
        return 1;                  /* fallo de hardware/SPI */
    }

    /* SLEEP + LongRange (el bit LR solo se cambia en sleep) */
    lora_write(REG_OP_MODE, MODE_LONG_RANGE_MODE | MODE_SLEEP);
    _delay_ms(10);

    /* Frecuencia: FRF = (freq << 19) / 32 MHz */
    frf = ((uint64_t)frequency << 19) / 32000000UL;
    lora_write(REG_FRF_MSB, (uint8_t)(frf >> 16));
    lora_write(REG_FRF_MID, (uint8_t)(frf >> 8));
    lora_write(REG_FRF_LSB, (uint8_t)(frf));

    lora_write(REG_FIFO_TX_BASE_ADDR, 0x00);
    lora_write(REG_FIFO_RX_BASE_ADDR, 0x00);

    /* LNA boost ON */
    lora_write(REG_LNA, lora_read(REG_LNA) | 0x03);

    /* AGC automatico */
    lora_write(REG_MODEM_CONFIG_3, 0x04);

    /* Potencia TX = 17 dBm via PA_BOOST */
    lora_write(REG_PA_CONFIG, PA_BOOST | (17 - 2));

    /* Standby antes de RX */
    lora_write(REG_OP_MODE, MODE_LONG_RANGE_MODE | MODE_STDBY);

    /* Recepcion continua */
    lora_write(REG_OP_MODE, MODE_LONG_RANGE_MODE | MODE_RX_CONTINUOUS);

    return 0;                      /* OK */
}

/* ════════════════════════════════════════════════════════════════════
 *  ParsePacket — chequea IRQ y devuelve tamanio (0 si no hay)
 * ═══════════════════════════════════════════════════════════════════ */
uint8_t LoRa_ParsePacket(void) {
    uint8_t irq = lora_read(REG_IRQ_FLAGS);
    lora_write(REG_IRQ_FLAGS, irq);   /* limpiar flags */

    if ((irq & IRQ_RX_DONE_MASK) && !(irq & IRQ_PAYLOAD_CRC_ERROR)) {
        packet_size = lora_read(REG_RX_NB_BYTES);
        lora_write(REG_FIFO_ADDR_PTR, lora_read(REG_FIFO_RX_CURRENT_ADDR));
        return packet_size;
    }
    return 0;
}

/* ════════════════════════════════════════════════════════════════════
 *  ReadBytes — drena el FIFO en una sola transaccion SPI
 * ═══════════════════════════════════════════════════════════════════ */
void LoRa_ReadBytes(uint8_t *buffer, uint8_t size) {
    uint8_t i;
    lora_select();
    SPI_Transfer(REG_FIFO & 0x7F);
    for (i = 0; i < size; i++) {
        buffer[i] = SPI_Transfer(0x00);
    }
    lora_deselect();
}

/* ════════════════════════════════════════════════════════════════════
 *  Transmit — envio bloqueante de N bytes
 *
 *  Secuencia:
 *    1. STDBY
 *    2. FIFO_ADDR_PTR = TX_BASE (0)
 *    3. Escribir payload al FIFO
 *    4. PAYLOAD_LENGTH = size
 *    5. Modo TX → arranca transmision
 *    6. Esperar DIO0 = HIGH (TxDone)
 *    7. Limpiar IRQ_TX_DONE
 *    8. Volver a STDBY
 *
 *  Devuelve el numero de bytes enviados.
 * ═══════════════════════════════════════════════════════════════════ */
uint8_t LoRa_Transmit(uint8_t *buffer, uint8_t size) {
    uint8_t  i;
    uint16_t timeout_ms = 100;     /* 100 ms maximo de espera TxDone */

    /* 1. STDBY */
    lora_write(REG_OP_MODE, MODE_LONG_RANGE_MODE | MODE_STDBY);

    /* 2. Apuntar FIFO al inicio del area TX */
    lora_write(REG_FIFO_ADDR_PTR, 0x00);

    /* 3. Cargar payload en el FIFO (una sola transaccion SPI) */
    lora_select();
    SPI_Transfer(REG_FIFO | 0x80);
    for (i = 0; i < size; i++) {
        SPI_Transfer(buffer[i]);
    }
    lora_deselect();

    /* 4. Tamanio del payload */
    lora_write(REG_PAYLOAD_LENGTH, size);

    /* 4b. Mapear DIO0 → TxDone (sin esto DIO0 nunca sube en TX) */
    lora_write(0x40, 0x40);                    /* REG_DIO_MAPPING_1   */

    /* 5. Disparar transmision */
    lora_write(REG_OP_MODE, MODE_LONG_RANGE_MODE | MODE_TX);

    /* 6. Esperar TxDone con TIMEOUT (antes era bucle infinito) */
    while (!(DIO0_PIN & (1 << DIO0_BIT))) {
        if (timeout_ms == 0) {
            /* TIMEOUT — abortar limpiamente */
            lora_write(REG_IRQ_FLAGS, 0xFF);          /* limpia todas */
            lora_write(REG_OP_MODE,
                       MODE_LONG_RANGE_MODE | MODE_STDBY);
            return 0;                                  /* error */
        }
        _delay_ms(1);
        timeout_ms--;
    }

    /* 7. Limpiar bandera IRQ_TX_DONE */
    lora_write(REG_IRQ_FLAGS, IRQ_TX_DONE_MASK);

    /* 7b. Restaurar DIO0 → RxDone (por seguridad) */
    lora_write(0x40, 0x00);                    /* REG_DIO_MAPPING_1   */

    /* 8. Volver a STDBY */
    lora_write(REG_OP_MODE, MODE_LONG_RANGE_MODE | MODE_STDBY);

    return size;
}
