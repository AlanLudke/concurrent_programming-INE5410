#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <stdio.h>
#include <string.h>
//                          (principal)
//                               |
//              +----------------+--------------+
//              |                               |
//           filho_1                         filho_2
//              |                               |
//    +---------+-----------+          +--------+--------+
//    |         |           |          |        |        |
// neto_1_1  neto_1_2  neto_1_3     neto_2_1 neto_2_2 neto_2_3

// ~~~ printfs  ~~~
//      principal (ao finalizar): "Processo principal %d finalizado\n"
// filhos e netos (ao finalizar): "Processo %d finalizado\n"
//    filhos e netos (ao iniciar): "Processo %d, filho de %d\n" x

// Obs:
// - netos devem esperar 5 segundos antes de imprmir a mensagem de finalizado (e terminar)
// - pais devem esperar pelos seu descendentes diretos antes de terminar


//printf("Processo principal %d finalizado\n", getpid());
//printf("Processo %d finalizado\n", getpid());
//printf("Processo %d, filho de %d\n", getpid(), getppid());



int main(int argc, char** argv) {

    
    pid_t pid;// cria cópia do processo

    int status; // Variável para status do filho
    
    for (int i = 0; i < 2; i++) {
      fflush(stdout);
      pid = fork();

      if (pid == 0) {
        break;
      }
    }
    
    if (pid > 0) {// é o processo pai
      
      wait(&status);
      printf("Processo principal %d finalizado\n", getpid());
      
    } else if (pid == 0) {// é o processo filho

      if(pid == 0) {
        for (int i = 0; i < 3; i++) {
          fflush(stdout);
          pid = fork();

          if (pid == 0) {
            break;
          }
        }
      }
      printf("Processo %d, filho de %d\n", getpid(), getppid());
      sleep(5);
      wait(&status);
      printf("Processo %d finalizado\n", getpid());
    }
    

    return 0;
}

