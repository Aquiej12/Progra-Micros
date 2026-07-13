# Robot Cuadrúpedo — Proyecto 2 IE2023

> Universidad del Valle de Guatemala · Programación de Microcontroladores
> Ciclo 1, 2026

Robot cuadrúpedo de 8 servos controlado inalámbricamente por LoRa. Tiene **3 modos de operación** (Manual, EEPROM, UART) y se conecta a un **dashboard de Adafruit IO** a través de un puente Python.

---


## Tabla de contenidos

1. [Arquitectura del sistema](#1-arquitectura-del-sistema)
2. [Hardware](#2-hardware)
3. [Modos de operación](#3-modos-de-operación)
4. [Estructura de archivos](#4-estructura-de-archivos)
5. [Protocolo de comunicación](#5-protocolo-de-comunicación)
6. [Solución de problemas](#6-solución-de-problemas)

---

## 1. Arquitectura del sistema

```
                 ┌─────────────────────────────────────────────┐
                 │                  PC (Python)                │
                 │       puente_adafruit.py                    │
                 └────────┬─────────────────────────────┬──────┘
                          │ MQTT                        │ USB-Serial
                          ▼                             ▼
        ┌──────────────────────────┐         ┌──────────────────────┐
        │     ADAFRUIT IO          │         │   CONTROL TX         │
        │     (Dashboard)          │         │   ATmega328P         │
        │   Feed: robot-comando    │         │  ──────────────────  │
        └──────────────────────────┘         │  • 4 ADC joysticks   │
                                             │  • 2 botones         │
                                             │  • 3 LEDs            │
                                             │  • EEPROM (macros)   │
                                             │  • UART ← PC         │
                                             │  • LoRa SX1276 TX    │
                                             └──────────┬───────────┘
                                                        │ LoRa 915 MHz
                                                        │ Payload 10 B
                                                        ▼
                                             ┌──────────────────────┐
                                             │   ROBOT RX           │
                                             │   ATmega328P         │
                                             │  ──────────────────  │
                                             │  • 8 servos SG90     │
                                             │  • LoRa SX1276 RX    │
                                             │  • FSM de marcha     │
                                             │   (cinemática)       │
                                             │  • Watchdog 500 ms   │
                                             └──────────────────────┘
```

### División de responsabilidades

| Componente | Responsabilidad |
|------------|-----------------|
| **Control TX** | **Cerebro del sistema.** Lee 4 joysticks, 2 botones, controla 3 LEDs, graba/lee EEPROM, recibe comandos UART desde la PC, y en **todos los modos** arma un `Payload_t` que envía por LoRa. |
| **Robot RX** | **Ejecutor.** Solo recibe Payload por LoRa, aplica `fb / lr / yw / height` a la cinemática y mueve los 8 servos. No conoce los modos. |
| **Python (PC)** | **Puente.** Conecta Adafruit IO (MQTT) con el control (USB-Serial). Traduce texto del dashboard a un byte ASCII. |
| **Adafruit IO** | Interfaz web. Dashboard con 7 botones que publican en un feed MQTT. |

---

## 2. Hardware

### CONTROL TX (ATmega328P @ 16 MHz)

| Pin | Función | Tipo |
|-----|---------|------|
| PC0 / A0 | Joystick fwd_bwd | ADC |
| PC1 / A1 | Joystick left_right | ADC |
| PC2 / A2 | Joystick yaw | ADC |
| PC3 / A3 | Joystick height | ADC |
| PD2 / D2 | Botón MODO (pull-up) | IN |
| PD3 / D3 | Botón ACCIÓN (pull-up) | IN |
| PD5 / D5 | LED_MANUAL | OUT |
| PD6 / D6 | LED_EEPROM | OUT |
| PD7 / D7 | LED_UART | OUT |
| PD0 / D0 | UART RX (← PC) | IN |
| PD1 / D1 | UART TX (→ PC) | OUT |
| PB3 / D11 | LoRa MOSI | SPI |
| PB4 / D12 | LoRa MISO | SPI |
| PB5 / D13 | LoRa SCK | SPI |
| PB2 / D10 | LoRa NSS | OUT |
| PB1 / D9 | LoRa RST | OUT |
| PB0 / D8 | LoRa DIO0 (TxDone) | IN |
| EEPROM interna | Macros grabadas (~200 eventos) | — |

### ROBOT RX (ATmega328P @ 16 MHz)

8 servos SG90 — todos PWM por software (Timer1):

| Pata | Lado | Hip | Knee |
|------|------|-----|------|
| S1 — Frente Izquierda (FL) | Izq | D3 (PD3) | D2 (PD2) |
| S2 — Frente Derecha (FR) | Der | D8 (PB0) | D9 (PB1) |
| S3 — Atrás Derecha (RR) | Der | D7 (PD7) | D6 (PD6) |
| S4 — Atrás Izquierda (RL) | Izq | D5 (PD5) | D4 (PD4) |

LoRa:
- MOSI/MISO/SCK/NSS = SPI estándar
- RST = PC0 (A0)
- DIO0 = PC1 (A1)

---

## 3. Modos de operación

El **botón MODO (PD2)** del control cicla entre los 3 modos. Cada modo enciende su propio LED.

### Modo 0 — MANUAL · LED_MANUAL (D5)

- El control lee los **4 joysticks** y arma `Payload_t`.
- Lo envía por LoRa cada 20 ms.
- Si el **botón ACCIÓN** está en latch ON (LED_MANUAL **parpadea**), el control **graba en su EEPROM** los movimientos del joystick (valores simplificados a -1/0/+1 + duración).
- Al soltar el botón ACCIÓN se escribe el marcador EOF y la macro queda guardada.

### Modo 1 — EEPROM · LED_EEPROM (D6)

- El control **ignora los joysticks**.
- Lee la macro grabada en EEPROM evento por evento.
- Por cada evento, magnifica los valores `-1/0/+1` a `±100` (para que pasen el deadzone del robot).
- Envía `Payload_t` por LoRa cada 20 ms.
- Reproduce en **loop infinito** (cuando llega al EOF, vuelve al principio).

### Modo 2 — UART · LED_UART (D7)

- El control **lee bytes desde la PC** (UART).
- Cada byte ASCII es un comando que mapea a un movimiento.
- El último comando se mantiene activo hasta que llegue otro.
- Genera `Payload_t` desde el comando y lo envía por LoRa.

| Byte | Comando |
|------|---------|
| `F` / `f` | Forward (avanzar) |
| `B` / `b` | Backward (retroceder) |
| `L` / `l` | Left turn (giro izq) |
| `R` / `r` | Right turn (giro der) |
| `I` / `i` | strafe Izquierda |
| `D` / `d` | strafe Derecha |
| `S` / `s` | Stop |

---

## 4. Estructura de archivos

### Carpeta `Control` (mando)

| Archivo | Función |
|---------|---------|
| `main.c` | Lógica completa del control (joysticks, modos, EEPROM, UART, LoRa TX) |
| `spi.c/h` | SPI maestro a 1 MHz |
| `lora.c/h` | Driver SX1276 (TX bloqueante con timeout 100 ms) |
| `uart.c/h` | USART0 polling con TX + RX no bloqueante |
| `puente_adafruit.py` | Script Python que corre en la PC |
| `README.md` | Este documento |

### Carpeta `Servomotor_pot_ejemplo` (robot)

| Archivo | Función |
|---------|---------|
| `main.c` | Lógica del robot — solo recibe LoRa y ejecuta cinemática |
| `soft_servo.c/h` | PWM software, Timer1 ISR @ 20 µs, 8 canales |
| `flexi_timer.c/h` | Timer2 → frame_flag cada 10 ms |
| `spi.c/h` | SPI (igual que el control) |
| `lora.c/h` | Driver SX1276 (RX continuo) |
| `uart.c/h` | UART solo para debug prints (RX sin uso real) |



## 5. Protocolo de comunicación

### Payload LoRa (Control → Robot, 10 bytes)

```c
typedef struct {
    int16_t fwd_bwd;       // ±DEADZONE define "avanzar/retroceder"
    int16_t left_right;    // ±DEADZONE define "strafe izq/der"
    int16_t yaw;           // ±DEADZONE define "giro izq/der"
    int16_t height;        // offset de rodilla
    uint8_t mode;          // info para debug — el robot lo ignora
    uint8_t action_btn;    // info para debug — el robot lo ignora
} Payload_t;
```

El robot interpreta `fb / lr / yw` con prioridad **fb > lr > yw** y aplica la cinemática correspondiente (avance, strafe, giro).

### Evento en EEPROM (Control, 5 bytes)

```c
typedef struct {
    int8_t   j_fb;          // -1, 0 o +1
    int8_t   j_lr;          // -1, 0 o +1
    int8_t   j_yaw;         // -1, 0 o +1
    uint16_t duration_ticks;// 0xFFFF = EOF
} EEPROM_Macro_t;
```

Capacidad: 1000 bytes / 5 = **~200 eventos por macro** (reservados 5 bytes finales para el EOF).

### Comando UART (PC → Control, 1 byte)

Ver tabla en sección **3 - Modo 2**.

### Echo UART (Control → PC, ASCII)

El control responde por UART:
- `UART OK: F` por cada comando recibido
- `Modo: 2` al cambiar de modo
- `EEPROM Grabado!` por cada evento escrito en EEPROM (modo 0 + REC)
- `Error: Tx Timeout` si LoRa no responde al transmitir

---


## 6. Solución de problemas

| Síntoma | Posible causa | Cómo verificar |
|---------|---------------|----------------|
| Robot no se mueve | Sin señal LoRa | Serial del robot debe mostrar `Pkt fb=...` cada ~5 paquetes |
| `ERROR: Fallo comunicacion SPI LoRa` | Cableado SPI o módulo sin 3.3V | Revisa MOSI/MISO/SCK/NSS y la alimentación 3.3V |
| `Error: Tx Timeout` repetido en el control | Módulo TX vivo pero no transmite | Revisa antena, frecuencia y `DIO0` del control (PB0) |
| Dashboard envía pero el robot no responde | Modo UART no activo o serial mal conectado | LED_UART (D7) del control debe estar encendido |
| `[ERROR] No se pudo abrir COM3` en Python | Puerto incorrecto u ocupado | Cierra Arduino IDE u otros monitores serial |
| Python conecta pero `comando desconocido` | Texto del botón no está en la tabla | Usa exactamente `FORWARD`, `BACKWARD`, etc. (mayúsculas) |
| EEPROM no graba | Está en modo 1 (Reproducción) | `rec_*` tiene guardias; pasa a modo 0 primero |
| EEPROM macro queda incompleta | Cambiaste de modo sin soltar ACCIÓN | `rec_stop` es agnóstico al modo — debería cerrar; si no, suelta ACCIÓN primero |
| Servos tiemblan al arrancar | Pico de corriente | Fuente 5V/3A + capacitor 470 µF cerca de los servos |
| Robot se va para un lado | Calibración de joysticks o `side_mirror` | Mantén los joysticks centrados al arrancar |
