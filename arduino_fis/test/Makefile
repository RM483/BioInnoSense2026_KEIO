# bap_lite / hpp のホスト検証 (Arduino不要)
CXX     = g++
CXXFLAGS = -Wall -Wextra -std=c++17 -I..

.PHONY: test clean
test: test_fis
	./test_fis

test_fis: test_fis.cpp ../bap_lite.cpp ../hpp.cpp
	$(CXX) $(CXXFLAGS) -o $@ test_fis.cpp ../bap_lite.cpp ../hpp.cpp

clean:
	rm -f test_fis
