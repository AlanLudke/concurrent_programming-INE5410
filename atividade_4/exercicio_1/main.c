#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <stdio.h>
#include <pthread.h>

//                 (main)
//                    |
//    +----------+----+------------+
//    |          |                 |
// worker_1   worker_2   ....   worker_n


// ~~~ argumentos (argc, argv) ~~~
// ./program n_threads

// ~~~ printfs  ~~~
// pai (ao criar filho): "Contador: %d\n"
// pai (ao criar filho): "Esperado: %d\n"

// Obs:
// - pai deve criar n_threds (argv[1]) worker threads
// - cada thread deve incrementar contador_global n_threads*1000
// - pai deve esperar pelas worker threads  antes de imprimir!


int contador_global = 0;
pthread_mutex_t mutex; // Mutex para proteger o acesso ao contador

void *ThreadFunc(void *arg) {
    int numOfLoops = *(int *)arg;
    int i;
    for (i = 0; i < numOfLoops; i++) {
      pthread_mutex_lock(&mutex);
      contador_global += 1;
      pthread_mutex_unlock(&mutex);
    }
    pthread_exit(NULL);
}

int main(int argc, char* argv[]) {
  pthread_mutex_init(&mutex, NULL); // Inicializa o mutex destravado
    if (argc < 2) {
        printf("n_threads é obrigatório!\n");
        printf("Uso: %s n_threads\n", argv[0]);
        return 1;
    }

    int numOfThreads = atoi(argv[1]);
    int numOfLoops = 1000 * numOfThreads;
    pthread_t threads[numOfThreads];
    int i;
    for (i = 0; i < numOfThreads; i++)
        pthread_create(&threads[i], NULL, ThreadFunc, (void*)&numOfLoops);

    for (i = 0; i < numOfThreads; i++)
        pthread_join(threads[i], NULL);
    pthread_mutex_destroy(&mutex);
    printf("Contador: %d\n", contador_global);
    printf("Esperado: %d\n", numOfThreads * numOfLoops);
    return 0;
}
