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

	pid_t pid;
	printf("Processo pai iniciado\n");
	int status;
	char* encontrou = "não";

	for (int i = 0; i < 2; i++) {
		pid = fork();
		if (i == 0) {
			printf("sed PID %d iniciado\n", getpid());
			execlp("text", "grep silver text", NULL);
		} else {
			printf("grep PID %d iniciado\n", getpid());
			execlp("text", "grep adamantium text", NULL);
		}
		if (pid == 0) {
			break;
		}
	}

    if (pid > 0) { // é o processo pai
      
      wait(&status);
      printf("grep retornou com código %d,%s encontrou silver\n", status, encontrou);
      
    } else if (pid == 0) {// é o processo filho
    	if(status == 0) {
    		printf("grep retornou com código 0, encontrou adamantium\n");
    	} else {
    		printf("grep retornou com código %d, não encontrou adamantium\n", status);
    	}

    } else {
    	printf("Erro %d na criação do processo filho\n", pid);
    }
    
    return 0;
}
