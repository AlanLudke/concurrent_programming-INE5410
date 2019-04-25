#include <stdio.h>
#include <pthread.h>
#include <semaphore.h>
#include <time.h>
#include <stdlib.h>

FILE* out;

sem_t sem_a;
sem_t sem_b;

int qtdA = 0;
int qtdB = 0;

void *thread_a(void *args) {
    for (int i = 0; i < *(int*)args; ++i) {
	//      +---> arquivo (FILE*) destino
	//      |    +---> string a ser impressa
	//      v    v
      if(qtdA - qtdB >= 1) {
        sem_wait(&sem_a);
        fprintf(out, "A");
        qtdA++;
        fflush(stdout);
        sem_post(&sem_a);
      } else {
        sem_wait(&sem_b);
        sem_post(&sem_a);
      }

    // Importante para que vocês vejam o progresso do programa
    // mesmo que o programa trave em um sem_wait().
    }
    return NULL;
}

void *thread_b(void *args) {
    for (int i = 0; i < *(int*)args; ++i) {
        if(qtdA - qtdB >= 1) {
          sem_wait(&sem_b);
          fprintf(out, "B");
          qtdB++;
          fflush(stdout);
          sem_post(&sem_b);
        } else {
          sem_wait(&sem_a);
          sem_post(&sem_b);
        }
    }
    return NULL;
}

int main(int argc, char** argv) {
    if (argc < 2) {
        printf("Uso: %s iteraões\n", argv[0]);
        return 1;
    }
    int iters = atoi(argv[1]);
    srand(time(NULL));
    out = fopen("result.txt", "w");

    sem_init(&sem_a, 0, 1);
    sem_init(&sem_b, 0, 1);

    pthread_t ta, tb;

    // Cria threads
    pthread_create(&ta, NULL, thread_a, &iters);
    pthread_create(&tb, NULL, thread_b, &iters);

    // Espera pelas threads
    pthread_join(ta, NULL);
    pthread_join(tb, NULL);


    //Imprime quebra de linha e fecha arquivo
    fprintf(out, "\n");
    fclose(out);

    sem_destroy(&sem_a);
    sem_destroy(&sem_b);

    return 0;
}
