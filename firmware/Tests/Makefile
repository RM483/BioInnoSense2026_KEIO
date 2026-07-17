# HydroPaw ホスト単体テスト (HAL非依存モジュールのみ)
CC      = gcc
CFLAGS  = -Wall -Wextra -Werror -std=c11 -I../App/Inc -I../Core/Inc
SRC     = ../App/Src/hpp.c ../App/Src/dgs2.c ../App/Src/ring_buffer.c

.PHONY: test clean

test: test_hpp test_dgs2_parser
	./test_hpp
	./test_dgs2_parser

test_hpp: test_hpp.c $(SRC)
	$(CC) $(CFLAGS) -o $@ test_hpp.c $(SRC)

test_dgs2_parser: test_dgs2_parser.c $(SRC)
	$(CC) $(CFLAGS) -o $@ test_dgs2_parser.c $(SRC)

clean:
	rm -f test_hpp test_dgs2_parser
