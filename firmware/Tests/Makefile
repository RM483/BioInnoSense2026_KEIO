# HydroPaw ホスト単体テスト (HAL非依存モジュールのみ)
CC      = gcc
CFLAGS  = -Wall -Wextra -Werror -std=c11 -I../App/Inc -I../Core/Inc
SRC     = ../App/Src/hpp.c ../App/Src/dgs2.c ../App/Src/ring_buffer.c
SM_SRC  = $(SRC) ../App/Src/ble_link.c ../App/Src/state_machine.c

TESTS   = test_hpp test_dgs2_parser test_ring_buffer test_state_machine

.PHONY: test clean

test: $(TESTS)
	./test_hpp
	./test_dgs2_parser
	./test_ring_buffer
	./test_state_machine

test_hpp: test_hpp.c $(SRC)
	$(CC) $(CFLAGS) -o $@ test_hpp.c $(SRC)

test_dgs2_parser: test_dgs2_parser.c $(SRC)
	$(CC) $(CFLAGS) -o $@ test_dgs2_parser.c $(SRC)

test_ring_buffer: test_ring_buffer.c $(SRC)
	$(CC) $(CFLAGS) -o $@ test_ring_buffer.c $(SRC)

test_state_machine: test_state_machine.c $(SM_SRC)
	$(CC) $(CFLAGS) -o $@ test_state_machine.c $(SM_SRC)

clean:
	rm -f $(TESTS)
