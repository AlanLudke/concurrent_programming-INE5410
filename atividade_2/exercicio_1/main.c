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
    int status; // Variável para status do filho

    if (pid > 0) {// é o processo pai
      pid = fork();

      if (pid > 0) {// é o processo pai
        while(wait(&status) >= 0);
        printf("Processo pai finalizado!\n");
      } else if (pid == 0) {// é o processo filho
        printf("Processo pai criou %d\n", getpid());
        printf("Processo filho %d criado\n", getpid());
      }

    } else if (pid == 0) {// é o processo filho
      printf("Processo pai criou %d\n", getpid());
      printf("Processo filho %d criado\n", getpid());

    }
    return 0;
}
