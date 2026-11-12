/*
 * Host unit test for the SSCMA SPI framing code (in the Grove
 * submodule: sdk/Seeed_Grove_Vision_AI_Module_V2/.../watcher_executorch/sscma_spi_framing.c).
 * No test framework: compile with a host C compiler and run; any failed
 * assertion aborts with a message. Run via tests/run_tests.sh.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "sscma_spi_framing.h"

static int failures = 0;

#define CHECK(cond)                                                        \
    do {                                                                   \
        if (!(cond)) {                                                     \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
            failures++;                                                    \
        }                                                                  \
    } while (0)

static void build_packet(uint8_t *pkt, uint8_t cmd, uint16_t len, int trailer_ok)
{
    size_t i;
    memset(pkt, 0, WATCHER_SPI_RX_PACKET_LEN);
    pkt[0] = WATCHER_SPI_FEATURE_TRANSPORT;
    pkt[1] = cmd;
    pkt[2] = (uint8_t)(len >> 8);
    pkt[3] = (uint8_t)(len & 0xFFu);
    if (cmd == WATCHER_SPI_CMD_WRITE) {
        pkt[4 + len] = 0xFF;
        pkt[5 + len] = 0xFF;
    } else {
        pkt[4] = 0xFF;
        pkt[5] = 0xFF;
    }
    if (!trailer_ok) {
        if (cmd == WATCHER_SPI_CMD_WRITE) {
            pkt[4 + len] = 0x00;
        } else {
            pkt[4] = 0x00;
        }
    }
    (void)i;
}

static void test_parse(void)
{
    uint8_t pkt[WATCHER_SPI_RX_PACKET_LEN];
    uint8_t cmd = 0;
    uint16_t len = 0;

    build_packet(pkt, WATCHER_SPI_CMD_WRITE, 5, 1);
    CHECK(watcher_spi_parse_packet(pkt, &cmd, &len) == 0);
    CHECK(cmd == WATCHER_SPI_CMD_WRITE && len == 5);

    build_packet(pkt, WATCHER_SPI_CMD_WRITE, 250, 1);
    CHECK(watcher_spi_parse_packet(pkt, &cmd, &len) == 0);
    CHECK(len == 250);

    build_packet(pkt, WATCHER_SPI_CMD_READ, 4095, 1);
    CHECK(watcher_spi_parse_packet(pkt, &cmd, &len) == 0);
    CHECK(cmd == WATCHER_SPI_CMD_READ && len == 4095);

    build_packet(pkt, WATCHER_SPI_CMD_AVAILABLE, 0, 1);
    CHECK(watcher_spi_parse_packet(pkt, &cmd, &len) == 0);
    build_packet(pkt, WATCHER_SPI_CMD_RESET, 0, 1);
    CHECK(watcher_spi_parse_packet(pkt, &cmd, &len) == 0);
    build_packet(pkt, WATCHER_SPI_CMD_START, 0, 1);
    CHECK(watcher_spi_parse_packet(pkt, &cmd, &len) == 0);
    build_packet(pkt, WATCHER_SPI_CMD_STOP, 0, 1);
    CHECK(watcher_spi_parse_packet(pkt, &cmd, &len) == 0);

    /* Errors: feature, unknown command, lengths, trailer. */
    build_packet(pkt, WATCHER_SPI_CMD_WRITE, 5, 1);
    pkt[0] = 0x11;
    CHECK(watcher_spi_parse_packet(pkt, &cmd, &len) == -1);
    build_packet(pkt, 0x07, 0, 1);
    CHECK(watcher_spi_parse_packet(pkt, &cmd, &len) == -2);
    build_packet(pkt, WATCHER_SPI_CMD_WRITE, 251, 1);
    CHECK(watcher_spi_parse_packet(pkt, &cmd, &len) == -3);
    build_packet(pkt, WATCHER_SPI_CMD_READ, 0, 1);
    CHECK(watcher_spi_parse_packet(pkt, &cmd, &len) == -3);
    build_packet(pkt, WATCHER_SPI_CMD_READ, 4096, 1);
    CHECK(watcher_spi_parse_packet(pkt, &cmd, &len) == -3);
    build_packet(pkt, WATCHER_SPI_CMD_AVAILABLE, 1, 1);
    CHECK(watcher_spi_parse_packet(pkt, &cmd, &len) == -3);
    build_packet(pkt, WATCHER_SPI_CMD_WRITE, 5, 0);
    CHECK(watcher_spi_parse_packet(pkt, &cmd, &len) == -4);
    /* Exact 250-byte boundary: trailer must sit at 254/255. */
    build_packet(pkt, WATCHER_SPI_CMD_WRITE, 250, 1);
    pkt[253] = 0xFF;
    CHECK(watcher_spi_parse_packet(pkt, &cmd, &len) == 0);
}

static void test_available(void)
{
    uint8_t out[2];
    watcher_spi_encode_available(out, 0);
    CHECK(out[0] == 0x00 && out[1] == 0x00);
    watcher_spi_encode_available(out, 1234);
    CHECK(out[0] == 0x04 && out[1] == 0xD2);
    watcher_spi_encode_available(out, 65534);
    CHECK(out[0] == 0xFF && out[1] == 0xFE);
    /* 0xFFFF is reserved as "none pending": clamp, never report it. */
    watcher_spi_encode_available(out, 65535);
    CHECK(out[0] == 0xFF && out[1] == 0xFE);
}

static void test_queue(void)
{
    uint8_t buf[16];
    uint8_t out[16];
    watcher_tx_queue_t q;
    watcher_tx_queue_init(&q, buf, sizeof(buf));
    CHECK(watcher_tx_queue_available(&q) == 0);

    CHECK(watcher_tx_queue_enqueue(&q, (const uint8_t *)"hello", 5));
    CHECK(watcher_tx_queue_enqueue(&q, (const uint8_t *)" world!", 7));
    CHECK(watcher_tx_queue_available(&q) == 12);
    /* Overflow is rejected and leaves the queue unchanged. */
    CHECK(!watcher_tx_queue_enqueue(&q, (const uint8_t *)"0123456789", 10));
    CHECK(watcher_tx_queue_available(&q) == 12);

    CHECK(watcher_tx_queue_drain(&q, out, 5) == 5);
    CHECK(memcmp(out, "hello", 5) == 0);
    /* Wraparound: enqueue across the end of the ring. */
    CHECK(watcher_tx_queue_enqueue(&q, (const uint8_t *)"012345678", 9));
    CHECK(watcher_tx_queue_available(&q) == 16);
    CHECK(watcher_tx_queue_drain(&q, out, 16) == 16);
    CHECK(memcmp(out, " world!012345678", 16) == 0);
    CHECK(watcher_tx_queue_available(&q) == 0);
    CHECK(watcher_tx_queue_drain(&q, out, 4) == 0);

    watcher_tx_queue_enqueue(&q, (const uint8_t *)"abc", 3);
    watcher_tx_queue_reset(&q);
    CHECK(watcher_tx_queue_available(&q) == 0);
}

static void test_assembler(void)
{
    char buf[32];
    watcher_cmd_asm_t a;
    char *cmd = NULL;

    watcher_cmd_asm_init(&a, buf, sizeof(buf));
    /* Command split across WRITE packets, CRLF stripped. */
    CHECK(!watcher_cmd_asm_feed(&a, (const uint8_t *)"AT+IN", 5, &cmd));
    CHECK(!watcher_cmd_asm_feed(&a, (const uint8_t *)"VOKE=-1,0", 9, &cmd));
    CHECK(watcher_cmd_asm_feed(&a, (const uint8_t *)",1\r\n", 4, &cmd));
    CHECK(cmd != NULL && strcmp(cmd, "AT+INVOKE=-1,0,1") == 0);

    /* Bare LF also terminates. */
    CHECK(watcher_cmd_asm_feed(&a, (const uint8_t *)"AT+ID?\n", 7, &cmd));
    CHECK(cmd != NULL && strcmp(cmd, "AT+ID?") == 0);

    /* Oversized line is discarded through its newline (across feeds);
     * bytes of that line arriving later are dropped, then the next
     * command assembles normally. */
    CHECK(!watcher_cmd_asm_feed(&a, (const uint8_t *)"AT+INFO=\"XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX", 36, &cmd));
    CHECK(!watcher_cmd_asm_feed(&a, (const uint8_t *)"AT+BREAK\r", 9, &cmd));
    CHECK(!watcher_cmd_asm_feed(&a, (const uint8_t *)"\n", 1, &cmd));
    CHECK(watcher_cmd_asm_feed(&a, (const uint8_t *)"AT+BREAK\r\n", 10, &cmd));
    CHECK(cmd != NULL && strcmp(cmd, "AT+BREAK") == 0);
}

int main(void)
{
    test_parse();
    test_available();
    test_queue();
    test_assembler();
    if (failures == 0) {
        printf("test_sscma_spi_framing: all checks passed\n");
        return 0;
    }
    fprintf(stderr, "test_sscma_spi_framing: %d failure(s)\n", failures);
    return 1;
}
