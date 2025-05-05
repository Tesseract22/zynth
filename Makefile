CC ?= cc
RAYLIB_PATH ?= raylib
RAYLIB_SRC := $(RAYLIB_PATH)/src
RAYLIB_DLL := $(RAYLIb_SRC)/libraylib.a
ifdef OS
	TARGET := key.exe
	LD_FLAGS := -lmsvcrt -lwinmm -limm32 -lgdi32
else
	TARGET := key
	LD_FLAGS := 
endif

$(TARGET): main.c $(RAYLIB_DLL)
	$(CC) $< -o $@ -L$(RAYLIB_SRC) -lraylib -I$(RAYLIB_SRC) $(LD_FLAGS)


$(RAYLIB_DLL):
	make -C $(RAYLIB_SRC)


clean_raylib:
	make -C $(RAYLIB_SRC) clean
clean: clean_raylib
	rm $(TARGET)
