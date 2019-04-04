#Esse makefile só serve para fazer o arquivo a ser enviado pro moodle

.PHONY: submission clean

# Prepara .tar.gz pra submissão no moodle
# Note que antes de preparar o tar.gz, é feito um clean
submission: clean
	./grade-atividade_1.sh || true
	SUBNAME=$$(basename "$$(pwd)"); \
		cd ..; \
		rm -fr "$$SUBNAME.tar.gz"; \
		tar zcf "$$SUBNAME.tar.gz" "$$SUBNAME"
	@echo Submeta o arquivo $$(cd .. && pwd)/$$(basename "$$(pwd)").tar.gz no moodle

# Limpa binários
clean:
	$(MAKE) -C exercicio_1             clean
	$(MAKE) -C exercicio_2             clean
	$(MAKE) -C exercicio_3             clean
