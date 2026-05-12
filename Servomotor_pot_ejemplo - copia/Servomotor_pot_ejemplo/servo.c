#include "servo.h"

static uint8_t  s_min_ocr[4];
static uint8_t  s_max_ocr[4];
static uint16_t s_min_adc[4];
static uint16_t s_max_adc[4];

void Servo_Init(uint8_t canal, uint16_t prescaler, uint8_t min_ocr, uint8_t max_ocr,
                uint16_t min_adc, uint16_t max_adc) {
    s_min_ocr[canal] = min_ocr;
    s_max_ocr[canal] = max_ocr;
    s_min_adc[canal] = min_adc;
    s_max_adc[canal] = max_adc;

    if (canal == CANAL_T0_A || canal == CANAL_T0_B) {
        // Reset Timer0 solo una vez; llamadas posteriores solo agregan COM bits
        static uint8_t t0_ready = 0;
        if (!t0_ready) {
            TCCR0A = (1 << WGM01) | (1 << WGM00); // Fast PWM, COM bits en cero
            TCCR0B = 0;
            t0_ready = 1;
        }

        if (canal == CANAL_T0_A) {
            DDRD   |= (1 << PD6);
            TCCR0A |= (1 << COM0A1);  // OR: preserva COM0B1 si ya está activo
            OCR0A   = min_ocr;
        } else {
            DDRD   |= (1 << PD5);
            TCCR0A |= (1 << COM0B1);  // OR: preserva COM0A1 si ya está activo
            OCR0B   = min_ocr;
        }

        if      (prescaler == 64)   TCCR0B = (1 << CS01) | (1 << CS00);
        else if (prescaler == 256)  TCCR0B = (1 << CS02);
        else if (prescaler == 1024) TCCR0B = (1 << CS02) | (1 << CS00);

    } else if (canal == CANAL_T2_A || canal == CANAL_T2_B) {
        TCCR2A = 0;
        TCCR2B = 0;
        TCCR2A = (1 << WGM21) | (1 << WGM20); // Fast PWM

        if (canal == CANAL_T2_A) {
            DDRB  |= (1 << PB3);
            TCCR2A |= (1 << COM2A1);
            OCR2A  = min_ocr;
        } else {
            DDRD  |= (1 << PD3);
            TCCR2A |= (1 << COM2B1);
            OCR2B  = min_ocr;
        }

        if      (prescaler == 64)   TCCR2B = (1 << CS22);
        else if (prescaler == 256)  TCCR2B = (1 << CS22) | (1 << CS21);
        else if (prescaler == 1024) TCCR2B = (1 << CS22) | (1 << CS21) | (1 << CS20);
    }
}

void Servo_SetFromADC(uint8_t canal, uint16_t adc_val) {
    uint8_t  min_ocr = s_min_ocr[canal];
    uint8_t  max_ocr = s_max_ocr[canal];
    uint16_t min_adc = s_min_adc[canal];
    uint16_t max_adc = s_max_adc[canal];

    if (adc_val < min_adc) adc_val = min_adc;
    if (adc_val > max_adc) adc_val = max_adc;

    uint8_t ocr = (max_adc == min_adc)
        ? min_ocr
        : (uint8_t)(min_ocr + ((uint32_t)(adc_val - min_adc) * (max_ocr - min_ocr)) / (max_adc - min_adc));

    if      (canal == CANAL_T0_A) OCR0A = ocr;
    else if (canal == CANAL_T0_B) OCR0B = ocr;
    else if (canal == CANAL_T2_A) OCR2A = ocr;
    else if (canal == CANAL_T2_B) OCR2B = ocr;
}

void Servo_SetAngle(uint8_t canal, uint8_t deg) {
    uint8_t ocr = s_min_ocr[canal] +
        (uint8_t)((uint16_t)deg * (s_max_ocr[canal] - s_min_ocr[canal]) / 180);

    if      (canal == CANAL_T0_A) OCR0A = ocr;
    else if (canal == CANAL_T0_B) OCR0B = ocr;
    else if (canal == CANAL_T2_A) OCR2A = ocr;
    else if (canal == CANAL_T2_B) OCR2B = ocr;
}
