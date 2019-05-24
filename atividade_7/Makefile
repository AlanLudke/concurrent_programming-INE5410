#Esse makefile só serve para fazer o arquivo a ser enviado pro moodle

.PHONY: submission compile clean

# Prepara .tar.gz pra submissão no moodle
# Note que antes de preparar o tar.gz, é feito um clean
submission: clean
	./grade-openmp.sh || true
	SUBNAME=$$(basename "$$(pwd)"); \
		cd ..; \
		rm -fr "$$SUBNAME.tar.gz"; \
		tar zcf "$$SUBNAME.tar.gz" "$$SUBNAME"
	@echo Atividade empacotada em $$(cd .. && pwd)/$$(basename "$$(pwd)").tar.gz
compile:
	$(MAKE) -C exercicio_1
	$(MAKE) -C exercicio_2
	$(MAKE) -C exercicio_3

# Limpa binários
clean:
	$(MAKE) -C exercicio_1             clean
	$(MAKE) -C exercicio_2             clean
	$(MAKE) -C exercicio_3             clean
