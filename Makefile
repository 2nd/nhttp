t:
	@mkdir -p bin
	@nim c --out:./bin/tests --nimcache:./bin/nimcache --threads:on nhttp_test.nim
	@./bin/tests
