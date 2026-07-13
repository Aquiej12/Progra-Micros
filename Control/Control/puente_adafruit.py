"""
puente_adafruit.py
Created: Guatemala 17/05/2026
Author: Abner Quiej
Description: Puente bidireccional Adafruit IO <-> CONTROL UART
======================================================================

"""

import os
import sys
import time
import threading

# ─── Librerias de terceros ─────────────────────────────────────────────
try:
    import serial
except ImportError:
    print("ERROR: pyserial no instalado. Ejecuta: pip install pyserial")
    sys.exit(1)

try:
    from Adafruit_IO import MQTTClient
except ImportError:
    print("ERROR: Adafruit_IO no instalado. Ejecuta: pip install adafruit-io")
    sys.exit(1)


# ═══════════════════════════════════════════════════════════════════════
#  CONFIGURACION 
# ═══════════════════════════════════════════════════════════════════════
# Las credenciales NO van en el codigo (para no subirlas a git).
# Opcion A: variables de entorno ADAFRUIT_IO_USERNAME / ADAFRUIT_IO_KEY
# Opcion B: archivo local credenciales.py (ignorado por git)
#           -> copia credenciales.ejemplo.py a credenciales.py y pon tus datos
ADAFRUIT_IO_USERNAME = os.environ.get("ADAFRUIT_IO_USERNAME")
ADAFRUIT_IO_KEY      = os.environ.get("ADAFRUIT_IO_KEY")

if not ADAFRUIT_IO_USERNAME or not ADAFRUIT_IO_KEY:
    try:
        from credenciales import ADAFRUIT_IO_USERNAME, ADAFRUIT_IO_KEY
    except ImportError:
        print("ERROR: faltan las credenciales de Adafruit IO.\n"
              "  Opcion A: define las variables de entorno "
              "ADAFRUIT_IO_USERNAME y ADAFRUIT_IO_KEY\n"
              "  Opcion B: copia credenciales.ejemplo.py a credenciales.py "
              "y coloca tus datos.")
        sys.exit(1)

# Feed donde el dashboard publica los comandos de movimiento
FEED_COMANDO = "robot-comando"

# Feeds donde el script publica los valores de los joysticks (ADC)
FEED_FB  = "joystick-fb"        # Movimiento Adelante - Atras 
FEED_LR  = "joystick-lr"        # Movimiento Izquierda - Derecha
FEED_YAW = "joystick-yaw"       # Giro Izquierda - Derecha
FEED_HT  = "joystick-ht"        # altura 


# Feed opcional para republicar status 
FEED_STATUS  = "robot-status"

# Definicion del Puerto serial y los baudios de comunicación
SERIAL_PORT = "COM6"
SERIAL_BAUD = 9600


# ═══════════════════════════════════════════════════════════════════════
#  TABLA DE TRADUCCION — texto del dashboard → byte para el control
# ═══════════════════════════════════════════════════════════════════════
COMANDOS = {
    "FORWARD":  "F",        # Camina hacia adelante
    "F":        "F",
    
    "BACKWARD": "B",        # Camina hacia atras
    "B":        "B",

    "LEFT":     "L",        # Camina hacia la izquierda
    "L":        "L",

    "RIGHT":    "R",        # Camina hacia la derecha
    "R":        "R",

    "STRAFE_L": "I",        # Gira en su eje A la izquierda
    "I":        "I",
    
    "STRAFE_R": "D",        # Gira en su eje a la derecha
    "D":        "D",
    
    "RECORD":   "C",        # toggle EEPROM 
    "C":        "C",

    "STOP":     "S",        # detiene el movimiento (devuelve a stand)
    "S":        "S",
}


# ═══════════════════════════════════════════════════════════════════════
#  Conexion serial con el CONTROL
# ═══════════════════════════════════════════════════════════════════════
try:
    ser = serial.Serial(SERIAL_PORT, SERIAL_BAUD, timeout=1)
    print(f"[OK] Puerto serial {SERIAL_PORT} @ {SERIAL_BAUD} baud abierto.")
    time.sleep(2)
except serial.SerialException as e:
    print(f"[ERROR] No se pudo abrir {SERIAL_PORT}: {e}")
    sys.exit(1)


# ─── Cliente MQTT global ──
client = MQTTClient(ADAFRUIT_IO_USERNAME, ADAFRUIT_IO_KEY)

# Bandera para detener el thread serial al cerrar
running = True


# ═══════════════════════════════════════════════════════════════════════
#  CALLBACKS DE ADAFRUIT IO (MQTT)
# ═══════════════════════════════════════════════════════════════════════
def connected(client):
    print(f"[OK] Conectado a Adafruit IO. Suscribiendo a '{FEED_COMANDO}'...")
    client.subscribe(FEED_COMANDO)
    print("[INFO] Esperando comandos del dashboard...")


def disconnected(client):
    print("[ERROR] Desconectado de Adafruit IO.")
    sys.exit(1)


def message(client, feed_id, payload):
    """Llega un valor nuevo a un feed suscrito → mandar byte al control."""
    print(f"[RX MQTT] Feed '{feed_id}' = '{payload}'")

    cmd_text = payload.strip().upper()
    if cmd_text not in COMANDOS:
        print(f"[WARN] Comando desconocido: '{cmd_text}'")
        return

    char = COMANDOS[cmd_text]
    try:
        ser.write(char.encode("ascii"))
        print(f"[TX UART] Enviado: '{char}' al control.")
    except serial.SerialException as e:
        print(f"[ERROR] Fallo escritura serial: {e}")


# ═══════════════════════════════════════════════════════════════════════
#  THREAD DE LECTURA SERIAL  (SEND-ON-CHANGE — anti-throttle de Adafruit)
# ═══════════════════════════════════════════════════════════════════════

DELTA_THRESHOLD = 15        # cambio minimo (en cuentas ADC) para publicar
COOLDOWN_SEC    = 1.5       # tiempo minimo entre publicaciones por feed

# Ultimos valores publicados a Adafruit (por feed)
last_fb  = None
last_lr  = None
last_yw  = None
last_ht  = None

# Timestamp del ultimo publish exitoso (por feed)
ts_last_fb = 0.0
ts_last_lr = 0.0
ts_last_yw = 0.0
ts_last_ht = 0.0

# ─── Bandera de modo del control (anti-throttle inteligente) ──────────
#
#   None  → desconocido (al arrancar, antes del primer "Modo:" o "Modo UART")
#   0     → MANUAL (joysticks fisicos)   → SI publicar telemetria ADC
#   1     → EEPROM PLAYBACK              → NO publicar (es reproduccion)
#   2     → UART (Adafruit dashboard)    → SI publicar

control_mode = None


def publish_si_cambia(feed, valor_nuevo, valor_anterior, ts_anterior):
    """Publica en MQTT solo si pasa el filtro de delta + cooldown.

    Retorna una tupla (publicado, valor_actualizado, ts_actualizado).
    """
    ahora = time.monotonic()

    if (ahora - ts_anterior) < COOLDOWN_SEC:
        return (False, valor_anterior, ts_anterior)

    if valor_anterior is not None:
        if abs(valor_nuevo - valor_anterior) < DELTA_THRESHOLD:
            return (False, valor_anterior, ts_anterior)

    try:
        client.publish(feed, valor_nuevo)
        print(f"[ADC → AIO] {feed} = {valor_nuevo} "
              f"(delta={valor_nuevo - (valor_anterior or 0)})")
        return (True, valor_nuevo, ahora)
    except Exception as e:
        print(f"[WARN] Fallo publish '{feed}': {e}")
        return (False, valor_anterior, ts_anterior)


def serial_reader_thread():
    global last_fb, last_lr, last_yw, last_ht
    global ts_last_fb, ts_last_lr, ts_last_yw, ts_last_ht
    global control_mode

    while running:
        try:
            if ser.in_waiting > 0:
                line = ser.readline().decode("ascii", errors="ignore").strip()
                if not line:
                    continue

                # ─── Telemetria de los ADC (4 valores: fb, lr, yw, ht) ────
                if line.startswith("AIO_ADC:"):

                    if control_mode == 1:
                        continue   # ignora la trama, no publica

                    try:
                        valores = line[len("AIO_ADC:"):].split(",")
                        fb_nuevo = int(valores[0])
                        lr_nuevo = int(valores[1])
                        yw_nuevo = int(valores[2])
                        ht_nuevo = int(valores[3])


                        _, last_fb, ts_last_fb = publish_si_cambia(
                            FEED_FB,  fb_nuevo, last_fb, ts_last_fb)
                        _, last_lr, ts_last_lr = publish_si_cambia(
                            FEED_LR,  lr_nuevo, last_lr, ts_last_lr)
                        _, last_yw, ts_last_yw = publish_si_cambia(
                            FEED_YAW, yw_nuevo, last_yw, ts_last_yw)
                        _, last_ht, ts_last_ht = publish_si_cambia(
                            FEED_HT,  ht_nuevo, last_ht, ts_last_ht)

                    except (ValueError, IndexError) as e:
                        print(f"[WARN] Trama AIO_ADC mal formada: '{line}' ({e})")

                # ─── Detecta el modo actual del control ─────────────────
                elif line == "Modo UART":
                    control_mode = 2
                    print(f"[MODO] Control en MODO 2 (UART) — publicacion ADC activa")
                elif line.startswith("Modo: "):
                    try:
                        m = int(line[len("Modo: "):])
                        control_mode = m
                        nombre = {0: "MANUAL", 1: "PLAYBACK (EEPROM)"}.get(m, f"?{m}")
                        estado_pub = ("ADC desactivada" if m == 1
                                      else "ADC activa")
                        print(f"[MODO] Control en MODO {m} ({nombre}) — {estado_pub}")
                    except ValueError:
                        print(f"[RX UART] {line}")

                else:
                    print(f"[RX UART] {line}")

            else:
                time.sleep(0.02)
        except serial.SerialException as e:
            print(f"[ERROR] Lectura serial fallo: {e}")
            break
        except Exception as e:
            print(f"[WARN] Excepcion en thread serial: {e}")
            time.sleep(0.1)


# ═══════════════════════════════════════════════════════════════════════
#  Cierre limpio (libera puerto serial + desconecta MQTT)
# ═══════════════════════════════════════════════════════════════════════
def cerrar_todo():
    """Cierra el puerto serial y desconecta MQTT sin dejar nada colgado."""
    global running
    running = False
    print("[INFO] Cerrando puente...")

    # Esperar a que el thread serial termine su iteracion actual
    time.sleep(0.1)

    try:
        if ser.is_open:
            ser.close()
            print("[OK] Puerto serial cerrado.")
    except Exception as e:
        print(f"[WARN] Error cerrando serial: {e}")

    try:
        client.disconnect()
        print("[OK] MQTT desconectado.")
    except Exception as e:
        print(f"[WARN] Error cerrando MQTT: {e}")


# ═══════════════════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════════════════
def main():
    client.on_connect    = connected
    client.on_disconnect = disconnected
    client.on_message    = message

    print("[INFO] Conectando a Adafruit IO...")
    client.connect()
    client.loop_background()

    # Lanza el thread que lee el serial y publica a Adafruit
    t_serial = threading.Thread(target=serial_reader_thread, daemon=True)
    t_serial.start()
    print("[OK] Thread de lectura serial iniciado.")

    try:
        # El main se queda dormido — todo el trabajo lo hace el thread
        # serial y el loop_background() de MQTT.
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n[INFO] Ctrl+C detectado.")
    finally:
        cerrar_todo()
        sys.exit(0)


if __name__ == "__main__":
    main()
