#include <stdio.h>
#include <unistd.h>
#include <sys/wait.h>

//       (pai)
//         |
//    +----+----+
//    |         |
// filho_1   filho_2


// ~~~ printfs  ~~~
// pai (ao criar filho): "Processo pai criou %d\n"
//    pai (ao terminar): "Processo pai finalizado!\n"
//  filhos (ao iniciar): "Processo filho %d criado\n"

// Obs:
// - pai deve esperar pelos filhos antes de terminar!



int main(int argc, char** argv) {

    int pid = fork();// cria cópia do processo
    int status; 

    if (pid > 0) {
      for (int i = 0; i < 2; ++i) {
        pid = fork();

        if (pid == 0) {
          printf("Processo filho %d criado\n", getpid());
          break;
        }
      }

      if (pid > 0) {
        while(wait(&status) >= 0);
        printf("Processo pai finalizado!\n");

      } else if (pid == 0) {
        printf("Processo pai criou %d\n", getpid());
      }

    }
    return 0;
}
