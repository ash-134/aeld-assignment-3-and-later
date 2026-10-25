CROSS_COMPILE ?= aarch64-linux-gnu-
CC := $(CROSS_COMPILE)gcc

all: writer

writer: writer.c
	$(CC) -o writer writer.c

clean:
	rm -f writer *.o
