SOURCE_FOLDER = src
OUTPUT_FOLDER = output
OUTPUT_FILE = $(OUTPUT_FOLDER)/Main
INPUT_FILE = $(SOURCE_FOLDER)/test.c
OUTPUT_ASM_FILE = $(OUTPUT_FOLDER)/output.asm
OUTPUT_ASM_DESTINATION = ./ASMBox/c_disk/EXERCISE/test.asm
HAPPY_OUTPUT_FILE = $(SOURCE_FOLDER)/Main.hs

all:
	clear && printf '\e[3J'
	rm -f $(HAPPY_OUTPUT_FILE) $(OUTPUT_FILE)
	# rm -f $(SOURCE_FOLDER)/*.hi $(SOURCE_FOLDER)/*.o
	happy $(SOURCE_FOLDER)/Main.y -o $(HAPPY_OUTPUT_FILE)
	ghc $(HAPPY_OUTPUT_FILE) -i$(SOURCE_FOLDER) -o $(OUTPUT_FILE) -package ghc-7.10.3
	./$(OUTPUT_FILE) $(INPUT_FILE) $(OUTPUT_ASM_FILE) --verbose 
	cp $(OUTPUT_ASM_FILE) $(OUTPUT_ASM_DESTINATION)
	