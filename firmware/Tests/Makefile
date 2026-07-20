# HydroPaw ホスト単体テスト (HAL非依存モジュールのみ)
CC      = gcc
CFLAGS  = -Wall -Wextra -Werror -std=c11 -I../App/Inc -I../Core/Inc
SRC     = ../App/Src/hpp.c ../App/Src/dgs2.c ../App/Src/ring_buffer.c
SM_SRC  = $(SRC) ../App/Src/ble_link.c ../App/Src/state_machine.c ../App/Src/bap.c

TESTS   = test_hpp test_dgs2_parser test_ring_buffer test_state_machine \
          test_bap test_arq test_bgapi

.PHONY: test clean

test: $(TESTS)
	./test_hpp
	./test_dgs2_parser
	./test_ring_buffer
	./test_state_machine
	./test_bap
	./test_arq
	./test_bgapi

test_hpp: test_hpp.c $(SRC)
	$(CC) $(CFLAGS) -o $@ test_hpp.c $(SRC)

test_dgs2_parser: test_dgs2_parser.c $(SRC)
	$(CC) $(CFLAGS) -o $@ test_dgs2_parser.c $(SRC)

test_ring_buffer: test_ring_buffer.c $(SRC)
	$(CC) $(CFLAGS) -o $@ test_ring_buffer.c $(SRC)

test_state_machine: test_state_machine.c $(SM_SRC)
	$(CC) $(CFLAGS) -o $@ test_state_machine.c $(SM_SRC)

test_bap: test_bap.c ../App/Src/bap.c
	$(CC) $(CFLAGS) -o $@ test_bap.c ../App/Src/bap.c

test_arq: test_arq.c ../App/Src/hpp.c ../App/Src/ble_link.c
	$(CC) $(CFLAGS) -o $@ test_arq.c ../App/Src/hpp.c ../App/Src/ble_link.c

test_bgapi: test_bgapi.c ../App/Src/bgapi.c
	$(CC) $(CFLAGS) -o $@ test_bgapi.c ../App/Src/bgapi.c

# 擬似センサ(HYDROPAW_SIM_SENSOR)の合成呼気カーブを実state_machine+bapに
# 流し、実機に焼く前に一連の経路(初期化→呼気検出→解析→採点→BLE)を先行検証。
# make sim で実行。既定の test ターゲットには含めない(プレビュー用途)。
.PHONY: sim
sim: sim_preview
	./sim_preview

sim_preview: sim_preview.c $(SM_SRC)
	$(CC) $(CFLAGS) -DHYDROPAW_SIM_SENSOR -o $@ sim_preview.c $(SM_SRC)

clean:
	rm -f $(TESTS) sim_preview
