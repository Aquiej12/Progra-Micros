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
5. [Compilar y flashear](#5-compilar-y-flashear)
6. [Configurar Adafruit IO](#6-configurar-adafruit-io)
7. [Ejecutar el puente Python](#7-ejecutar-el-puente-python)
8. [Protocolo de comunicación](#8-protocolo-de-comunicación)
9. [Mapeo de pines](#9-mapeo-de-pines)
10. [Cumplimiento de requisitos](#10-cumplimiento-de-requisitos)
11. [Solución de problemas](#11-solución-de-problemas)

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

### Carpeta `Control/Control/` (mando)

| Archivo | Función |
|---------|---------|
| `main.c` | Lógica completa del control (joysticks, modos, EEPROM, UART, LoRa TX) |
| `spi.c/h` | SPI maestro a 1 MHz |
| `lora.c/h` | Driver SX1276 (TX bloqueante con timeout 100 ms) |
| `uart.c/h` | USART0 polling con TX + RX no bloqueante |
| `puente_adafruit.py` | Script Python que corre en la PC |
| `README.md` | Este documento |

### Carpeta `Servomotor_pot_ejemplo/Servomotor_pot_ejemplo/` (robot)

| Archivo | Función |
|---------|---------|
| `main.c` | Lógica del robot — solo recibe LoRa y ejecuta cinemática |
| `soft_servo.c/h` | PWM software, Timer1 ISR @ 20 µs, 8 canales |
| `flexi_timer.c/h` | Timer2 → frame_flag cada 10 ms |
| `spi.c/h` | SPI (igual que el control) |
| `lora.c/h` | Driver SX1276 (RX continuo) |
| `uart.c/h` | UART solo para debug prints (RX sin uso real) |

---

## 5. Compilar y flashear

### Control TX

1. Abre `Control/Control/Control.cproj` en **Microchip Studio**.
2. Verifica que estén estos archivos en el proyecto:
   `main.c`, `spi.c/h`, `lora.c/h`, `uart.c/h`.
3. **Build → F7**, confirma 0 errores.
4. Flashea al ATmega328P.

### Robot RX

1. Abre `Servomotor_pot_ejemplo/Servomotor_pot_ejemplo/Proyecto2.cproj`.
2. Verifica los archivos:
   `main.c`, `soft_servo.c/h`, `flexi_timer.c/h`, `spi.c/h`, `lora.c/h`, `uart.c/h`.
3. **Build → F7**.
4. Flashea al ATmega328P del robot.

---

## 6. Configurar Adafruit IO

### Paso 1 — Cuenta y API Key
1. Crea cuenta en [io.adafruit.com](https://io.adafruit.com).
2. Header → ícono de **llave amarilla** → copia tu `username` y `AIO Key`.

### Paso 2 — Crear los feeds

Crea **5 feeds** (todos públicos):

| Nombre del feed | Dirección | Uso |
|-----------------|-----------|-----|
| `robot-comando` | Dashboard → script | Botones de control |
| `joystick-fb` | Control → dashboard | Telemetría joystick adelante/atrás |
| `joystick-lr` | Control → dashboard | Telemetría joystick lateral |
| `joystick-yaw` | Control → dashboard | Telemetría joystick giro |
| `joystick-ht` | Control → dashboard | Telemetría joystick altura |

### Paso 3 — Crear el dashboard
1. Menú **Dashboards** → **+ New Dashboard**
2. **Name:** `Robot Control`
3. Habilita **Dashboard Privacy: Public**.

### Paso 4 — Agregar bloques al dashboard

#### A) Botones de control (Momentary Button, enlazados a `robot-comando`)

| Botón | Texto | Press Value |
|-------|-------|-------------|
| 1 | ▲ Avanzar | `FORWARD` |
| 2 | ▼ Retroceder | `BACKWARD` |
| 3 | ◄ Giro Izq | `LEFT` |
| 4 | ► Giro Der | `RIGHT` |
| 5 | ◄◄ Strafe Izq | `STRAFE_L` |
| 6 | ►► Strafe Der | `STRAFE_R` |
| 7 | ● REC | `RECORD` |

> El script Python acepta también los valores cortos: `F`, `B`, `L`, `R`, `I`, `D`, `C`.
> El botón **REC** envía `'C'` al control → toggle de `action_btn` → arranca/cierra la grabación en EEPROM (igual que apretar el botón físico ACCIÓN).

#### B) Bloques de telemetría (Line Chart o Gauge)

Agrega **4 bloques tipo Line Chart** o **Gauge**, cada uno enlazado a su feed:

| Bloque | Feed | Sugerencia visual |
|--------|------|-------------------|
| Joystick Adelante/Atrás | `joystick-fb` | Line Chart con rango [-512, +512] |
| Joystick Lateral | `joystick-lr` | Line Chart con rango [-512, +512] |
| Joystick Giro | `joystick-yaw` | Line Chart con rango [-512, +512] |
| Joystick Altura | `joystick-ht` | Line Chart con rango [-512, +512] |

Estos se actualizan automáticamente cada ~200 ms desde el control (en cualquier modo), **pero el puente Python filtra**: solo publica un feed cuando el valor cambió ≥15 cuentas **Y** han pasado ≥1.5 s desde la última publicación a ese feed (anti-throttle de Adafruit).

---

## 7. Ejecutar el puente Python

### Requisitos
```bash
pip install adafruit-io pyserial
```

### Configurar `puente_adafruit.py`
Edita las primeras líneas:
```python
ADAFRUIT_IO_USERNAME = "tu_usuario"
ADAFRUIT_IO_KEY      = "tu_key_aqui"
SERIAL_PORT          = "COM3"   # Windows
# SERIAL_PORT        = "/dev/ttyUSB0"  # Linux/Mac
SERIAL_BAUD          = 9600
```

### Pasos para usar el modo UART

1. **Encender el robot** (flasheo con el `main.c` del RX).
2. **Encender el control** y presionar el botón MODO hasta que **LED_UART (D7) se encienda fijo**.
3. **Conectar el control a la PC** vía USB-Serial:
   - USB-Serial TX → D0 del control
   - USB-Serial RX → D1 del control
   - GND común
4. **Ejecutar el script:**
   ```bash
   python puente_adafruit.py
   ```
5. **Presionar botones** en el dashboard de Adafruit IO.

Salida esperada:
```
[OK] Puerto serial COM3 @ 9600 baud abierto.
[INFO] Conectando a Adafruit IO...
[OK] Conectado a Adafruit IO. Suscribiendo a 'robot-comando'...
[INFO] Esperando comandos del dashboard...
[RX MQTT] Feed 'robot-comando' = 'FORWARD'
[TX UART] Enviado: 'F' al control.
[RX UART] UART OK: F
```

---

## 8. Protocolo de comunicación

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

## 9. Mapeo de pines (resumen)

### CONTROL TX
```
A0  PC0 → Joystick fwd_bwd     PD0 → UART RX (de la PC)
A1  PC1 → Joystick left_right  PD1 → UART TX (a la PC)
A2  PC2 → Joystick yaw         D5  PD5 → LED_MANUAL
A3  PC3 → Joystick height      D6  PD6 → LED_EEPROM
D2  PD2 → Botón MODO            D7  PD7 → LED_UART
D3  PD3 → Botón ACCIÓN
D8  PB0 → LoRa DIO0             D11 PB3 → LoRa MOSI
D9  PB1 → LoRa RST              D12 PB4 → LoRa MISO
D10 PB2 → LoRa NSS              D13 PB5 → LoRa SCK
```

### ROBOT RX
```
D2  PD2 → S1 knee       D8  PB0 → S2 hip
D3  PD3 → S1 hip        D9  PB1 → S2 knee
D4  PD4 → S4 knee       D10 PB2 → LoRa NSS
D5  PD5 → S4 hip        D11 PB3 → LoRa MOSI
D6  PD6 → S3 knee       D12 PB4 → LoRa MISO
D7  PD7 → S3 hip        D13 PB5 → LoRa SCK
A0  PC0 → LoRa RST      A1  PC1 → LoRa DIO0
```

---

## 10. Cumplimiento de requisitos

| # | Requisito del proyecto | ✅ | Dónde |
|---|------------------------|----|-------|
| 1 | Estados grabables y reproducibles en EEPROM | ✓ | `rec_*` y `pb_*` en `Control/main.c` |
| 2 | ≥4 servos controlados por PWM | ✓ | 8 servos en `soft_servo.c` del robot |
| 3 | 4 entradas analógicas (potenciómetros) | ✓ | 4 joysticks ADC en `Control/main.c` |
| 4 | Modo Manual | ✓ | `mode == 0` en `Control/main.c` |
| 5 | Modo EEPROM | ✓ | `mode == 1` en `Control/main.c` |
| 6 | Modo UART | ✓ | `mode == 2` en `Control/main.c` |
| 7 | LED indicador del modo | ✓ | 3 LEDs en el control (D5/D6/D7) |
| 8 | Dashboard Adafruit IO + comunicación serial | ✓ | `puente_adafruit.py` + Adafruit |

---

## 11. Cómo detener el sistema sin romper nada

### Detener el script Python (forma correcta)

En la terminal donde corre el script, presiona **`Ctrl + C`**.

El script captura el `KeyboardInterrupt` y ejecuta `cerrar_todo()`, que:

1. Pone la bandera `running = False` → el thread de lectura serial sale de su loop.
2. Cierra el puerto serial (`ser.close()`) → libera el COM.
3. Desconecta MQTT (`client.disconnect()`) → cierra la sesión con Adafruit IO.
4. Sale con `sys.exit(0)`.

Verás en consola:
```
[INFO] Ctrl+C detectado.
[INFO] Cerrando puente...
[OK] Puerto serial cerrado.
[OK] MQTT desconectado.
```

### ⚠️ NO hagas esto

- **No cierres la terminal con la `X`** sin antes presionar `Ctrl + C`. Si lo haces, el puerto serial puede quedar bloqueado por el sistema operativo.
- **No mates el proceso con `kill -9`** (Linux/Mac) o **Task Manager → End Task** (Windows). Mismo problema.

### Si el puerto quedó bloqueado

| Sistema | Solución |
|---------|----------|
| Windows | Desenchufa y vuelve a enchufar el adaptador USB-Serial |
| Linux | `sudo fuser -k /dev/ttyUSB0` o reinicia la terminal |
| Mac | Desconecta el cable USB y vuélvelo a conectar |

### Detener el hardware

- **El control:** puede quedar encendido sin problemas. El robot detecta watchdog (sin paquetes LoRa) y se queda quieto solo. El LED de enlace LoRa (PC2 del robot) se apaga.
- **El robot:** desconecta la alimentación. Si lo dejas con servos energizados mucho rato sin moverse, los SG90 se calientan.

### Si quieres apagar todo "limpiamente"

1. **`Ctrl + C`** en la terminal del script Python (libera el puerto y MQTT).
2. **Apaga el control** (cualquier modo, presionando el switch de batería).
3. **Apaga el robot**.

---

## 12. Solución de problemas

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
