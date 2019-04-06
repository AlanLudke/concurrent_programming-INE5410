#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <stdio.h>
#include <string.h>
//        (pai)
//          |
//      +---+---+
//      |       |
//     sed    grep

// ~~~ printfs  ~~~
//        sed (ao iniciar): "sed PID %d iniciado\n"
//       grep (ao iniciar): "grep PID %d iniciado\n"
//          pai (ao iniciar): "Processo pai iniciado\n"
// pai (após filho terminar): "grep retornou com código %d,%s encontrou silver\n"
//                            , onde %s é
//                              - ""    , se filho saiu com código 0
//                              - " não" , caso contrário

// Obs:
// - processo pai deve esperar pelo filho
// - 1º filho deve trocar seu binário para executar "grep silver text"
//   + dica: use execlp(char*, char*...)
//   + dica: em "grep silver text",  argv = {"grep", "silver", "text"}
// - 2º filho, após o término do 1º deve trocar seu binário para executar
//   sed -i /silver/axamantium/g;s/adamantium/silver/g;s/axamantium/adamantium/g text
//   + dica: leia as dicas do grep

int main(int argc, char** argv) {

	pid_t filho;
	int pidgrep;
	int pidsed;

	int codgrep;
	int status;

	printf("Processo pai iniciado\n");

	for (int i = 0; i < 2; i++) {
		fflush(stdout);
		filho = fork();

		if (filho > 0) {
			break;
		}

		if (i == 0) {
			printf("sed PID %d iniciado\n", getpid());
			pidsed = getpid();

			fflush(stdout);
			execlp("sed", "sed", "-i", "s/silver/axamantium/g;s/adamantium/silver/g;s/axamantium/adamantium/g", "text");

		} else {
			printf("grep PID %d iniciado\n", getpid());
			pidgrep = getpid();

			fflush(stdout);
			execlp("grep", "grep", "adamantium", "text");
		}
	}
  if (filho > 0) { //pai
		while (waitpid(pidsed, &status, 0) >= 0) {}
		codgrep = WEXITSTATUS(status);

		waitpid(pidgrep, &status, 0);

		if (codgrep == 0) {
			printf("grep retornou com código %d, encontrou adamantium\n", codgrep);
		} else {
			codgrep = codgrep % 3;
			printf("grep retornou com código %d, não encontrou adamantium\n", codgrep);
		}
  }
	return status;
}
